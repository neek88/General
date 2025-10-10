############################################
### These functions are no longer needed ###
############################################

def write_coe_file(self, file_name):
    file1 = open(file_name,"w")
    file1.write("memory_initialization_radix=16;\n")
    file1.write("memory_initialization_vector= ")

    for i in self.divisor_table: 
        strHex = "%0.4X" % i
        file1.write(" ")
        file1.write(strHex)
    file1.write(";")
    file1.close()

## multiply data together by using the divisor array
def fpga_frac_mult_pwrtwo(self,input_val, kernel_array):
    # divisor array example: [16,-32, 64, 128, -256]
    val = 0
    for div in kernel_array:
        val += int(input_val * 1/div)
    return val

## convert filter kernel to fractional power-of-two sum
def convert_kernel_pwrtwo(self,filter_kernel,pwr_range):

    pwr_two         = []
    pwr_two_kernel  = []
    pwr_two_fac     = []

    ## generate powers of two list
    for i in range(pwr_range-1):
        pwr_two.append(2**(i+1))

    ## generate power of two sum from pwr_two list
    for i in filter_kernel:
        sum = 0
        pwr_two_i = []
        for j in pwr_two:
            if( i > 0): # positive kernel values
                if( 1/j < i):
                    if(sum > i):              ## too high
                        sum -= (1/j)
                        pwr_two_i.append(-j)
                    elif(sum < i):            ## too low
                        sum += (1/j)
                        pwr_two_i.append(j)
                elif (1/j == i): # perfect power of two
                    sum = 1/j
                    pwr_two_i.append(j)
                    break
            elif (i < 0): # negative kernel values
                if(-1/j > i):
                    if(sum > i):              ## too low
                        sum += (-1/j)
                        pwr_two_i.append(-j)
                    elif(sum < i):            ## too high
                        sum -= (-1/j)
                        pwr_two_i.append(j)
                elif (-1/j == i): # perfect power of two
                    sum = -1/j
                    pwr_two_i.append(-j)
                    break

        # store captured info 
        pwr_two_fac.append(pwr_two_i)
        # append filter kernel array
        pwr_two_kernel.append(sum)

    return pwr_two_kernel,pwr_two_fac



#### Generate sinc and show FFT

## python utils
import matplotlib.pyplot as plt
import numpy as np
import math as m
import sig_util as signal

sig = signal.util()

f0 = 100
a = 2 * f0 
Ts = 1 / a 

Nt = 100            # periods of signal 
sample_factor = 50  # samples per period
total_len = Nt * sample_factor
sample_rate = f0 * sample_factor

## generate sinc 
time_range = Nt * Ts
r_t = np.linspace(0,time_range,total_len)
l_t = np.flip(r_t,0)                               
l_t = -l_t

sinc_t = np.array( list(l_t[0:total_len-1]) + list(r_t) )  
sinc_ex = np.sinc((a)*sinc_t)

sinc_ft = np.fft.fft(sinc_ex)
sinc_freq = np.fft.fftfreq(sinc_ex.size)
sinc_freq = sinc_freq * sample_rate  ## scale frequency axis by sample rate

## generate square wave 
boc_phase = 0
boc_factor = 1
chip_number = 10
chipping_rate = 1.024e6
boc_sample_factor = 50
boc_sample_rate = sample_factor * chip_number / 2
T_boc = 1 / (boc_factor * chipping_rate)  
boc_sample_len = chip_number * sample_factor
boc_time_len   = chip_number * T_boc

boc = sig.gen_boc_code(boc_phase, chip_number, sample_factor)
boc = np.array(boc)
boc_time = np.linspace(0, boc_time_len, chip_number*sample_factor)

boc_ft = np.fft.fft(boc)
boc_freq = np.fft.fftfreq(boc.size)
boc_freq = boc_freq * boc_sample_rate  ## scale frequency axis by sample rate

### Figure 1
plt.figure(1,figsize=(8,8))
## bandpass filter FFT
plt.subplot(2,1,1)
plt.plot(sinc_t, sinc_ex, 'b.')
plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

plt.subplot(2,1,2)
plt.plot(sinc_freq, sinc_ft.real, 'b.')
plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

### Figure 2
plt.figure(2,figsize=(8,8))
## bandpass filter FFT
plt.subplot(2,1,1)
plt.plot(boc_time, boc, 'b')
plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

plt.subplot(2,1,2)
plt.plot(boc_freq, boc_ft.real, 'b')
plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

plt.show()