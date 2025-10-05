#	Target: Dependencies
#		Command 

# Target
main	: main.o 
	gcc -o main main.o
main.o	: main.c
	gcc -c main.c

# Target
eth	: eth.o
	gcc -o eth eth.o
eth.o	: eth.c 
	gcc -c eth.c 

# Target
rec	: eth_rcv.o
	gcc -o rec eth_rcv.o
eth_rcv.o : eth_rcv.c
	gcc -c eth_rcv.c 

# Target 
test : test.c
	gcc -o test test.c


clean:	
	rm main main.o eth eth.o test.o
