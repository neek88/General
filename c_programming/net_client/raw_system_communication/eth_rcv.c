// Receive Data over particular interface 
// Standard C
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
// Sys
#include <sys/types.h>
#include <sys/socket.h>			// Socket Opening
#include <sys/ioctl.h>			// IO-Cntrl - Request Interface Information
#include <unistd.h>
#include <sys/un.h>
#include <linux/sockios.h>
// Net
#include <netdb.h>
#include <netinet/in.h>
#include <net/if.h>				// Network Interface - Struct Ifreq Definition
#include <netinet/ip.h>
#include <netinet/udp.h>
#include <netinet/ether.h>
//#include <netpacket/packet.h>
// IDK
#include <linux/if_packet.h>
#include <arpa/inet.h>


#define TYPE_LEN	(2)
#define ARG_LEN		(2)
#define DATA_LEN	(256)
#define ADDR_LEN	(4)
#define TOTL_LEN	(258)
#define PKT_LEN		(272)
#define RUN_COUNT	(1)

// Create Ethernet Packet
typedef struct eth_pkt
{
	uint8_t dest_mac[6];						// From FPGA
	uint8_t source_mac[6];						// From PC - Updated automatically By Program
	uint8_t len_type[2];						// Just length of Data in bytes, ETH <= 1500
	char data[DATA_LEN];
}Ether;

int compare_addr(uint8_t* addr1, uint8_t* addr2)
{
	for(int i=0; i<ETH_ALEN; i++)
		if(*addr1++ != *addr2++) return 0;
	return 1;
}

int raw_recvfrom(int sockfd, uint8_t* rx_dest, Ether* packet)
{

	// Receive buff/ sockaddr
	size_t rx_buff_len = PKT_LEN;
	char rx_buff[272] = {0};
	uint8_t* rxptr = rx_buff;

	// Receive sockaddr struct 
	struct sockaddr rcv; 
	socklen_t addr_len = sizeof(struct sockaddr);

	int size;
	ioctl(sockfd,SIOCINQ,&size);
	printf("buffer size: %d\n",size);
	
	while(1)
	{
		while(!compare_addr(packet->dest_mac,rx_dest))
		{
			if(recvfrom(sockfd,rx_buff,rx_buff_len,0,&rcv,&addr_len) < 0 )
		 	{
		 		printf("Error in recfrom function\n");
		 		return -1;
		 	}

			memcpy(packet->dest_mac,	rxptr,		ETH_ALEN);
		 	memcpy(packet->source_mac,	rxptr+6,	ETH_ALEN);
		 	memcpy(packet->len_type,	rxptr+12,	TYPE_LEN);
		 	memcpy(packet->data,		rxptr+14,	TOTL_LEN);
		 	memset(rx_buff,0,PKT_LEN);

		 	printf("Data: %s \n",packet->data);

		}
		memset(packet->dest_mac,0,ETH_ALEN);
		ioctl(sockfd,SIOCINQ,&size);
		printf("buffer size: %d\n",size);	
	}

	return 0;
} 

//////////////////
//		MAIN	//
//////////////////
int main(int argc,char* argv[])
{	
	printf("welcome to eth recv");
	if(argc == 0)
	{
		printf("Need to enter the interface to receive from");
		return 1; 
	}
	else
	{

		printf("%s\n",argv[1]);
	}

	// Open Raw Socket for Receive
	int sockrcv; 
	if( (sockrcv = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL))) == -1)
		perror("socket error");

	struct ifreq if_mac;
	struct ifreq if_idx;
	memset(&if_mac,0,sizeof(struct ifreq));
	memset(&if_idx,0,sizeof(struct ifreq));

	// ioctl() for sockrcv
	if (ioctl(sockrcv, SIOCGIFINDEX, &if_idx) < 0)
	    perror("SIOCGIFINDEX");
	// Get the MAC address of the interface to receive on 
	if (ioctl(sockrcv, SIOCGIFHWADDR, &if_mac) < 0)
	    perror("SIOCGIFHWADDR");

	// Setup Receive Packet 
	Ether rcv_msg = {0};
	uint8_t src_check[6] = {0xd5,0xde,0x0,0x0,0x68,0x57};

	raw_recvfrom(sockrcv, src_check, &rcv_msg);



	return 0; 
}
