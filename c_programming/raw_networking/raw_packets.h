#ifndef RAW_PACKET_H
#define RAW_PACKET_H

/*	Networking library documentation
	<sys/socket.h> 
		Core BSD socket functions and data structures.
	<netinet/in.h> 
		AF INET and AF INET6 address families and their corresponding protocol families PF_INET and PF_INET6. 
		Widely used on the Internet, these include IP addresses and TCP and UDP port numbers.
	<sys/un.h> 
		PF_UNIX/PF_LOCAL address family. 
		Used for local communication between programs running on the same computer. 
		Not used on networks.
	<arpa/inet.h> 
		Functions for manipulating numeric IP addresses.
	<netdb.h>
		Functions for translating protocol names and host names into numeric addresses. 
		Searches local data as well as DNS.
*/

// sys
#include <sys/types.h>
#include <sys/socket.h>			// Socket Opening
#include <sys/ioctl.h>			// IO-Cntrl - Request Interface Information
#include <sys/un.h>
#include <linux/sockios.h>
#include <unistd.h>
// net
#include <netdb.h>
#include <netinet/in.h>
#include <net/if.h>				// Network Interface - Struct Ifreq Definition
#include <netinet/ip.h>
#include <netinet/tcp.h>
#include <netinet/udp.h>
#include <netinet/ether.h>
#include <netpacket/packet.h>
//#include <linux/if_packet.h>
#include <arpa/inet.h>
// standard
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BUFF_LEN		(500)
#define TCP_HDR_LEN		(20)
#define IP_HDR_LEN		(20)
#define TOTAL_HDR_LEN	(TCP_HDR_LEN+IP_HDR_LEN+ETH_HLEN)

void print_buffer_hex(uint8_t* data, uint32_t len);

void print_buffer_char(uint8_t* data, uint32_t len);

void print_packet_str(uint8_t* packet);

void print_packet_hex(uint8_t* packet, uint32_t len);

int compare_addr(uint8_t* addr1, uint8_t* addr2);

int copy_to_file(FILE* fp, uint8_t* buffer, uint32_t capture_len);

int load_from_file(FILE* fp, uint8_t* buffer, uint32_t max_length);

void send_sample_file(int sockfd, struct sockaddr_ll* socket_address, char* file_name);

int raw_recvfrom(int sockfd, uint8_t* mac, uint16_t port, uint8_t* rx_buff);

void* recv_thread();

void free_arg_list(char** arglist,int length);

int break_string(char* string_to_break, char*** broken_string, int buff_len);

#endif  // RAW_PACKETS_H