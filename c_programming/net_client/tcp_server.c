// Sys --------------------
#include <sys/types.h>
#include <sys/time.h>
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
#define CLIENT_IP		"10.0.0.2"
#define LOCAL_IP		"10.0.0.1"
#define SRV_PORT		(50005)
#define TCP_PKT_LEN		(300)
#define MAX_PKT_LEN		(1024)

int main() 
{
	/* ------------- Setup Command Stream Server Connection --------- */
	int sock_tcp;
	int sock_accept;

	int addrlen = sizeof(struct sockaddr);

	// store connection info of peer
	struct sockaddr_in accept_addr;

	/* ---------- */ 
	printf("Starting up TCP Server\n");
	/* ---------- */ 

	//Setup the Rx / Tx Buffer + Rx Sockaddr
	uint8_t recv_buff[MAX_PKT_LEN] = {0};
	uint8_t tx_buff[MAX_PKT_LEN] = {0};
	int recv_len = 0;

	struct sockaddr_in local_addr;
	memset(&local_addr,0,sizeof(struct sockaddr));
	local_addr.sin_family = AF_INET;
	local_addr.sin_port = htons(SRV_PORT);
	if( inet_pton(AF_INET,LOCAL_IP,&(local_addr.sin_addr.s_addr)) <= 0)
		perror("Error Setting Local IPADDR");

	memset(&accept_addr,0,sizeof(struct sockaddr_in));

	if( (sock_tcp = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP)) ==  -1)
		perror("Error creating socket");

	printf("Binding sock_TCP to port 50005\n");
	if( bind(sock_tcp,(struct sockaddr *)&local_addr,sizeof(local_addr)) == -1)
		printf("Error, could not bind socket to local addr\n");

	printf("Listening for new connection\n");
	if( listen(sock_tcp,32) == -1)
		printf("Error could not set socket to listen mode\n");
	
	if( sock_accept = accept(sock_tcp,(struct sockaddr*)&accept_addr,&addrlen) == -1)
		printf("Error, could not accept new connection\n");


	printf("accepted new connection!\n");

	// receive data from server
	for(;;){
		recv_len = recv(sock_accept,recv_buff,MAX_PKT_LEN,0);
		printf("Data received from remote host: %s\n",recv_buff);

		sleep(1);
	}



	close(sock_accept);
	close(sock_tcp);
	return 0;
}
