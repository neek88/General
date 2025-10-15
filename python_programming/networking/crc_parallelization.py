import math as m
import numpy as np 
import zlib as z

## In order to process a CRC-32 calculation of a running byte stream
##  there is a four step process
##  1. Take the current running CRC-32 calculation (32-bits) and 
##      XOR in the next 32-bits
##  2. separate each byte into a rotated zero pad boundary
##  3. use a lookup table to compute the 32-bit CRC of each 
##      individual padded-byte
##  4. XOR each 32-bit CRC result together

def reverse_bits_in_byte(byte_value: int) -> int:
    reversed_byte = 0
    for _ in range(8):  # Iterate 8 times for each bit in a byte
        reversed_byte <<= 1  # Left-shift the result to make space for the next bit
        if byte_value & 1:  # Check if the LSB of the input is 1
            reversed_byte |= 1  # Set the LSB of the result if it was 1
        byte_value >>= 1  # Right-shift the input to process the next bit
    return reversed_byte

def reverse_bits_32bit(n: int) -> int:
    reversed_n = 0
    for i in range(32):
        # Check if the i-th bit of n is set
        if (n >> i) & 1:
            # If set, set the corresponding bit in the reversed_n
            # The corresponding bit is at position (31 - i)
            reversed_n |= (1 << (31 - i))
    return reversed_n

## operates on 32-bit data
def endian_swap(data): 
    return (((data & 0xff000000) >> 24) + \
            ((data & 0x00ff0000) >> 8) + \
            ((data & 0x0000ff00) << 8) + ((data & 0x000000ff) << 24))

## operates on 32-bit data
def endian_swap_list(data):
    return [endian_swap(word) for word in data]

## Basic algorithm:
##  1. append 8 zeros to the input data
##  2. create a zero'd out list of length 8
##  3. shift in one bit from the input_data
##      into the working_data list at a time
##  4. when the highest order bit in the working_data
##      list is '1', compute the XOR between the vectors
##  5. repeat the process with the resulting data
## uses polynomial 100000111
def crc_8(input_data,init=0):
    poly = 0b100000111
    work = input_data[0] if init==0 else (input_data[0] ^ 0xff)
    for byte in input_data[1:]:
        for i in range(8):
            ## capture the highest order bit of the input data
            bit = (byte & 0b10000000) >> 7
            ## shift-out the top bit of the input
            byte = (byte & 0x7f) << 1
            ## shift captured bit into working register
            work = ((work << 1) & 0x1ff) ^ bit
            ## highest order bit is 1
            if(work >= 2**8): work ^= poly
    for i in range(8): ## shift final 8 zeros in
        ## shift captured bit into working register
        work = ((work << 1) & 0x1ff)
        ## highest order bit is 1
        if(work >= 2**8): work ^= poly
    return work 

## CRC_32 non-reciprocol
##  -Input one byte at a time
##  -reverse bit-order of input
##  -Align input byte with MSB of CRC
def crc_32(data: list):
    poly = 0x04C11DB7
    crc =  0xffffffff
    for word in data:
        crc = crc ^ (reverse_bits_in_byte(word) << 24)
        for i in range(8):
            if(crc & 0x80000000): crc = ((crc << 1) ^ poly) & 0xffffffff
            else: crc = (crc << 1) & 0xffffffff
    return reverse_bits_32bit(crc) ^ 0xffffffff

## CRC_32 reciprocal
##  -Input one byte at a time
##  -Polynomial is bit-reversed
def crc_32_reciprocal(data: list):
    poly = 0xedb88320
    crc = 0xffffffff
    for word in data:
        crc ^= word 
        for i in range(8):
            if(crc & 1): crc = (crc >> 1) ^ poly 
            else: crc >>= 1
    return crc ^ 0xffffffff

## Generate table of CRC-32 for 1-byte inputs
def gen_crc_32_reciprocal_table():
    poly = 0xedb88320
    crc_table = []
    for byte in range(256):
        for bit in range(8):
            if(byte & 1): byte = (byte >> 1) ^ poly
            else: byte >>= 1
        crc_table.append(byte)
    return crc_table 

def crc_32_reciprocol_table(data: list, crc_32_table: list):
    crc = 0xffffffff
    for byte in data:
        index = (byte ^ crc) & 0xff
        crc = (crc >> 8) ^ crc_32_table[index]
    return crc ^ 0xffffffff

def generate_crc32_table(polynomial=0x04C11DB7):
    crc_table = [0] * 256
    for i in range(256):
        crc = i << 24  # Start with the byte shifted to the most significant position
        for _ in range(8):
            if (crc & 0x80000000):  # If the MSB is set
                crc = (crc << 1) ^ polynomial
            else:
                crc = crc << 1
        crc_table[i] = crc & 0xFFFFFFFF  # Ensure 32-bit result
    return crc_table

## Make sure the input byte is bit-reversed, and the 
##  output word is bit-reversed on 32-bit boundary
def ethernet_crc32(data: bytes, crc_table: list):
    crc = 0xFFFFFFFF  # Initial CRC value for Ethernet CRC32
    for byte in data:
        # XOR the current byte with the MSB of the CRC, then use as index for table
        table_index = ((crc >> 24) ^ reverse_bits_in_byte(byte)) & 0xFF
        # Shift CRC left by 8 bits and XOR with the table value
        crc = ((crc << 8) & 0xFFFFFFFF) ^ crc_table[table_index]        
    return reverse_bits_32bit(crc) ^ 0xFFFFFFFF

## Test CRC-8 function
ina = [0b11001001, 0b11001001]
print("crc-a: ", bin(crc_8(ina,0)))

## Test CRC-8 linearity
in1 = [0b11001001,0b00000000]
in2 = [0b00000000,0b11100101]
in1_xor_in2 = [in1[0], in2[1]]
crc_a_xor_b = crc_8(in1_xor_in2)
crc_a_xor_crc_b = crc_8(in1) ^ crc_8(in2)
print("CRC(a ^ b):")
print(bin(crc_a_xor_b))
print("CRC-8(a) ^ CRC-8(b): ")
print(bin(crc_a_xor_crc_b))

## CRC-32 reciprocol byte
crc32_in = [0xAA,0xAA,0xAA,0xAA,0xAA,0xAA,0x55,0x55,0x55,0x55,0x55,0x55,0xDD,0xDD,0xDD,0xDD]
print("crc_32_reciprocol:", hex(crc_32_reciprocal(crc32_in)))

## CRC-32 reciprocol table version
crc_32_table_r = gen_crc_32_reciprocal_table()
crc_32_out_r = crc_32_reciprocol_table(crc32_in, crc_32_table_r)
print("crc_32_recip_table: ", hex(crc_32_out_r))

## CRC-32 forward table version
crc32_table = generate_crc32_table()
print("crc-forward: ", hex(ethernet_crc32(crc32_in, crc32_table)))

## CRC-32 direct
print("crc-no_table: ",hex(crc_32(crc32_in)))
