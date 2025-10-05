#ifndef RAW_PACKET_H
#define RAW_PACKET_H

// sys
#include <sys/types.h>
#include <sys/socket.h>			// Socket Opening
#include <sys/ioctl.h>			// IO-Cntrl - Request Interface Information
#include <unistd.h>
#include <sys/un.h>
#include <linux/sockios.h>
// net
#include <netdb.h>
#include <netinet/in.h>
#include <net/if.h>				// Network Interface - Struct Ifreq Definition
#include <netinet/ip.h>
#include <netinet/udp.h>
#include <netinet/ether.h>
#include <netpacket/packet.h>
// #include <linux/if_packet.h>
#include <arpa/inet.h>
// standard
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ETH_ALEN	(6)
#define TYPE_LEN	(2)
#define ARG_LEN		(2)
#define DATA_LEN	(256)
#define ADDR_LEN	(4)
#define TOTL_LEN	(258)
#define PKT_LEN		(272)
#define DADDR_LEN	(4)
#define INTERFACE	("enx3c18a0d36857")

// Create Ethernet Packet
typedef struct eth_pkt
{
	uint8_t dest_mac[6];						
	uint8_t source_mac[6];						
	uint8_t len_type[2];
	char data[TOTL_LEN];
}Ether;

void print_buffer_hex(uint8_t* data, uint32_t len);

void print_buffer_char(uint8_t* data, uint32_t len);

void print_packet_str(Ether* packet);

void print_packet_hex(Ether* packet);

int compare_addr(uint8_t* addr1, uint8_t* addr2);

int raw_sendto(int sockfd, Ether msg, struct sockaddr_ll sock_addr);

int send_data(int sockfd, Ether* msg, struct sockaddr_ll* sock_addr, uint32_t addr_start);

int send_command(int sockfd, Ether* msg, struct sockaddr_ll* sock_addr, int arg_count, uint32_t* args);

void send_sample_file(int sockfd, struct sockaddr_ll* socket_address, char* file_name, int* addr_start, Ether* msg);

int raw_recvfrom(int sockfd, uint8_t* rx_dest, Ether* packet);

void* recv_thread();


#endif  // RAW_PACKETS_H