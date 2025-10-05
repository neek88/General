// Standard C
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Sys
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/ioctl.h>

#include <unistd.h>

// Net
#include <netdb.h>
#include <netinet/in.h>
#include <net/if.h>
#include <netinet/ip.h>
#include <netinet/udp.h>
#include <netinet/ether.h>
//#include <netpacket/packet.h>

// IDK
#include <linux/if_packet.h>
#include <arpa/inet.h>


// Scan through our ethernet message, converting to Network Order on word-word basis
// uint8_t* ptr = (uint8_t*)&msg; 
// uint8_t* baseptr = ptr;
// uint32_t* word = (uint32_t*)&msg;
// uint32_t* step = (uint32_t*)&no_msg;
// for(int i=0; i<68;i++)
// *step = htonl(*word); word++; step++;
// /////////////////////////////////


int main(int argc,char* argv[])
{	
	//-- Documentation of some basic structures used by Network System calls --//

	// 'struct ifreq'
	// Passed to IOCTL() - interface with input/output devices
	struct ifreq
	{
		union 
		{
			struct sockaddr	ifr_addr;
			struct sockaddr ifr_dstaddr;
			struct sockaddr ifr_broadaddr;
			struct sockaddr ifr_netmask;
			struct sockaddr ifr_hwaddr;
			short 			ifr_flags;
			int				ifr_ifindex;
			int				ifr_metric;
			int				ifr_mtu;
			struct ifmap	ifr_map;
			char			ifr_slave[IFNAMESIZ];
			char			ifr_newname[IFNAMESIZ];
			char*			ifr_data; 
		};
	};

	struct sockaddr_ll 
	{
		unsigned short sll_family;   /* Always AF_PACKET */
		unsigned short sll_protocol; /* Physical-layer protocol */
		int            sll_ifindex;  /* Interface number */
		unsigned short sll_hatype;   /* ARP hardware type */
		unsigned char  sll_pkttype;  /* Packet type */
		unsigned char  sll_halen;    /* Length of address */
		unsigned char  sll_addr[8];  /* Physical-layer address */
    };

	// Basic structure to hold Address info
	// Usually Casted to particular type based on Family - IPV4/ IPV6
	struct sockaddr
	{
		sa_family_t			sa_family;
		char				sa_data[14];
	};

	// Format of structure returned by 'getaddrinfo()' sys call
	struct addrinfo
	{
		int ai_flags;							// AI_PASSIVE, AI_CANONNAME
		int	ai_family;							// AF_INET, AF_INET6, AF_UNSPEC
		int ai_socktype;						// SOCK_STREAM, SOCK_DGRAM
		int ai_protocol;						// use '0' for any
		size_t ai_addrlen;						// size of ai_addr in bytes
		struct sockaddr* ai_addr;				// sockaddr_in or in6
		char*  ai_canonname; 					// full canonical hostname

		struct addrinfo* ai_next; 		// next 'addrinfo' node
	};

	//    *  sll_protocol is the standard ethernet protocol type in network
    //       byte order as defined in the <linux/if_ether.h> include file.
    //       It defaults to the socket's protocol.

    //    *  sll_ifindex is the interface index of the interface (see
    //       netdevice(7)); 0 matches any interface (only permitted for
    //       binding).  sll_hatype is an ARP type as defined in the
    //       <linux/if_arp.h> include file.

    //    *  sll_pkttype contains the packet type.  Valid types are
    //       PACKET_HOST for a packet addressed to the local host,
    //       PACKET_BROADCAST for a physical-layer broadcast packet,
    //       PACKET_MULTICAST for a packet sent to a physical-layer
    //       multicast address, PACKET_OTHERHOST for a packet to some other
    //       host that has been caught by a device driver in promiscuous
    //       mode, and PACKET_OUTGOING for a packet originating from the
    //       local host that is looped back to a packet socket.  These
    //       types make sense only for receiving.

    //    *  sll_addr and sll_halen contain the physical-layer (e.g., IEEE
    //       802.3) address and its length.  The exact interpretation
    //       depends on the device.

	struct sockaddr 
	{
		unsigned short sa_family;				// address family, AF_INET, AF_INET6, etc..
		char sa_data[14];						// 14 bytes of protocol address
	};

	// These two go together IPV4
	struct in_addr								// used for IPV4
	{
		uint32_t s_addr; 						// 32 bit int
	};

	struct sockaddr_in 							// Can be cast to 'struct sockaddr' due to padding...
	{
		short int 			sin_family;			// Address Family: AF_INET
		unsigned short int 	sin_port;			// Port number - must be in 'Network Byte Order'
		struct in_addr		sin_addr;			// Address Structure
		unsigned char 		sin_zero[8];		// same size as 'struct sockaddr' - Padding - set to zero with 'memset()'
	};

	//These two go together IPV6
	struct sockaddr_in6
	{
		uint16_t 		sin6_family;			// Address Family: AF_INET6
		uint16_t	 	sin6_port;				// Port number - must be in 'Network Byte Order'
		uint16_t		sin6_flowinfo;			// IPV6 Flow info
		struct in6_addr		sin6_addr;			// Address Structure - IPV6
		uint32_t		sin6_scope_id;			// Scope ID 
	};

	struct in6_addr								// used for IPV6
	{
		unsigned char		sd_addr[16];		// 16 bytes, IPV6 addr
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

	//	getaddrinfo(const char* node,				// website, www.example.com
	//				const char* service,			// http or port number
	//				const struct addrinfo* hints,	// structure used to configure/ help
	//				struct addrinfo** res);			// returned structure 

	//-- End Documentation --//