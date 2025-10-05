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
#include <netpacket/packet.h>

// IDK
#include <linux/if_packet.h>
#include <arpa/inet.h>


// Include Paths
// #include "/usr/include/netinet"
// #include "/usr/include/netpacket"
// #include "/usr/include/net"
// #include "/usr/include/arpa"
// 
// #include "/usr/include/linux/socket.h
// #include "/usr/include/linux/sockios.h
// #include "/usr/include/linux/types.h
// #include "/usr/include/linux/tcp.h
// #include "/usr/include/linux/udp.h
// #include "/usr/include/linux/ip.h


///////////////////////////////////////////////////////////////////////
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
///////////////////////////////////////////////////////////////////////

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

getaddrinfo(const char* node,				// website, www.example.com
			const char* service,			// http or port number
			const struct addrinfo* hints,	// structure used to configure/ help
			struct addrinfo** res);			// returned structure 


struct msghdr 
{
	void	*	msg_name;	/* Socket name			*/
	int		msg_namelen;	/* Length of name		*/
	struct iovec *	msg_iov;	/* Data blocks			*/
	int 		msg_iovlen;	/* Number of blocks		*/
	void 	*	msg_control;	/* Per protocol magic (eg BSD file descriptor passing) */
	int		msg_controllen;	/* Length of rights list */
	int		msg_flags;	/* 4.4 BSD item we dont use      */
};

/* Control Messages */

#define SCM_RIGHTS		1

/* Socket types. */
#define SOCK_STREAM	1		/* stream (connection) socket	*/
#define SOCK_DGRAM	2		/* datagram (conn.less) socket	*/
#define SOCK_RAW	3		/* raw socket			*/
#define SOCK_RDM	4		/* reliably-delivered message	*/
#define SOCK_SEQPACKET	5		/* sequential packet socket	*/
#define SOCK_PACKET	10		/* linux specific way of	*/
					/* getting packets at the dev	*/
					/* level.  For writing rarp and	*/
					/* other similar things on the	*/
					/* user level.			*/

/* Supported address families. */
#define AF_UNSPEC	0
#define AF_UNIX		1	/* Unix domain sockets 		*/
#define AF_INET		2	/* Internet IP Protocol 	*/
#define AF_AX25		3	/* Amateur Radio AX.25 		*/
#define AF_IPX		4	/* Novell IPX 			*/
#define AF_APPLETALK	5	/* Appletalk DDP 		*/
#define	AF_NETROM	6	/* Amateur radio NetROM 	*/
#define AF_BRIDGE	7	/* Multiprotocol bridge 	*/
#define AF_AAL5		8	/* Reserved for Werner's ATM 	*/
#define AF_X25		9	/* Reserved for X.25 project 	*/
#define AF_INET6	10	/* IP version 6			*/
#define AF_MAX		12	/* For now.. */

/* Protocol families, same as address families. */
#define PF_UNSPEC	AF_UNSPEC
#define PF_UNIX		AF_UNIX
#define PF_INET		AF_INET
#define PF_AX25		AF_AX25
#define PF_IPX		AF_IPX
#define PF_APPLETALK	AF_APPLETALK
#define	PF_NETROM	AF_NETROM
#define PF_BRIDGE	AF_BRIDGE
#define PF_AAL5		AF_AAL5
#define PF_X25		AF_X25
#define PF_INET6	AF_INET6

#define PF_MAX		AF_MAX

/* Maximum queue length specifiable by listen.  */
#define SOMAXCONN	128

/* Flags we can use with send/ and recv. */
#define MSG_OOB		1
#define MSG_PEEK	2
#define MSG_DONTROUTE	4
/*#define MSG_CTRUNC	8	- We need to support this for BSD oddments */
#define MSG_PROXY	16	/* Supply or ask second address. */

/* Setsockoptions(2) level. Thanks to BSD these must match IPPROTO_xxx */
#define SOL_IP		0
#define SOL_IPX		256
#define SOL_AX25	257
#define SOL_ATALK	258
#define	SOL_NETROM	259
#define SOL_TCP		6
#define SOL_UDP		17

/* IP options */
#define IP_TOS		1
#define	IPTOS_LOWDELAY		0x10
#define	IPTOS_THROUGHPUT	0x08
#define	IPTOS_RELIABILITY	0x04
#define IP_TTL		2
#define IP_HDRINCL	3
#define IP_OPTIONS	4

#define IP_MULTICAST_IF			32
#define IP_MULTICAST_TTL 		33
#define IP_MULTICAST_LOOP 		34
#define IP_ADD_MEMBERSHIP		35
#define IP_DROP_MEMBERSHIP		36

/* These need to appear somewhere around here */
#define IP_DEFAULT_MULTICAST_TTL        1
#define IP_DEFAULT_MULTICAST_LOOP       1
#define IP_MAX_MEMBERSHIPS              20
 
/* IPX options */
#define IPX_TYPE	1

/* TCP options - this way around because someone left a set in the c library includes */
#define TCP_NODELAY	1
#define TCP_MAXSEG	2

/* The various priorities. */
#define SOPRI_INTERACTIVE	0
#define SOPRI_NORMAL		1
#define SOPRI_BACKGROUND	2

extern void memcpy_fromiovec(unsigned char *kdata, struct iovec *iov, int len);
extern int verify_iovec(struct msghdr *m, struct iovec *iov, char *address, int mode);
extern void memcpy_toiovec(struct iovec *v, unsigned char *kdata, int len);
extern int move_addr_to_user(void *kaddr, int klen, void *uaddr, int *ulen);
extern int move_addr_to_kernel(void *uaddr, int ulen, void *kaddr);