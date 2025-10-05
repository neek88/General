
#include "include/raw_packets.h"

void print_buffer_hex(uint8_t* data, uint32_t len)
{
	for(int i=0; i<len;i++)
		printf("%x ",*data++);
	printf("\n");
}

void print_buffer_char(uint8_t* data, uint32_t len)
{
	for(int i=0; i<len;i++)
		printf("%c",*data++);
	printf("\n");
}

void print_packet_str(Ether* packet)
{
	uint8_t* data = (uint8_t*)packet;

	printf("Dest MAC: ");
	for(int i=0; i<ETH_ALEN;i++) printf("%x",*data++);
	printf("\n");
	
	printf("Src MAC: ");
	for(int i=0; i<ETH_ALEN;i++) printf("%x",*data++);
	printf("\n");

	printf("Len Type: ");
	for(int i=0; i<TYPE_LEN;i++) printf("%x",*data++);
	printf("\n");

	printf("Message: %s\n", packet->data);
}

void print_packet_hex(Ether* packet)
{
	uint8_t* data = (uint8_t*)packet;

	printf("Dest MAC: ");
	for(int i=0; i<ETH_ALEN;i++) printf("%x",*data++);
	printf("\n");
	
	printf("Src MAC: ");
	for(int i=0; i<ETH_ALEN;i++) printf("%x",*data++);
	printf("\n");

	printf("Len Type: ");
	for(int i=0; i<TYPE_LEN;i++) printf("%x",*data++);
	printf("\n");

	printf("Data: ");
	for(int i=0; i<TOTL_LEN;i++) printf("%x",*data++);
	printf("\n");
}

int compare_addr(uint8_t* addr1, uint8_t* addr2)
{
	for(int i=0; i<ETH_ALEN; i++)
		if(*addr1++ != *addr2++) return 0;
	return 1;
}


int raw_sendto(int sockfd, Ether msg, struct sockaddr_ll sock_addr)
{
	// SOCK_DGRAM/ SOCK_RAW must be used with 'sendto' and 'recvfrom' commands  
	if( sendto(sockfd, &msg, sizeof(msg), 0, (struct sockaddr*)&sock_addr, sizeof(struct sockaddr_ll)) < 0)
	{
		perror("Packet Send Failed: "); 
		return 1;
	}	
	printf("Sending Message: %s \n", (msg.data));
	return 0;
}

int send_data(int sockfd, Ether* msg, struct sockaddr_ll* sock_addr, uint32_t addr_start)
{
	uint8_t data_string[TOTL_LEN] = {0};

	// Set data as 'command'
	memset(data_string,0x0D0D,2);
	memset(data_string+2,addr_start,DADDR_LEN);

	// // Write count into the data stream
	// for(int i=0; i<DATA_LEN-DADDR_LEN;i++) data_string[i+6] = i;

	memcpy(msg->data,data_string,TOTL_LEN);

	// Transmit the packet 
	// SOCK_DGRAM/ SOCK_RAW must be used with 'sendto' and 'recvfrom' commands  
	if( sendto(sockfd, msg, sizeof(Ether), 0, (struct sockaddr*)sock_addr, sizeof(struct sockaddr_ll)) < 0)
	{
		perror("Packet Send Failed - "); 
		return 1;
	}	
	print_buffer_hex(msg->data,TOTL_LEN);

	return 0;
}

int send_command(int sockfd, Ether* msg, struct sockaddr_ll* sock_addr, int arg_count, uint32_t* args)
{
	char buffer[100] = {0};
	char command_string[TOTL_LEN] = {0};

	// Set data as 'command'
	memset(command_string,0x0C0C,2); 
	strcpy(command_string+2,">0(!)\0");

	for(int i=0; i++;i<arg_count)
		printf("%d\n",args[i]);

	for(int i=0; i<arg_count;i++)
	{
		// Take each argument and put it into string format
		sprintf(buffer,"%u",args[i]);
		print_buffer_char(buffer,25);
		// Concatenate with the running command string
		strcat(command_string,buffer);
		// Add a space after each value 
		strcat(command_string," \0");
	}

	// Overwrite the final space ' ' with a terminating '<'
	strcpy(command_string+strlen(command_string)-1,"<\0");

	// Load Data into Eth Struct 
	memcpy(msg->data,command_string,TOTL_LEN);

	// Transmit the packet 
	// SOCK_DGRAM/ SOCK_RAW must be used with 'sendto' and 'recvfrom' commands  
	if( sendto(sockfd, msg, sizeof(Ether), 0, (struct sockaddr*)sock_addr, sizeof(struct sockaddr_ll)) < 0)
	{
		perror("Packet Send Failed - "); 
		return 1;
	}	
	printf("Sending Message: %s\n", (msg->data));

	return 0;
}

void send_sample_file(int sockfd, struct sockaddr_ll* socket_address, char* file_name, int* addr_start, Ether* msg)
{

	/// First two bytes are "data" cmd code 
	/// Next four bytes are "Start Address" code 
	/// 258 - 6 = 252, number of bytes to write. 
	/// 252 / 4 = 63 words ("Addresses")
	
	int val = 0;
	int byte = 0;
	int idx  = 0; 
	int addr_step = 63; 
	uint8_t* ptr = msg->data; ptr+= 6; 

	// Setup Receive Packet 
	Ether rcv_msg = {0};

	// Open up the File
	FILE* fp = fopen(file_name,"rb");

	if(!fp)
	{
		perror("Error Opening File");
		exit(EXIT_FAILURE);
	}

	// Continue sending packets until file is completely sent
	while(val != EOF)
	{
		// Read back from the file, place into Ether msg
		while( (val = fgetc(fp)) != EOF && idx++ < 252)
			memset(ptr++,val,1);
		
		print_buffer_hex(msg->data,TOTL_LEN);
		printf("val is: %i\n",val);
		//send_data(sockfd,msg,socket_address,(*addr_start));

		// Reset our parameters
		idx = 0;
		addr_start+=addr_step;
		ptr = msg->data; ptr+=6; 
		memset(msg->data,0,TOTL_LEN);
		
	}

	fclose(fp);

}

int raw_recvfrom(int sockfd, uint8_t* rx_dest, Ether* packet)
{

	// Receive buff/ sockaddr
	size_t	rx_buff_len		= PKT_LEN+6;
	uint8_t rx_buff[PKT_LEN+6]	= {0};
	uint8_t* rxptr			= rx_buff;

	// Receive sockaddr struct 
	struct sockaddr_ll rcv = {0};
	socklen_t addr_len = sizeof(struct sockaddr_ll);

	// int size;
	// ioctl(sockfd,SIOCINQ,&size);
	// printf("buffer size: %d\n",size);
	
	while(!compare_addr(packet->dest_mac,rx_dest))
	{
		if(recvfrom(sockfd,rx_buff,rx_buff_len,0, (struct sockaddr*)&rcv,&addr_len) < 0 )
		{
			printf("Error in recfrom function\n");
			return -1;
		}

		memcpy(packet->dest_mac,	rxptr,		ETH_ALEN);
		memcpy(packet->source_mac,	rxptr+6,	ETH_ALEN);
		memcpy(packet->len_type,	rxptr+12,	TYPE_LEN);
		memcpy(packet->data,		rxptr+14,	TOTL_LEN);

		memset(rx_buff,0,PKT_LEN);
		memset(&rcv,0,sizeof(struct sockaddr_ll));
		printf("Data: %s\n",packet->data);

	}

	memset(packet->dest_mac,0,ETH_ALEN);
	// ioctl(sockfd,SIOCINQ,&size);
	// printf("buffer size: %d\n",size);	

	return 0;
} 

void* recv_thread(){

    printf("Entering recv_thread\n");

	// Open Raw Socket for Receive
	int sockrcv; 
	if( (sockrcv = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL))) == -1)
		perror("socket error");

	struct ifreq if_mac;
	struct ifreq if_idx;
	memset(&if_mac,0,sizeof(struct ifreq));
	memset(&if_idx,0,sizeof(struct ifreq));

	// Get the index of the interface to recv from 
	strncpy(if_idx.ifr_name, INTERFACE, IFNAMSIZ-1);
	if (ioctl(sockrcv, SIOCGIFINDEX, &if_idx) < 0)
		perror("SIOCGIFINDEX");

	// Get the MAC address of the interface to recv from
	strncpy(if_mac.ifr_name, INTERFACE, IFNAMSIZ-1);
	if (ioctl(sockrcv, SIOCGIFHWADDR, &if_mac) < 0)
		perror("SIOCGIFHWADDR");

	// Pick up HW Addr from interface name
	printf("Source Address of Receiving HW Device is: ");
	print_buffer_hex(if_mac.ifr_hwaddr.sa_data,ETH_ALEN);
	printf("Index of HW device is: %i \n", if_idx.ifr_ifindex);

	// Setup Receive Packet 
	Ether rcv_msg = {0};

	raw_recvfrom(sockrcv,if_mac.ifr_hwaddr.sa_data, &rcv_msg);

    close(sockrcv);
}


