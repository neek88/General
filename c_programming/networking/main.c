#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>

#include <netinet/in.h>
#include <arpa/inet.h>

int main(int argc,char* argv[])
{
	printf("IP Handling \n");
	
	// Documentation of some basic structures used by Network System calls

	// Format of structure returned by 'getaddrinfo()' sys call
	struct addrinfo
	{
		int ai_flags;					// AI_PASSIVE, AI_CANONNAME
		int	ai_family;					// AF_INET, AF_INET6, AF_UNSPEC
		int ai_socktype;				// SOCK_STREAM, SOCK_DGRAM
		int ai_protocol;				// use '0' for any
		size_t ai_addrlen;				// size of ai_addr in bytes
		struct sockaddr* ai_addr;		// sockaddr_in or in6
		char*  ai_canonname; 			// full canonical hostname


		struct addrinfo* ai_next; 		// next 'addrinfo' node
	};

	struct sockaddr 
	{
		unsigned short sd_family;	// address family, AF_INET, AF_INET6, etc..
		char sd_data[14];			// 14 bytes of protocol address
	};

	// These two go together IPV4
	struct sockaddr_in 					// Can be cast to 'struct sockaddr' due to padding...
	{
		short int 			sin_family;		// Address Family: AF_INET
		unsigned short int 	sin_port;		// Port number - must be in 'Network Byte Order'
		struct in_addr		sin_addr;		// Address Structure
		unsigned char 		sin_zero[8];	// same size as 'struct sockaddr' - Padding - set to zero with 'memset()'
	};

	struct in_addr							// used for IPV4
	{
		uint32_t s_addr; 		// 32 bit int
	};

	//These two go together IPV6
	struct sockaddr_in6
	{
		uint16_t 		sin6_family;		// Address Family: AF_INET6
		uint16_t	 	sin6_port;			// Port number - must be in 'Network Byte Order'
		uint16_t		sin6_flowinfo;		// IPV6 Flow info
		struct in6_addr		sin6_addr;		// Address Structure - IPV6
		uint32_t		sin6_scope_id;		// Scope ID 
	};

	struct in6_addr							// used for IPV6
	{
		unsigned char		sd_addr[16];	// 16 bytes, IPV6 addr
	};

	// Converting from IP address 'number' to struct in_addr/ in6_addr
	struct sockaddr_in sa; 
	struct sockaddr_in6 sa6;

	// These functions return -1 on error, 0 on address error, >0 otherwise 
	// 'pton' =  presentation to network
	// 'ntop' =  network to presentation
	inet_pton(AF_INET, "10.12.110.57", &(sa.sin_addr));					// stuff IPV4 into struct
	inet_pton(AF_INET6, "2001:db8:636b:1::3490", &(sa6.sin6_addr));		// stuff IPV6 into struct

	char ip4[INET_ADDRSTRLEN];
	char ip6[INET6_ADDRSTRLEN];
	inet_ntop(AF_INET, &(sa.sin_addr), ip4, INET_ADDRSTRLEN);			// store IP-addr string in 'ip4'


	// NAT - Network Address Translation
	// Firewall translated Public IP addresses into local so many computers can share one external IP
	// Private network IP addresses allocated to computers are (for example):
	//	10.x.x.x, 192.168.x.x, 172.y.x.x (y: 16-31) (x: 0-255)


	//	getaddrinfo(const char* node,				// website, www.example.com
	//				const char* service,			// http or port number
	//				const struct addrinfo* hints,	// structure used to configure/ help
	//				struct addrinfo** res);			// returned structure 

	// End Documentation

	int status; 
	struct addrinfo hints; 
	struct addrinfo* servinfo;
	struct addrinfo* pnt;

	memset(&hints,0, sizeof hints);			// set hints struct to '0's 
	hints.ai_family = AF_UNSPEC; 			// not sure v4/ v6
	hints.ai_socktype = SOCK_STREAM;		// Stream Socket (... so TCP not UDP)
	hints.ai_flags	= AI_PASSIVE;			// Assign address of local host to the Socket Structures

	// Call 'getaddrinfo' and handle possible errors by streaming to stderr
	// stderr is a standard file pointer
	if( (status = getaddrinfo(argv[1], NULL, &hints, &servinfo)) != 0)
	{
		fprintf(stderr,"getaddrinfo error: %s\n", gai_strerror(status));
		exit(1); 
	}

	printf("Here are the IP Addresses for %s: \n\n",argv[1]);


	for(pnt = servinfo; pnt != NULL; pnt = pnt->ai_next)
	{
		void* addr;
		char* ipver;

		if(pnt-> ai_family == AF_INET)
		{
			struct sockaddr_in* ipv4 = (struct sockaddr_in*)pnt->ai_addr;		// Cast to ipv4 type
			addr = &(ipv4->sin_addr);
			ipver = "IPV4";
		}
		else	// must be IPV6
		{
			struct sockaddr_in6* ipv6 = (struct sockaddr_in6*)pnt->ai_addr;
			addr = &(ipv6->sin6_addr);
			ipver = "IPV6";
		}

		inet_ntop(pnt->ai_family, addr, ip4, sizeof ip4);
		printf(" %s: %s\n", ipver, ip4);

	}


	// Free's Entire linked list built on servinfo
	freeaddrinfo(servinfo);

	return 0; 
}
