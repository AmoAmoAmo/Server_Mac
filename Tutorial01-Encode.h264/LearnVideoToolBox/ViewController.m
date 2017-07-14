//
//  ViewController.m
//  LearnVideoToolBox
//
//  Created by 林伟池 on 16/9/1.
//  Copyright © 2016年 林伟池. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic , strong) UILabel  *mLabel;
@property (nonatomic , strong) AVCaptureSession *mCaptureSession; //负责输入和输出设备之间的数据传递
@property (nonatomic , strong) AVCaptureDeviceInput *mCaptureDeviceInput;//负责从AVCaptureDevice获得输入数据
@property (nonatomic , strong) AVCaptureVideoDataOutput *mCaptureDeviceOutput; //
@property (nonatomic , strong) AVCaptureVideoPreviewLayer *mPreviewLayer;
@property (weak, nonatomic) IBOutlet UIView *testView;

@end

@implementation ViewController
{
    int frameID;
    dispatch_queue_t mCaptureQueue;
    dispatch_queue_t mEncodeQueue;
    VTCompressionSessionRef EncodingSession;
//    CMFormatDescriptionRef  format;
    NSFileHandle *fileHandle;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.mLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 200, 100)];
    self.mLabel.textColor = [UIColor redColor];
    [self.view addSubview:self.mLabel];
    self.mLabel.text = @"测试H264硬编码";
    
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(200, 20, 100, 100)];
    [button setTitle:@"play" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [self.view addSubview:button];
    [button addTarget:self action:@selector(onClick:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)onClick:(UIButton *)button {
    if (!self.mCaptureSession || !self.mCaptureSession.running) {
        [button setTitle:@"stop" forState:UIControlStateNormal];
        [self startCapture];
        
    }
    else {
        [button setTitle:@"play" forState:UIControlStateNormal];
        [self stopCapture];
        
    }
}

- (void)startCapture {
    self.mCaptureSession = [[AVCaptureSession alloc] init];
    self.mCaptureSession.sessionPreset = AVCaptureSessionPreset640x480;
    
    mCaptureQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    mEncodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0); // 获取全局队列，后台执行
    
    AVCaptureDevice *inputCamera = nil;
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices)
    {
        if ([device position] == AVCaptureDevicePositionBack)
        {
            inputCamera = device;
        }
    }
    // 获取当前设备支持的像素格式
//    NSLog(@"-- videoDevice.formats = %@", inputCamera.formats);

    
    self.mCaptureDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:inputCamera error:nil];
    
    if ([self.mCaptureSession canAddInput:self.mCaptureDeviceInput]) {
        [self.mCaptureSession addInput:self.mCaptureDeviceInput];
    }
    
    self.mCaptureDeviceOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.mCaptureDeviceOutput setAlwaysDiscardsLateVideoFrames:NO];
    
    [self.mCaptureDeviceOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    [self.mCaptureDeviceOutput setSampleBufferDelegate:self queue:mCaptureQueue];
    if ([self.mCaptureSession canAddOutput:self.mCaptureDeviceOutput]) {
        [self.mCaptureSession addOutput:self.mCaptureDeviceOutput];
    }
    AVCaptureConnection *connection = [self.mCaptureDeviceOutput connectionWithMediaType:AVMediaTypeVideo];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
//    [connection setVideoOrientation:AVCaptureVideoOrientationLandscapeLeft];
    
    self.mPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.mCaptureSession];
    [self.mPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    [self.mPreviewLayer setFrame:self.view.bounds];
    [self.view.layer addSublayer:self.mPreviewLayer];
    
    // 沙盒路径，Library -》 Caches
    NSString *file = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"abc.h264"];
    NSLog(@"-------- path = %@ ---------",file);
    [[NSFileManager defaultManager] removeItemAtPath:file error:nil];
    [[NSFileManager defaultManager] createFileAtPath:file contents:nil attributes:nil];
    fileHandle = [NSFileHandle fileHandleForWritingAtPath:file];
    
    [self initVideoToolBox];
    [self.mCaptureSession startRunning];
}

- (void)stopCapture {
    [self.mCaptureSession stopRunning];
    [self.mPreviewLayer removeFromSuperlayer];
    [self EndVideoToolBox];
    [fileHandle closeFile];
    fileHandle = NULL;
}



- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // 简单打印摄像头输出数据的信息
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (CVPixelBufferIsPlanar(pixelBuffer)) {
        NSLog(@"kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange -> planar buffer");
    }
    CMVideoFormatDescriptionRef desc = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuffer, &desc);
    CFDictionaryRef extensions = CMFormatDescriptionGetExtensions(desc);
    NSLog(@"extensions = %@", extensions);

    /*
     kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange -> planar buffer
     extensions = {
     CVBytesPerRow = 2904;
     CVImageBufferColorPrimaries = "ITU_R_709_2";
     CVImageBufferTransferFunction = "ITU_R_709_2";
     CVImageBufferYCbCrMatrix = "ITU_R_709_2";
     Version = 2;
     }
     */
    
    // 获取摄像头输出图像的宽高
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    NSLog(@"---- width = %d, height = %d",(int)width,(int)height);// ---- width = 480, height = 640
    
    
    
    /*
     实际：
     extensions = {
     CVBytesPerRow = 724;
     CVImageBufferChromaLocationTopField = Center;
     CVImageBufferColorPrimaries = "ITU_R_709_2";
     CVImageBufferTransferFunction = "ITU_R_709_2";
     CVImageBufferYCbCrMatrix = "ITU_R_601_4";
     Version = 2;
     }
     
     // CVBytesPerRow
     图像数据每行的字节数。平面缓冲区，这个函数返回一个值，rowbytes 每行的字节数 *高覆盖整个图像，包括所有的平面。
     */
    
    
    dispatch_sync(mEncodeQueue, ^{
        [self encode:sampleBuffer];
    });
}

- (void)initVideoToolBox {
    dispatch_sync(mEncodeQueue  , ^{  // 在后台 同步执行 （同步，需要加锁）
        frameID = 0;
        
        // ----- 1. 创建session -----
        int width = 640, height = 480;
        OSStatus status = VTCompressionSessionCreate(NULL, width, height,
                                                     kCMVideoCodecType_H264, NULL, NULL, NULL,
                                                     didCompressH264, (__bridge void *)(self),  &EncodingSession);
        NSLog(@"H264: VTCompressionSessionCreate %d", (int)status);
        if (status != 0)
        {
            NSLog(@"H264: Unable to create a H264 session");
            return ;
        }
        
        // ----- 2. 设置session属性 -----
        // 设置实时编码输出（避免延迟）
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
        
        // 设置关键帧（GOPsize)间隔
        int frameInterval = 10;
        CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
        
        // 设置期望帧率
        int fps = 10;
        CFNumberRef  fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
        
        
        //设置码率，上限，单位是bps
        int bitRate = width * height * 3 * 4 * 8;
        CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
        
        //设置码率，均值，单位是byte
        int bitRateLimit = width * height * 3 * 4;
        CFNumberRef bitRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRateLimit);
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_DataRateLimits, bitRateLimitRef);
        
        // Tell the encoder to start encoding
        VTCompressionSessionPrepareToEncodeFrames(EncodingSession);
    });
}


// -------- 3. 传入编码帧 ---------
- (void) encode:(CMSampleBufferRef )sampleBuffer
{
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    // 帧时间，如果不设置会导致时间轴过长。
    CMTime presentationTimeStamp = CMTimeMake(frameID++, 1000); // CMTimeMake(分子，分母)；分子/分母 = 时间(秒)
    VTEncodeInfoFlags flags;
    OSStatus statusCode = VTCompressionSessionEncodeFrame(EncodingSession,
                                                          imageBuffer,
                                                          presentationTimeStamp,
                                                          kCMTimeInvalid,
                                                          NULL, NULL, &flags);
    if (statusCode != noErr) {
        NSLog(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
        
        VTCompressionSessionInvalidate(EncodingSession);
        CFRelease(EncodingSession);
        EncodingSession = NULL;
        return;
    }
    NSLog(@"H264: VTCompressionSessionEncodeFrame Success");
}

// 编码完成回调
void didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer) {
    NSLog(@"didCompressH264 called with status %d infoFlags %d", (int)status, (int)infoFlags);
    if (status != 0) {
        return;
    }
    
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    ViewController* encoder = (__bridge ViewController*)outputCallbackRefCon;
    
    // ----- 关键帧获取SPS和PPS ------
    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    // 判断当前帧是否为关键帧
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
                // Found pps
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
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
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
    序列参数集SPS：作用于一系列连续的编码图像；
    图像参数集PPS：作用于编码视频序列中一个或多个独立的图像；
 */
- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps
{
    NSLog(@"-------- 编码后SpsPps长度: gotSpsPps %d %d", (int)[sps length] + 4, (int)[pps length]+4);
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    [fileHandle writeData:ByteHeader];
    [fileHandle writeData:sps];
    [fileHandle writeData:ByteHeader];
    [fileHandle writeData:pps];
    
}
- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame
{
//    NSLog(@"--------- 编码后数据长度： %d, sizeof data = %ld", (int)[data length],sizeof(data));
//    NSLog(@"----------- data = %@ ------------", data);
    
    if (fileHandle != NULL)
    {
        // 把每一帧的所有NALU数据前四个字节变成0x00 00 00 01之后再写入文件
        const char bytes[] = "\x00\x00\x00\x01";  // null null null 标题开始
        size_t length = (sizeof bytes) - 1; //字符串文字具有隐式结尾 '\0'  。    把上一段内容中的’\0‘去掉，
        NSData *ByteHeader = [NSData dataWithBytes:bytes length:length]; // 复制C数组所包含的数据来初始化NSData的数据
        [fileHandle writeData:ByteHeader];
        [fileHandle writeData:data];
    }
}

- (void)EndVideoToolBox
{
    VTCompressionSessionCompleteFrames(EncodingSession, kCMTimeInvalid);
    VTCompressionSessionInvalidate(EncodingSession);
    CFRelease(EncodingSession);
    EncodingSession = NULL;
}


@end
