
#include "raw_packets.h"

void print_buffer_hex(uint8_t* data, uint32_t len)
{
	for(int i=0; i<len;i++){
		printf("%x ",*data++);
		if(i % 20 == 0 && i != 0) printf("\n");
	}
	printf("\n");
}

void print_buffer_char(uint8_t* data, uint32_t len)
{
	for(int i=0; i<len;i++)
		printf("%c",*data++);
	printf("\n");
}

void print_packet_str(uint8_t* packet)
{

	printf("Dest MAC: ");
	for(int i=0; i<ETH_ALEN;i++) printf("%x ",*packet++);
	printf("\n");
	
	printf("Src MAC: ");
	for(int i=0; i<ETH_ALEN;i++) printf("%x ",*packet++);
	printf("\n");

	printf("Len Type: ");
	for(int i=0; i<ETH_TLEN;i++) printf("%x ",*packet++);
	printf("\n");

	printf("Message: %s\n", packet);
}

void print_packet_hex(uint8_t* packet, uint32_t len)
{
	printf("Dest MAC: ");
	for(int i=0; i<ETH_ALEN;i++) printf("%x ",*packet++);
	printf("\n");
	
	printf("Src MAC: ");
	for(int i=0; i<ETH_ALEN;i++) printf("%x ",*packet++);
	printf("\n");

	printf("Len Type: ");
	for(int i=0; i<ETH_TLEN;i++) printf("%x ",*packet++);
	printf("\n");

	printf("Data: ");
	for(int i=0; i<(len-ETH_HLEN);i++){
		printf("%x ",*packet++);
		if(i % 20 == 0 && i != 0) printf("\n");
	}
	printf("\n");
}

int compare_addr(uint8_t* addr1, uint8_t* addr2)
{
	for(int i=0; i<ETH_ALEN; i++)
		if(*addr1++ != *addr2++) return 1;
	return 0;
}

void send_sample_file(int sockfd, struct sockaddr_ll* socket_address, char* file_name)
{	
	int val = 0;
	int byte = 0;
	int idx  = 0; 
	int addr_step = 63; 
	uint8_t* ptr;

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

		//send_data(sockfd,msg,socket_address,(*addr_start));		
	}

	fclose(fp);
}

/* Copy a single network packet into the given file. Function is
   meant to be called multiple times during a network capture
 */
int copy_to_file(FILE* fp, uint8_t* buffer, uint32_t capture_len){
		
	// skip over packet header info
	buffer += TOTAL_HDR_LEN;
	capture_len -= TOTAL_HDR_LEN;

	// write the total upcoming packet length to file
	fwrite(&capture_len,sizeof(uint32_t),1,fp);

	// copy contents of buffer to file
	for(int i = 0; i<capture_len;i++){
		fputc((buffer[i]),fp);
	}

	return 0;
}

/* Load a single network packet from the given file. Function is
	meant to be called multiple times during a network transfer
 */ 
int load_from_file(FILE* fp, uint8_t* buffer, uint32_t max_length){

	int packet_length;

	// ead out first word, capturing the packet length
	fread(&packet_length,sizeof(uint32_t),1,fp);

	if(packet_length <= max_length){
		// copy file contents from buffer
		for(int i = 0; i < packet_length; i++){
			buffer[i] = fgetc(fp);
		}
		return packet_length;
	}
	else {
		return -1;
	}
}

int raw_recvfrom(int sockfd, uint8_t* rx_mac, uint16_t rx_port, uint8_t* rx_buff)
{
	// Receive buff/ sockaddr
	uint8_t buffer[BUFF_LEN] = {0};
	uint32_t recv_count;

	// filtering parameters
	struct ethhdr* eth_hdr = (struct ethhdr*)buffer;
	uint16_t dest_port;

	// Receive sockaddr struct 
	struct sockaddr_ll recv_addr = {0};
	socklen_t addr_len = sizeof(struct sockaddr_ll);
	
	printf("Looking for data on socket: %i, interface: ",sockfd);
	print_buffer_hex(rx_mac,ETH_ALEN);
	
	// receive data on socket until destination mac matches our local MAC & Port
	while( compare_addr(recv_addr.sll_addr,rx_mac) || ntohs(dest_port) != rx_port){

		// reset the recv_addr struct for next check
		memset(&recv_addr,0,addr_len);
		memset(buffer,0,BUFF_LEN);

		if( (recv_count = recvfrom(sockfd,buffer,BUFF_LEN,0,(struct sockaddr*)&recv_addr,&addr_len)) < 0 ){
			printf("Error in recfrom function\n");
			return -1;
		}
		// capture port from received packet
		memcpy(&dest_port,(buffer+ETH_HLEN+IP_HDR_LEN+2),sizeof(uint16_t));
	}

	// copy contents to user buffer
	memcpy(rx_buff, buffer, recv_count);
	
	return recv_count;
} 

void* recv_thread(){

	// Setup Receive Packet Thread 
	// pthread_t tid;
	// int tc;
	// if( (tc= pthread_create(&tid,NULL,recv_thread,NULL)) == 1){
	// 	printf("ERROR: Return code from pthread_create() is %d\n",tc);
	// 	exit(-1);
	// }
	//pthread_exit(NULL);


	#define INTERFACE	("enx3c18a0d36857")

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

	//raw_recvfrom(sockrcv,if_mac.ifr_hwaddr.sa_data,NULL);

    close(sockrcv);
}

int break_string(char* string_to_break, char*** broken_string, int buff_len)
{
	/* ToDo: 
	* protect against strings without terminator: \0
	* remove \n + \r from strings
	*/

	int max_str_len = 0;		// determine size of largest entered string
	int max_num_strs = 0;		// determine number of strings entered 
	int char_cnt = 0;
	int buff_cnt = 0;

	char* step = string_to_break;

	// Scan through string to determine number of strings/ max length of string
	while(*step != '\0' && buff_cnt < buff_len){

		while(*step != '\0' && buff_cnt < buff_len && *step != ' '){
			//printf("Debug - Length Counter: %c\n",*step);			
			char_cnt++;
			buff_cnt++;
			step++;
		}
		step++;
		buff_cnt++;
		if(char_cnt > max_str_len)
			max_str_len = char_cnt;

		char_cnt = 0;
		max_num_strs++;
	}

	// Create string arrary to hold each input string individually
	char** str_broken = malloc(max_num_strs*sizeof(char*));
	char** str_stable = str_broken;
	char* str_cnt;

	// allocate array for each entry in array of strings 
	for(int i=0; i<max_num_strs;i++)
		str_broken[i] = malloc(max_str_len);

	while(*string_to_break != '\0')
	{
		str_cnt = (*str_broken);
		while(*string_to_break != ' ' && *string_to_break != '\0' && *string_to_break != '\n' && *string_to_break != '\r')
		{	
			(*str_cnt) = *string_to_break;
			string_to_break++;	
			str_cnt++;
		}
		*str_cnt = '\0';
		str_broken++;
		string_to_break++;
		str_cnt = *str_broken;
	}

	// for(int i=0; i<max_num_strs;i++)
	//  	printf("Debug - captured strings: %s\n",str_stable[i]);

	*broken_string = str_stable;
	return max_num_strs;
}


