//
//  ViewController.m
//  Mac_GUI_Test
//
//  Created by Josie on 2017/7/14.
//  Copyright © 2017年 Josie. All rights reserved.
//
//  Mac采集摄像头视频socket实时传播 （由服务端采集发送数据）

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import "MyDefine.h"
#import "TCPDataDefine.h"
#import "AACEncoder.h"
#import "HJTCPServer.h"


typedef enum : NSUInteger {
    NOTCONNECT,
    WAITING,
    CONNECTED,
} DeviceStatusEnum;



@interface ViewController()<AVCaptureAudioDataOutputSampleBufferDelegate,AVCaptureVideoDataOutputSampleBufferDelegate>
{
    int                     frameID;
//    dispatch_queue_t        mCaptureQueue;
    dispatch_queue_t        mEncodeQueue;
    dispatch_queue_t        mWriteDataQueue;  //
    
    VTCompressionSessionRef encodingSession;
    NSFileHandle            *fileHandle;
    NSFileHandle            *audioFileHandle;
    
    int                     connectfd;
    char                    mBuffer[20480];  // 用于线程间传数据的buffer  字符数组
//    Byte                    mBytesBuf[20480];
    NSMutableData           *tempData;
//    NSMutableData           *lastData;  // 记录上一次的data
    
    BOOL                    isConnected;
}
@property (nonatomic, strong)   AVCaptureSession            *avSession;

@property (nonatomic , strong)  AVCaptureVideoDataOutput    *videoOutput; //

@property (nonatomic, strong)   AVCaptureVideoPreviewLayer  *previewLayer;

@property (weak) IBOutlet NSButton *searchBtn;

@property (weak) IBOutlet NSButton *alarmBtn;

@property (weak) IBOutlet NSView *captureView;



@property (nonatomic, retain) HJTCPServer   *tcpServer;

@property (nonatomic, assign) DeviceStatusEnum  devStatueEnum;

@end


@implementation ViewController


- (void)viewDidLoad {
    [super viewDidLoad];

//    NSLog(@"---- int = %ld", sizeof(int));
    
    // Do any additional setup after loading the view.
    self.captureView.layer.backgroundColor = [NSColor lightGrayColor].CGColor;
    self.captureView.layer.borderWidth = 2;
    self.captureView.layer.borderColor = [NSColor redColor].CGColor;
//    self.alarmBtn.enabled = NO;
    
    
    // 测试代码
    self.devStatueEnum = CONNECTED;
    // 在子线程里面操作TCP
    [NSThread detachNewThreadSelector:@selector(startTCPServiceThread) toTarget:self withObject:nil];
}



-(void)startCapture
{
//    mCaptureQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    mEncodeQueue =  dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0); // 获取全局队列，后台执行
    mWriteDataQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    // 显示采集数据的层
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.avSession];
//    NSLog(@"---- capture width = %f, height = %f ", self.captureView.frame.size.width, self.captureView.frame.size.height);
    self.previewLayer.frame = self.captureView.bounds;
    // 保留纵横比
    [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    /*
     AVVideoScalingModeResizeAspectFill ; 
     AVLayerVideoGravityResizeAspect
     AVVideoYCbCrMatrix_ITU_R_601_4
     AVVideoColorPrimaries_SMPTE_C
     
     AVVideoColorPropertiesKey
     */
    
    
//    [[self.previewLayer connection] setVideoMirrored:YES];
    
    
    [self.captureView.layer insertSublayer:self.previewLayer above:0];    //设置layer插入的位置为above0，也就是图层的最底层的上一层
//    [self.view.layer insertSublayer:self.previewLayer below:self.alarmBtn.layer];
    
    
    // 沙盒路径，Library -》 Caches
    NSString *file = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"hello.h264"];
//    NSLog(@"-------- path = %@ ---------",file);
    [[NSFileManager defaultManager] removeItemAtPath:file error:nil]; //
    [[NSFileManager defaultManager] createFileAtPath:file contents:nil attributes:nil];
    fileHandle = [NSFileHandle fileHandleForWritingAtPath:file];
    
    NSString *audioFile = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"hello.aac"];
    [[NSFileManager defaultManager] removeItemAtPath:audioFile error:nil];
    [[NSFileManager defaultManager] createFileAtPath:audioFile contents:nil attributes:nil];
    audioFileHandle = [NSFileHandle fileHandleForWritingAtPath:audioFile];
    
    
    
    
    
    
    
    memset(mBuffer, 0, sizeof(mBuffer));
    
    [self initVideoToolBox];
    [self.avSession startRunning];
}


- (void)stopCapture {
    [self.avSession stopRunning];
    [self.previewLayer removeFromSuperlayer];
    [self EndVideoToolBox];
    [fileHandle closeFile];
    fileHandle = NULL;
}


// 镜像
- (IBAction)sellectPreviewMirrored:(id)sender {
    [[self.previewLayer connection] setVideoMirrored:[(NSButton *)sender state]];
    
}


/*
 ------------- VideoToolbox编码算法如下： ------------
 
 1.创建编码会话 (session)
 2.准备编码
 3.逐帧编码
 4.结束编码
 */
- (void)initVideoToolBox {
    dispatch_sync(mEncodeQueue  , ^{  // 在后台 同步执行 （同步，需要加锁）
        frameID = 0;
        
        // ----- 1. 创建session -----
        int width = 640, height = 480;  // session的宽高为编码后输出的视频帧的像素宽高
        OSStatus status = VTCompressionSessionCreate(NULL, width, height,
                                                     kCMVideoCodecType_H264,
                                                     NULL, NULL, NULL,
                                                     didCompressH264, (__bridge void *)(self),
                                                     &encodingSession);
        NSLog(@"H264: VTCompressionSessionCreate %d", (int)status);
        if (status != 0)
        {
            NSLog(@"H264: Unable to create a H264 session");
            return ;
        }
        
        // ----- 2. 设置session属性 -----
        // 设置实时编码输出（避免延迟）
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
        
        // 设置关键帧（GOPsize)间隔
        int frameInterval = 10;
        CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
        
        // 设置期望帧率
        int fps = 10;
        CFNumberRef  fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
        
        
        //设置码率，上限，单位是bps
        int bitRate = width * height * 3 * 4 * 8;
        CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
        
        //设置码率，均值，单位是byte
        int bitRateLimit = width * height * 3 * 4;
        CFNumberRef bitRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRateLimit);
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_DataRateLimits, bitRateLimitRef);
        
        // Tell the encoder to start encoding
        VTCompressionSessionPrepareToEncodeFrames(encodingSession);
    });
}

// 视频图像编码完成后回调
/**
 *  h.264硬编码完成后回调 VTCompressionOutputCallback
 *  将硬编码成功的CMSampleBuffer转换成H264码流，通过网络传播
 *  解析出参数集SPS和PPS，加上开始码后组装成NALU。提取出视频数据，将长度码转换成开始码，组长成NALU。将NALU发送出去。
 *  VideoToolbox编码输出为avcC格式
 */
void didCompressH264(void *outputCallbackRefCon,
                     void *sourceFrameRefCon,
                     OSStatus status,
                     VTEncodeInfoFlags infoFlags,
                     CMSampleBufferRef sampleBuffer) {
//    NSLog(@"didCompressH264 called with status %d infoFlags %d", (int)status, (int)infoFlags);
    if (status != 0) {
        return;
    }
    
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    

    
    
    ViewController* encoder = (__bridge ViewController*)outputCallbackRefCon;
    
    
    
    // ----- 关键帧获取SPS和PPS ------  // 判断当前帧是否为关键帧
    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    
    // 获取sps & pps数据
    if (keyframe)
    {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        size_t sparameterSetSize, sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
        if (statusCode == noErr)
        {
            // Found sps and now check for pps
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
            if (statusCode == noErr)
            {
                // Found sps pps
                NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                NSData *pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                if (encoder)
                {
                    [encoder gotSpsPps:sps pps:pps];  // 获取sps & pps数据
                }
            }
        }
    }
    
    
    // --------- 写入数据 ----------
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);// 编码后的图像，以CMBlockBuffe方式存储
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4; // 返回的nalu数据前四个字节不是0001的startcode，而是大端模式的帧长度length
        
        // 循环获取nalu数据
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            uint32_t NALUnitLength = 0;
            // Read the NAL unit length
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            // 从大端转系统端
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            NSData* data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            [encoder gotEncodedData:data isKeyFrame:keyframe];
            
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
}

// 获取sps & pps数据
/*
    序列参数集SPS：作用于一系列连续的编码图像；            --编码后的第一帧,长度是4;
    图像参数集PPS：作用于编码视频序列中一个或多个独立的图像； --编码后的第二帧
 */
- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps
{
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];

    [self getHeadData:ByteHeader andData:sps];
    [self getHeadData:ByteHeader andData:pps];
}
- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame
{
//    NSLog(@"--------- 编码后数据长度： %d", (int)[data length]);
//    NSLog(@"----------- data = %@ ------------", data);
    if (fileHandle != NULL)
    {
        // 把每一帧的所有NALU数据前四个字节变成0x00 00 00 01之后再写入文件
        const char bytes[] = "\x00\x00\x00\x01";  // null null null 标题开始
        size_t length = (sizeof bytes) - 1; //字符串文字具有隐式结尾 '\0'  。    把上一段内容中的’\0‘去掉，
        NSData *ByteHeader = [NSData dataWithBytes:bytes length:length]; // 复制C数组所包含的数据来初始化NSData的数据

        [self getHeadData:ByteHeader andData:data];
    }
}



// ++++++++++ 得到编码后的数据 ++++++++++++++
-(void)getHeadData:(NSData*)headData andData:(NSData*)data
{
    dispatch_sync(mWriteDataQueue, ^{
        
        //    NSLog(@"----------- %@ %@ ------------",headData,data);
//        [fileHandle writeData:headData];
//        [fileHandle writeData:data];
//        NSLog(@"---- data = %@ ---", data);
        // NSData --> Byte, 输出验证data是否完整写入file。  完整。
//        Byte *dataByte = (Byte*)[data bytes];
//        int len = (int)[data length];
//        printf("================\n");
//        printf("----- len = %d \n", len);
//        for (int i=0; i<len; i++){
//            printf("%02x", (unsigned char)dataByte[i]);
//        }
//        printf("\n");
        
        
        tempData = [NSMutableData dataWithData:headData];
        [tempData appendData:data];
        //    NSLog(@"--------------- len = %d ------------", (int)[tempData length]);
//        [self dataTest];
        
        
        // 编码后的数据 data,传给TCP 开始发送给client
        [self.tcpServer sendDataToClientWithData:tempData];
    });
    

}





-(void)dataTest
{
//    NSLog(@"======= %@ ===",tempData);
    int len = (int)[tempData length];
    NSLog(@"--------------- len = %d ------------", len);
//    NSLog(@"----- size of data = %ld --", sizeof(tempData)); // ----- size of data = 8 --
//    printf("--- data %c", tempData->1000);
    Byte *dataByte = (Byte*)[tempData bytes];
//    NSLog(@"--- sizeof byte = %ld ==", sizeof(dataByte)); // --- sizeof byte = 8 ==
    
    printf("================\n");
    for (int i=0; i<len; i++){
        printf("%02x", dataByte[i]);
    }
    printf("\n");
}



- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}



- (IBAction)clickButton:(NSButton *)sender {
    printf("----- startCapture ----- \n");
    
    [self startCapture];
}

- (IBAction)startUDPSearch:(NSButton *)sender {
    
    // UDP搜索
}

- (IBAction)stopCapture:(id)sender {
    [self stopCapture];
    // reset时，TCP应该被停止
    if (self.tcpServer) {
        [self stopTCP];
        self.tcpServer = nil;
    }
}

#pragma mark - TCP

-(void)startTCPServiceThread
{
    NSLog(@"---- status = %ld ", self.devStatueEnum);
    if (self.devStatueEnum == CONNECTED) {
        self.tcpServer = [[HJTCPServer alloc] init];
        [self.tcpServer startTCPTransmissionService];
        
        //        // $$$$ 测试代码 ￥￥￥￥NSString *str = @"hello world";
        //        NSString *str = @"hello world";
        //        NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
        //        [self.tcpServer sendDataToClientWithData:data];
    }
}
-(void)stopTCP
{
    [self.tcpServer stopTCPTransmissionService];
}




#pragma mark - AVCapture-输出流-Delegate

// 默认情况下，为30 fps，意味着该函数每秒调用30次
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    
    
    
    // 获取输入设备数据，有可能是音频有可能是视频
    if (captureOutput == self.videoOutput) {
        //捕获到视频数据
        /*
         mediaType:'vide'
         mediaSubType:'420v'     // videoOutput设置成什么类型就是什么类型
         */
//        NSLog(@"视频 ---");
//        NSLog(@"---- sampleBuffer = %@--", sampleBuffer);
//        NSLog(@"==========================================================");
//        // 简单打印摄像头输出数据的信息  (CVImageBufferRef 和 CVPixelBufferRef 可以看作是一样的)
//        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//        OSType videoType =  CVPixelBufferGetPixelFormatType(pixelBuffer);
//        NSLog(@"***** videoType = %d *******",videoType);
//        if (CVPixelBufferIsPlanar(pixelBuffer)) {
//            NSLog(@"kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange -> planar buffer");
//        }
//        CMVideoFormatDescriptionRef desc = NULL;
//        CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuffer, &desc);
//        CFDictionaryRef extensions = CMFormatDescriptionGetExtensions(desc);
//        NSLog(@"extensions = %@", extensions);
        
        
//         YUV422转YUV420
        CVPixelBufferRef pixelBuf_After = [self processYUV422ToYUV420WithSampleBuffer:sampleBuffer];
        
//        NSLog(@"&&&&&&&&& pixelBuf_After = %@ &&&&&&&&&",pixelBuf_After);
//        
//        CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuf_After, &desc);
//        CFDictionaryRef extensions2 = CMFormatDescriptionGetExtensions(desc);
//        NSLog(@"++++++++ extensions2 = %@ ++++++++++", extensions2);
        
        
        dispatch_sync(mEncodeQueue, ^{
            [self encode:pixelBuf_After];
        });
        
        
    }
    else
    {
        // 音频
        /*
         mediaType:'soun'
         mediaSubType:'lpcm'
         */
//        NSLog(@"--- 音频 ----");
        
    
    
    }
}


// ========== 处理YUV422数据 ==========
/*
    1. CMSampleBufferRef 中提取yuv数据
    2. 处理yuv数据
    3. yuv数据 转CVPixelBufferRef ，继续进行编码
 */
-(CVPixelBufferRef)processYUV422ToYUV420WithSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    // 1. 从CMSampleBufferRef中提取yuv数据
    // 获取yuv数据
    // 通过CMSampleBufferGetImageBuffer方法，获得CVImageBufferRef。
    // 这里面就包含了yuv420数据的指针
    CVImageBufferRef pixelBuffer_Before = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    //表示开始操作数据
    CVPixelBufferLockBaseAddress(pixelBuffer_Before, 0);
    
    //图像宽度（像素）
    size_t pixelWidth = CVPixelBufferGetWidth(pixelBuffer_Before);
    //图像高度（像素）
    size_t pixelHeight = CVPixelBufferGetHeight(pixelBuffer_Before);
    //yuv中的y所占字节数
    size_t y_size = pixelWidth * pixelHeight;
    
    
    // 2. yuv中的u和v分别所占的字节数
    size_t uv_size = y_size / 4;
    
    uint8_t *yuv_frame = malloc(uv_size * 2 + y_size);
    
    //获取CVImageBufferRef中的y数据
    uint8_t *y_frame = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer_Before, 0);
    memcpy(yuv_frame, y_frame, y_size);
    
    //获取CMVImageBufferRef中的uv数据
    uint8_t *uv_frame = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer_Before, 1);
    memcpy(yuv_frame + y_size, uv_frame, uv_size * 2);
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer_Before, 0);
    
    NSData *yuvData = [NSData dataWithBytesNoCopy:yuv_frame length:y_size + uv_size * 2];
    
    
    
    
    // 3. yuv 变成 转CVPixelBufferRef
    
//    //视频宽度
//    size_t pixelWidth = 640;
//    //视频高度
//    size_t pixelHeight = 480;
    
    //现在要把NV12数据放入 CVPixelBufferRef中，因为 硬编码主要调用VTCompressionSessionEncodeFrame函数，此函数不接受yuv数据，但是接受CVPixelBufferRef类型。
    CVPixelBufferRef pixelBuf_After = NULL;
    //初始化pixelBuf，数据类型是kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange，此类型数据格式同NV12格式相同。
    CVPixelBufferCreate(NULL,
                        pixelWidth, pixelHeight,
                        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                        NULL,
                        &pixelBuf_After);
    
    // Lock address，锁定数据，应该是多线程防止重入操作。
    if(CVPixelBufferLockBaseAddress(pixelBuf_After, 0) != kCVReturnSuccess){
        NSLog(@"encode video lock base address failed");
        return NULL;
    }
    
    //将yuv数据填充到CVPixelBufferRef中
//    size_t y_size = aw_stride(pixelWidth) * pixelHeight;
//    size_t uv_size = y_size / 4;
    uint8_t *yuv_frame_2 = (uint8_t *)yuvData.bytes;
    
    //处理y frame
    uint8_t *y_frame_2 = CVPixelBufferGetBaseAddressOfPlane(pixelBuf_After, 0);
    memcpy(y_frame_2, yuv_frame_2, y_size);
    
    uint8_t *uv_frame_2 = CVPixelBufferGetBaseAddressOfPlane(pixelBuf_After, 1);
    memcpy(uv_frame_2, yuv_frame_2 + y_size, uv_size * 2);
    
    
    CVPixelBufferUnlockBaseAddress(pixelBuf_After, 0);
    
    return pixelBuf_After;
}





//CMSampleBufferRef转byte*
-(void) getAudioData: (CMSampleBufferRef)sampleBuffer{
    
    AudioBufferList audioBufferList;
    CMBlockBufferRef blockBuffer;
    
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, NULL, &audioBufferList, sizeof(audioBufferList), NULL, NULL, 0, &blockBuffer);
    
    for( int y=0; y<audioBufferList.mNumberBuffers; y++ )
    {
        AudioBuffer audioBuffer = audioBufferList.mBuffers[y];
        void* audio = audioBuffer.mData;//这里获取
        NSLog(@"--- audio = %s ----",audio);
    }
    
    CFRelease(blockBuffer);
}


// yuv422转yuv420
int yuv422toyuv420(unsigned char *out, const unsigned char *in, unsigned int width, unsigned int height)
{
    unsigned char *y = out;
    unsigned char *u = out + width*height;
    unsigned char *v = out + width*height + width*height/4;
    
    unsigned int i,j;
    unsigned int base_h;
    unsigned int is_y = 1, is_u = 1;
    unsigned int y_index = 0, u_index = 0, v_index = 0;
    
    unsigned long yuv422_length = 2 * width * height;
    
    //序列为YU YV YU YV，一个yuv422帧的长度 width * height * 2 个字节
    //丢弃偶数行 u v
    
    for(i=0; i<yuv422_length; i+=2){
        *(y+y_index) = *(in+i);
        y_index++;
    }
    
    for(i=0; i<height; i+=2){
        base_h = i*width*2;
        for(j=base_h+1; j<base_h+width*2; j+=2){
            if(is_u){
                *(u+u_index) = *(in+j);
                u_index++;
                is_u = 0;
            }
            else{
                *(v+v_index) = *(in+j);
                v_index++;
                is_u = 1;
            }
        }
    }
    
    return 1;
}








// -------- 3. 传入编码帧 ---------
- (void) encode:(CVPixelBufferRef )pixelBuf
{
    // --- 这里CVPixelBufferRef 和 CVImageBufferRef 可以替换 -----
//    CVPixelBufferRef pixelBuf = CMSampleBufferGetImageBuffer(sampleBuffer);
    
//    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    // 帧时间，如果不设置会导致时间轴过长。 此帧的表示时间戳，要附加到示例缓冲区。
    CMTime presentationTimeStamp = CMTimeMake(frameID++, 1000); // CMTimeMake(分子，分母)；分子/分母 = 时间(秒)
    VTEncodeInfoFlags flags;
    
    // 使用硬编码接口VTCompressionSessionEncodeFrame来对该帧进行硬编码
    // 编码成功后，会自动调用session初始化时设置的回调函数
    OSStatus statusCode = VTCompressionSessionEncodeFrame(encodingSession,
                                                          pixelBuf,
                                                          presentationTimeStamp,
                                                          kCMTimeInvalid,
                                                          NULL, NULL, &flags);
    if (statusCode != noErr) {
        NSLog(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
        
        VTCompressionSessionInvalidate(encodingSession);
        CFRelease(encodingSession);
        encodingSession = NULL;
        return;
    }
//    NSLog(@"H264: VTCompressionSessionEncodeFrame Success");
}






- (void)EndVideoToolBox
{
    VTCompressionSessionCompleteFrames(encodingSession, kCMTimeInvalid);
    VTCompressionSessionInvalidate(encodingSession);
    CFRelease(encodingSession);
    encodingSession = NULL;
}






-(void)sendDataToClient
{
//    printf("+++++ send +++++\n");
    
    
    if (isConnected) {
        // send
        HJ_VideoDataContent dataContent;
        memset((void *)&dataContent, 0, sizeof(dataContent));
        dataContent.msgHeader.msgHeader[0] = 'M';
        dataContent.msgHeader.msgHeader[1] = 'O';
        dataContent.msgHeader.msgHeader[2] = '_';
        dataContent.msgHeader.msgHeader[3] = 'V';
        dataContent.msgHeader.controlMask = CONTROLLCODE_VIDEO_TRANS_DATA_REPLY;
        
        int dataLen = (int)[tempData length];
        dataContent.videoLength = dataLen;
        
        // ------ 把HJ_VideoDataContent和tempData放在一起发出去 ------
        // -- 但是不能直接用data传输，要先转成Byte ------
        Byte *dataByte = (Byte*)[tempData bytes];
        
        int contentLen = sizeof(dataContent);
        int totalLen = contentLen + dataLen;
        char *sendBuf = (char *)malloc(totalLen * sizeof(char));
        memcpy(sendBuf, &dataContent, contentLen);
        // 直接把data拷到C字符串里是不行的
        memcpy(sendBuf + contentLen, dataByte, dataLen);//testByte是指针，所以不用再取地址了，注意
        
        printf("================\n");
        for (int i=0; i<totalLen; i++){
            printf("%02x", (unsigned char)sendBuf[i]);
        }
        printf("\n");
        NSLog(@"------- len = %d -----\n", dataLen);
        printf("\n");
        
        long sendRet = -1;
        sendRet = send(connectfd, sendBuf, totalLen, 0);
        if (sendRet < 0) {
            perror("send error");
            return;
        }
//        printf("----- send -----, ret = %ld --\n", sendRet);
        // 发送完把tempData清空
        tempData = 0;
    }
    
    
    
}








#pragma mark - 懒加载
-(AVCaptureSession *)avSession
{
    if (!_avSession) {
        
        _avSession = [[AVCaptureSession alloc] init];
        _avSession.sessionPreset = AVCaptureSessionPreset640x480;
        /*
         sessionPreset为AVCaptureSessionPresetHigh，可不显式指定；      为什么设置成什么值都没有反应？
         AVCaptureSessionPreset320x240
         AVCaptureSessionPreset640x480, 
         AVCaptureSessionPreset960x540
         AVCaptureSessionPreset1280x720
         */
        
        // 设备对象 (audio)
        AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        // 输入流
        AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
        // 输出流
        AVCaptureAudioDataOutput *audioOutput = [[AVCaptureAudioDataOutput alloc] init];
        [audioOutput setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
        // 添加输入输出流
        if ([_avSession canAddInput:audioInput]) {
            [_avSession addInput:audioInput];
        }
        if ([_avSession canAddOutput:audioOutput]) {
            [_avSession addOutput:audioOutput];
        }
    
    
    
        
        // 设备对象 (video)
        AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        
        // 输入流
        AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];

        // 输出流
        self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
        
        [self.videoOutput setAlwaysDiscardsLateVideoFrames:NO];
//        [self.videoOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
        
        // 帧的大小在这里设置才有效
        self.videoOutput.videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                          [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange], kCVPixelBufferPixelFormatTypeKey,
                                          [NSNumber numberWithInt: 640], (id)kCVPixelBufferWidthKey,
                                          [NSNumber numberWithInt: 480], (id)kCVPixelBufferHeightKey,
                                          nil];
        /*
                                                                            调用次数       CVBytesPerRow
         kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;      （420f）                       1924
         kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ;      420v                        1924            964
         kCVPixelFormatType_422YpCbCr8_yuvs;                    yuvs            30          2560
         kCVPixelFormatType_422YpCbCr8                          2vuy            30          2560
         */
        [self.videoOutput setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
        
        
        
        
        
        // 获取当前设备支持的像素格式
//        NSLog(@"-- videoDevice.formats = %@", videoDevice.formats);
        
        //根据设备输出获得连接
        AVCaptureConnection *connection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
        [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
        
        
        
        // 摄像头翻转
        connection.videoMirrored = YES;
        
        if ([_avSession canAddInput:videoInput]) {
            [_avSession addInput:videoInput];
        }
        if ([_avSession canAddOutput:self.videoOutput]) {
            [_avSession addOutput:self.videoOutput];
        }

        
        
    }
    return _avSession;
}


@end












