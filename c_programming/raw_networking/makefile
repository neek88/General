#	Target: Dependencies
#		Command 

# Target
network_capture	: network_capture.c raw_packets.c
	gcc -o network_capture network_capture.c raw_packets.c

# Target
rec	: eth_rcv.c
	gcc -o rec eth_rcv.c

clean:	
	rm eth eth.o