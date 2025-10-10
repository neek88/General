import matplotlib.pyplot as plt
import sig_util as sig
import numpy as np
import math as m
import sig_util as sig
import filter_gen as filt
import bpsk_gen as bpsk

# useful objects
pi = np.pi
s = sig.util()
b = bpsk.bpsk()
f = filt.filter()

###################
### User Params ###
###################

N_periods = 1                         ## total number of periods of waveform
N_paths = 4                           ## number of paths
f0 = 100
T0 = 1/ f0

## total samples of waveform 
## MUST BE divisible by N_paths
Ns = 32                             

##
sample_factor = int(Ns/ N_periods)    ## number of samples per periods
sample_rate = f0 * sample_factor      ## number of samples per second
##
Nk = sample_factor                    ## total number of samples for the filter kernel
Nds = int(Ns/ N_paths)                ## samples in 1/4 broken waveform
Ndk = int(Nk/ N_paths)                ## samples in 1/4 broken filter kernel

#######################
### Signal Creation ###
#######################

## sinusoidal signal
sig_time_range = T0 * N_periods
time = np.linspace(0,T0 * N_periods, Ns)
sig_phase_arg = 2 * pi * f0 * time
sinu = np.sin(sig_phase_arg)

# create moving average kernel
# kernel length is one period of 'sinu'
kernel_time_range = T0
kernel_time = np.linspace(0,T0,Nk)
kern_phase_arg = 2 * pi * f0 * kernel_time
kernel = np.ones(Nk)
kernel = kernel/ sum(kernel)

## determine length of convolution signals + time arguments
# length of convolution between signal and kernel
conv_len = Ns + Nk - 1
conv_time_range = sig_time_range + kernel_time_range

# convolve signals together
conv_time = np.linspace(0,conv_time_range,conv_len)
conv = np.convolve(sinu,kernel)

########################################################
### Down sampled signal + kernel (padded with zeros) ###
########################################################

# down-sampled-padded signals
sa_dp = np.zeros(Ns)
sb_dp = np.zeros(Ns)
sc_dp = np.zeros(Ns)
sd_dp = np.zeros(Ns)

# populate down-sampled signal arrays
for idx in range(len(sinu)):
  if(idx % N_paths == 0): sa_dp[idx] = sinu[idx]
  if(idx % N_paths == 1): sb_dp[idx] = sinu[idx]
  if(idx % N_paths == 2): sc_dp[idx] = sinu[idx]
  if(idx % N_paths == 3): sd_dp[idx] = sinu[idx]

# convolve down-sampled signals with kernel
sa_dp_conv = np.convolve(sa_dp,kernel)
sb_dp_conv = np.convolve(sb_dp,kernel)
sc_dp_conv = np.convolve(sc_dp,kernel)
sd_dp_conv = np.convolve(sd_dp,kernel)

sb_conv = sa_dp_conv+sb_dp_conv+sc_dp_conv+sd_dp_conv

####################################
### Down sampled signal + kernel ###
####################################

# down-sampled signals
sa_ds = []
sb_ds = []
sc_ds = []
sd_ds = []

for i in range(len(sinu)):
  if(i % N_paths == 0): sa_ds.append(sinu[i])
  if(i % N_paths == 1): sb_ds.append(sinu[i])
  if(i % N_paths == 2): sc_ds.append(sinu[i])
  if(i % N_paths == 3): sd_ds.append(sinu[i])

# down sample kernel by factor of number-of-paths
k_ds = s.down_sample_signal(kernel,N_paths)
k_ds = np.array(k_ds)

# convolve broken-unpacked signals with kernel
sa_ds_conv = np.convolve(sa_ds, k_ds)
sb_ds_conv = np.convolve(sb_ds, k_ds)
sc_ds_conv = np.convolve(sc_ds, k_ds)
sd_ds_conv = np.convolve(sd_ds, k_ds)

# length of convolution between down-sampled signal / kernel
conv_ds_len = Nds + Ndk - 1
sig_ds_time_range = sig_time_range/ N_paths
conv_ds_time_range = (sig_time_range+kernel_time_range)/N_paths
kernel_ds_time_range = kernel_time_range/ N_paths

# time arrays for down-sampled signal / down-sampled convolution
ds_time = np.linspace(0,sig_ds_time_range, Nds)
conv_ds_time = np.linspace(0,conv_ds_time_range,conv_ds_len)
k_ds_t = np.linspace(0,kernel_ds_time_range,Ndk)

# recombine
ds_conv_alt = np.zeros(conv_len)

print("kn len:",len(k_ds)," sa_ds len:",len(sa_ds)," sa_ds_conv len:",len(sa_ds_conv))

Np = N_paths
for i in range(Nds + Ndk):
  if(i == 0):
    ds_conv_alt[i] = sa_ds_conv[i] + 0
    ds_conv_alt[i+1] = sa_ds_conv[i] + sb_ds_conv[i] + 0
    ds_conv_alt[i+2] = sa_ds_conv[i] + sb_ds_conv[i] + sc_ds_conv[i] + 0
    ds_conv_alt[i+3] = sa_ds_conv[i] + sb_ds_conv[i] + sc_ds_conv[i] + sd_ds_conv[i]
  elif(i == Nds+Ndk-1):
    ds_conv_alt[Np*i] = 0 + sb_ds_conv[i-1] + sc_ds_conv[i-1] + sd_ds_conv[i-1]
    ds_conv_alt[Np*i+1] = 0 + sc_ds_conv[i-1] + sd_ds_conv[i-1]
    ds_conv_alt[Np*i+2] = 0 + sd_ds_conv[i-1]
  else:   
    ds_conv_alt[Np*i] = sa_ds_conv[i] + sb_ds_conv[i-1] + sc_ds_conv[i-1] + sd_ds_conv[i-1]
    ds_conv_alt[Np*i+1] = sa_ds_conv[i] + sb_ds_conv[i] + sc_ds_conv[i-1] + sd_ds_conv[i-1]
    ds_conv_alt[Np*i+2] = sa_ds_conv[i] + sb_ds_conv[i] + sc_ds_conv[i] + sd_ds_conv[i-1]
    ds_conv_alt[Np*i+3] = sa_ds_conv[i] + sb_ds_conv[i] + sc_ds_conv[i] + sd_ds_conv[i]

################
### Plotting ###
################

## Figure 1
plt.figure(1,figsize=(8, 8))
## single convolution
plt.subplot(3,1,1)
plt.title("signal")
plt.plot(time, sinu, 'b.')
## kernel
plt.subplot(3,1,2)
plt.title("kernel")
plt.plot(kernel_time,kernel,'r.')
## conv result
plt.subplot(3,1,3)
plt.title("signal ** kernel")
plt.plot(conv_time,conv,'g')

## Figure 2
plt.figure(2,figsize=(8, 8))
## down-sampled-padded signals
plt.subplot(2,2,1)
plt.plot(time, sa_dp, 'b.')
plt.subplot(2,2,2)
plt.plot(time, sb_dp,'r.')
plt.subplot(2,2,3)
plt.plot(time, sc_dp,'g.')
plt.subplot(2,2,4)
plt.plot(time, sd_dp,'m.')

## Figure 3
plt.figure(3,figsize=(8, 8))
## conv result
plt.subplot(2,2,1)
plt.title("down-sampled-padded signal ** kernel")
plt.plot(ds_time, sa_ds, 'b.')
plt.subplot(2,2,2)
plt.plot(ds_time, sb_ds,'r.')
plt.subplot(2,2,3)
plt.plot(ds_time, sc_ds,'g.')
plt.subplot(2,2,4)
plt.plot(ds_time, sd_ds,'m.')

## Figure 4
plt.figure(4,figsize=(8, 8))
## conv result
plt.subplot(2,2,1)
plt.title("down-sampled signal ** down-sampled kernel")
plt.plot(conv_ds_time, sa_ds_conv, 'b.')
plt.subplot(2,2,2)
plt.plot(conv_ds_time, sb_ds_conv,'r.')
plt.subplot(2,2,3)
plt.plot(conv_ds_time, sc_ds_conv,'g.')
plt.subplot(2,2,4)
plt.plot(conv_ds_time, sd_ds_conv,'m.')

## Figure 5
plt.figure(5,figsize=(8, 8))
plt.subplot(2,1,1)
plt.plot(conv_time, ds_conv_alt, 'm.')
plt.subplot(2,1,2)
plt.plot(k_ds_t, k_ds, 'g.')

plt.show()