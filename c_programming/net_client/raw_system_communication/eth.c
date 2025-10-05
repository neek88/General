// Local Raw Packet Files
#include "include/raw_packets.h"

//Standard C
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

// P-Threads
#include <pthread.h>

// 
int break_string(char* string_to_break, char*** broken_string)
{
	int max_str_len = 0;
	int max_num_strs = 0;
	int char_cnt = 0;

	char* step = string_to_break;

	// Scan through string to determine number of strings/ max length of string
	while(*step != '\0'){

		while(*step != '\0' && *step != ' '){
			printf("calling len counter: %c\n",*step);			
			char_cnt++;
			step++;
		}
		step++;
		if(char_cnt > max_str_len)
			max_str_len = char_cnt;

		char_cnt = 0;
		max_num_strs++;
	}

	char** str_break = malloc(max_num_strs*sizeof(char*));
	char** str_stable = str_break;
	char* str_cnt;
	for(int i=0; i<max_num_strs;i++)
		str_break[i] = malloc(max_str_len);

	while(*string_to_break != '\0')
	{
		str_cnt = (*str_break);
		while(*string_to_break != ' ' && *string_to_break != '\0')
		{	
			(*str_cnt) = *string_to_break;
			string_to_break++;	
			str_cnt++;
		}
		*str_cnt = '\0';
		str_break++;
		string_to_break++;
		str_cnt = *str_break;
	}
	for(int i=0; i<max_num_strs;i++)
	 	printf("captured strings: %s\n",str_stable[i]);

	*broken_string = str_stable;
	return max_num_strs;
}

void free_arg_list(char** arglist,int length)
{
	for(int i=0;i<length;i++){
		free(arglist[i]);
	}
}
//////////////////
// 		MAIN	//
//////////////////
int main(int argc,char* argv[])
{	

	// When using sructs to layout Header information, the data is automatically big endian 
	Ether msg = 
	{
		{0x00,0x0A,0x35,0x04,0xD5,0xDE},			// FPGA MAC
		{0x3c,0x18,0xa0,0xd3,0x68,0x57},			// Ubuntu enx0
		{0x01,0x02},
		{0},
	};

	// Protocols: IPPROTO_RAW, htons(ETH_P_ALL)
	struct ifreq if_mac;
	struct ifreq if_idx;
	memset(&if_mac,0,sizeof(struct ifreq));
	memset(&if_idx,0,sizeof(struct ifreq));
	
	// Open Raw Socket for Send 
	int sockfd; 
	if( (sockfd = socket(AF_PACKET, SOCK_RAW, IPPROTO_RAW)) == -1) perror("socket error");
	
	// Get the index of the interface to send on 
	strncpy(if_idx.ifr_name, INTERFACE, IFNAMSIZ-1);
	if (ioctl(sockfd, SIOCGIFINDEX, &if_idx) < 0)
	    perror("SIOCGIFINDEX");

	// Get the MAC address of the interface to send on 
	strncpy(if_mac.ifr_name, INTERFACE, IFNAMSIZ-1);
	if (ioctl(sockfd, SIOCGIFHWADDR, &if_mac) < 0)
	    perror("SIOCGIFHWADDR");

	// Pick up HW Addr from interface name
	memcpy(msg.source_mac,if_mac.ifr_hwaddr.sa_data,ETH_ALEN);
	printf("Source Address of HW Device is: ");
	print_buffer_hex(msg.source_mac,ETH_ALEN);
	printf("Index of HW device is: %i \n", if_idx.ifr_ifindex);

	// Setup Link-Layer socket struct 
	// dest MAC, interface index
	struct sockaddr_ll socket_address;
	socket_address.sll_ifindex = if_idx.ifr_ifindex;
	socket_address.sll_halen = ETH_ALEN;
	memcpy(socket_address.sll_addr, msg.dest_mac,ETH_ALEN);

	// ******************************** //
	// 	Send packets over ethernet		//
	// ******************************** //



	// Setup Receive Packet Thread 
	pthread_t tid;
	int tc;
	// if( (tc= pthread_create(&tid,NULL,recv_thread,NULL)) == 1){
	// 	printf("ERROR: Return code from pthread_create() is %d\n",tc);
	// 	exit(-1);
	// }

	//// Send Command ////
	// send_command(sockfd,&msg,&socket_address,1,20);
	// raw_recvfrom(sockrcv, msg.source_mac, &rcv_msg);

	//	send_command(sockfd,&msg,&socket_address,3,1,1200000000,1500000000);
	//	raw_recvfrom(sockrcv, msg.source_mac, &rcv_msg);

	//// Send Data ////
	char buff[100] = "Hello Message\0";
	memcpy(msg.data,buff, 100);
	print_buffer_char(msg.data,100);
	while(1)
	{
		if( sendto(sockfd, &msg, sizeof(Ether), 0, (struct sockaddr*)&socket_address, sizeof(struct sockaddr_ll)) < 0)
		{
			perror("Packet Send Failed - "); 
			return 1;
		}	
		sleep(5);
	}
	//	send_data(sockfd,&msg,&socket_address,0);
	//	raw_recvfrom(sockrcv, msg.source_mac, &rcv_msg);


	//// Put Count Data into File for Testing	////
	FILE* fp; 
	fp = fopen("bytes.bin","wb+");

	for(int i=0; i<350;i++)
		fputc(i,fp);
	fclose(fp);

	char* parse;
	uint32_t cmd_entry[10] = {0};
	uint32_t addr_start = 0;

	#define ARGC_MIN	(1)
	#define ARGC_MAX	(9)		// User may enter 'eth' + '-c' + 'cmd' + 6 arguments
	#define ARG_FUN		(0)
	#define ARG_CMD		(1)		

	char cmd_string[100] = {0};
	char** arg_str;
	int num_args;

	while(1){
		// Pull from CMD Line 
		printf("Please Enter Command starting with '-c' OR '-d' \n");
		fgets(cmd_string,100,stdin);
		// Put string into array of strings separated by incoming spaces
		num_args = break_string(cmd_string,&arg_str);

		if(num_args > ARGC_MIN && num_args < ARGC_MAX){

			// Handle User Command
			if( !strcmp(arg_str[ARG_FUN], "-c\0")){
				for(int i=0;i<num_args-1;i++)
					cmd_entry[i] = strtol(arg_str[i+1],&parse,10);
				send_command(sockfd,&msg,&socket_address,(num_args-ARG_CMD),cmd_entry);
			}
			// Handle File Write to DRAM at given Address
			else if(!strcmp(arg_str[ARG_FUN],"-d\0")){
				parse = NULL;
				addr_start = strtol(arg_str[ARG_CMD],&parse,10);
				send_sample_file(sockfd,&socket_address,arg_str[ARG_CMD+1],&addr_start, &msg);
			}
			else{
				printf("Error: Must send '-c' / '-d' command tags...\n");
			}
		}
		else{
			printf("Please Enter Correct Command Sequence\n");
			printf("eth -c cmd val val2 val3 ...\n");
			printf("eth -d file.bin\n");
		}
		sleep(1);
		// Reset cmd
		memset(cmd_string,0,100*4);
		memset(cmd_entry,0,10*4);
	}

	//// Clean up ////
	free_arg_list(arg_str,num_args);
	close(sockfd);
	//pthread_exit(NULL);
	return 0; 
}
