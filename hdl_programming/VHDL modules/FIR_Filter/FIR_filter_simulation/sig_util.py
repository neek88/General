import numpy as np
import math as m
import gps as gp

### Notes: 
#    * We are using numpy arrays
#        - this way we can sum/ multiply them 
#            together element wise 
#        - they behave similar to MATLAB arrays
#        - how to convert ? 
#            list_1  = [a, b, c]
#            np_list = np.array(list_1) -> ([a, b, c])

class util: 
    
    ##########################
    ### Global Static Data ###
    ##########################

    ############################
    ### Function definitions ###
    ############################

    # less than 
    def SMLR(self,n,m):
        if(n<m): return n
        else:    return m

    # greater than
    def GRTR(self,n,m): 
        if(n>m): return n 
        else:    return m

    ## init the object with a divisor table given signal-data resolution
    def __init__(self,Nr=16):

        # instance variables
        self.Nr = Nr

    def down_sample_signal(self,signal,Nds):
        # down sample signal by down-sample factor (Nds)
        signal_ds = []
        for i in range(len(signal)):
            if (i % Nds == 0): signal_ds.append(signal[i])
        return signal_ds

    def down_sample_split_path(self,signal,Nds):
        
        #########################
        # s8,  s4, s0  ->  path 1
        # s9,  s5, s1  ->  path 2
        # s10, s6, s2  ->  path 3
        # s11, s7, s3  ->  path 4
        #########################

        # empty list to hold path lists
        s_ds = []
        
        # for each path, a new 'empty' list is appended
        for path in range(Nds):
            s_ds.append(list([]))   

        # run through signal list, each path gets one sample
        # then, go back to first path
        for path in range(Nds):
            for s in range(len(signal)):
                if(s % Nds == path): s_ds[path].append(signal[s])
        return s_ds

    
    def scale_signal(self,signal,resolution):
        ## determine scale factor and scale the signal
        scale_factor = (2 ** (resolution-1))

        ## keep signal inside of signed power-of-two range
        for idx in range(len(signal)):
            signal[idx] = int(signal[idx]*scale_factor)
            if(signal[idx] > scale_factor-1): signal[idx] = scale_factor-1
            elif(signal[idx] < -scale_factor): signal[idx] = -scale_factor

    # Forces  (boc_sampling_rate), (carrier_list_length), and (L1_PRN_MULT * sampling_factor) 
    #   to be integer values by changing the effective sampling rate 
    def adjust_sample_rate(self,sampling_factor, f0, chipping_rate, boc_factor, prn_factor, chip_number):

        f0_prn = f0/ (chipping_rate * prn_factor)           # ratio of f0 to PRN code chip rate
        sr_int_flag = False 
        cr_len_flag = False 
        ca_stretch_flag = False 
        
        while(1):
            sr_boc = sampling_factor * f0_prn / boc_factor             # BOC sampling rate 
            carrier_len = f0_prn * chip_number * sampling_factor       # carrier list length 
            ca_stretch  = f0_prn * sampling_factor                     # C/A code stretching factor 
            boc_len = sr_boc * boc_factor * chip_number                # BOC list length (for reference)            
            
            # Check if above values are integers 
            sr_int_flag = (sr_boc == m.ceil(sr_boc))
            cr_len_flag = (carrier_len == m.ceil( carrier_len) )
            ca_stretch_flag  = (ca_stretch  == m.ceil(ca_stretch))
            
            if(sr_int_flag and cr_len_flag and ca_stretch_flag):
                return int(sr_boc),int(sampling_factor)
            else:
                sampling_factor += 1

    # create C/A code array, stretched to length of carrier
    def generate_ca_code(self,chip_number, cycles_per_chip, sample_factor):
        
        # Generate GPS C/A Code 
        ca = gp.generate_prn(1,chip_number)

        # Stretch C/A code out by factor of length difference to carrier 
        # chip length: cycles_per_chip * sample_rate
        c_a = []
        for i in ca:
            for j in range(int(cycles_per_chip*sample_factor)):
                c_a.append(i)
        return c_a
    
    # create C/A code array, stretched to length of carrier
    def gen_ca_code(self,chip_number, prn_sample_factor):
        
        # Generate GPS C/A Code 
        ca = gp.generate_prn(1,chip_number)

        # Stretch C/A code out by factor of length difference to carrier 
        # chip length: cycles_per_chip * sample_rate
        c_a = []
        for i in ca:
            for j in range(int(prn_sample_factor)):
                c_a.append(i)
        return c_a

    def gen_boc_code(self, boc_phase, boc_chip_number, boc_sample_factor):
        # generate boc +1/ -1 signal
        boc_l = []
        for i in range(boc_chip_number):
            if(boc_phase == 0):     # sin phase (start at -1)
                if(i % 2 == 0):
                    boc_l.append(-1)
                else:
                    boc_l.append(1)
            else:                   # cosine phase (start at +1)
                if(i % 2 == 0):
                    boc_l.append(1)
                else:
                    boc_l.append(-1)
        # stretch by boc_sample_factor
        boc = []
        for i in boc_l:
            for j in range(int(boc_sample_factor)):
                boc.append(i)
        return boc


    # convert binary (1/0) square wave to (+1/ -1)
    def conv_square(self,x_n):
        # return sign of original waveform
        x_n = np.sign(x_n)

        # Fix the zero values in the waveform  
        prev = 0
        for i in range(len(x_n)):
            curr = x_n[i]
            if(curr == 0 and prev == 1):
                x_n[i] = 1
            elif(curr == 0 and prev == -1):
                x_n[i] = -1
            elif(curr == 0 and prev == 0):
                x_n[i] = 1
            prev = curr 
        
        return x_n

    # convert the kernel to power-of-two fractional representation
    def discretize_kernel(self,filter_kernel):

        Ndy = 30          ## proper scaling resolution
        mult = pow(2,Ndy) - 1

        disc_kernel = []
        for i in range(len(filter_kernel)):
            disc_kernel.append( m.floor(filter_kernel[i] * mult) / pow(2,Ndy) )
            #print("mult: ", mult, "filter_kernel: ",filter_kernel[i],"disc_kernel: ",disc_kernel[i]) 

        return disc_kernel

    # create filter kernel multiples
    def generate_filt_mult(self,kernel):

        Ndy = 2 * (self.Nr - 1)
        # invert filter kernel / get indicies
        kern_m = []
        for i in range(len(kernel)):
            kern_m.append(m.floor(kernel[i] * ((2**Ndy)-1) ))
        
        return kern_m

    def fpga_fractional_mult(self, x_n, y_m):
        # -  We have a 16-bit number (x_n) being divided by upto a 
        #     15 bit number (y_m). The technique here is to multiply
        #     our input data by (2^30 -1)/ (y_m), then right shift by 30
        # - multiplying a 16 bit number by a 30 bit number produces a 46 bit
        #     number. Right shifting a 46 bit number by 30 produces a 16 bit number
        # - x / y = x * (1/y) = ( x * [(2^Ndy - 1) / y] ) >> Ndy

        # determine multiplier for input sample
        Nd = 15       ## max right shift for samples
        Ndy = 2 * Nd            ## proper scaling resolution
        
        y_i = m.floor(y_m *  (pow(2,Ndy) - 1))

        ## compute multiplication, followed by right shift 
        res = int(x_n * y_i) >> Ndy 
        #print("x:",x_n," y:",y_m, " y_i:",y_i, " res: ",res) 
        return res 

    # convolve two signals of length 'n' and 'm'
    # y_m is 'flipped' and shifted across x_n
    def convolve(self,x_n, y_m):
        n = len(x_n)
        m = len(y_m)

        OVERLAP_MAX = self.SMLR(n,m)
        OVERLAP_HOLD = self.GRTR(n,m)-self.SMLR(n,m)+1

        # keep track of state of waveform overlaps
        overlap = 0
        overlap_flag = 0
        overlap_hold_cnt = 0

        # starting index of array 'x'
        omi_x = 0
        # ending index of array 'y'
        omi_y = 0

        # result is of length N + M - 1
        conv = np.zeros(n+m-1)

        # are we in overlap state? 
        for i in range(len(conv)):

            # When we reach overlap state, we've already 
            #  calculated '1' overlap term, so reduce overlap_hold_cnt by '1'
            if(overlap == OVERLAP_MAX):
                if(overlap_hold_cnt < OVERLAP_HOLD-1):
                    overlap_flag = 1
                    overlap_hold_cnt += 1
                else:   # passed overlap_max ? 
                    overlap_flag = -1

            # count until overlap flag is set
            if(overlap_flag == 0): 
                overlap += 1
            elif(overlap_flag == -1):
                overlap -= 1

            for j in range(overlap):
                # multiply array indicies starting at end of y_m and 
                #  beginning of x_n
                #                     <-- *      
                #   [0][1][2][3][4][5][6][7]            x_n[]
                #         [7][6][5][4][3][2][1][0]      y_m[]
                #                     <-- *  
                conv[i] += (x_n[omi_x-j] * y_m[omi_y-overlap+1+j])

            # incriment starting index of array-x
            if( omi_x < (n-1)):
                omi_x += 1 
            # incriment ending index of array-y
            if( omi_y < (m-1)):
                omi_y += 1

        return conv

    # - convolve two signals of length 'n' and 'm'
    #   h_m is 'flipped' and shifted across x_n
    # - fractional multiplication is done how 
    #   an FPGA would do it through power of two
    #   sum approximation
    # - h_m is assumed to be 'kernel' getting
    #   converted to power of two
    def fpga_convolve(self, x_n, h_m):
        n = len(x_n)
        m = len(h_m)

        # ## invert kernel values
        # hm_i = self.inv_kernel(h_m)

        OVERLAP_MAX = self.SMLR(n,m)
        OVERLAP_HOLD = self.GRTR(n,m)-self.SMLR(n,m)+1

        # keep track of state of waveform overlaps
        overlap = 0
        overlap_flag = 0
        overlap_hold_cnt = 0

        # starting index of array 'x'
        omi_x = 0
        # ending index of array 'h'
        omi_h = 0

        # result is of length N + M - 1
        conv = np.zeros(n+m-1)

        # are we in overlap state? 
        for i in range(len(conv)):

            # When we reach overlap state, we've already 
            #  calculated '1' overlap term, so reduce overlap_hold_cnt by '1'
            if(overlap == OVERLAP_MAX):
                if(overlap_hold_cnt < OVERLAP_HOLD-1):
                    overlap_flag = 1
                    overlap_hold_cnt += 1
                else:   # passed overlap_max ? 
                    overlap_flag = -1

            # count until overlap flag is set
            if(overlap_flag == 0): 
                overlap += 1
            elif(overlap_flag == -1):
                overlap -= 1

            for j in range(overlap):
                # multiply array indicies starting at end of n_n and 
                #  beginning of k_m
                #                     <-- *      
                #   [0][1][2][3][4][5][6][7]            x_n[]
                #         [7][6][5][4][3][2][1][0]      k_m[]
                #                     <-- *  
                conv[i] += self.fpga_fractional_mult(x_n[omi_x-j], h_m[omi_h-overlap+1+j])

            # incriment starting index of array-x
            if( omi_x < (n-1)):
                omi_x += 1 
            # incriment ending index of array-y
            if( omi_h < (m-1)):
                omi_h += 1

        return conv