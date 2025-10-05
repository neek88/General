	// Standard C
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>



int main(int argc,char* argv[])
{
    pid_t  pid;
	pid = fork();
  
 	char* arg_v[] = {"./rec", INTERFACE};
		if(pid == -1){
     pid == -1 means error occured
     printf("can't fork, error occured\n");
     exit(EXIT_FAILURE);
	 	}
	 		else if (pid == 0)
	 	{
  
     // pid == 0 means child process created
     // getpid() returns process id of calling process
     // Here It will return process id of child process
     printf("child process, pid = %u\n",getpid());
     // Here It will return Parent of child Process means Parent process it self
     printf("parent of child process, pid = %u\n",getppid()); 
  
     // the argv list first argument should point to  
     // filename associated with file being executed
     // the array pointer must be terminated by NULL 
     // pointer
     char * argv_list[] = {"mkdir","./file",NULL};
  
     // the execv() only return if error occured.
     // The return value is -1
     execv("mkdir",argv_list);
     exit(0);
  	}
  	else
  	{
   	// a positive number is returned for the pid of
   	// parent process
   	// getppid() returns process id of parent of 
   	// calling process
   	// Here It will return parent of parent process's ID
   	printf("Parent Of parent process, pid = %u\n",getppid());
     	printf("parent process, pid = %u\n",getpid()); 


    return 0;
}