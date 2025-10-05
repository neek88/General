#include <stdint.h>

#ifndef COMMAND_H
#define COMMAND_H

void print_buffer_hex(uint8_t* data, uint32_t len);

void print_buffer_char(uint8_t* data, uint32_t len);

/* Doc: 	Free argument string-list 
 */
void free_arg_list(char** arglist,int length);

/* Doc: 	Takes string buffer and breaks it apart into multiple strings based on spaces
 * Return:	number of strings in broken string array
 */
int break_string(char* string_to_break, char*** broken_string, int buff_len);

/* Doc: 	sends command to computer on 'connected' UDP socket
 * Return:	0 - pass, 1 - Fail 
 */
int send_command(int sockfd, int arg_count, uint32_t* args);

int send_command_str(int sockfd, int arg_count, char** args);

/* Doc: 	sends binary waveform file over UDP to given port on local connection
 *			Will this work if the destination address is a memory address, not corresponding to the network ?
 * Return:	0 - pass, 1 - Fail 
 */
int send_sample_file(int sockfd, char* restrict file_name, int addr_start);

#endif  // COMMAND_H