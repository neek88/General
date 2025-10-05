#include <stdio.h>
#include <stdlib.h>

// Generate test binary file
// Counts from 0:255, 1024 times
// Writes 262,144 bytes/ 64K words (4-bytes)
int main() 
{
	// Put Count Data into File for Testing
	FILE* fp; 
	fp = fopen("test_bytes.bin","wb+");

	for(int j=0; j<1024; j++)
		for(int i=0; i<256;i++)
			fputc(i,fp);

	fclose(fp);
}