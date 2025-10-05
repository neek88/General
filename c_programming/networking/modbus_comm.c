#include <stdio.h>
#include <modbus.h>


int main(){

    modbus_new_tcp("127.0.0.1",1502);

    return 0;
}