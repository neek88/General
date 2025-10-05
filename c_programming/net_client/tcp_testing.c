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
#define SERVER_IP		"10.0.0.5"
#define LOCAL_IP		"10.0.0.1"
#define TCP_PORT		(50003)
#define MAX_PKT_LEN		(1500)
#define TXBUFF_LEN		(100)


int main()
{

/* ------------- Setup TCP Connection --------- */

/* Steps for setting up a TCP connection
 *  1. define a server "sockaddr_in" struct with:
 *		- internet family (AF_INET)
 *		- remote port number
 *		- remote IP address
 *	2. Get a socket file descriptor
 *		- SOCK_STREAM or SOCK_DGRAM
 *	3. Connect() w/ server 
 *		- use the server "sockddr_in" struct to start the connection
 *	4. Setup TX/ RX buffers for sending and receiving data
 *
 */

	char buff[10] = {0};
	// Setup our socket file descriptor + local sockaddr struct
	int sock_tcp;
	int addrlen = sizeof(struct in_addr);

	// struct sockaddr_in tcp_sockaddr;
	// memset(&tcp_sockaddr, 0, sizeof(struct sockaddr_in));
	// tcp_sockaddr.sin_family = AF_INET; 
	// tcp_sockaddr.sin_port	= htons(TCP_PORT);

	// if(inet_pton(AF_INET,LOCAL_IP,&(tcp_sockaddr.sin_addr)) <= 0)
	// 	perror("Error Setting local IPADDR");

	// printf("Local IP: %x\n",ntohl(tcp_sockaddr.sin_addr.s_addr));


	/* ---------- */ 
	printf("Starting up TCP connection\n");
	/* ---------- */ 

	if( (sock_tcp = socket(PF_INET, SOCK_STREAM, IPPROTO_IP)) ==  -1)
		perror("Error creating socket");

	//Setup the Rx / Tx Buffer + Rx Sockaddr
	uint8_t recvbuff[MAX_PKT_LEN] = {0};
	uint8_t tx_buff[TXBUFF_LEN] = {0};
	int recv_len = 0;

	struct sockaddr_in tcp_server_addr;
	memset(&tcp_server_addr,0,sizeof(struct sockaddr));
	tcp_server_addr.sin_family = AF_INET;
	tcp_server_addr.sin_port = htons(TCP_PORT);
	if( inet_pton(AF_INET,SERVER_IP,&(tcp_server_addr.sin_addr.s_addr)) <= 0)
		perror("Error Setting Remote IPADDR");

	// connect to remote host
	// calling 'connect()' in STREAM mode will establish connection to host or fail
	while( connect(sock_tcp, (struct sockaddr*)&tcp_server_addr, sizeof(struct sockaddr)) == -1 )
	{
		perror("Error in connecting TCP socket");
		sleep(1);
	}
	printf("Connect successful! Starting Data Transmission\n");

	// look for response packet
	if((recv_len = recv(sock_tcp, &recvbuff,MAX_PKT_LEN-1, 0)) == -1)
	{
		perror("recv");
		exit(1);
	}
	print_buffer_char(recvbuff,recv_len);

	// transmit series of packets 
	for(int i = 0; i < 3; i++)
	{
		// send test data
		sprintf(tx_buff,"Here is a packet #%d",i);
		send(sock_tcp,tx_buff,TXBUFF_LEN,0);
		printf("Sent Packet %i\n",i);

		// look for response packet
		if((recv_len = recv(sock_tcp, &recvbuff,MAX_PKT_LEN-1, 0)) == -1)
		{
			perror("recv");
			exit(1);
		}
		print_buffer_char(recvbuff,recv_len);

		sleep(1);
	}

	// fgets(buff,10,stdin);

	if(close(sock_tcp) != 0)
		perror("error closing socket: ");

	return 0;
}