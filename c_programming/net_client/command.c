#include "include/command.h"
// Standard C
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// Networking
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

void print_buffer_hex(uint8_t* data, uint32_t len)
{
	for(int i=0; i<len;i++){
		printf("%02x ",*data++);
		if( (i+1) % 25 == 0) printf("\n");
	}
	printf("\n");
}

void print_buffer_char(uint8_t* data, uint32_t len)
{
	for(int i=0; i<len;i++)
		printf("%c",*data++);
	printf("\n");
}

void free_arg_list(char** arglist,int length)
{
	for(int i=0;i<length;i++){
		free(arglist[i]);
	}
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

int send_command(int sockfd, int arg_count, uint32_t* args)
{
	#define MAX_CMD_LEN	(100)

	char buffer[MAX_CMD_LEN] = {0};
	char command_string[MAX_CMD_LEN] = {0};

	for(int i=0; i<arg_count;i++)
	{
		// Take each argument and put it into string format
		sprintf(buffer,"%u",args[i]);
		//print_buffer_char(buffer,25);
		// Concatenate with the running command string
		strcat(command_string,buffer);
		// Add a space after each value 
		strcat(command_string," \0");
	}

	// Overwrite the final space ' ' with a terminating '<'
	strcpy(command_string+strlen(command_string)-1,"<\0");

	// Transmit the packet 
	if(send(sockfd, command_string, MAX_CMD_LEN, 0) == -1){
		perror("Send packet Failed: ");
		return 1;
	}
	printf("Sending Message: %s\n", command_string);

	return 0;
}

int send_command_str(int sockfd, int arg_count, char** args)
{
	#define MAX_CMD_LEN	(100)

	char buffer[MAX_CMD_LEN] = {0};
	char command_string[MAX_CMD_LEN] = {0};

	for(int i=0; i<arg_count;i++)
	{
		// Concatenate with the running command string
		strcat(command_string,args[i]);
		// Add a space after each value 
		strcat(command_string," \0");
	}

	// Overwrite the final space ' ' with a terminating '<'
	strcpy(command_string+strlen(command_string)-1,"<\0");

	// Transmit the packet 
	if(send(sockfd, command_string, MAX_CMD_LEN, 0) == -1){
		perror("Send packet Failed: ");
		return 1;
	}
	printf("Sending Message: %s\n", command_string);

	return 0;
}

int send_sample_file(int sockfd, char* restrict file_name, int addr_start)
{
	// packet_len 			= 1000
	// header_len (UDP) 	= 42
	// ddr_address + flugg  = 6
	// Total payload length => 1000 - 42 = 958
	// Total sample bytes 	=> 958-6 = 952

	// Note: Number of 16-bit words must be divisible by 4,
	// due to DDR4 addresses incrimenting by 4 each write

	#define PAYLD_LEN 		(958)			// bytes	
	#define SAMPLE_BYTES	(952)
	#define SAMPLE_LEN		(2)		
	#define ADDR_GAP		(6)				// # bytes taken up by store-address + byte alignment
	#define RECV_LEN		(6)
	#define DDR_BASE_ADDR	(0x80000000)	// 0x8000_0000 (PhII-networking)

	// tracking variables
	int val = 0;
	int idx  = 0; 
	int pkt_cnt = 0;
	int byte_count = 0;
	int fail_flag = 0;

	// packet construction
	uint8_t msg_buff[PAYLD_LEN] = {0};
	uint8_t recvbuff[RECV_LEN];
	uint8_t* msg_ptr = msg_buff;
	uint32_t store_addr = htonl(DDR_BASE_ADDR + addr_start);


	// Open up the File
	FILE* fp = fopen(file_name,"rb");

	if(!fp)
	{
		perror("Error Opening File");
		printf("File: %s\n", file_name);
		return 1;
	}

	// Continue sending packets until file is completely sent
	while(val != EOF && !fail_flag)
	{	
		memcpy(msg_ptr,&store_addr,4);
		msg_ptr += ADDR_GAP;
		idx += ADDR_GAP;

		// Read back from the file, place into udp msg
		while(idx++ < PAYLD_LEN)
		{
			if((val = fgetc(fp)) != EOF)
			{
				memset(msg_ptr++,(uint8_t)val,1);
				byte_count++;
			}
			else	// main while() loop will exit after packet sent
				break;
		}

		// track number of packets sent for current file
		pkt_cnt++;
		
		// print_buffer_hex(msg_buff,PAYLD_LEN);
		// printf("byte_count= %i\n",byte_count);
		// printf("store addr= %u\n", ntohl(store_addr)-DDR_BASE_ADDR);
		// printf("file_pointer= 0x%08x\n", ftell(fp));
		// printf("packet count= %u\n",pkt_cnt);
		// printf("file_pointer deref is: %i\n",val);

		// Transmit the packet 
		if(send(sockfd, msg_buff, PAYLD_LEN, 0) == -1){
			perror("Send packet Failed: ");
			return 1;
		}

		//Receive reply from ethernet_handler CRC check
		recv(sockfd,recvbuff,RECV_LEN,0);
		// printf("Data received from eth_handler: \n");
		// print_buffer_hex(recvbuff,RECV_LEN);
		if(recvbuff[RECV_LEN-1] != 1)
			fail_flag = 1;
			// printf("Outgoing UDP Packet valid!\n");
		memset(recvbuff,0,RECV_LEN);

		// Reset message buffer
		// incriment storage base-address
		store_addr = htonl(ntohl(store_addr)+SAMPLE_BYTES);
		memset(msg_buff,0,PAYLD_LEN);
		msg_ptr = msg_buff;
		idx = 0;
		
	}

	if(!fail_flag)
		printf("File transfer complete!\n");
	else
		printf("File transfer failed. Retry transfer\n");

	fclose(fp);
	return 0;

}