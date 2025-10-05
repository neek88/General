#	Target: Dependencies
#		Command 

# Target
eth	: eth.c raw_packets.c
	gcc -o eth eth.c raw_packets.c

# Target
rec	: eth_rcv.c
	gcc -o rec eth_rcv.c

clean:	
	rm eth eth.o