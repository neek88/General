import matplotlib.pyplot as plt
import sig_util as sig
import numpy as np
import math as m
import sig_util as sig
import filter_gen as filt
import bpsk_gen as bpsk

## NOTES:
##   - sample_rate / f0 MUST be an integer (num samples per period)

# useful objects
pi = np.pi
s = sig.util()
b = bpsk.bpsk()
f1 = filt.filter()
f2 = filt.filter()

#######################
### Signal Creation ###
#######################

# custom params
f0 = 12.5e5        ## frequency of waveform
T0 = 1/ f0         ## period of waveform
N_paths = 8        ## number of paths/ number of 'generators'
N_periods = 50     ## how many periods in our waveform?

### digitals system down-sampled-convolution example
# digitals params
sample_clk = 100e6
sample_rate = sample_clk * N_paths
PLT_RANGE = int((sample_rate/f0)*25) 

sine, sine_t = b.generate_sine(f0,sample_rate,N_periods)
sine_time_range = T0 * N_periods
Ns = len(sine)
Nds = int(Ns/N_paths)                       ## samples in 1/N_paths broken waveform

# create bpfilter from filter object
Ns_dk = 31                                  ## number of samples for down-sampled (must be odd)
Ns_fk = Ns_dk * N_paths + 1                 ## number of samples for full kernel  (forced to be odd)
kernel, kernel_time = f1.gen_mv_avg_filt(Ns_fk,sample_rate)

Nk = len(kernel)                            ## samples in kernel
kernel_time_range = Ns_fk / sample_rate

print("signal len: ",len(sine), "kernel len: ",len(kernel))
print("center_freq: ",f0, "bpsk time range: ",sine_time_range)

## determine length of convolution signals + time arguments
# length of convolution between signal and kernel
conv_len = Ns + Nk - 1
conv_time_range = sine_time_range + kernel_time_range

# convolve signals together
conv_time = np.linspace(0,conv_time_range,conv_len)
conv = np.convolve(sine,kernel)

########################################################
### Down sampled signal + kernel (padded with zeros) ###
########################################################

# down-sampled-padded signals
s_dp = []
for i in range(N_paths): 
  s_dp.append(list(np.zeros(Ns)))

# populate down-sampled signal arrays
for path in range(N_paths):
  for idx in range(len(sine)):
    if(idx % N_paths == path): s_dp[path][idx] = sine[idx]

# convolve down-sampled signals with kernel
s_dp_conv = []
for path in range(N_paths):
  s_dp_conv.append(list(np.convolve(s_dp[path],kernel)))

# rebuild convolution output array
sb_conv = np.zeros(conv_len)
for path in range(N_paths):
  sb_conv = sb_conv + np.array(s_dp_conv[path])

print("conv_len= ",conv_len,"sb_conv len=",len(sb_conv))
print("s_dp_conv[pth] len=",len(s_dp_conv[0]), "kernel len= ",len(kernel))

####################################
### Down sampled signal + kernel ###
####################################

# down sample signal by splitting into 'N_paths' seperate paths
s_ds = s.down_sample_split_path(sine,N_paths)
#s_ds = np.array(s_ds)

# create down-sampled kernel bpfilter from fitler object
k_ds, k_ds_t = f2.gen_mv_avg_filt(Ns_dk,sample_rate/N_paths)
k_ds = k_ds / N_paths
Ndk = len(k_ds)

# convolve broken-unpacked signals with kernel
s_ds_conv = list()
for i in range(N_paths):
  s_ds_conv.append(list(np.convolve(s_ds[i],k_ds)))

# length of convolution between down-sampled signal / kernel
conv_ds_len = Nds + Ndk - 1
sig_ds_time_range = sine_time_range/ N_paths
conv_ds_time_range = (sine_time_range+kernel_time_range)/N_paths
kernel_ds_time_range = kernel_time_range/ N_paths

# time arrays for down-sampled signal / down-sampled convolution
ds_time = np.linspace(0,sig_ds_time_range, Nds)
conv_ds_time = np.linspace(0,conv_ds_time_range,conv_ds_len)
k_ds_t = np.linspace(0,kernel_ds_time_range,Ndk)

## Take FFT of both filters
## Take FFT of our bandpass filter
kernel_ft = np.abs(np.fft.fft(kernel))
kernel_freq = np.fft.fftfreq(kernel_ft.size)
kernel_freq *= f1.BP_SR     ## scale frequency axis by sample rate

kds_ft = np.abs(np.fft.fft(k_ds))
kds_freq = np.fft.fftfreq(kds_ft.size)
kds_freq *= f2.BP_SR      ## scale frequency axis by sample rate

# recombine
ds_conv_alt = np.zeros(conv_len)

print("kn len:",len(k_ds)," sa_ds len:",len(s_ds[0])," sa_ds_conv len:",len(s_ds_conv[0]))
print("Nds: ",Nds,"Ndk: ",Ndk)

prev_val = 0
Np = N_paths
for i in range(Nds + Ndk):
  if(i == 0):                   ## ramp up
    for path in range(N_paths):
      ds_conv_alt[i+path] = prev_val + s_ds_conv[path][i]
      prev_val = ds_conv_alt[i+path]
  elif(i < conv_ds_len):        ## center
    for path in range(N_paths):
      ds_conv_alt[Np*i+path] = -s_ds_conv[path][i-1] + s_ds_conv[path][i] + ds_conv_alt[Np*i+(path-1)]
      #prev_val = ds_conv_alt[Np*i+path]
  else:                         ## ramp down
    for path in range(N_paths):
      ds_conv_alt[Np*i+path] = -s_ds_conv[path][i-1] + ds_conv_alt[Np*i+(path-1)]
      #prev_val = ds_conv_alt[Np*i+path]

################
### Plotting ###
################

Nrows = int(N_paths/2)
Ncolumns = int(N_paths/ Nrows)
color = ["b.","r.","g.","m.","b.","r.","g.","m."]
## Figure 1
plt.figure(1,figsize=(8, 8))
## single convolution
plt.subplot(3,1,1)
plt.title("signal")
plt.plot(sine_t[0:PLT_RANGE], sine[0:PLT_RANGE], 'b')
## kernel
plt.subplot(3,1,2)
plt.title("kernel")
plt.plot(kernel_time,kernel,'r')
## conv result
plt.subplot(3,1,3)
plt.title("signal ** kernel")
plt.plot(conv_time[0:PLT_RANGE],conv[0:PLT_RANGE],'g')

## Figure 2
plt.figure(2,figsize=(8, 8))
plt.suptitle("down-sampled-padded input signals")
## down-sampled-padded signals
for i in range(N_paths):
  plt.subplot(Nrows,Ncolumns,i+1)
  plt.plot(sine_t[0:PLT_RANGE],s_dp[i][0:PLT_RANGE],color[i])

## Figure 3
plt.figure(3,figsize=(8, 8))
plt.suptitle("down-sampled-padded convolution")
## Down-sampled padded signal convolution result
for i in range(N_paths):
  plt.subplot(Nrows,Ncolumns,i+1)
  plt.plot(ds_time[0:PLT_RANGE],s_ds[i][0:PLT_RANGE],color[i])

## Figure 4
plt.figure(4,figsize=(8, 8))
plt.suptitle("down_sampled signals ** down_sampled kernel")
## down-sampled signal ** down-sampled kernel"
for i in range(N_paths):
  plt.subplot(Nrows,Ncolumns,i+1)
  plt.plot(conv_ds_time[0:PLT_RANGE],s_ds_conv[i][0:PLT_RANGE],color[i])

## Figure 5
## N-lane convolution reconstruction
## down-sampled filter kernel
plt.figure(5,figsize=(8, 8))
plt.suptitle("down_sampled conv. recombinations")
plt.subplot(2,1,1)
plt.plot(conv_time[0:PLT_RANGE], ds_conv_alt[0:PLT_RANGE], 'm')
plt.subplot(2,1,2)
plt.plot(k_ds_t, k_ds, 'g')

## Figure 6
# plt.figure(6,figsize=(8, 8))
# plt.subplot(2,1,1)
# plt.plot(kernel_freq, kernel_ft.real, 'm.')
# plt.subplot(2,1,2)
# plt.plot(kds_freq, kds_ft.real, 'g.')


plt.show()

## golden down-sampled convolution sum
## works for 4-lanes only
## use this as reference..
# Np = N_paths
# for i in range(Nds + Ndk):
#   if(i == 0):
#     ds_conv_alt[i] = s_ds_conv[0][i] + 0
#     ds_conv_alt[i+1] = s_ds_conv[0][i] + s_ds_conv[1][i] + 0
#     ds_conv_alt[i+2] = s_ds_conv[0][i] + s_ds_conv[1][i] + s_ds_conv[2][i] + 0
#     ds_conv_alt[i+3] = s_ds_conv[0][i] + s_ds_conv[1][i] + s_ds_conv[2][i] + s_ds_conv[3][i]
#   elif(i == conv_ds_len):
#     ds_conv_alt[Np*i]   = 0 + s_ds_conv[1][i-1] + s_ds_conv[2][i-1] + s_ds_conv[3][i-1]
#     ds_conv_alt[Np*i+1] = 0 + s_ds_conv[2][i-1] + s_ds_conv[3][i-1]
#     ds_conv_alt[Np*i+2] = 0 + s_ds_conv[3][i-1]
#   else:   
#     ds_conv_alt[Np*i]   = s_ds_conv[0][i] + s_ds_conv[1][i-1] + s_ds_conv[2][i-1] + s_ds_conv[3][i-1]
#     ds_conv_alt[Np*i+1] = s_ds_conv[0][i] + s_ds_conv[1][i]   + s_ds_conv[2][i-1] + s_ds_conv[3][i-1]
#     ds_conv_alt[Np*i+2] = s_ds_conv[0][i] + s_ds_conv[1][i]   + s_ds_conv[2][i]   + s_ds_conv[3][i-1]
#     ds_conv_alt[Np*i+3] = s_ds_conv[0][i] + s_ds_conv[1][i]   + s_ds_conv[2][i]   + s_ds_conv[3][i]