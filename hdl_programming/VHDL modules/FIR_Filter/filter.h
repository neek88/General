#include "lusi.h"
#include "platform.h"
#include <stdint.h>
#include <stdlib.h>
#include <math.h>

#ifndef _FILTER_H_
#define _FILTER_H_

// samples in kernel
#define KERNEL_LEN		(31)

// Digital bandpass filter
#define DSP_FILT_BASE					(XPAR_FIR_FILT_0_BASEADDR)

// RF filter board controller addresses - these derive from the AXI reg file at the top level of the block design
#define FILT_BASE						(XPAR_FILTER_DRIVER_0_BASEADDR)
#define ADDR_WR_RF_BOARD_TX_DATA        (FILT_BASE)
#define ADDR_WR_RF_BOARD_DATA_LEN		(FILT_BASE + 0x04)
#define ADDR_WR_RF_BOARD_FREQ_DIV		(FILT_BASE + 0x08)
#define ADDR_WR_RF_BOARD_SPI_SEL		(FILT_BASE + 0x0C)
#define ADDR_WR_RF_BOARD_GO_STRB		(FILT_BASE + 0x10)
#define ADDR_RD_RF_BOARD_STATUS			(FILT_BASE + 0x20)


#define SMLR(n,m)		(n < m ? n : m)
#define GRTR(n,m)		(n > m ? n : m)

/*
 * @brief print an array to the screen
 */
void display_array(double* data, uint32_t length);

/*
 * @brief Generate a linear-stepped array with given end points and length
 */
double* linspace(double start, double end, uint32_t length);

/*
 * @brief creates a new array with reversed data order.
 * 		  original array is not affected
 */
double* flip_array(double* data, uint32_t length);

/*
 * @brief remove first and last data points from array
 */
double* remove_endpoints(double* data, uint32_t length);

/*
 * @brief combine two arrays together
 */
double* concat_array(double* s1, double* s2, uint32_t l1, uint32_t l2);

/*
 * @brief multiply two signals together, element wise
 */
double* multiply_a(double* s1, double* s2, uint32_t length);

/*
 * @brief scale every value of an array by given scalar
 */
void scale_a(double* signal, double scalar, uint32_t length);

/*
 * @brief scale every value of an array by given scalar
 */
void add_a(double* signal, double scalar, uint32_t length);

/*
 * @brief sum array elements
 */
double sum_a(double* data, uint32_t length);

/*
 * @brief compute sinc
 */
double sinc(double arg);

/*
 * @brief pass array to mathematical function as an argument
 */
double* trig_of(double(*op)(double), double* input, uint32_t len);

/*
 * @brief computes the convolution between two signals
 * 		  the second signal 's2' is flipped and shifted across 's1'
 */
double* convolve_signals(double* s1, double* s2, uint32_t l1, uint32_t l2);

/*
 * @brief convert kernel values into scaled value for loading into hardware
 */
int32_t* scale_kernel(double* kernel, uint32_t length, uint32_t scaling_res);

/*
 * @brief create low pass filter kernel of given cutoff freq/ sample count
 */
double* gen_lp_filter(double f0, uint32_t num_samples, double num_periods);

/*
 * @brief Generate DSP filter, and load it into kernel module on board
 */
void dsp_filter_generate(double fc, double bandwidth, uint32_t kernel_length);

/*
 * @public
 * @brief - Sets all required registers in 'spi_data_shifter' Block for RF board
 * @param[in] clk_div to control speed of SPI Bus, data string to send, length of data in bits, selector bits for particular SPI device
 */
void set_rf_board_tx_info(uint32_t tx_data, uint32_t tx_data_len, uint32_t sel_bits);

/* @public
 * @brief - rounds attenuation entered to nearest allowed value, prioritizing lower atten value
 * @param[in] desired attenuation
 * @retval calculated attenuator bit stream pointers
 */
void round_attenuation(double* entered_atten, uint8_t* atten0, uint8_t* atten1);

/* @public
 * @brief calculates filter programming bit streams, RF switch bit streams , and programs all devices (including attenuators) on Filter PCB through SPI drivers
 * @param[in] desired frequency for each lane , attenuation to be adjusted
 */
uint32_t lane_config(uint32_t* l1_freq, uint32_t* l2_freq, double* atten_setting, int p_switch, uint32_t f_div);

#endif /* _FILTER_H_ */
