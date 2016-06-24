//
//  TBExampleVideoCapture.m
//  otkit-objc-libs
//
//  Created by Charley Robinson on 10/11/13.
//
//

#import <Availability.h>
#import <UIKit/UIKit.h>
#import <OpenTok/OpenTok.h>
#import <CoreVideo/CoreVideo.h>
#import "TBExampleVideoCapture.h"

#define kTimespanWithNoFramesBeforeRaisingAnError 10.0

NSString *TBExampleVideoCaptureCannotOpenDeviceNotification = @"TBExampleVideoCaptureCannotOpenDeviceNotification";
NSString *TBExampleVideoCaptureCannotCaptureFrames = @"TBExampleVideoCaptureCannotCaptureFrames";

@interface TBExampleVideoCapture()
@property (nonatomic, strong) OTVideoFrame *videoFrame;
@property (nonatomic, assign) BOOL capturing;
@property (nonatomic, strong) NSTimer *noFramesCapturedTimer;
@end

@implementation TBExampleVideoCapture {
    __unsafe_unretained id<OTVideoCaptureConsumer> _videoCaptureConsumer;
    uint32_t _captureWidth;
    uint32_t _captureHeight;
    NSString* _capturePreset;
}
@synthesize videoCaptureConsumer = _videoCaptureConsumer;

#define OTK_VIDEO_CAPTURE_IOS_DEFAULT_INITIAL_FRAMERATE 20

-(id)init {
    self = [super init];
    if (self) {
        _capturePreset = AVCaptureSessionPreset640x480;
        [[self class] dimensionsForCapturePreset:_capturePreset
                                           width:&_captureWidth
                                          height:&_captureHeight];
        _capture_queue = dispatch_queue_create("com.tokbox.OTVideoCapture",
                                               DISPATCH_QUEUE_SERIAL);
        _videoFrame = [[OTVideoFrame alloc] initWithFormat:
                       [OTVideoFormat videoFormatNV12WithWidth:_captureWidth
                                                        height:_captureHeight]];
    }
    return self;
}

- (int32_t)captureSettings:(OTVideoFormat*)videoFormat {
    videoFormat.pixelFormat = OTPixelFormatNV12;
    videoFormat.imageWidth = _captureWidth;
    videoFormat.imageHeight = _captureHeight;
    return 0;
}

- (void)dealloc {
    [self stopCapture];
    [self releaseCapture];
    
    if (_capture_queue) {
        _capture_queue = nil;
    }
}

- (AVCaptureDevice *) cameraWithPosition:(AVCaptureDevicePosition) position {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if ([device position] == position) {
            return device;
        }
    }
    return nil;
}

- (AVCaptureDevice *) frontFacingCamera {
    return [self cameraWithPosition:AVCaptureDevicePositionFront];
}

- (AVCaptureDevice *) backFacingCamera {
    return [self cameraWithPosition:AVCaptureDevicePositionBack];
}

- (BOOL) hasMultipleCameras {
    return [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count] > 1;
}

- (BOOL) hasTorch {
    return [[[self videoInput] device] hasTorch];
}

- (AVCaptureTorchMode) torchMode {
    return [[[self videoInput] device] torchMode];
}

- (void) setTorchMode:(AVCaptureTorchMode) torchMode {
    
    AVCaptureDevice *device = [[self videoInput] device];
    if ([device isTorchModeSupported:torchMode] &&
        [device torchMode] != torchMode)
    {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            [device setTorchMode:torchMode];
            [device unlockForConfiguration];
        } else {
            //Handle Error
        }
    }
}

- (double) maxSupportedFrameRate {
    AVFrameRateRange* firstRange =
    [self.videoInput.device.activeFormat.videoSupportedFrameRateRanges
     objectAtIndex:0];
    
    CMTime bestDuration = firstRange.minFrameDuration;
    double bestFrameRate = bestDuration.timescale / bestDuration.value;
    CMTime currentDuration;
    double currentFrameRate;
    for (AVFrameRateRange* range in
         self.videoInput.device.activeFormat.videoSupportedFrameRateRanges)
    {
        currentDuration = range.minFrameDuration;
        currentFrameRate = currentDuration.timescale / currentDuration.value;
        if (currentFrameRate > bestFrameRate) {
            bestFrameRate = currentFrameRate;
        }
    }
    
    return bestFrameRate;
}

- (BOOL)isAvailableActiveFrameRate:(double)frameRate
{
    return (nil != [self frameRateRangeForFrameRate:frameRate]);
}

- (double) activeFrameRate {
    CMTime minFrameDuration = self.videoInput.device.activeVideoMinFrameDuration;
    double framesPerSecond =
    minFrameDuration.timescale / minFrameDuration.value;
    
    return framesPerSecond;
}

- (AVFrameRateRange*)frameRateRangeForFrameRate:(double)frameRate {
    for (AVFrameRateRange* range in
         self.videoInput.device.activeFormat.videoSupportedFrameRateRanges)
    {
        if (range.minFrameRate <= frameRate && frameRate <= range.maxFrameRate)
        {
            return range;
        }
    }
    return nil;
}

// Yes this "lockConfiguration" is somewhat silly but we're now setting
// the frame rate in initCapture *before* startRunning is called to
// avoid contention, and we already have a config lock at that point.
- (void)setActiveFrameRateImpl:(double)frameRate : (BOOL) lockConfiguration {
    
    if (!self.videoOutput || !self.videoInput) {
        return;
    }
    
    AVFrameRateRange* frameRateRange =
    [self frameRateRangeForFrameRate:frameRate];
    if (nil == frameRateRange) {
        NSLog(@"unsupported frameRate %f", frameRate);
        return;
    }
    CMTime desiredMinFrameDuration = CMTimeMake(1, frameRate);
    CMTime desiredMaxFrameDuration = CMTimeMake(1, frameRate); // iOS 8 fix
    /*frameRateRange.maxFrameDuration*/;
    
    if(lockConfiguration) [self.captureSession beginConfiguration];
    
    NSError* error;
    if ([self.videoInput.device lockForConfiguration:&error]) {
        [self.videoInput.device
         setActiveVideoMinFrameDuration:desiredMinFrameDuration];
        [self.videoInput.device
         setActiveVideoMaxFrameDuration:desiredMaxFrameDuration];
        [self.videoInput.device unlockForConfiguration];
    } else {
        NSLog(@"%@", error);
    }
    if(lockConfiguration) [self.captureSession commitConfiguration];
}

- (void)setActiveFrameRate:(double)frameRate {
    dispatch_sync(_capture_queue, ^{
        return [self setActiveFrameRateImpl : frameRate : TRUE];
    });
}

+ (void)dimensionsForCapturePreset:(NSString*)preset
                             width:(uint32_t*)width
                            height:(uint32_t*)height
{
    if ([preset isEqualToString:AVCaptureSessionPreset352x288]) {
        *width = 352;
        *height = 288;
    } else if ([preset isEqualToString:AVCaptureSessionPreset640x480]) {
        *width = 640;
        *height = 480;
    } else if ([preset isEqualToString:AVCaptureSessionPreset1280x720]) {
        *width = 1280;
        *height = 720;
    } else if ([preset isEqualToString:AVCaptureSessionPreset1920x1080]) {
        *width = 1920;
        *height = 1080;
    } else if ([preset isEqualToString:AVCaptureSessionPresetPhoto]) {
        // see AVCaptureSessionPresetLow
        *width = 1920;
        *height = 1080;
    } else if ([preset isEqualToString:AVCaptureSessionPresetHigh]) {
        // see AVCaptureSessionPresetLow
        *width = 640;
        *height = 480;
    } else if ([preset isEqualToString:AVCaptureSessionPresetMedium]) {
        // see AVCaptureSessionPresetLow
        *width = 480;
        *height = 360;
    } else if ([preset isEqualToString:AVCaptureSessionPresetLow]) {
        // WARNING: This is a guess. might be wrong for certain devices.
        // We'll use updeateCaptureFormatWithWidth:height if actual output
        // differs from expected value
        *width = 192;
        *height = 144;
    }
}

+ (NSSet *)keyPathsForValuesAffectingAvailableCaptureSessionPresets
{
    return [NSSet setWithObjects:@"captureSession", @"videoInput", nil];
}

- (NSArray *)availableCaptureSessionPresets
{
    NSArray *allSessionPresets = [NSArray arrayWithObjects:
                                  AVCaptureSessionPreset352x288,
                                  AVCaptureSessionPreset640x480,
                                  AVCaptureSessionPreset1280x720,
                                  AVCaptureSessionPreset1920x1080,
                                  AVCaptureSessionPresetPhoto,
                                  AVCaptureSessionPresetHigh,
                                  AVCaptureSessionPresetMedium,
                                  AVCaptureSessionPresetLow,
                                  nil];
    
    NSMutableArray *availableSessionPresets =
    [NSMutableArray arrayWithCapacity:9];
    for (NSString *sessionPreset in allSessionPresets) {
        if ([[self captureSession] canSetSessionPreset:sessionPreset])
            [availableSessionPresets addObject:sessionPreset];
    }
    
    return availableSessionPresets;
}

- (void)updateCaptureFormatWithWidth:(uint32_t)width height:(uint32_t)height
{
    _captureWidth = width;
    _captureHeight = height;
    [self.videoFrame setFormat:[OTVideoFormat
                            videoFormatNV12WithWidth:_captureWidth
                            height:_captureHeight]];
    
}

- (NSString*)captureSessionPreset {
    return self.captureSession.sessionPreset;
}

- (void) setCaptureSessionPreset:(NSString*)preset {
    dispatch_sync(_capture_queue, ^{
        AVCaptureSession *session = [self captureSession];
        
        if ([session canSetSessionPreset:preset] &&
            ![preset isEqualToString:session.sessionPreset]) {
            
            [self.captureSession beginConfiguration];
            self.captureSession.sessionPreset = preset;
            _capturePreset = preset;
            
            [self.videoOutput setVideoSettings:
             [NSDictionary dictionaryWithObjectsAndKeys:
              [NSNumber numberWithInt:
               kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
              kCVPixelBufferPixelFormatTypeKey,
              nil]];
            
            [self.captureSession commitConfiguration];
        }
    });
}

- (BOOL) toggleCameraPosition {
    AVCaptureDevicePosition currentPosition = self.videoInput.device.position;
    if (AVCaptureDevicePositionBack == currentPosition) {
        [self setCameraPosition:AVCaptureDevicePositionFront];
    } else if (AVCaptureDevicePositionFront == currentPosition) {
        [self setCameraPosition:AVCaptureDevicePositionBack];
    }
    
    // TODO: check for success
    return YES;
}

- (NSArray*)availableCameraPositions {
    NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    NSMutableSet* result = [NSMutableSet setWithCapacity:devices.count];
    for (AVCaptureDevice* device in devices) {
        [result addObject:[NSNumber numberWithInt:device.position]];
    }
    return [result allObjects];
}

- (AVCaptureDevicePosition)cameraPosition {
    return self.videoInput.device.position;
}

- (void)setCameraPosition:(AVCaptureDevicePosition) position {
    __block BOOL success = NO;
    
    NSString* preset = self.captureSession.sessionPreset;
    
    if (![self hasMultipleCameras]) {
        return;
    }
    
    NSError *error;
    AVCaptureDeviceInput *newVideoInput;
    
    if (position == AVCaptureDevicePositionBack) {
        newVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:
                         [self backFacingCamera] error:&error];
        [self setTorchMode:AVCaptureTorchModeOff];
        self.videoOutput.alwaysDiscardsLateVideoFrames = YES;
    } else if (position == AVCaptureDevicePositionFront) {
        newVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:
                         [self frontFacingCamera] error:&error];
        self.videoOutput.alwaysDiscardsLateVideoFrames = YES;
    } else {
        return;
    }
    
    dispatch_sync(_capture_queue, ^() {
        AVCaptureSession *session = [self captureSession];
        [session beginConfiguration];
        [session removeInput:self.videoInput];
        if ([session canAddInput:newVideoInput]) {
            [session addInput:newVideoInput];
            self.videoInput = newVideoInput;
            success = YES;
        } else {
            success = NO;
            [session addInput:self.videoInput];
        }
        [session commitConfiguration];
    });
    
    if (success) {
        [self setCaptureSessionPreset:preset];
    }
    return;
}

- (void)releaseCapture {
    [self stopCapture];
    [self.videoOutput setSampleBufferDelegate:nil queue:NULL];
    dispatch_sync(_capture_queue, ^() {
        [self.captureSession stopRunning];
    });
    
    self.captureSession = nil;
    
    self.videoOutput = nil;
    
    
    self.videoInput = nil;
}

- (void)setupAudioVideoSession {
    //-- Setup Capture Session.
    self.captureSession = [[AVCaptureSession alloc] init];
    [self.captureSession beginConfiguration];
    
    [self.captureSession setSessionPreset:_capturePreset];
    
    //Needs to be set in order to receive audio route/interruption events.
    self.captureSession.usesApplicationAudioSession = NO;
    
    //-- Create a video device and input from that Device.
    // Add the input to the capture session.
    AVCaptureDevice * videoDevice = [self frontFacingCamera];
    if(videoDevice == nil) {
        [[NSNotificationCenter defaultCenter] postNotificationName:TBExampleVideoCaptureCannotOpenDeviceNotification
                                                            object:nil
                                                          userInfo:nil];
        NSLog(@"ERROR[OpenTok]: Failed to acquire camera device for video "
              "capture.");
        [self invalidateNoFramesTimerSettingItUpAgain:NO];
        return;
    }
    
    //-- Add the device to the session.
    NSError *error;
    self.videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice
                                                         error:&error];
    
    if(error || self.videoInput == nil) {
        self.captureSession = nil;
        [[NSNotificationCenter defaultCenter] postNotificationName:TBExampleVideoCaptureCannotOpenDeviceNotification
                                                            object:nil
                                                          userInfo:nil];
        NSLog(@"ERROR[OpenTok]: Failed to initialize default video caputre "
              "session. (error=%@)", error);
        [self invalidateNoFramesTimerSettingItUpAgain:NO];
        return;
    }
    
    [self.captureSession addInput:self.videoInput];
    
    //-- Create the output for the capture session.
    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.videoOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    [self.videoOutput setVideoSettings:
     [NSDictionary dictionaryWithObject:
      [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                                 forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    
    [self.videoOutput setSampleBufferDelegate:self queue:_capture_queue];
    
    [self.captureSession addOutput:self.videoOutput];
    
    [self setActiveFrameRateImpl
     : OTK_VIDEO_CAPTURE_IOS_DEFAULT_INITIAL_FRAMERATE : FALSE];
    
    [self.captureSession commitConfiguration];
    
    // Fix for 10 seconds delay occuring with new resolution and fps
    // constructor as well as if you set cameraPosition right after regular init
    // OPENTOK-27013, OPENTOK-26905
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW,
                                          0.1 * NSEC_PER_SEC);
    dispatch_after(delay,_capture_queue,^{
        [self.captureSession startRunning];
    });
    
}

- (void)initCapture {
    dispatch_sync(_capture_queue, ^{
        [self setupAudioVideoSession];
    });
}

- (BOOL) isCaptureStarted {
    return self.captureSession && self.capturing;
}

- (int32_t) startCapture {
    self.capturing = YES;
    [self invalidateNoFramesTimerSettingItUpAgain:YES];
    return 0;
}

- (int32_t) stopCapture {
    self.capturing = NO;
    [self invalidateNoFramesTimerSettingItUpAgain:NO];
    return 0;
}

- (void)invalidateNoFramesTimerSettingItUpAgain:(BOOL)value {
    if (self.noFramesCapturedTimer == nil) {
        [self.noFramesCapturedTimer invalidate];
        self.noFramesCapturedTimer = nil;
    }
    if (value) {
        self.noFramesCapturedTimer = [NSTimer scheduledTimerWithTimeInterval:kTimespanWithNoFramesBeforeRaisingAnError
                                                                  target:self
                                                                selector:@selector(noFramesTimerFired:)
                                                                userInfo:nil
                                                                 repeats:NO];
    }
}

- (void)noFramesTimerFired:(NSTimer *)timer {
    if (self.isCaptureStarted) {
        [[NSNotificationCenter defaultCenter] postNotificationName:TBExampleVideoCaptureCannotCaptureFrames
                                                            object:nil
                                                          userInfo:nil];
    }
}

- (OTVideoOrientation)currentDeviceOrientation {
    UIInterfaceOrientation orientation =
    [[UIApplication sharedApplication] statusBarOrientation];
    // transforms are different for
    if (AVCaptureDevicePositionFront == self.cameraPosition)
    {
        switch (orientation) {
            case UIInterfaceOrientationLandscapeLeft:
                return OTVideoOrientationUp;
            case UIInterfaceOrientationLandscapeRight:
                return OTVideoOrientationDown;
            case UIInterfaceOrientationPortrait:
                return OTVideoOrientationLeft;
            case UIInterfaceOrientationPortraitUpsideDown:
                return OTVideoOrientationRight;
            case UIInterfaceOrientationUnknown:
                return OTVideoOrientationUp;
        }
    }
    else
    {
        switch (orientation) {
            case UIInterfaceOrientationLandscapeLeft:
                return OTVideoOrientationDown;
            case UIInterfaceOrientationLandscapeRight:
                return OTVideoOrientationUp;
            case UIInterfaceOrientationPortrait:
                return OTVideoOrientationLeft;
            case UIInterfaceOrientationPortraitUpsideDown:
                return OTVideoOrientationRight;
            case UIInterfaceOrientationUnknown:
                return OTVideoOrientationUp;
        }
    }
    
    return OTVideoOrientationUp;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
  didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    
}

/**
 * Def: sanitary(n): A contiguous image buffer with no padding. All bytes in the
 * store are actual pixel data.
 */
- (BOOL)imageBufferIsSanitary:(CVImageBufferRef)imageBuffer
{
    size_t planeCount = CVPixelBufferGetPlaneCount(imageBuffer);
    // (Apple bug?) interleaved chroma plane measures in at half of actual size.
    // No idea how many pixel formats this applys to, but we're specifically
    // targeting 4:2:0 here, so there are some assuptions that must be made.
    BOOL biplanar = (2 == planeCount);
    
    for (int i = 0; i < CVPixelBufferGetPlaneCount(imageBuffer); i++) {
        size_t imageWidth =
        CVPixelBufferGetWidthOfPlane(imageBuffer, i) *
        CVPixelBufferGetHeightOfPlane(imageBuffer, i);
        
        if (biplanar && 1 == i) {
            imageWidth *= 2;
        }
        
        size_t dataWidth =
        CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, i) *
        CVPixelBufferGetHeightOfPlane(imageBuffer, i);
        
        if (imageWidth != dataWidth) {
            return NO;
        }
        
        BOOL hasNextAddress = CVPixelBufferGetPlaneCount(imageBuffer) > i + 1;
        BOOL nextPlaneContiguous = YES;
        
        if (hasNextAddress) {
            size_t planeLength =
            dataWidth;
            
            uint8_t* baseAddress =
            CVPixelBufferGetBaseAddressOfPlane(imageBuffer, i);
            
            uint8_t* nextAddress =
            CVPixelBufferGetBaseAddressOfPlane(imageBuffer, i + 1);
            
            nextPlaneContiguous = &(baseAddress[planeLength]) == nextAddress;
        }
        
        if (!nextPlaneContiguous) {
            return NO;
        }
    }
    
    return YES;
}
- (size_t)sanitizeImageBuffer:(CVImageBufferRef)imageBuffer
                         data:(uint8_t**)data
                       planes:(NSPointerArray*)planes
{
    uint32_t pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
    if (kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange == pixelFormat ||
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange == pixelFormat)
    {
        return [self sanitizeBiPlanarImageBuffer:imageBuffer
                                            data:data
                                          planes:planes];
    } else {
        NSLog(@"No sanitization implementation for pixelFormat %d",
              pixelFormat);
        *data = NULL;
        return 0;
    }
}

- (size_t)sanitizeBiPlanarImageBuffer:(CVImageBufferRef)imageBuffer
                                 data:(uint8_t**)data
                               planes:(NSPointerArray*)planes
{
    size_t sanitaryBufferSize = 0;
    for (int i = 0; i < CVPixelBufferGetPlaneCount(imageBuffer); i++) {
        size_t planeImageWidth =
        // TODO: (Apple bug?) biplanar pixel format reports 1/2 the width of
        // what actually ends up in the pixel buffer for interleaved chroma.
        // The only thing I could do about it is use image width for both plane
        // calculations, in spite of this being technically wrong.
        //CVPixelBufferGetWidthOfPlane(imageBuffer, i);
        CVPixelBufferGetWidth(imageBuffer);
        size_t planeImageHeight =
        CVPixelBufferGetHeightOfPlane(imageBuffer, i);
        sanitaryBufferSize += (planeImageWidth * planeImageHeight);
    }
    uint8_t* newImageBuffer = malloc(sanitaryBufferSize);
    size_t bytesCopied = 0;
    for (int i = 0; i < CVPixelBufferGetPlaneCount(imageBuffer); i++) {
        [planes addPointer:&(newImageBuffer[bytesCopied])];
        void* planeBaseAddress =
        CVPixelBufferGetBaseAddressOfPlane(imageBuffer, i);
        size_t planeDataWidth =
        CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, i);
        size_t planeImageWidth =
        // Same as above. Use full image width for both luma and interleaved
        // chroma planes.
        //CVPixelBufferGetWidthOfPlane(imageBuffer, i);
        CVPixelBufferGetWidth(imageBuffer);
        size_t planeImageHeight =
        CVPixelBufferGetHeightOfPlane(imageBuffer, i);
        for (int rowIndex = 0; rowIndex < planeImageHeight; rowIndex++) {
            memcpy(&(newImageBuffer[bytesCopied]),
                   &(planeBaseAddress[planeDataWidth * rowIndex]),
                   planeImageWidth);
            bytesCopied += planeImageWidth;
        }
    }
    assert(bytesCopied == sanitaryBufferSize);
    *data = newImageBuffer;
    return bytesCopied;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    
    if (!(self.capturing && _videoCaptureConsumer)) {
        return;
    }
    
    [self invalidateNoFramesTimerSettingItUpAgain:YES];
    
    CMTime time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    self.videoFrame.timestamp = time;
    uint32_t height = (uint32_t)CVPixelBufferGetHeight(imageBuffer);
    uint32_t width = (uint32_t)CVPixelBufferGetWidth(imageBuffer);
    if (width != _captureWidth || height != _captureHeight) {
        [self updateCaptureFormatWithWidth:width height:height];
    }
    self.videoFrame.format.imageWidth = width;
    self.videoFrame.format.imageHeight = height;
    CMTime minFrameDuration;
    
    minFrameDuration = self.videoInput.device.activeVideoMinFrameDuration;
    self.videoFrame.format.estimatedFramesPerSecond =
    minFrameDuration.timescale / minFrameDuration.value;
    // TODO: how do we measure this from AVFoundation?
    self.videoFrame.format.estimatedCaptureDelay = 100;
    self.videoFrame.orientation = [self currentDeviceOrientation];
    
    [self.videoFrame clearPlanes];
    uint8_t* sanitizedImageBuffer = NULL;
    
    if (!CVPixelBufferIsPlanar(imageBuffer))
    {
        [self.videoFrame.planes
         addPointer:CVPixelBufferGetBaseAddress(imageBuffer)];
    } else if ([self imageBufferIsSanitary:imageBuffer]) {
        for (int i = 0; i < CVPixelBufferGetPlaneCount(imageBuffer); i++) {
            [self.videoFrame.planes addPointer:
             CVPixelBufferGetBaseAddressOfPlane(imageBuffer, i)];
        }
    } else {
        [self sanitizeImageBuffer:imageBuffer
                             data:&sanitizedImageBuffer
                           planes:self.videoFrame.planes];
    }
    
    [_videoCaptureConsumer consumeFrame:self.videoFrame];
    
    free(sanitizedImageBuffer);
    
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    
}

@end