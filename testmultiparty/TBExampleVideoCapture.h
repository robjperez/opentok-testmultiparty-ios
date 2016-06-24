//
//  TBExampleVideoCapture.h
//  OpenTok iOS SDK
//
//  Copyright (c) 2013 Tokbox, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <OpenTok/OpenTok.h>

@protocol OTVideoCapture;

extern NSString *_Nonnull TBExampleVideoCaptureCannotOpenDeviceNotification;
extern NSString *_Nonnull TBExampleVideoCaptureCannotCaptureFrames;

@interface TBExampleVideoCapture : NSObject
<AVCaptureVideoDataOutputSampleBufferDelegate, OTVideoCapture>
{
@protected
    dispatch_queue_t _capture_queue;
}

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) AVCaptureDeviceInput *videoInput;

@property (nonatomic, assign) NSString* captureSessionPreset;
@property (readonly) NSArray* availableCaptureSessionPresets;

@property (nonatomic, assign) double activeFrameRate;
- (BOOL)isAvailableActiveFrameRate:(double)frameRate;

@property (nonatomic, assign) AVCaptureDevicePosition cameraPosition;
@property (readonly) NSArray* availableCameraPositions;
- (BOOL)toggleCameraPosition;

@end