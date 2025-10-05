// Sys --------------------
#include <sys/types.h>
#include <sys/socket.h>				// Socket Opening
#include <sys/ioctl.h>				// IO-Cntrl - Request Interface Information
#include <unistd.h>
#include <sys/un.h>
// Net --------------------
#include <netdb.h>
#include <netinet/in.h>
#include <net/if.h>					// Network Interface - Struct Ifreq Definition
#include <netinet/ip.h>
#include <netinet/udp.h>
#include <netinet/ether.h>
#include <netpacket/packet.h>		
//#include <linux/if_packet.h>		
#include <linux/sockios.h>		
#include <arpa/inet.h>	
#include <linux/sockios.h>
// Standard C --------------
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// Command -----------------
#include "include/command.h"		// Exchange data w/ Server  

// Networking constants
#define SERVER_IP		"10.0.0.2"
#define LOCAL_IP		"10.0.0.1"
#define CMD_PORT		(50001)
#define SAMPLE_PORT		(50000)
#define INTERFACE		("enp0s3\0")
#define UDP_PKT_LEN		(300)
#define MAX_PKT_LEN		(1024)

// Command line constants
#define ARGC_MIN		(1)
#define ARGC_MAX		(8)			// User may enter '-c' + 'cmd' + 6 arguments
#define ARG_FUN			(0)
#define ARG_CMD			(1)		
#define CMD_BYTE_LEN  	(100)
#define CMD_ARG_LEN		(10)
#define BASE_10			(10)


int main() 
{
	/* ------------- Setup Command Stream Server Connection --------- */
	int sockfd; 
	int addrlen = sizeof(struct in_addr);
	char src_addr[INET_ADDRSTRLEN];

	struct sockaddr_in udp_sock;
	memset(&udp_sock, 0, sizeof(struct sockaddr_in));
	udp_sock.sin_family = AF_INET; 
	udp_sock.sin_port	= htons(CMD_PORT);

	if(inet_pton(AF_INET,LOCAL_IP,&(udp_sock.sin_addr)) <= 0)
		perror("Error Setting local IPADDR");

	if( (sockfd = socket(PF_INET, SOCK_DGRAM, IPPROTO_IP)) ==  -1)
		perror("Error creating socket");

	printf("Local IP: %x\n",ntohl(udp_sock.sin_addr.s_addr));

	// Setup the RX Buffer/ Sockaddr
	struct sockaddr_in server_addr;
	memset(&server_addr,0,sizeof(struct sockaddr));
	server_addr.sin_family = AF_INET;
	server_addr.sin_port = htons(CMD_PORT);
	if( inet_pton(AF_INET,SERVER_IP,&(server_addr.sin_addr.s_addr)) <= 0)
		perror("Error Setting Remote IPADDR");

	uint8_t recvbuff[UDP_PKT_LEN];
	int recv_len = 0;

	// connect to remote host
	// calling 'connect()' in DGRAM mode will setup external 
	// port and IP address for future 'send()' calls 
	// It will not establish TCP style connection
	if(connect(sockfd, (struct sockaddr*)&server_addr, sizeof(struct sockaddr)) == -1 )
		perror("Error in connecting UDP socket");

	// // Send Data to Remote Host 
	// // We can use 'send()' call since we've associated
	// // our 'sockfd' w/ this remote server 
	uint8_t sendbuff[UDP_PKT_LEN] = "Starting UDP Connection\0";
	int sent_bytes = send(sockfd,sendbuff,UDP_PKT_LEN,0);
	printf("Data sent to remote host: %d bytes\n",sent_bytes);
	recv(sockfd,recvbuff,UDP_PKT_LEN,0);
	printf("Data received from remote host: %s\n",recvbuff);
	memset(recvbuff,0,UDP_PKT_LEN);

	/* ------------- Setup Sample Stream Server Connection --------- */
	int sample_sock; 
	int addrlen_sample = sizeof(struct in_addr);
	char src_addr_smpl[INET_ADDRSTRLEN];

	// Setup our sample stream socket
	struct sockaddr_in udp_smpl_sock;
	memset(&udp_smpl_sock, 0, sizeof(struct sockaddr_in));
	udp_smpl_sock.sin_family = AF_INET; 
	udp_smpl_sock.sin_port	= htons(SAMPLE_PORT);

	if(inet_pton(AF_INET,LOCAL_IP,&(udp_smpl_sock.sin_addr)) <= 0)
		perror("Error Setting local IPADDR, sample socket");

	if( (sample_sock = socket(PF_INET, SOCK_DGRAM, IPPROTO_IP)) ==  -1)
		perror("Error creating sample socket");

	// Setup the RX Buffer/ Sockaddr
	struct sockaddr_in smpl_server_addr;
	memset(&smpl_server_addr,0,sizeof(struct sockaddr));
	smpl_server_addr.sin_family = AF_INET;
	smpl_server_addr.sin_port = htons(SAMPLE_PORT);
	if( inet_pton(AF_INET,SERVER_IP,&(smpl_server_addr.sin_addr.s_addr)) <= 0)
		perror("Error Setting Remote IPADDR, sample socket");

	// connect to remote host
	// calling 'connect()' in DGRAM mode will setup external 
	// port and IP address for future 'send()' calls 
	// It will not establish TCP style connection
	if(connect(sample_sock, (struct sockaddr*)&smpl_server_addr, sizeof(struct sockaddr)) == -1 )
		perror("Error in connecting UDP sample socket");

	/* ---------------- Command Line Interface ---------------------- */
	char* parse;
	uint32_t addr_start = 0;
	uint32_t cmd_entry[CMD_ARG_LEN] = {0};
	char cmd_string[CMD_BYTE_LEN] = {0};		// full command string
	char** arg_str;								// command string array, holds separated strings
	int num_args;

	while(1){
		// Pull from CMD Line 
		printf("> Please enter command starting with '-c' OR '-d' \n");
		printf("> ");
		fgets(cmd_string,CMD_BYTE_LEN,stdin);

		// Put string into array of strings separated by incoming spaces
		num_args = break_string(cmd_string,&arg_str, CMD_BYTE_LEN);

		if(num_args >= ARGC_MIN && num_args <= ARGC_MAX){

			// Handle User Command
			if( !strcmp(arg_str[ARG_FUN], "-c\0")){
				send_command_str(sockfd,num_args-1,++arg_str);
				recv(sockfd,recvbuff,UDP_PKT_LEN,0);
				printf("Received message:\n%s",recvbuff);
				printf("\n\n");
			}

			// Handle File Write to DRAM at given Address
			else if(!strcmp(arg_str[ARG_FUN],"-d\0") && num_args == 3){
				parse = NULL;
				addr_start = strtol(arg_str[ARG_CMD],&parse,BASE_10);
				send_sample_file(sample_sock,arg_str[ARG_CMD+1],addr_start);
			}

			// terminate program, closing the socket for next run
			else if(!strcmp(arg_str[ARG_FUN],"close\0")){
				break;
			}
			else{
				printf("Error: Must enter '-c' / '-d' command tags...\n");
			}
		}
		else{
			printf("Please Enter Correct Command Sequence\n");
		}
		// Reset cmd
		memset(cmd_string,0,CMD_BYTE_LEN);
		memset(cmd_entry,0,CMD_ARG_LEN*4);
	}

	//// Clean up ////
	free_arg_list(arg_str,num_args);
	close(sockfd);

	return 0; 
}