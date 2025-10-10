## python utils
import matplotlib.pyplot as plt
import numpy as np
import math as m
## our utils
import sig_util as sig
import filter_gen as bp
import bpsk_gen as bpsk

### Notes: 
#    * The goal here is to generate a BOC signal
#        at the base rate (BEFORE mixing), and pass
#        it through a digital FIR filter (band pass)
#            - x[n] ** h[n] = y[n]
#            - X[k] * H[k] = Y[k]
#
#    * We can achieve this through convolution, OR
#        we can calculate the FFT of each first, 
#        and then multiply the responses
#
#    * We will try a few different filters and
#        plot the results...

##############
### MACROS ###
##############
PLT_BPSK = 0
PLT_FILT = 1
PLT_BPSK_FILT = 1

###########################
### instantiate objects ###
###########################

f = bp.filter()
b = bpsk.bpsk()
s = sig.util()

#############################
### Generate BPSK signals ###
#############################
print("generating BPSK signals...")

# digitals params
sample_clk = 307.2e6
num_generators = 8

# custom params
# Note: f0 / chip_rate should be an integer
#   to produce a integer-length carrier
f0 = 10.24e6
chip_rate = 1.024e6
chip_number = 1024
prn_fac = 1
boc_fac = 1
boc_phase = 0
sample_factor = 6

## determine useful plotting bandwidth
BOC_BW = boc_fac * chip_rate 
PRN_BW = prn_fac * chip_rate
delta_BW = 25 * PRN_BW

## plotting time range for bpsk
BPSK_TR = int(b.custom_f0_prn_mult*sample_factor*20)

# custom bpsk signal
c_bpsk, c_bpsk_t = b.custom_bpsk(f0,sample_factor,chip_rate,chip_number,prn_fac,boc_fac,boc_phase)

###################################
### Generate HP/ LP/ BP filters ###
###################################
print("generating filters...")

## setup params
# setup our control parameters
f_c = 10e6       # center freq
BW = 10e6        # filter bandwidth
Nh = 2           # number of total periods of high-pass sinc function

## generate high/ low / band pass filters
bp_filt, bp_time = f.gen_bp_filt(f_c, BW, Nh, sample_factor)
lp_filt, lp_time = f.gen_lp_filt(f.f_cl, f.Nl, f.M_k)
hp_filt, hp_time = f.gen_hp_filt(f.f_ch, f.Nh, f.M_k)

#################################
### convolve bpsk + BP filter ###
#################################
print("filtering carrier...")

print("length of carrier= ",len(c_bpsk))
print("length of bp_filt= ",len(bp_filt))
## discretize kernel to tabulated fractions
bp_filt_disc = s.discretize_kernel(bp_filt)

## convolve the input signal with bandpass filter 
bpsk_bp_filt = np.convolve(c_bpsk, bp_filt)

## convolve the input signal with filter using FPGA convolve technique
bpsk_bp_filt_f = s.fpga_convolve(c_bpsk, bp_filt)

## determine filter kernel multipliers for FPGA
fpga_kernel = s.generate_filt_mult(bp_filt)
#print("fpga kernel mult's: ", fpga_kernel)


###########
### FFT ###
###########
print("calculating FFT's...")

### FFT of filters
## Take FFT of our low pass filter
lp_filt_ft = np.abs(np.fft.fft(lp_filt))
lp_filt_freq = np.fft.fftfreq(lp_filt_ft.size)
lp_filt_freq *= f.LP_SR       ## scale frequency axis by sample rate
LP_FR = 2 * f.f_cl            ## low pass frequency range

## Take FFT of our high pass filter 
hp_filt_ft = np.abs(np.fft.fft(hp_filt))
hp_filt_freq = np.fft.fftfreq(hp_filt_ft.size)
hp_filt_freq *= f.HP_SR       ## scale frequency axis by sample rate
HP_FR = 2 * f.f_ch            ## high pass frequency range

## Take FFT of our bandpass filter
bp_filt_ft = np.abs(np.fft.fft(bp_filt))
bp_filt_freq = np.fft.fftfreq(bp_filt_ft.size)
bp_filt_freq *= f.BP_SR     ## scale frequency axis by sample rate

### FFT of carrier and filtered carriers
## Take FFT of our new carrier wave 
bpsk_ft = np.fft.fft(c_bpsk)
bpsk_freq = np.fft.fftfreq(c_bpsk.size)
bpsk_freq = bpsk_freq * b.custom_sample_rate  ## scale frequency axis by sample rate

## Take FFT of filtered carrier
bpsk_bp_ft = np.fft.fft(bpsk_bp_filt)
bpsk_bp_freq = np.fft.fftfreq(bpsk_bp_filt.size)
bpsk_bp_freq = bpsk_bp_freq * b.custom_sample_rate  ## scale frequency axis by sample rate

# Take FFT of FPGA-filtered carrier
bpsk_bp_fpga_ft = np.fft.fft(bpsk_bp_filt_f)
bpsk_bp_fpga_freq = np.fft.fftfreq(bpsk_bp_fpga_ft.size)
bpsk_bp_fpga_freq = bpsk_bp_fpga_freq * b.custom_sample_rate  ## scale frequency axis by sample rate

################
### Plotting ###
################
print("plotting...")

plt.rcParams['agg.path.chunksize'] = 10000

if(PLT_FILT):

  ### Figure 1
  plt.figure(1,figsize=(8,8))
  ## BPSK low pass kernel
  plt.subplot(2,2,1)
  plt.plot(lp_time, lp_filt, 'k')
  plt.xlabel("time(s)")
  plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

  ## BPSK high pass kernel
  plt.subplot(2,2,2)
  plt.plot(hp_time,hp_filt,'r')
  plt.xlabel("time(s)")
  plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

  ## BPSK low pass FT
  plt.subplot(2,2,3)
  plt.plot(lp_filt_freq,lp_filt_ft.real,'k.')
  plt.xlabel("frequency(Hz)")
  plt.xlim(0,LP_FR)
  plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

  ## BPSK high pass FT
  plt.subplot(2,2,4)
  plt.plot(hp_filt_freq,hp_filt_ft.real,'r.')
  plt.xlabel("frequency(Hz)")
  plt.xlim(0,HP_FR)
  plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

  ### Figure 2
  plt.figure(2,figsize=(8,8))
  ## bandpass filter FFT
  plt.subplot(3,1,1)
  plt.plot(bp_filt_freq, bp_filt_ft.real, 'b.')
  plt.xlabel("frequency(Hz)")
  plt.xlim(-2*LP_FR,2*LP_FR)
  plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

  ## bandpass filter kernel
  plt.subplot(3,1,2)
  plt.plot(bp_time,bp_filt, 'k')
  plt.xlabel("time(s)")
  plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

  ## bandpass filter kernel - pwr of two
  plt.subplot(3,1,3)
  plt.plot(bp_time,bp_filt_disc, 'r')
  plt.xlabel("time(s)")
  plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

if(PLT_BPSK):
  ## Figure 3
  plt.figure(3,figsize=(8, 8))

  ## BPSK
  plt.subplot(2,1,1)
  plt.plot(c_bpsk_t[0:BPSK_TR],c_bpsk[0:BPSK_TR],'r')
  plt.xlabel("time (s)")
  plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

  ## C/A Code 
  # plt.subplot(3,1,3)
  # plt.plot(c_bpsk_t[0:BPSK_TR],c_a[0:BPSK_TR],'r')
  # plt.xlabel("time (s)")
  # plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

if(PLT_BPSK_FILT):
  ### Figure 4
  plt.figure(4,figsize=(8, 8))

  ## BPSK FFT
  plt.subplot(3,1,1)
  plt.semilogy(bpsk_freq, bpsk_ft.real, 'b')
  #plt.plot(bpsk_ft, bpsk_ft.real, 'b.')
  plt.xlim(-(f0+delta_BW),f0 + delta_BW)
  #plt.ylim(1e-3,1e6)
  plt.xlabel("frequency (Hz)")
  plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

  ## BPSK filtered FFT
  plt.subplot(3,1,2)
  plt.semilogy(bpsk_bp_freq, bpsk_bp_ft.real, 'b')
  #plt.plot(bpsk_bp_freq, bpsk_bp_ft.real, 'b.')
  plt.xlim(-(f0+delta_BW),f0 + delta_BW)
  #plt.ylim(1e-3,1e6)
  plt.xlabel("frequency (Hz)")
  plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

  # BPSK FPGA filtered FFT
  plt.subplot(3,1,3)
  plt.semilogy(bpsk_bp_fpga_freq, bpsk_bp_fpga_ft.real, 'b')
  #plt.plot(freq, ft.real, 'b.')
  plt.xlim(-(f0+delta_BW),f0 + delta_BW)
  #plt.ylim(1e-3,1e6)
  plt.xlabel("frequency (Hz)")
  plt.ticklabel_format(axis='x', style='sci', scilimits=(0,0))

## Show
if(PLT_BPSK or PLT_FILT or PLT_BPSK_FILT):
  plt.show()