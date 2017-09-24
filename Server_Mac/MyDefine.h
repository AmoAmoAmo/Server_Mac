//
//  MyDefine.h
//  Server_Mac
//
//  Created by Josie on 2017/7/18.
//  Copyright © 2017年 Josie. All rights reserved.
//

#ifndef MyDefine_h
#define MyDefine_h

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <err.h>
#include <netdb.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <pthread.h>
#include <time.h>
#include <signal.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <string.h>
#include <netinet/in.h>
//#include <net/if_dl.h>
//#include <ifaddrs.h>
#include <errno.h>
#include <netdb.h>


#define MYPORT      30001
#define BACKLOG     10


#define     INT8           unsigned char
#define     INT16          unsigned short
#define     INT32          unsigned int

#endif /* MyDefine_h */
