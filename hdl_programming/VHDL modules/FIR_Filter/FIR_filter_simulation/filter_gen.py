import matplotlib.pyplot as plt
import numpy as np
import math as m
import gps as gp
import bpsk_gen as bpsk
import sig_util as sig

  ##################
  ### Notes ########
  #    * We are using numpy arrays
  #        - this way we can sum/ multiply them 
  #            together element wise 
  #        - they behave similar to MATLAB arrays
  #        - how to convert ? 
  #            list_1  = [a, b, c]
  #            np_list = np.array(list_1) -> ([a, b, c])

class filter: 

  ##########################
  ### Global Static Data ###
  ##########################
  TAB = " "
  pi = np.pi            ## pi
  sig = sig.util()        ## signal utility functions

  ############################
  ### Function definitions ###
  ############################

  ## init the object with a divisor table given signal-data resolution
  def __init__(s,sample_resolution=16):
    s.Nr = sample_resolution       # power-of-two accuracy for filter kernel

    ## sample rates/ time range for this objects filters
    s.LP_SR = 0                    # low-pass filter sample rate
    s.LP_TR = [0,0]                # low-pass filter time range
    s.HP_SR = 0                    # high-pass filter sample rate
    s.HP_TR = [0,0]                # high-pass filter time range
    s.BP_SR = 0                    # band-pass filter sample rate
    s.BP_TR = [0,0]                # band-pass filter time scale

    ## high-pass / low pass sinc parameters
    s.f_cl = 0
    s.f_ch = 0
    s.Nh = 0    # number of periods in low pass filter kernel (sinc)
    s.Nl = 0    # number of periods in low pass filter kernel (sinc)
    s.M_k = 0   # number of samples in high-pass/ low-pass filter
    s.M_b = 0   # number of samples in band-pass filter

  ## moving average filter, simply a 'box' in time domain, scaled by its length
  def gen_mv_avg_filt(s,sample_len,sample_rate):
    time_range = sample_len/ sample_rate
    time = np.linspace(0,time_range,sample_len)
    mv_avg = np.ones(sample_len)
    mv_avg = mv_avg / sum(mv_avg)
    return mv_avg, time
  
  ## moving average filter with chosen cutoff frequency
  ##  - cutoff frequency is chosen to be halfway between
  ##    the peak and the first zero of the SINC(f) function
  def gen_ma_filt(s,sample_rate,cutoff_freq):
    ## determine length of filter inputs
    N_samples = int(sample_rate / (2 * cutoff_freq))
    ## force length to be odd
    if(N_samples % 2 == 0): N_samples += 1
    ## create matching time array for filter
    time_range = N_samples/sample_rate
    time = np.linspace(0,time_range,N_samples)
    mv_avg = np.ones(N_samples)
    mv_avg = mv_avg / sum(mv_avg)
    return mv_avg, time

  ## generate sinc-based LP filter with blackman/hamming window
  def gen_lp_filt(s,cutoff_freq,lp_periods,sample_cnt):
    
    ## user params
    f_cl = cutoff_freq                  ## filter cutoff freq
    Nl = lp_periods                     ## number of periods for the sinc function
    M = int(m.floor((sample_cnt-1)/2))  ## number of samples for RHS of LP filter
                                        ## sample_cnt should be odd, M should be even!

    ## sinc-parameters
    a_lp = 2 * f_cl                   # argument for lp sincs
    T_lp_sinc = 2/ a_lp               # period of low-pass sinc window 
    T_lp_black = 2 * Nl * T_lp_sinc   # relative period of blackman window

    # Sample rate of LP window function
    # shouldn't be needed here
    s.LP_SR = f_cl * sample_cnt / (2 * Nl) 

    ## generate time array
    lp_time_range = Nl * T_lp_sinc
    lpr_t = np.linspace(0,lp_time_range,M+1)                # create RHS array with one extra point (t = 0)
    lpl_t = np.flip(lpr_t,0)                                # create mirror image of array
    lpl_t = -lpl_t                                          # negate values in mirrored half
    lp_filt_t = np.array( list(lpl_t[0:M]) + list(lpr_t) )  # combine LHS/ RHS

    s.LP_TR = [-lp_time_range,lp_time_range]

    ## generate lowpass sinc
    lp_filt_sinc = np.sinc((a_lp)*lp_filt_t)
    lp_filt_blackman = 0.5 - 0.5*(np.cos(2*s.pi*(1/T_lp_black)*(lp_filt_t + (T_lp_black/2))))

    ## calculate lowpass filter
    # calculate the blackman filter window
    lp_filt = lp_filt_sinc * lp_filt_blackman
    lp_filt = lp_filt / sum(lp_filt)

    # print("inside LP filt gen...")
    # print("Nl: ",Nl, "M:",M, "a_lp:",a_lp)
    # print("T_lp_sinc:",T_lp_sinc,"T_lp_black:",T_lp_black)
    # print("lp_time_range:",lp_time_range)
    # print("lp sinc: ",lp_filt_sinc)
    # print("lp_blackman:",lp_filt_blackman)

    return lp_filt, lp_filt_t

  ## generate sinc-based HP filter with 
  ## blackman/hamming window
  def gen_hp_filt(s,cuton_freq,hp_periods,sample_cnt):
    ## setup our control parameters
    f_ch = cuton_freq                   ## cut-on frequency of filter
    Nh = hp_periods                     ## number of periods for the sinc function
    M = int(m.floor((sample_cnt-1)/2))  ## number of samples for RHS of HP filter
                                        ## sample_cnt should be odd, M should be even!

    ## Sample rate of HP window function                                
    s.HP_SR = cuton_freq * sample_cnt / (2 * hp_periods)
    ## generate waveform period parameters
    a_hp = 2 * f_ch                   ## argument for hp sinc
    T_hp_sinc = 2/ a_hp               ## period of high-pass since window
    T_hp_black = 2 * Nh * T_hp_sinc   ## relative period of blackman window

    ## high pass time
    hp_time_range = Nh * T_hp_sinc
    hpr_t = np.linspace(0,hp_time_range,M+1)
    hpl_t = np.flip(hpr_t,0)                               
    hpl_t = -hpl_t
    hp_filt_t = np.array( list(hpl_t[0:M]) + list(hpr_t) )  

    s.LP_TR = [-hp_time_range,hp_time_range]

    ## generate highpass sinc
    hp_filt_sinc = np.sinc((a_hp)*hp_filt_t)
    hp_filt_blackman = 0.5 - 0.5*(np.cos(2*s.pi*(1/T_hp_black)*(hp_filt_t + (T_hp_black/2))))

    ## calculate high pass filter 
    ## calculate the blackman filter window
    hp_filt = hp_filt_sinc * hp_filt_blackman
    hp_filt = hp_filt / sum(hp_filt)
    hp_filt = -hp_filt
    hp_filt[M] +=1

    return hp_filt, hp_filt_t

  ## generate sinc-based BP filter with 
  ## blackman/hamming window
  def gen_bp_filt(s,center_freq,bandwidth,hp_periods,sample_factor):

    # setup our control parameters
    f_c = center_freq                     # center frequency of filter
    BW = bandwidth                        # filter bandwidth
    Nh = hp_periods                       # number of total periods of high-pass sinc function
                                          # (N pos and N neg)
    ## generate highpass / low pass filter pair
    f_ch    = f_c - BW/2                  # high-pass cut-on frequency
    f_cl    = f_c + BW/2                  # low-pass cut-off frequency
    f_ratio = f_cl / f_ch                 # ratio of high_freq cutoff to low_freq cuton

    # total periods of low-pass sinc function
    Nl = Nh * f_ratio                  

    ## generate waveform period parameters
    T_lp_sinc = 1/ f_cl                   # period of low-pass sinc window 
    T_hp_sinc = 1/ f_ch                   # period of high-pass since window

    ## Determine proper sample freq. from f0 and sample factor
    ## Align our sample freq. to that of the bpsk signal
    # M = 64                              # half length of filter kernel (NO DC)
    # M_k = 2 * M + 1                     # total filter kernel length
    # M_b = 2 * M_k - 1                   # total bandpass (convolution) filter length
    carrier_sample_freq = f_c * sample_factor

    ## Must set the kernel sample frequency equal to carrier sample frequency
    ## kernel_sample_rate = (num_samples/ num_periods ) * f_filter
    ## kernel_fp = f_filter/ num_periods    (ratio of freq to num periods)
    kernel_fp = f_ch / (4 * Nh)
    ## calculate the effective sample count of our filter kernel
    ##  - we need the kernel sample rate to match that of the bpsk signal
    ##  - they wont match perfectly due to the rounding of the below calculation
    ##  - kernel_len = sample_rate * num_periods/ f_filter
    M_b = int(carrier_sample_freq / kernel_fp)
    ## calculate length of low-pass/ bandpass filters
    M_k = int((M_b + 1) / 2)
    M   = int((M_k - 1)/ 2)
    # insure that M is even
    if(M % 2 != 0): M -= 1

    # recalculate M_k/ M_b
    M_k = 2 * M + 1       ## odd length of lp / hp filter
    M_b = 2 * M_k - 1     ## convolution between lp/ hp

    ## store calculated parameters
    s.M_k = M_k
    s.M_b = M_b
    s.Nh = Nh 
    s.Nl = Nl 
    s.f_cl = f_cl 
    s.f_ch = f_ch

    ## calculate the sample freq of our kernel
    ##  - compare with desired sample freq 
    ##  - sample freq = freq * (number of samples/ number of periods)
    kernel_sample_freq = M_b / (4 * Nh * T_hp_sinc)

    ## display our calculated parameters
    print(s.TAB,"M=", M, " M_k=", M_k, " M_b=", M_b)
    print(s.TAB,"f_ch=",f_ch," f_cl=",f_cl," f_0=",f_c)
    print(s.TAB,"carrier_sample_freq= ", carrier_sample_freq)
    print(s.TAB,"filter kernel_sample_freq= ", kernel_sample_freq)

    ## generate high and low pass filter components
    lp_filt, lp_time = s.gen_lp_filt(f_cl, Nl, M_k)
    hp_filt, hp_time = s.gen_hp_filt(f_ch, Nh, M_k)

    # Sample rate of BP window function
    #   SR = f * num_samples / num_periods
    #     - f = frequency of one signal being convolved
    #     - num_samples = n + m - 1 (n/ m are the same in this case)
    #     - num_periods = 2 * (2 * Np)
    #           - Np positive periods/ Np negative periods
    #           - convolving doubles the number of periods since were
    #             shifting from -2*Tl to +2*Tl
    #     - this was calc. above (kernel_sample_freq)
    s.BP_SR = f_ch * (M_b) / (2 * 2 * Nh) 

    # bandpass time scale
    #   - higher frequency signal is being shifted across
    #     2 * Nh periods of the lower frequency waveform
    #     starting at -2 * Nh * T_hp_sinc -> 2 * Nh * T_hp_sinc
    #   - same logic applies shifting lower freq. signal across higher
    #        [-2 * Nl * T_lp_sinc : 2 * Nl * T_lp_sinc]
    s.BP_TR = [-2 * Nh *  T_hp_sinc, 2 * Nh * T_hp_sinc]

    ## calculate the bandpass filter
    bp_filt = s.sig.convolve(lp_filt, hp_filt)
    bp_filt_t = np.linspace(s.BP_TR[0],s.BP_TR[1],len(bp_filt))

    return bp_filt, bp_filt_t

  ## generate sinc-based BP filter with 
  ## blackman/hamming window
  def digitals_bp_filt(s,center_freq,bandwidth,num_samples,sample_rate):

    # setup our control parameters
    f_c = center_freq             ## center frequency of filter
    BW = bandwidth                ## filter bandwidth
    Ns = num_samples              ## length of filter kernel
    SR = sample_rate              ## number of samples per second

    ## generate highpass / low pass filter pair
    f_ch    = f_c - BW/2                # high-pass cut-on frequency
    f_cl    = f_c + BW/2                # low-pass cut-off frequency

    ## generate waveform period parameters
    T_lp_sinc = 1/ f_cl                   # period of low-pass sinc window 
    T_hp_sinc = 1/ f_ch                   # period of high-pass since window

    ## effective sample count of our filter kernel is given by Ns
    ##  - we need the bandpass kernel sample rate to match that of the bpsk signal
    ##  - therefore, the sample rate of the low/high pass kernels will be 
    ##  - they wont match perfectly due to the rounding of the below calculation
    M_k = int((Ns + 1) / 2)
    ## Make sure M_k is odd, otherwise add one and set flag 
    Mk_flag = 0
    if(M_k % 2 == 0):
      M_k += 1
      Mk_flag = 1

    ## recalculate M/ M_k/ M_b
    M = int((M_k - 1) / 2)
    M_k = 2 * M + 1       ## odd length of lp / hp filter
    M_b = 2 * M_k - 1     ## convolution between lp/ hp
                          ## should be EQUAL to Ns when M_k is odd

    ## determine number of periods for each filter kernel
    ##  - sample rate of filter kernel must match that of the center freq 'f_c'
    ##  - sample FACTOR must be >= 2, per the sampling theorm
    ##    -EX:  SR/ f_ch >= 2, otherwise the signal will fail the samplig theorm 
    Nh = M_k / (SR/f_ch)        # number of total periods of high-pass sinc function
    Nl = M_k / (SR/f_cl)        # number of total periods of low-pass sinc function  

    ## calculate the sample freq of our kernel
    ##  - compare with desired sample freq 
    ##  - sample freq = freq * (number of samples/ number of periods)
    ##  - kernel has twice as many periods due to convolution
    kernel_sample_freq = f_ch * M_b / (2 * Nh)

    ## display our calculated parameters
    print(s.TAB,"M=", M, " M_k=", M_k, " M_b=", M_b)
    print(s.TAB,"Nhp=",Nh," Nlp=",Nl)
    print(s.TAB,"f_ch=",f_ch," f_cl=",f_cl," f_0=",f_c)
    print(s.TAB,"carrier_sample_freq= ", SR)
    print(s.TAB,"filter kernel_sample_freq= ", kernel_sample_freq)

    ## generate high and low pass filter components
    lp_filt, lp_time = s.gen_lp_filt(f_cl, (Nl/2), M_k)
    hp_filt, hp_time = s.gen_hp_filt(f_ch, (Nh/2), M_k)


    # Sample rate of BP window function
    #   SR = f * num_samples / num_periods
    #     - f = frequency of one signal being convolved
    #     - num_samples = n + m - 1 (n/ m are the same in this case)
    #     - num_periods = (Np)
    #           - Np/2 positive periods +  Np/2 negative periods
    #           - convolving doubles the number of periods since were
    #             shifting from -Tl to +Tl
    #     - this was calc. above (kernel_sample_freq)
    s.BP_SR = f_ch * (M_b) / (2 * Nh) 

    # bandpass time scale
    #   - higher frequency signal is being shifted across
    #     2 * Nh periods of the lower frequency waveform
    #     starting at -Nh * T_hp_sinc -> Nh * T_hp_sinc
    #   - same logic applies shifting lower freq. signal across higher
    #        [-Nl * T_lp_sinc : Nl * T_lp_sinc]
    s.BP_TR = [-Nh *  T_hp_sinc, Nh * T_hp_sinc]

    ## calculate the bandpass filter
    bp_filt   = np.convolve(lp_filt, hp_filt)
    bp_filt_t = np.linspace(s.BP_TR[0],s.BP_TR[1],len(bp_filt))

    ## calculate the scaled bp filter, showing FPGA kernel coefficients
    bp_filt_fpga = bp_filt * (pow(2,30) - 1)
    for i in range(len(bp_filt_fpga)):
      bp_filt_fpga[i] = int(bp_filt_fpga[i])

    # print("filter parameters:")
    # print("fc: ", f_c, "BW: ",BW, "Mb: ",Ns)
    # print("LP filter kernel:")
    # print(lp_filt)
    # print("HP filter kernel:")
    # print(hp_filt)
    # print("BP filter kernel")
    # print(bp_filt)
    # print("BP filter kernel scaled")
    # print(bp_filt_fpga)
    
    ## check if Mk_flag is set. Reduce size by two 
    if(Mk_flag):
      bp_filt   = bp_filt[1:len(bp_filt)-1]
      bp_filt_t = bp_filt_t[1:len(bp_filt_t)-1]

    ## store calculated parameters
    s.M_k = M_k
    s.M_b = Ns
    s.Nh = Nh 
    s.Nl = Nl 
    s.f_cl = f_cl 
    s.f_ch = f_ch

    return bp_filt, bp_filt_t