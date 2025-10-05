#	Target: Dependencies
#		Command 

# Target
main	: main.o 
	gcc -o main main.o
main.o	: main.c
	gcc -c main.c

# Target
eth	: eth.c raw_packets.c
	gcc -o eth eth.c raw_packets.c

# Target
rec	: eth_rcv.o
	gcc -o rec eth_rcv.o
eth_rcv.o : eth_rcv.c
	gcc -c eth_rcv.c 

# Target 
test : test.c
	gcc -o test test.c

# Target
tcp_server: tcp_server.c command.c 
	gcc -o tcp_server tcp_server.c 

# Target
tcp_client : tcp_client.c command.c
	gcc -o tcp_client tcp_client.c command.c

# Target
udp_client : udp_client.c command.c
	gcc -o udp_client udp_client.c command.c

# Target 
test_file_gen : test_file_gen.c 
	gcc -o test_file_gen test_file_gen.c 

# Target 
tcp_testing : tcp_testing.c command.c
	gcc -o tcp_testing tcp_testing.c command.c

clean:	
	rm main main.o eth eth.o test test.o \
	 	udp_client udp_client.o tcp_client tcp_client.o tcp_testing tcp_testing.o 
