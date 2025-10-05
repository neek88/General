//Standard C
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
// P-Threads
#include <pthread.h>
// Local Raw Packet Files
#include "raw_packets.h"

#define WIRED			("enx3c18a0d36857")
#define WIRELESS		("wlp59s0")
#define SERVICE_PORT	(443)

/*
- Simple raw networking communication program
- Main purpose is to watch a network interface
	for incoming packets, and break them apart for 
	file storage
- socket protocols:
	- IPPROTO_RAW: only accept data running on raw network protocol
	- ETH_P_ALL: all network packets, pass as 'htons(ETH_P_ALL)'
*/

int main(int argc,char* argv[])
{	

	int sockfd; 
	int recv_count;
	uint8_t rx_buff[ETH_FRAME_LEN];
	FILE* fp;

	// Zero ifreq structs
	struct ifreq if_mac;
	struct ifreq if_idx;
	memset(&if_mac,0,sizeof(struct ifreq));
	memset(&if_idx,0,sizeof(struct ifreq));
	
	// open a raw socket for receive functionality 
	if((sockfd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL))) == -1) 
		perror("socket error");
	
	// Get the index of the interface to send on 
	strncpy(if_idx.ifr_name, WIRELESS, IFNAMSIZ-1);
	if (ioctl(sockfd, SIOCGIFINDEX, &if_idx) < 0)
	    perror("SIOCGIFINDEX");

	// Get the MAC address of the interface to send/ recieve on 
	strncpy(if_mac.ifr_name, WIRELESS, IFNAMSIZ-1);
	if (ioctl(sockfd, SIOCGIFHWADDR, &if_mac) < 0)
	    perror("SIOCGIFHWADDR");

	// Setup Link-Layer socket struct 
	// dest MAC, interface index
	struct sockaddr_ll socket_address;
	socket_address.sll_ifindex = if_idx.ifr_ifindex;
	socket_address.sll_halen = ETH_ALEN;
	memcpy(socket_address.sll_addr, if_mac.ifr_hwaddr.sa_data,ETH_ALEN);

	// bind our socket to the local HW, so we can capture outgoing packets
	bind(sockfd,(struct sockaddr*)&socket_address,sizeof(struct sockaddr_ll));

	// Open file to copy packets over to
	fp = fopen("data_capture.txt","wb+");

	if(!fp){
		perror("Error Opening File: ");
		return 1;
	}

	// Pull data off of network interface
	for(int i = 0; i<5; i++){

		recv_count = raw_recvfrom(sockfd, socket_address.sll_addr, SERVICE_PORT, rx_buff);

		// display full packet contents
		printf("received data:\n");
		print_packet_hex(rx_buff, recv_count);

		if(copy_to_file(fp, rx_buff, recv_count)){
			printf("failed to write file\n");
			break;
		}
        
        sleep(2);
        memset(rx_buff,0,ETH_FRAME_LEN);
    }

	/* -- Clean up -- */ 
	close(sockfd);
	fclose(fp);

	/* -- Exit program -- */
	return 0; 
}

    // fclose(fp);
    // // open file in read mode
    // fp = fopen("data_capture.txt","rb");
    // uint8_t tx_buff[ETH_FRAME_LEN];
    // uint32_t pkt_len;

    // for(int i = 0; i<5; i++){
    //     // populate the transmit buffer
    //     if( (pkt_len = load_from_file(fp,tx_buff,ETH_FRAME_LEN)) < 0){
    //         printf("failed to read from file\n");
    //     }

    //     //display read-back data to confirm operation
    //     printf("retrieved data:\n");
	// 	print_buffer_hex(tx_buff, pkt_len);

    //     memset(tx_buff,0,ETH_FRAME_LEN);
	// }