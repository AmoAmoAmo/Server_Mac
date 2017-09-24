//
//  TCPDataDefine.h
//  Server_Mac
//
//  Created by Josie on 2017/7/20.
//  Copyright © 2017年 Josie. All rights reserved.
//

#ifndef TCPDataDefine_h
#define TCPDataDefine_h

#define     INT8           unsigned char
#define     INT16          unsigned short
#define     INT32          unsigned int

// -------------------------- 数据传输 -------------------------------
static INT16        CONTROLLCODE_LOGIN_TRANS_WIDTHID_REQUEST         =0;   //登陆请求
static INT16        CONTROLLCODE_VIDEO_TRANS_DATA_REPLY              =1;   // 视频
static INT16        CONTROLLCODE_AUDIO_TRANS_DATA_REPLY              =2;   //音频
static INT16        CONTROLLCODE_TALKT_TRANS_DATA                    =3;   //对讲



//包头
typedef struct MessageHeader
{
    unsigned char           msgHeader[4];       //协议头 MO_O 命令  MO_V 传数据.
    short                   controlMask;        //操作码，区分同个协议的命令。
//    unsigned char           reserved0;
//    unsigned char           reserved1[8];
    int                     commandLength;      //包后面跟的数据的长度。  命令中的正文长度
//    int                     reserved2;
    
}HJ_MsgHeader;

//视频正文结构体  ---- 数据 ----
typedef struct VideoDataContent
{
    HJ_MsgHeader             msgHeader;
//    unsigned int             timeStamp;     //时间戳
//    unsigned int             frameTime;     //帧采集时间
//    unsigned char            reserved;      //保留
    unsigned int             videoLength;   //video长度
//    char                     *videoData;
    
}HJ_VideoDataContent;

#endif /* TCPDataDefine_h */
