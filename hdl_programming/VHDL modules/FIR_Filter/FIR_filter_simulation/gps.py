def SV(vehicle_num):
    if(vehicle_num == 1):
        return [2,6]
    elif(vehicle_num == 2):
        return [3,7]
    elif(vehicle_num == 3):
        return [4,8]
    elif(vehicle_num == 4):
        return [5,9]
    elif(vehicle_num == 5):
        return [1,9]
    elif(vehicle_num == 6):
        return [2,10]
    elif(vehicle_num == 7):
        return [1,8]
    elif(vehicle_num == 8):
        return [2,9]
    elif(vehicle_num == 9):
        return [3,10]
    elif(vehicle_num == 10):
        return [2,3]
    elif(vehicle_num == 11):
        return [3,4]
    elif(vehicle_num == 12):
        return [5,6]
    elif(vehicle_num == 13):
        return [6,7]
    elif(vehicle_num == 14):
        return [7,8]
    elif(vehicle_num == 15):
        return [8,9]
    elif(vehicle_num == 16):
        return [9,10]
    elif(vehicle_num == 17):
        return [1,4]
    elif(vehicle_num == 18):
        return [2,5]
    elif(vehicle_num == 19):
        return [3,6]
    elif(vehicle_num == 20):
        return [4,7]
    elif(vehicle_num == 21):
        return [5,8]
    elif(vehicle_num == 22):
        return [6,9]
    elif(vehicle_num == 23):
        return [1,3]
    elif(vehicle_num == 24):
        return [4,6]
    elif(vehicle_num == 25):
        return [5,7]
    elif(vehicle_num == 26):
        return [6,8]
    elif(vehicle_num == 27):    
        return [7,9]
    elif(vehicle_num == 28):
        return [8,10]
    elif(vehicle_num == 29):
        return [1,6]
    elif(vehicle_num == 30):
        return [2,7]
    elif(vehicle_num == 31):
        return [3,8]
    elif(vehicle_num == 32):
        return [4,9]
    else:
        return [2,6]
               
def shift(register, feedback, output):

    """ GPS Shift Register
    :param list feedback: which positions to use as feedback (1 indexed)
    :param list output: which positions are output (1 indexed)
    :returns output of shift register:
    """
    # calculate output
    out = [register[i-1] for i in output]
    if len(out) > 1:
        out = sum(out) % 2
    else:
        out = out[0]
        
    # modulo 2 add feedback
    fb = sum([register[i-1] for i in feedback]) % 2
    
    # shift to the right
    for i in reversed(range(len(register[1:]))):
        register[i+1] = register[i]
        
    # put feedback in position 1
    register[0] = fb
    
    return out
    
def generate_prn(sv, chip_count):
    c_a = []

    # init registers
    G1 = [1 for i in range(10)]
    G2 = [1 for i in range(10)]

    for i in range(chip_count):
        g1 = shift(G1, [3,10], [10]) #feedback 3,10, output 10
        g2 = shift(G2, [2,3,6,8,9,10], SV(sv)) #feedback 2,3,6,8,9,10, output 2,6 for sat 1
        c_a.append((g1 + g2) % 2)

    # Convert C/A code to +/- 1
    for i in range(len(c_a)):
        if(c_a[i] == 0):
            c_a[i] = -1

    return c_a
   