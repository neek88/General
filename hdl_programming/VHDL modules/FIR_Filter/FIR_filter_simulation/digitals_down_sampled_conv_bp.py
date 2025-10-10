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
f1 = filt.filter()
f2 = filt.filter()

# plotting control
PLT_SIGNAL            = 1
PLT_DOWN_PADDED       = 0
PLT_DOWN_PADDED_CONV  = 0
PLT_DSS_CONV_DSK      = 0
PLT_NLANE_CONV_RECON  = 1
PLT_K_FFT_DSK_FFT     = 1
#######################
### Signal Creation ###
#######################

# custom params
f0 = 200e6
BW = 25e6
T0 = 1/ f0
N_paths = 8                 ## number of paths/ number of 'generators'
chip_rate = 1.024e6
chip_number = 256
prn_fac = 1
boc_fac = 0
boc_phase = 0

### digitals system down-sampled-convolution example
# digitals params
sample_clk = 307.2e6
sample_rate = sample_clk * N_paths
PLT_RANGE = 10000

# digitals bpsk signal
d_bpsk, d_bpsk_t = b.digitals_bpsk_mod(sample_clk,f0,N_paths,chip_rate,chip_number,prn_fac,boc_fac,boc_phase)
center_freq = b.digitals_center_freq
bpsk_time_range = chip_number * b.digitals_f0_prn_mult * 1/ f0

Ns = len(d_bpsk)
Nds = int(Ns/N_paths)                       ## samples in 1/N_paths broken waveform

# create bpfilter from filter object
Ns_dk =127                                  ## number of samples for down-sampled (must be odd)
Ns_fk = Ns_dk * N_paths + 1                 ## number of samples for full kernel  (forced to be odd)
kernel, kernel_time = f1.digitals_bp_filt(center_freq,BW,Ns_fk,sample_rate)

Nk = len(kernel)                            ## samples in kernel
kernel_time_range = 2*f1.Nl*(1/center_freq) * len(kernel)/f1.M_b

print("signal len: ",len(d_bpsk), "kernel len: ",len(kernel))
print("center_freq: ",center_freq, "bpsk time range: ",bpsk_time_range)

## determine length of convolution signals + time arguments
# length of convolution between signal and kernel
conv_len = Ns + Nk - 1
conv_time_range = bpsk_time_range + kernel_time_range

# convolve signals together
conv_time = np.linspace(0,conv_time_range,conv_len)
conv = np.convolve(d_bpsk,kernel)

########################################################
### Down sampled signal + kernel (padded with zeros) ###
########################################################

# down-sampled-padded signals
s_dp = []
for i in range(N_paths): 
  s_dp.append(list(np.zeros(Ns)))

# populate down-sampled signal arrays
for path in range(N_paths):
  for idx in range(len(d_bpsk)):
    if(idx % N_paths == path): s_dp[path][idx] = d_bpsk[idx]

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
s_ds = s.down_sample_split_path(d_bpsk,N_paths)

# create down-sampled kernel bpfilter from fitler object
k_ds, k_ds_t = f2.digitals_bp_filt(center_freq,BW,Ns_dk,(sample_rate/N_paths))
k_ds = k_ds * N_paths
Ndk = len(k_ds)

# convolve broken-unpacked signals with kernel
s_ds_conv = list()
for i in range(N_paths):
  s_ds_conv.append(list(np.convolve(s_ds[i],k_ds)))

# length of convolution between down-sampled signal / kernel
conv_ds_len = Nds + Ndk - 1
sig_ds_time_range = bpsk_time_range/ N_paths
conv_ds_time_range = (bpsk_time_range+kernel_time_range)/N_paths
kernel_ds_time_range = kernel_time_range/ N_paths

# time arrays for down-sampled signal / down-sampled convolution
ds_time = np.linspace(0,sig_ds_time_range, Nds)
conv_ds_time = np.linspace(0,conv_ds_time_range,conv_ds_len)
k_ds_t = np.linspace(0,kernel_ds_time_range,Ndk)


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

## Take FFT of our bandpass filter
kernel_ft = np.abs(np.fft.fft(kernel))
kernel_freq = np.fft.fftfreq(kernel_ft.size)
kernel_freq *= f1.BP_SR     ## scale frequency axis by sample rate

## Take FFT of the downsampled filter kernel
kds_ft = np.abs(np.fft.fft(k_ds))
kds_freq = np.fft.fftfreq(kds_ft.size)
kds_freq *= f2.BP_SR      ## scale frequency axis by sample rate

## Take FFT of the reconstructed signal 
recon_ft = np.abs(np.fft.fft(ds_conv_alt))
recon_freq = np.fft.fftfreq(ds_conv_alt.size)
recon_freq *= sample_rate

################
### Plotting ###
################

Nrows = int(N_paths/2)
Ncolumns = int(N_paths/ Nrows)
color = ["b.","r.","g.","m.","b.","r.","g.","m."]

if(PLT_SIGNAL):
  ## Figure 1
  plt.figure(1,figsize=(8, 8))
  ## single convolution
  plt.subplot(3,1,1)
  plt.title("signal")
  plt.plot(d_bpsk_t[0:PLT_RANGE], d_bpsk[0:PLT_RANGE], 'b')
  ## kernel
  plt.subplot(3,1,2)
  plt.title("kernel")
  plt.plot(kernel_time,kernel,'r')
  ## conv result
  plt.subplot(3,1,3)
  plt.title("signal ** kernel")
  plt.plot(conv_time[0:PLT_RANGE],conv[0:PLT_RANGE],'g')

if(PLT_DOWN_PADDED):
  ## Figure 2
  plt.figure(2,figsize=(8, 8))
  ## down-sampled-padded signals
  for i in range(N_paths):
    plt.subplot(Nrows,Ncolumns,i+1)
    plt.plot(d_bpsk_t[0:PLT_RANGE],s_dp[i][0:PLT_RANGE],color[i])

if(PLT_DOWN_PADDED_CONV):
  ## Figure 3
  plt.figure(3,figsize=(8, 8))
  ## Down-sampled padded signal convolution result
  for i in range(N_paths):
    plt.subplot(Nrows,Ncolumns,i+1)
    plt.plot(ds_time[0:PLT_RANGE],s_ds[i][0:PLT_RANGE],color[i])

if(PLT_DSS_CONV_DSK):
  ## Figure 4
  plt.figure(4,figsize=(8, 8))
  ## down-sampled signal ** down-sampled kernel"
  for i in range(N_paths):
    plt.subplot(Nrows,Ncolumns,i+1)
    plt.plot(conv_ds_time[0:PLT_RANGE],s_ds_conv[i][0:PLT_RANGE],color[i])

if(PLT_NLANE_CONV_RECON):
  ## Figure 5
  ## N-lane convolution reconstruction
  ## down-sampled filter kernel
  plt.figure(5,figsize=(8, 8))
  plt.subplot(3,1,1)
  plt.title("N-lane convolution reconstruction")
  plt.plot(conv_time[0:PLT_RANGE], ds_conv_alt[0:PLT_RANGE], 'm')
  plt.subplot(3,1,2)
  plt.title("convolution reconstruction FFT")
  plt.plot(recon_freq, recon_ft.real, 'b')
  plt.xlim(f0 - 2*BW,f0 + 2*BW)
  plt.subplot(3,1,3)
  plt.title("down-sampled kernel")
  plt.plot(k_ds_t, k_ds, 'g')

if(PLT_K_FFT_DSK_FFT):
  ## Figure 6
  plt.figure(6,figsize=(8, 8))
  plt.subplot(2,1,1)
  plt.title("kernel FFT")
  plt.plot(kernel_freq, kernel_ft.real, 'm.')
  plt.xlim(-(f0 + 1.5*BW),f0 + 1.5*BW)
  plt.subplot(2,1,2)
  plt.title("down-sampled kernel FFT")
  plt.plot(kds_freq, kds_ft.real, 'g.')


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