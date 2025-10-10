import matplotlib.pyplot as plt
import numpy as np
import math as m
import gps as gp
import sig_util as signal


## custom BPSK signal generator class
## gives user control over center freq, chip rate, sample_factor/ sample_rate etc..
class bpsk:

  pi = np.pi

  # Note: the highest freq. content of the PRN code is chipping_rate / 2
  L1 = 1575.42e6           # Use w/ 1.023 chipping_rate, (use 1576.96e6 with 1.024 CR)
  L2 = 1227.60e6           # L2 - center for GPS signals  

  sig = signal.util()

  def __init__(s,sample_resolution=16):
    s.Nr = sample_resolution            # power-of-two accuracy for filter kernel

    # sample rates of each BPSK signal type
    s.custom_sample_rate = 0
    s.custom_sample_factor = 0
    s.custom_center_freq = 0
    s.custom_f0_prn_mult = 0
    ##
    s.digitals_sample_rate = 0
    s.digitals_sample_factor = 0
    s.digitals_center_freq = 0
    s.digitals_f0_prn_mult = 0

  ## Generate sinusoid with specified sample rate
  def generate_sine(s,f0,sample_rate,num_periods):

    T_f0 = 1 / f0

    ## generate sinusoid with specified sample rate, number of periods 
    carrier_len = int((sample_rate / f0) * num_periods )
    carrier_time      = np.linspace(0,(T_f0*num_periods),carrier_len)
    carrier_phase_vec = 2 * s.pi * f0 * carrier_time
    carrier_signal    = np.sin(carrier_phase_vec)

    ## scale sinusoid to proper resoluiton
    s.sig.scale_signal(carrier_signal,s.Nr)
    return carrier_signal, carrier_time

  ## Generate BPSK signal with given parameters
  def custom_bpsk(s,center_freq,sample_factor,chipping_rate,chip_number,prn_factor,boc_factor,boc_phase):

    f0 = center_freq

    #######################################
    ### Typical GPS waveform parameters ###
    #######################################
    # chipping_rate     = 1.024e6           # C/A (PRN) code rate [chips/second]
    # chip_number       = 1024              # number of chips to make
    # boc_phase         = 0                 # sin/ cos starting phase 
    # sample_factor     = 6                 # number of samples per period of f0
    # prn_factor        = 1                 # Rate multiple for PRN code 
    # boc_factor        = 1                 # BOC Parameters
    #                                       # Allowed discretized BOC factors = [1,2,3,5,6,10,15,25,30,50,75]
    
    ## Useful periods
    T_f0              = 1/ f0                               # Period of f0
    T_prn             = 1/ (prn_factor * chipping_rate)     # Period of C/A code 
    T_boc             = 1/ (boc_factor * chipping_rate)     # Period of BOC waveform

    # BOC sample rate - Larger by factor of:  (f0/chipping_rate) / boc_factor 
    # will udpate sample_factor to allow alignment between boc/ prn
    boc_sampling_factor, sample_factor = s.sig.adjust_sample_rate(sample_factor, f0, chipping_rate,  
                                                              boc_factor, prn_factor, chip_number)

    # actual sampling rate/ frequency of BPSK signal
    sample_freq       = f0 * sample_factor    

    ##############################
    ### Generate carrier waves ###
    ##############################

    ## How many f0 periods per PRN chip ?
    #   MUST BE AN INTEGER VALUE
    F0_PRN_MULT = f0/ (chipping_rate  * prn_factor) 

    ## how long must carrier list be ?
    #   - 'sample_factor' samples per period
    #   -  F0_PRN_MULT * chip_number  periods 
    carrier_length = int(F0_PRN_MULT * sample_factor * chip_number) 

    ## Generate carrier signal + time array 
    #   - 'F0_PRN_MULT' periods per chip 
    #   - 'chip_number' of chips
    carrier_time      = np.linspace(0,(F0_PRN_MULT*T_f0*chip_number),carrier_length)
    carrier_phase_vec = 2 * s.pi * f0 * carrier_time
    carrier_signal    = np.sin(carrier_phase_vec)

    ## Generate boc wave 
    #   - 'boc_factor/prn_factor' periods per chip 
    #   - 'chip_number' chips 
    #   - 'boc_sampling_factor' samples per period    - boc_sampling_factor is multiple of sampling_rate to create equal size lists 
    #   - 'boc_factor * chip_number'  periods 
    boc_time      = np.linspace(0,T_boc * (boc_factor/prn_factor) * chip_number, boc_sampling_factor * (boc_factor * chip_number))
    boc_phase_vec = 2*s.pi*chipping_rate*boc_factor*boc_time 
    boc_signal    = np.sin(boc_phase_vec + (s.pi/2)*boc_phase)
    # Convert BOC to square wave +/- 1 values 
    boc = s.sig.conv_square(boc_signal)
    # reduce size of BOC wave if generated length is longer than carrier length

    ## Generate C/A code for L1 signal 
    c_a = s.sig.generate_ca_code(chip_number, F0_PRN_MULT,sample_factor)

    ## Generate modulated carrier wave 
    BPSK = np.array(carrier_signal) * np.array(c_a) #* np.array(boc)  

    ## scale our BPSK signal to the discretized sample values
    s.sig.scale_signal(BPSK,s.Nr)

    ## store useful info 
    s.custom_center_freq = f0
    s.custom_sample_factor = sample_factor
    s.custom_sample_rate = sample_freq
    s.custom_f0_prn_mult = F0_PRN_MULT

    return BPSK, carrier_time

  def digitals_bpsk(s,clk_rate,center_freq,num_gen,chipping_rate,chip_number,prn_factor):
    ### DIGITALS unit limitations
    #   - In the case of the digitals unit, we have no control over sample rate (sample_frequency)
    #     due to the nature of how we generate sinusoids
    #       - the samples generated are 16-bit, generating a table of 2^16 = 65,536 total samples 
    #   - The base_rate we can generate is found from: (clk/65536) * 8
    #   - the 'M' factor is found from the chosen frequency 'f0' over the base rate
    #       - M = f0 / base_rate
    #   - The sample_factor (samples per period) is found from: 
    #       - sample_factor = 65536/ M 
    #       - sample_factor = 65536 * base_rate / f0 
    #       - sample_factor = sample_clk * 8 / f0 
    #   - finally, the sample_freq is found from:
    #       - sample_freq = f0 * sample_factor
    #       - sample_freq = f0 * sample_clk * 8 / f0
    #       - sample_freq = sample_clk * 8    (the sample frequency is constant)
    ##
    #   - The limitations on bandpass filter design are then limited by:
    #       - chosen center frequency 'fc'
    #       - chosen filter bandwidth 'BW'
    #       - number of periods for high-pass filter sinc 'Nh'

    ############################################
    ### Typical DIGITALS waveform parameters ###
    ############################################
    # clk_rate = 307.2e6                       # clk rate driving LUT signal gen
    # f0 = 614.4e6                             # frequency of tone being generated 
    # Ng = 8                                   # number of LUT generators
    # chipping_rate   = 1.024e6                # C/A (PRN) code rate [chips/second]
    # chip_number     = 1024                   # number of chips to make
    # prn_factor      = 1                      # Rate multiple for PRN code 

    # capture inputs
    f0 = center_freq
    Ng = num_gen
    
    ## determined system values
    Ns = 2**s.Nr                          # total number of samples in the table
    base_rate = (clk_rate/ Ns) * Ng       # base frequency
    f0 = int(f0 / base_rate) * base_rate  # adjust our frequency to the allowed freq
    T0 = 1/ f0                            # period 
    M = f0 / base_rate                    # M is guranteed to be an integer due to f0 adjustment
    sample_factor = clk_rate * Ng / f0    # number of samples per period
    sample_freq = clk_rate * Ng           # sample frequency

    print("Carrier Frequency Adjusted: ",f0)
    ##############################
    ### Generate carrier wave ###
    ##############################

    ## How many f0 periods per PRN chip ?
    #   MUST BE AN INTEGER VALUE
    F0_PRN_MULT = f0/ (chipping_rate * prn_factor)

    ## how long must carrier list be ?
    #   - 'sample_factor' samples per period
    #   -  L1_PRN_MULT * chip_number  periods 
    carrier_length = int(F0_PRN_MULT * sample_factor * chip_number) 
    print("carrier_len: ",carrier_length,"f0/ prn: ",F0_PRN_MULT * sample_factor * chip_number)
    ## Generate carrier signal + time array 
    #   - 'L1_PRN_mult' periods per chip 
    #   - 'chip_number' of chips
    carrier_time      = np.linspace(0,(F0_PRN_MULT*T0*chip_number),carrier_length)
    carrier_phase_vec = 2*s.pi*f0*carrier_time
    carrier_signal    = np.sin(carrier_phase_vec)
    
    ## Generate C/A code for f0 signal 
    c_a = s.sig.generate_ca_code(chip_number, F0_PRN_MULT,sample_factor)

    ## Generate modulated carrier wave 
    BPSK = np.array(c_a) * np.array(carrier_signal)

    ## scale our BPSK signal to the proper sample values
    s.sig.scale_signal(BPSK, s.Nr)

    ## store useful info 
    s.digitals_center_freq = f0
    s.digitals_sample_factor = sample_factor
    s.digitals_sample_rate = sample_freq
    s.digitals_f0_prn_mult = F0_PRN_MULT

    return BPSK, carrier_time

  def digitals_bpsk_mod(s,clk_rate,center_freq,num_gen,chipping_rate,chip_number,prn_factor,boc_factor,boc_phase):
    ### DIGITALS unit limitations
    #   - In the case of the digitals unit, we have no control over sample rate (sample_frequency)
    #     due to the nature of how we generate sinusoids
    #       - the samples generated are 16-bit, generating a table of 2^16 = 65,536 total samples 
    #   - The base_rate we can generate is found from: (clk/65536) * 8
    #   - the 'M' factor is found from the chosen frequency 'f0' over the base rate
    #       - M = f0 / base_rate
    #   - The sample_factor (samples per period) is found from: 
    #       - sample_factor = 65536/ M 
    #       - sample_factor = 65536 * base_rate / f0 
    #       - sample_factor = sample_clk * 8 / f0 
    #   - finally, the sample_freq is found from:
    #       - sample_freq = f0 * sample_factor
    #       - sample_freq = f0 * sample_clk * 8 / f0
    #       - sample_freq = sample_clk * 8    (the sample frequency is constant)
    ##
    #   - The limitations on bandpass filter design are then limited by:
    #       - chosen center frequency 'fc'
    #       - chosen filter bandwidth 'BW'
    #       - number of periods for high-pass filter sinc 'Nh'

    ############################################
    ### Typical DIGITALS waveform parameters ###
    ############################################
    # clk_rate = 307.2e6                       # clk rate driving LUT signal gen
    # f0 = 614.4e6                             # frequency of tone being generated 
    # Ng = 8                                   # number of LUT generators
    # chipping_rate   = 1.024e6                # C/A (PRN) code rate [chips/second]
    # chip_number     = 1024                   # number of chips to make
    # prn_factor      = 1                      # Rate multiple for PRN code 

    # capture inputs
    f0 = center_freq
    Ng = num_gen
    
    ## determined system values
    Ns = 2**s.Nr                          # total number of samples in the table
    base_rate = (clk_rate/ Ns) * Ng       # base frequency
    f0 = int(f0 / base_rate) * base_rate  # adjust our frequency to the allowed freq
    T0 = 1/ f0                            # period 
    M = f0 / base_rate                    # M is guranteed to be an integer due to f0 adjustment
    sample_factor = clk_rate * Ng / f0    # number of samples per period
    sample_freq = clk_rate * Ng           # sample frequency
    base_factor = sample_freq / chipping_rate
    print("Carrier Frequency Adjusted: ",f0)

    ### Determine PRN/ BOC waveform properties ###
    c_a = []
    boc = []

    if(prn_factor != 0):
      ## force prn/factor to be integers
      prn_factor = int(m.floor(prn_factor))

      # adjust prn_factor
      while((base_factor/prn_factor) != m.floor((base_factor/prn_factor))):
        prn_factor -= 1
      prn_sample_factor = base_factor / prn_factor

      # time length of single PRN chip - not an actual period
      T_prn = 1 / (prn_factor * chipping_rate)

      ## Generate C/A code 
      c_a = s.sig.gen_ca_code(chip_number, prn_sample_factor)

    if(boc_factor != 0):
      ## force boc factor to be integers
      boc_factor = int(m.floor(boc_factor))

      # adjust boc_factor 
      while((base_factor/boc_factor) != m.floor((base_factor/boc_factor))):
        boc_factor -= 1
      boc_sample_factor = base_factor / boc_factor

      # time length of single BOC chip - not an actual period
      T_boc = 1 / (boc_factor * chipping_rate) 

      ## Generate BOC signal 
      # overshoot length of BOC signal, and then chop down after 
      # to align with PRN code
      boc_chip_number = m.ceil((boc_factor/prn_factor) * chip_number)
      boc_sample_len = boc_chip_number* boc_sample_factor
      boc_time_len   = boc_chip_number * T_boc

      # generate boc signal
      boc = s.sig.gen_boc_code(boc_phase, boc_chip_number, boc_sample_factor)

      # cut-down boc signal to match length of PRN code
      boc = boc[0:len(c_a)]

    ##############################
    ### Generate carrier wave ###
    ##############################

    ## How many f0 periods per PRN chip ?
    F0_PRN_MULT = f0/ (chipping_rate * prn_factor)

    ## how long must carrier list be ?
    #   - samples per chip * chip_number
    carrier_length = int((sample_freq/(chipping_rate * prn_factor)) * chip_number)

    ## Generate carrier signal + time array 
    #   - 'L1_PRN_mult' periods per chip 
    #   - 'chip_number' of chips
    carrier_time      = np.linspace(0,(F0_PRN_MULT*T0*chip_number),carrier_length)
    carrier_phase_vec = 2*s.pi*f0*carrier_time
    carrier_signal    = np.sin(carrier_phase_vec)
    
    print("carrier_len: ",carrier_length)
    print("prn_length", len(c_a))
    print("boc_length", len(boc))

    ## Generate modulated carrier wave 
    BPSK = np.array(carrier_signal)
    if(prn_factor != 0):
      BPSK = BPSK * np.array(c_a)
    if(boc_factor != 0):
      BPSK = BPSK * np.array(boc)

    ## scale our BPSK signal to the proper sample values
    s.sig.scale_signal(BPSK, s.Nr)

    ## store useful info 
    s.digitals_center_freq = f0
    s.digitals_sample_factor = sample_factor
    s.digitals_sample_rate = sample_freq
    s.digitals_f0_prn_mult = F0_PRN_MULT

    return BPSK, carrier_time