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

f0 = 100
T0 = 1/ f0
N_periods = 5                         ## total number of periods of waveform
N_paths = 8                           ## number of paths (Ns/ Npaths must be an integer)

## total samples of waveform 
## MUST BE divisible by N_paths
Ns = 128

##
sample_factor = int(Ns/ N_periods)    ## number of samples per periods
sample_rate = f0 * sample_factor      ## number of samples per second
##
Nk = sample_factor                    ## total number of samples for the filter kernel
Nds = int(Ns/N_paths)                 ## samples in 1/4 broken waveform
Ndk = int(Nk/N_paths)                 ## samples in 1/4 broken filter kernel

#######################
### Signal Creation ###
#######################

## sinusoidal signal
sig_time_range = T0 * N_periods
time = np.linspace(0,T0*N_periods,Ns)
sig_phase_arg = 2 * pi * f0 * time
sinu = np.sin(sig_phase_arg)

# create moving average kernel
# kernel length is one period of 'sinu'
# kernel_time_range = T0
# kernel_time = np.linspace(0,T0,Nk)
# kern_phase_arg = 2 * pi * f0 * kernel_time
# kernel = np.ones(Nk)
# kernel = kernel/ sum(kernel)

# testing
# create bpfilter from object
fc = 200
BW = 100
Nhp = 4
kernel, kernel_time = f.gen_bp_filt(fc,BW,Nhp,sample_factor)
Nk = len(kernel)
kernel_time_range = 2*f.Nl*(1/fc) 
## done testing

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
s_dp = []
for i in range(N_paths): 
  s_dp.append(list(np.zeros(Ns)))

# populate down-sampled signal arrays
for path in range(N_paths):
  for idx in range(len(sinu)):
    if(idx % N_paths == path): s_dp[path][idx] = sinu[idx]

# convolve down-sampled signals with kernel
s_dp_conv = []
for path in range(N_paths):
  s_dp_conv.append(list(np.convolve(s_dp[path],kernel)))

# rebuild convolution output array
sb_conv = np.zeros(conv_len)
for path in range(N_paths):
  sb_conv = sb_conv + np.array(s_dp_conv[path])

print("conv_len= ",conv_len,"sb_conv len=",len(sb_conv))
print("s_dp_conv[pth] len=",len(s_dp_conv[0]), "kernel len= ", Nk)

####################################
### Down sampled signal + kernel ###
####################################

# down sample signal by splitting into 'N_paths' seperate paths
s_ds = s.down_sample_split_path(sinu, N_paths)
s_ds = np.array(s_ds)

# down sample kernel by factor of number-of-paths
# create bpfilter from object
k_ds, k_ds_t = f.gen_bp_filt(200,100,4,sample_factor/N_paths)
Ndk = len(k_ds)


# convolve broken-unpacked signals with kernel
s_ds_conv = list()
for i in range(N_paths):
  s_ds_conv.append(list(np.convolve(s_ds[i],k_ds)))

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

print("kn len:",len(k_ds)," sa_ds len:",len(s_ds[0])," sa_ds_conv len:",len(s_ds_conv[0]))
print("Nds: ",Nds,"Ndk: ",Ndk)

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
for i in range(N_paths):
  plt.subplot(Nrows,Ncolumns,i+1)
  plt.plot(time,s_dp[i],color[i])

## Figure 3
plt.figure(3,figsize=(8, 8))
## Down-sampled padded signal convolution result
for i in range(N_paths):
  plt.subplot(Nrows,Ncolumns,i+1)
  plt.plot(ds_time,s_ds[i],color[i])

## Figure 4
plt.figure(4,figsize=(8, 8))
## down-sampled signal ** down-sampled kernel"
for i in range(N_paths):
  plt.subplot(Nrows,Ncolumns,i+1)
  plt.plot(conv_ds_time,s_ds_conv[i],color[i])

## Figure 5
plt.figure(5,figsize=(8, 8))
plt.subplot(2,1,1)
plt.plot(conv_time, ds_conv_alt, 'm')
plt.subplot(2,1,2)
plt.plot(k_ds_t, k_ds, 'g')

plt.show()