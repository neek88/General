// // Get IP Addr from network interface 
// // Get the MAC address of the interface to send on 
// struct ifreq if_ip;
// memset(&if_ip,0,sizeof(struct ifreq));
// strncpy(if_ip.ifr_name, INTERFACE, IFNAMSIZ-1);
// if (ioctl(sockfd, SIOCGIFADDR, &if_ip) < 0)
//     perror("SIOCGIFADDR");
// // Copy IP Addr over from ifreq struct
// memcpy(&(udp_sock.sin_addr), &(if_ip.ifr_addr.sa_data), addrlen);

// inet_ntop(AF_INET,&udp_sock.sin_addr,src_addr,addrlen);
// printf("Local IP: %s\n",if_ip.ifr_addr.sa_data);


// // connect to remote host
// struct addrinfo hints, *res; 
// memset(&hints,0,sizeof(hints));
// hints.ai_family = AF_INET;
// hints.ai_socktype = SOCK_DGRAM;
// connect(sockfd,res->ai_addr, res->ai_addrlen);


// Scan through our ethernet message, converting to Network Order on word-word basis
// uint8_t* ptr = (uint8_t*)&msg; 
// uint8_t* baseptr = ptr;
// uint32_t* word = (uint32_t*)&msg;
// uint32_t* step = (uint32_t*)&no_msg;
// for(int i=0; i<68;i++)
// *step = htonl(*word); word++; step++;
// /////////////////////////////////