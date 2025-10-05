#include <stdint.h>
#include <stdio.h> 

#define ARR_LEN 4
int main(){

    uint8_t my_array_i[ARR_LEN] = {1,2,3,4};
    
    uint8_t my_array_ii[ARR_LEN][ARR_LEN]={
    {1,2,3,4},
    {5,6,7,8},
    {9,10,11,12},
    {13,14,15,16}
    };

    printf("1D array scan using pointer arithmetic\n");

    // increment pointer through 1D array
    for(int i=0; i<ARR_LEN; i++){
        printf("Entry %d: %d\n",i, *(my_array_i + i));
    }

    printf("1D array scan using brackets\n");

    // increment through 1D array using array indices   
    for(int i=0; i<ARR_LEN; i++){
        printf("Entry %d: %d\n",i, my_array_i[i]);
    }
    
    printf("\n\n");

    printf("2D array scan using pointer arithmetic\n");
    // increment pointer through 2D array 
    for(int i=0; i<ARR_LEN*ARR_LEN; i++){
        printf("Entry %d: %d\n",i, *((*my_array_ii) + i));
    }

    // increment through 2D array using array indicies
    printf("2D array scan using brackets\n");
    // increment pointer through 2D array 
    for(int i=0; i<ARR_LEN*ARR_LEN; i++){
        printf("Entry %d: %d\n",i, *(my_array_ii[0] + i));
    }

    // increment pointer through 2D array 
    for(int i=0; i<ARR_LEN*ARR_LEN; i++){
        printf("Entry %d: %d\n",i, my_array_ii);
    }

    return 0;
}