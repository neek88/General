import matplotlib.pyplot as plt
import sig_util as sig
import numpy as np
import math as m

## Note: There are different ways to down-sample the signal 
##  1. each clk cycle, 8 samples that are output go to a separate 
##    convolution lane for processing. Afterwards, they 
##    recombined mathematically, producing 9 sample outputs
##  2. each clk cycle, 8 samples are given to a single lane
##    for processing. After 8 cycles, each lane will be fed
##    8 samples, and the original 8 samples will be ready for 
##    recombination at the output
##  * this file simulates the second option. This option was
##    found to be infeasible in hardware due to the dependency
##    between data coming from each lane needed for recombination

##############
### Macros ###
##############
pi = np.pi

# useful objects
s = sig.util()

###################
### User Params ###
###################

f0 = 1
Ns = 32                               ## total samples of waveform (make divisible by 4...)
N_periods = 1                         ## total number of periods of waveform
N_paths = 4                           ## number of paths
##
T0 = 1 / f0
sample_factor = int(Ns/N_periods)     ## number of samples per period
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

## create kernel 
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

## Sum of split signals
## s * h = (sa + sb + sc + sd) * h
sa = np.zeros(Ns)
sa[0:Nds] = sinu[0:Nds]
sb = np.zeros(Ns)
sb[Nds:2*Nds] = sinu[Nds:2*Nds]
sc = np.zeros(Ns)
sc[2*Nds:3*Nds] = sinu[2*Nds:3*Nds]
sd = np.zeros(Ns)
sd[3*Nds:4*Nds] = sinu[3*Nds:4*Nds]

## convolve broken signals with kernel
sa_conv = np.convolve(sa,kernel)
sb_conv = np.convolve(sb,kernel)
sc_conv = np.convolve(sc,kernel)
sd_conv = np.convolve(sd,kernel)

## direct sum of convolution components
conv_sum = sa_conv + sb_conv + sc_conv + sd_conv

#########################
### Split Signal Path ###
#########################

# length of convolution between split signal / kernel
conv_split_len = Nds + Ndk - 1
sig_split_time_range = sig_time_range/ N_paths
conv_split_time_range = (sig_time_range+kernel_time_range)/N_paths
# time arrays for split signal + split signal convolution
si_time = np.linspace(0,sig_split_time_range, Nds)
si_conv_time = np.linspace(0,conv_split_time_range, conv_split_len)

# break apart main signal
si_a = sinu[0     : Nds]
si_b = sinu[Nds   : 2*Nds]
si_c = sinu[2*Nds : 3*Nds]
si_d = sinu[3*Nds : 4*Nds]

# down sample kernel by factor of number-of-paths
ka = []
for i in range(len(kernel)):
  if (i % N_paths == 0): ka.append(kernel[i])

# convolve split signal / split kernel
si_a_conv = np.convolve(si_a,ka)
si_b_conv = np.convolve(si_b,ka)
si_c_conv = np.convolve(si_c,ka)
si_d_conv = np.convolve(si_d,ka)

Nr = int( (Ns/N_paths + Nk/ N_paths)/ 2)
print(len(kernel),len(sinu),len(ka),len(si_a),len(si_a_conv),Nr)
# combine result of split signal convolution
si_comb_conv = np.array( 
  list(si_a_conv[0:Nr]) +                                                    # first sample set
  list(si_a_conv[Nr-1]+si_b_conv[0:Nr]) +                                    # second sample set
  list(si_a_conv[Nr-1]+si_b_conv[Nr-1]+si_c_conv[0:Nr]) +                    # third sample set
  list(si_a_conv[Nr-1]+si_b_conv[Nr-1]+si_c_conv[Nr-1]+si_d_conv[0:Nr]) +    # fourth sample set
  list(si_b_conv[Nr-1]+si_c_conv[Nr-1]+si_d_conv[Nr-1]+si_a_conv[-Nr+1:]) +  # fifth sample set
  list([si_b_conv[Nr-1]+si_c_conv[Nr-1]+si_d_conv[Nr-1]]) +                  # insert final point for set 'a' (0)
  list(si_c_conv[Nr-1]+si_d_conv[Nr-1]+si_b_conv[-Nr+1:]) +                  # sixth sample set
  list([si_c_conv[Nr-1]+si_d_conv[Nr-1]]) +                                  # insert final point for set 'b' (0)                         
  list(si_d_conv[Nr-1]+si_c_conv[-Nr+1:]) +                                  # seventh sample set
  list([si_d_conv[Nr-1]]) +                                                  # insert final point for set 'c' (0)  
  list(si_d_conv[-Nr+1:])
  )


############################
### Main signal plotting ###
############################

## Figure 1
plt.figure(1,figsize=(8, 8), dpi=80)
## main signal, kernel, convolution result
plt.subplot(3,1,1)
plt.plot(time,sinu,'r.')
plt.subplot(3,1,2)
plt.plot(kernel_time,kernel,'b.')
plt.subplot(3,1,3)
plt.plot(conv_time,conv,'g.')

# ## Figure 2
# plt.figure(2,figsize=(8, 8), dpi=80)
# ## convolution components
# plt.subplot(2,2,1)
# plt.plot(time, sa,'r.')
# plt.subplot(2,2,2)
# plt.plot(time, sb,'b.')
# plt.subplot(2,2,3)
# plt.plot(time, sc,'g.')
# plt.subplot(2,2,4)
# plt.plot(time, sd,'m.')

## Figure 3
plt.figure(3,figsize=(8, 8), dpi=80)
## convolution split results
plt.subplot(4,1,1)
plt.plot(conv_time, sa_conv, 'r.')
plt.subplot(4,1,2)
plt.plot(conv_time, sb_conv,'b.')
plt.subplot(4,1,3)
plt.plot(conv_time, sc_conv,'g.')
plt.subplot(4,1,4)
plt.plot(conv_time, sd_conv,'m.')

## Figure 4
## convolution sum 
plt.figure(4,figsize=(8, 8), dpi=80)
plt.plot(conv_time, conv_sum, 'b.')

##################################
### Split signal path plotting ###
##################################

# plt.figure(5,figsize=(8, 8), dpi=80)
# ## broken apart signals
# plt.subplot(2,2,1)
# plt.plot(si_time,si_a,'r.')
# plt.subplot(2,2,2)
# plt.plot(si_time,si_b,'b.')
# plt.subplot(2,2,3)
# plt.plot(si_time,si_c,'g.')
# plt.subplot(2,2,4)
# plt.plot(si_time,si_d,'m.')

plt.figure(6,figsize=(8, 8), dpi=80)
## broken apart signals
plt.subplot(2,2,1)
plt.plot(si_conv_time,si_a_conv,'r.')
plt.subplot(2,2,2)
plt.plot(si_conv_time,si_b_conv,'b.')
plt.subplot(2,2,3)
plt.plot(si_conv_time,si_c_conv,'g.')
plt.subplot(2,2,4)
plt.plot(si_conv_time,si_d_conv,'m.')

# plt.figure(7,figsize=(8, 8), dpi=80)
# plt.plot(conv_time,si_comb_conv,'r.')

plt.show()



## convolve individual signals with kernel
## total length = Ns + Nd -1 = 39
# sai_conv = np.convolve(sai,kernel)
# sbi_conv = np.convolve(sbi,kernel)
# sci_conv = np.convolve(sci,kernel)
# sdi_conv = np.convolve(sdi,kernel)
# convi_time = np.linspace(0,phase_factor+(phase_factor/Nds),Ns+Nds-1)

# z1 = np.zeros(Nds)
# z2 = np.zeros(2*Nds)
# z3 = np.zeros(3*Nds)

# # re align convolution outputs
# sai_shift = np.array(list(sai_conv) + list(z3))
# sbi_shift = np.array(list(z1) + list(sbi_conv) + list(z2))
# sci_shift = np.array(list(z2) + list(sci_conv) + list(z1))
# sdi_shift = np.array(list(z3) + list(sdi_conv))

# # sum new terms together 
# conv_shift_sum = sai_shift+sbi_shift+sci_shift+sdi_shift