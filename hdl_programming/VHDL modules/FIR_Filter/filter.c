#include "lusi.h"
#include "platform.h"
#include "filter.h"
#include <stdint.h>
#include <stdlib.h>
#include <math.h>


/* Array Modification / generation functions */

void display_double_array(double* data, uint32_t length){

	for(int i = 0; i<length; i++){
		rprintf("%f, ",data[i]);
		// create newline every 20 values
		if(i != 0 && i % 20 == 0) {rprintf("\r\n");}
	}
}

void display_int_array(int32_t* data, uint32_t length){

	for(int i = 0; i<length; i++){
		rprintf("%i, ",data[i]);
		// create newline every 20 values
		if(i != 0 && i % 20 == 0) {rprintf("\r\n");}
	}
}

double* linspace(double start, double end, uint32_t length){

	// determine step size for array data
	double step_size = (end-start)/ (length-1);

	// create array to store data
	double* data = (double*)malloc(length*sizeof(double));

	// populate array
	data[0] = start;
	for(int i = 1; i<length; i++){
		data[i] = data[i-1] + step_size;
	}

	return data;
}

double* flip_array(double* data, uint32_t length){

	double* res = (double*)malloc(length*sizeof(double));

	for(int i = 0; i<length; i++){
		res[i] = data[length-1-i];
	}

	return res;
}

double* remove_endpoints(double* data, uint32_t length){

	double* res = (double*)malloc((length-2)*sizeof(double));

	// populate array, ignoring first/ last data points
	for(int i = 1; i<length-1;i++){
		res[i-1] = data[i];
	}

	return res;
}

double* concat_array(double* s1, double* s2, uint32_t l1, uint32_t l2){

	double* res = (double*)malloc((l1+l2)*sizeof(double));

	// build first half
	for(int i = 0; i < l1;i++){
		res[i] = s1[i];
	}

	// build second half
	for(int i = 0; i < l2;i++){
		res[l1+i] = s2[i];
	}

	return res;
}

// multiply two signals together, element wise
double* multiply_a(double* s1, double* s2, uint32_t length){

	double* res = (double*)malloc(length*sizeof(double));

	for(int i = 0; i<length; i++){
		res[i] = s1[i] * s2[i];
	}

	return res;
}

// scale every value of an array by given scalar
void scale_a(double* signal, double scalar, uint32_t length){

	for(int i = 0; i<length; i++){
		signal[i] = signal[i] * scalar;
	}
}

void add_a(double* signal, double scalar, uint32_t length){

	for(int i = 0; i<length; i++){
		signal[i] = signal[i] + scalar;
	}
}

/* Mathmatical array operations */

double sum_a(double* data, uint32_t length){

	double sum = 0;

	for(int i = 0; i<length; i++){
		sum += data[i];
	}

	return sum;
}

double sinc(double arg){
	// sinc(x) = sin(pi * x)/ (pi * x)
	// sin(x)/(x) approaches one as x->0
	if(arg == 0){
		return 1;
	}
	else{
		return sin(M_PI*arg)/(M_PI*arg);
	}
}

// pass array to mathematical function as an argument
double* trig_of(double(*op)(double), double* input, uint32_t len){

	// storage for mathematical operation result
	double* res = (double*)malloc(len*sizeof(double));

	// calculate values of 'op' on 'input'
	for(int i = 0; i<len; i++){
		res[i] = (*op)(input[i]);
	}

	return res;
}

double* convolve_signals(double* s1, double* s2, uint32_t l1, uint32_t l2){

#define OVERLAP_MAX		(SMLR(l1,l2))
#define OVERLAP_HOLD	(GRTR(l1,l2) - SMLR(l1,l2) + 1)

	// result of convolution array
	double* res = (double*)malloc((l1+l2-1)*sizeof(double));

	// zero out convolution result array
	memset(res,0,sizeof(double)*(l1+l2-1));

	// track state of waveform overlap
	int overlap = 0;
	int overlap_flag = 0;
	int overlap_hold_cnt = 0;

	// starting indicies of signals
	int omi_1 = 0;
	int omi_2 = 0;

	// compute convolution between s1/ s2.
	// 	s2 inherently 'flipped'
	for(int i = 0; i < (l1+l2-1); i++){

		// when overlap state is reached, the first
		//  overlap term has already been calculated.
		//  reduce overlap_hold_cnt by 1 (second if statement)
		if(overlap == OVERLAP_MAX){
			if(overlap_hold_cnt < OVERLAP_HOLD-1){
				overlap_flag = 1;
				overlap_hold_cnt++;
			}
			else{
				overlap_flag = -1;
			}
		}

		// count until overlap flag is set
		if(overlap_flag == 0){overlap++;}
		else if(overlap_flag == -1){overlap--;}

		for(int j = 0; j < overlap; j++){
			// multiply array indices starting at end of y_m and
			//  beginning of x_n
			//                     <-- *
			//   [0][1][2][3][4][5][6][7]            x_n[]
			//         [7][6][5][4][3][2][1][0]      y_m[]
			//                     <-- *
			res[i] += s1[omi_1-j] * s2[omi_2-overlap+1+j];

		}

		// incriment starting index of signal arrays
		if(omi_1 < (l1-1)){omi_1++;}
		if(omi_2 < (l2-1)){omi_2++;}
	}

	return res;
}

// convert kernel values into scaled value for loading into hardware
int32_t* scale_kernel(double* kernel, uint32_t length, uint32_t scaling_res){

	int32_t scalar = pow(2,scaling_res) - 1;

	int32_t* res = (int32_t*)malloc(length*sizeof(int32_t));

	for(int i = 0; i < length; i++){
		res[i] = (int32_t)(kernel[i] * scalar);
	}

	return res;
}

double* gen_lp_filter(double f0, uint32_t num_samples, double num_periods){

	double f_cl = f0;
	double N_lp = num_periods;
	uint32_t Mk = num_samples;
	uint32_t M = ((Mk-1)/2);

	// arguments
	double a_lp = 2 * f_cl;								// argument for LP sinc
	double T_lp_sinc = 2 / a_lp;
	double T_lp_black = 2 * N_lp * T_lp_sinc;			// period of low-pass blackman window

	// build time array for LP sinc
	double lp_time_range = (N_lp) * T_lp_sinc;			// half of LP sinc time range
	double* lpr_t = linspace(0, lp_time_range, M+1);	// half of the LP sinc time array
	double* lpl_t = flip_array(lpr_t, M+1);				// reverse of lpr_t

	// build complete time array for sinc function
	// last element (t=0) of the left-hand array is removed
	double* lp_filt_t = concat_array(lpl_t, lpr_t, M, M+1);
	// scale our time array by the sinc argument 'a_lp'
	scale_a(lp_filt_t, a_lp, Mk);

	// take SINC of our time array
	double* lp_filt_sinc = trig_of(sinc, lp_filt_t, Mk);

	// generate blackman window
	// lp_filt_blackman = 0.5 - 0.5*[ cos(2*pi*(1/T_lp_black)*(lp_filt_t + (T_lp_black/2)))]
	// build complete time array for blackman window
	double lp_black_arg = (2 * M_PI) / T_lp_black;
	double* lp_blk_t = concat_array(lpl_t, lpr_t, M, M+1);
	// shift and scale time array
	add_a(lp_blk_t, (T_lp_black/2), Mk);
	scale_a(lp_blk_t, lp_black_arg, Mk);

	double* lp_filt_blackman = trig_of(cos, lp_blk_t, Mk);
	//shift and scale blackman result
	scale_a(lp_filt_blackman, -0.5, Mk);
	add_a(lp_filt_blackman, 0.5, Mk);

	// multiply sinc by blackman window
	double* lp_filt = multiply_a(lp_filt_sinc,lp_filt_blackman,Mk);

	// scale filter elements by total SUM
	double sum = sum_a(lp_filt,Mk);
	sum = 1 / sum;
	scale_a(lp_filt, sum, Mk);

//	uprintf("inside LP filt gen:");																		REMOVE
//
//	uprintf("Nl= %f, M= %i, a_lp= %f", N_lp, M, a_lp);
//	uprintf("T_lp_sinc= %e, T_lp_black= %e, a_lp= %f", T_lp_sinc, T_lp_black, a_lp);
//	uprintf("lp_time_range= %e, lp_black_arg= %e, sum= %f", lp_time_range, lp_black_arg, sum);
//
//	uprintf("lp filt sinc:");
//	display_double_array(lp_filt_sinc, Mk);
//	rprintf("\r\n\r\n");
//	uprintf("lp filt blakman:");
//	display_double_array(lp_filt_blackman,Mk);
//	rprintf("\r\n\r\n");

	// FREE all arrays
	free(lpr_t);
	free(lpl_t);
	free(lp_filt_t);
	free(lp_blk_t);
	free(lp_filt_sinc);
	free(lp_filt_blackman);

	return lp_filt;
}

/* Generate DSP filter, and load it into kernel module on board */
void dsp_filter_generate(double fc, double bandwidth, uint32_t kernel_length){

	// determine sample rate of system
	// BPSK signal is split into 8 lanes of traffic (8I/ 8Q)
	// const int num_lanes = 8;
	const double sample_rate = 307200000.0;

	// determine high-pass + low-pass filter cutoff frequencies
	double f_ch = fc - (bandwidth/ 2);
	double f_cl = fc + (bandwidth/ 2);

	// The effective sample count of our filter kernel is given by Ns
 	//  - we need the bandpass kernel sample rate to match that of the bpsk signal
 	//  - therefore, the sample rate of the low/high pass kernels will match as well,
	//	  but they will not match perfectly due to rounding
	//	- the length of Lp/ HP filter kernels will be 'Mk'. 'Mk' must be odd, so
	//	  the convolution between LP/ HP kernels will also be odd length
	int Mk = (kernel_length + 1 ) / 2;
	int Mk_flag = 0;						// Was Mk adjusted?
	if(Mk % 2 == 0){
		Mk++;
		Mk_flag = 1;
	}

	// Calculate M, Mb (bandpass kernel length)
	int M = (Mk - 1)/ 2;		// should be even after above correction to Mk
	int Mb = 2 * Mk - 1;		// should be odd after above correction to Mk

	// determine number of periods of HP/ LP kernels
	double N_hp = (Mk * f_ch) / sample_rate;		// high-pass sinc function
	double N_lp = (Mk * f_cl) / sample_rate;		// low-pass sinc function

	// calculate the sample freq of our kernel
	// 	- compare with desired sample freq
	//  - sample freq = freq * (number of samples/ number of periods)
	//  - kernel has twice as many periods due to convolution
	double kernel_sample_rate = f_ch * Mb / (2 * N_hp);

	uprintf("M= %i, Mk= %i, Mb= %i", M, Mk, Mb);
    uprintf("N_hp= %f, N_lp= %f",N_hp, N_lp);
    uprintf("f_ch= %f, f_cl= %f",f_ch, f_cl);
    uprintf("kernel sample rate= %f, lane sample rate= %f\n",kernel_sample_rate, sample_rate);

    // Gen low-pass filter
    double* lp_filt = gen_lp_filter(f_cl, Mk, (N_lp/2));

    // Gen high-pass filter
    // create low-pass
    double* hp_filt = gen_lp_filter(f_ch, Mk, (N_hp/2));
    // invert all values
    scale_a(hp_filt, -1, Mk);
    // add one to center value
    hp_filt[M] += 1;

    // Gen band-pass filter
    double* bp_filt_i = convolve_signals(lp_filt, hp_filt, Mk, Mk);

    // if Mk was adjusted, we must remove the endpoints to conform to user-defined sample length
    double* bp_filt;
    int Mb_a;

    if(Mk_flag){
    	bp_filt = remove_endpoints(bp_filt_i, Mb);
    	Mb_a = Mb-2;
    }

    // Scale values for fractional multiplication
    uint32_t Ns = 16;		// sample resolution
    uint32_t Nd = Ns - 1;	// Ns-bit sample can be right-shifted at most Ns-1 timess
    uint32_t Ndy = 2 * Nd;	// ideal multiplication factor for f

    int32_t* kernel = scale_kernel(bp_filt, Mb_a, Ndy);

    // display low pass, high pass, band-pass kernel values
//    rprintf("low pass kernel: \r\n");
//    display_double_array(lp_filt, Mk);
//    rprintf("\r\n\r\n");
//    rprintf("high pass kernel: \r\n");
//    display_double_array(hp_filt, Mk);
//    rprintf("\r\n\r\n");
//    rprintf("band pass kernel: \r\n");
//    display_double_array(bp_filt, Mb_a);
//    rprintf("\r\n\r\n");
//    rprintf("band pass kernel: \r\n");
//    display_double_array(bp_filt_i, Mb);
//    rprintf("\r\n\r\n");
    rprintf("band pass kernel adj: \r\n");
    display_int_array(kernel,  Mb_a);
    rprintf("\r\n\r\n");

    // Write kernel value to convolution block
    for(int i = 0; i<Mb_a;i++){
    	reg_write(DSP_FILT_BASE,kernel[i]);
    }

    // FREE all memory allocated
    free(lp_filt);
    free(hp_filt);
    free(bp_filt_i);
    free(bp_filt);
    free(kernel);
}


uint32_t lane_config(uint32_t* l1_freq, uint32_t* l2_freq, double* atten_setting, int p_switch, uint32_t f_div)
{

	// RF switches allow selection of correct filtering path
	// Below is the truth table for the signal lines
	// V3 is MSB when sending control data over SPI

	//	Top Down View of Filter Board signal input
	//
	//			 0  2
	//          _|__|_
	//     ____|SW0   |--<-- V3	-- LANE 1
	//    |	   |______|--<-- V2
	//    |      |  |
	//    |(1G5) 3	1 (1G)
	// -->|		 				--> signal flow
	//	  |(1G5) 0	2 (1G)
	//	  |     _|__|_
	//    |____|SW1   |--<-- V1
	//	       |______|--<-- V0	-- LANE 2
	//			 |  |
	//			 3  1


	// V3|V2|Lane-1		V1|V0|Lane-2
	// 0 |0 |Load		0 |0 |1G5-2G
	// 1 |0 |Atten		1 |0 |1G-1G5
	// 0 |1 |1G-1G5		0 |1 |HDR
	// 1 |1 |1G5-2G	    1 |1 |Cplr

	// Lane-Select configuration on PCB from top to bottom
	// Select Val	| freq range
	// ------------------------ L1
	// V3,V2
	// 	0x01		| 	1G-1G5
	// 	0x03		| 	1G5-2G
	// 	0xXX		| 	2G-2G5
	// 	0xXX		| 	2G5-3G
	// ------------------------	L2
	// V1,V0
	// 	0xXX		| 	2G5-3G
	// 	0xXX		| 	2G-2G5
	// 	0x00		| 	1G5-2G
	// 	0x01		| 	1G-1G5

	// determine closest allowed attenuation factor (round down), giving bit_sequence for programming
	// data is sent MSB first, so 'round_attenuation' will return correct programming strings
	uint8_t atten_1_val, atten_2_val;
	round_attenuation(atten_setting, &atten_1_val, &atten_2_val);

	// 100 MHz clock / 100 = 1 MHz SPI/shifter rate
	// filter_driver will divide by two internally
	//uint32_t rf_board_clk_div = 100;
	uint32_t rf_board_clk_div = f_div;

	reg_write(ADDR_WR_RF_BOARD_FREQ_DIV, rf_board_clk_div);

	uint32_t cs_atten_1	 = 0x8;
	uint32_t cs_atten_2  = 0x9;
	uint32_t cs_vcntrl	 = 0xB;				// Chip select for switch-config shift register
//	uint32_t cs_vreset   = 0xA;				// Clear switch-config shift reg -> not implemented in VHDL 'filter_driver'
	uint32_t const F_MAX  = 3000000000;
	uint32_t const F_MIN  = 1000000000;
	uint32_t step_size	  = 10000000;
	uint32_t freq_range[] = {1000000000, 1500000000, 2000000000, 2500000000, 3000000000};
	uint32_t freq_range_max = 4;

	// Switch control values for Filter lane selection
	//						{1G,1G5,2G,2G5}
	uint32_t sel_lane_1[] = {1, 3, 0, 2};	// current debugging
	uint32_t sel_lane_2[] = {2, 0, 1, 3};	// current debugging

	// Filter chip select values for lane programming
	//						{1G,1.5G,2G,2.5G}
	uint32_t cs_lane_1[] =  {2, 3, 0, 0};	// current debugging
	uint32_t cs_lane_2[] =  {5, 4, 0, 0};	// current debugging

	//Setup defaults for Filter board lane configuation
	uint32_t L1_sel;
	uint32_t L2_sel;
	uint32_t L1_CS;
	uint32_t L2_CS;
	uint32_t vcntrl;
	uint32_t L1_tuning_word;
	uint32_t L2_tuning_word;

	uint32_t rf_board_tx_data;
	uint32_t rf_board_tx_data_len;
	uint32_t rf_board_sel_bits;

	// setup local frequency values
	uint32_t L1_Freq = *l1_freq;
	uint32_t L2_Freq = *l2_freq;

	// Make sure user enters valid data
	if( L1_Freq > F_MAX || L1_Freq < F_MIN)
		return 1;
	if( L2_Freq > F_MAX || L2_Freq < F_MIN)
		return 1;

	int i = freq_range_max;
	for(;L1_Freq < freq_range[i];i--);			// determine lower limit of frequency range for Lane 1
	L1_sel = sel_lane_1[i];
	L1_CS  = cs_lane_1[i];
	L1_tuning_word = (L1_Freq - freq_range[i])/ step_size;

	int j = freq_range_max;
	for(;L2_Freq < freq_range[j];j--);			// determine upper limit of frequency range for Lane 2
	L2_sel = sel_lane_2[j];
	L2_CS  = cs_lane_2[j];
	L2_tuning_word = (L2_Freq - freq_range[j])/ step_size;

	/*	Write sequence
		Completed for: Filter_path_0, Filter_path_1, atten_1_val, atten_2_val, switch
			- Select Lines
			- Data to Transmit
			- Data Length (8 default)
			- TX Strobe
		System will take care of programming sequence once 'TX Enable' strobe is pulsed
	*/

	// Superpose VCNTRL Lines --> L2_sel contains MSB data

	vcntrl = (L1_sel << 2) | L2_sel;		// concatenate bits together

	// Print everything out just to make sure
	uprintf("VCntrl: %lu", vcntrl);
	uprintf("L1_sel: %lu", L1_sel);
	uprintf("L2_sel: %lu", L2_sel);
	uprintf("atten_1_val: %lu", atten_1_val);
	uprintf("atten_2_val: %lu", atten_2_val);
	uprintf("L1_tuning_word: %lu", L1_tuning_word);
	uprintf("L2_tuning_word: %lu", L2_tuning_word);
	uprintf("L1_CS: %lu", L1_CS);
	uprintf("L2_CS: %lu", L2_CS);

	if(p_switch == 1)
	{
		// filter path 1
	    // set and write RF board SPI/shifter parameters
		rf_board_tx_data     = L1_tuning_word;
		rf_board_tx_data_len = 8;
		rf_board_sel_bits    = L1_CS;
		set_rf_board_tx_info(rf_board_tx_data, rf_board_tx_data_len, rf_board_sel_bits);
		// strobe kickoff bit
		reg_write(ADDR_WR_RF_BOARD_GO_STRB, 0x01);
		usleep(f_div*20);															// NOTE: THIS IS A BAD WAY OF DOING THINGS...
		// wait for write to complete (checking busy signal 1 -> 0)
		while(reg_read(ADDR_RD_RF_BOARD_STATUS)) usleep(10);
		// reset kickoff strobe
		reg_write(ADDR_WR_RF_BOARD_GO_STRB, 0x00);
	}
	else if(p_switch == 2)
	{
		// filter_path_2 (same data flow as filter path 1)
		rf_board_tx_data     = L2_tuning_word;
		rf_board_tx_data_len = 8;
		rf_board_sel_bits    = L2_CS;
		set_rf_board_tx_info(rf_board_tx_data, rf_board_tx_data_len, rf_board_sel_bits);
		reg_write(ADDR_WR_RF_BOARD_GO_STRB, 0x01);
		usleep(f_div*20);
		// wait for write to complete (checking busy signal 1 -> 0)
		while(reg_read(ADDR_RD_RF_BOARD_STATUS)) usleep(10);
		// reset kickoff strobe
		reg_write(ADDR_WR_RF_BOARD_GO_STRB, 0x00);
	}
	else if(p_switch == 3)
	{
		// attenuator 1
		rf_board_tx_data     = atten_1_val;
		rf_board_tx_data_len = 6;
		rf_board_sel_bits    = cs_atten_1;
		set_rf_board_tx_info(rf_board_tx_data, rf_board_tx_data_len, rf_board_sel_bits);
		reg_write(ADDR_WR_RF_BOARD_GO_STRB, 0x01);
		usleep(f_div*20);
		// wait for write to complete (checking busy signal 1 -> 0)
		while(reg_read(ADDR_RD_RF_BOARD_STATUS)) usleep(10);
		// reset kickoff strobe
		reg_write(ADDR_WR_RF_BOARD_GO_STRB, 0x00);
	}
	else if(p_switch == 4)
	{
		// attenuator 2
		rf_board_tx_data     = atten_1_val;
		rf_board_tx_data_len = 6;
		rf_board_sel_bits    = cs_atten_2;
		set_rf_board_tx_info(rf_board_tx_data, rf_board_tx_data_len, rf_board_sel_bits);
		reg_write(ADDR_WR_RF_BOARD_GO_STRB, 0x01);
		usleep(f_div*20);
		// wait for write to complete (checking busy signal 1 -> 0)
		while(reg_read(ADDR_RD_RF_BOARD_STATUS)) usleep(10);
		// reset kickoff strobe
		reg_write(ADDR_WR_RF_BOARD_GO_STRB, 0x00);
	}
	else if(p_switch == 5)
	{
		// switch config
		rf_board_tx_data     = vcntrl;
		rf_board_tx_data_len = 4;
		rf_board_sel_bits    = cs_vcntrl;
		set_rf_board_tx_info(rf_board_tx_data, rf_board_tx_data_len, rf_board_sel_bits);
		reg_write(ADDR_WR_RF_BOARD_GO_STRB, 0x01);
		usleep(f_div*20);
		// wait for write to complete (checking busy signal 1 -> 0)
		while(reg_read(ADDR_RD_RF_BOARD_STATUS)) usleep(10);
		// reset kickoff strobe
		reg_write(ADDR_WR_RF_BOARD_GO_STRB, 0x00);
	}
	return 0;
}

void round_attenuation(double* prog_atten, uint8_t* atten_1, uint8_t* atten_2)
{
	double const max_attn = 63;
	double const atten_vals[] 	= {0.0, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 31.5};
	int select_values			= 8;
	// Programming the attenuators requires a 6 bit string - See data sheet Analog Devices - HMC1122
	uint8_t const atten_string[] = {0x3F, 0x3E, 0x3D, 0x3B, 0x37, 0x2F, 0x1F, 0x00};

	if( (*prog_atten) >= max_attn)
	{
		*atten_1 = 0x00; 			// Highest attenuation values - 31.5 dB each
		*atten_2 = 0x00;
		*prog_atten = max_attn;		// 63dB attenuation
	}
	else
	{
		// Select the first bit stream for Atten_1
		int j = 0;
		for(;atten_vals[j] <= (*prog_atten) && j < select_values ;j++);
		*atten_1 = atten_string[j-1];

		// Use selected value for Atten_1 to determine how much attenuation needed for Atten_2
		int i = 0;
		for(; (atten_vals[i] + atten_vals[j-1]) <= (*prog_atten) && i < select_values ;i++);
		*atten_2 = atten_string[i-1];

		// Return total attenuation to user for command response
		*prog_atten = atten_vals[i-1] + atten_vals[j-1];
	}
}

void set_rf_board_tx_info(uint32_t tx_data, uint32_t tx_data_len, uint32_t sel_bits)
{
	// tx data vector is all of one register
	reg_write(ADDR_WR_RF_BOARD_TX_DATA, tx_data);
	reg_write(ADDR_WR_RF_BOARD_DATA_LEN, tx_data_len);
	reg_write(ADDR_WR_RF_BOARD_SPI_SEL, sel_bits);
}
