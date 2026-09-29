#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <pthread.h>

#define PREF_PATH @"/var/mobile/Library/Preferences/com.weat.fakecamera.plist"
#define DEFAULT_IMAGE_PATH @"/var/mobile/Documents/FakeCamera/fake_image.jpg"
#define DEFAULT_VIDEO_PATH @"/var/mobile/Documents/FakeCamera/fake_video.mp4"

static BOOL isEnabled = NO;
static NSInteger mediaType = 1; // 1: Image, 2: Video
static NSString *imagePath = DEFAULT_IMAGE_PATH;
static NSString *videoPath = DEFAULT_VIDEO_PATH;

static AVPlayerItemVideoOutput *sharedVideoOutput = nil;
static AVPlayer *sharedPlayer = nil;
static CVPixelBufferRef staticImageBuffer = NULL;

static pthread_mutex_t mediaLock = PTHREAD_MUTEX_INITIALIZER;

static void cleanupMediaResources(void) {
    pthread_mutex_lock(&mediaLock);
    if (staticImageBuffer) {
        CVPixelBufferRelease(staticImageBuffer);
        staticImageBuffer = NULL;
    }
    if (sharedPlayer) {
        [sharedPlayer pause];
        sharedPlayer = nil;
        sharedVideoOutput = nil;
    }
    pthread_mutex_unlock(&mediaLock);
}

static void loadPreferences(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
    if (prefs) {
        isEnabled = [prefs[@"isEnabled"] boolValue];
        if (prefs[@"mediaType"]) mediaType = [prefs[@"mediaType"] integerValue];
        if (prefs[@"imagePath"]) imagePath = [prefs[@"imagePath"] copy];
        if (prefs[@"videoPath"]) videoPath = [prefs[@"videoPath"] copy];
    } else {
        isEnabled = NO;
        mediaType = 1;
        imagePath = DEFAULT_IMAGE_PATH;
        videoPath = DEFAULT_VIDEO_PATH;
    }
    cleanupMediaResources();
}

static CVPixelBufferRef createPixelBufferFromImage(UIImage *image) {
    if (!image) return NULL;
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return NULL;
    
    CGFloat width = CGImageGetWidth(cgImage);
    CGFloat height = CGImageGetHeight(cgImage);
    
    NSDictionary *options = @{
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    
    CVPixelBufferRef pxbuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          (size_t)width,
                                          (size_t)height,
                                          kCVPixelFormatType_32BGRA,
                                          (__bridge CFDictionaryRef)options,
                                          &pxbuffer);
    
    if (status == kCVReturnSuccess && pxbuffer != NULL) {
        CVPixelBufferLockBaseAddress(pxbuffer, 0);
        void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
        
        CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(pxdata,
                                                     (size_t)width,
                                                     (size_t)height,
                                                     8,
                                                     CVPixelBufferGetBytesPerRow(pxbuffer),
                                                     rgbColorSpace,
                                                     kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        
        if (context) {
            CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
            CGColorSpaceRelease(rgbColorSpace);
            CGContextRelease(context);
        } else {
            CGColorSpaceRelease(rgbColorSpace);
        }
        
        CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    }
    return pxbuffer;
}

static void setupMediaSourceIfNeeded(void) {
    pthread_mutex_lock(&mediaLock);
    
    if (mediaType == 1) {
        if (!staticImageBuffer) {
            NSString *effectivePath = imagePath ?: DEFAULT_IMAGE_PATH;
            UIImage *img = [UIImage imageWithContentsOfFile:effectivePath];
            if (img) {
                staticImageBuffer = createPixelBufferFromImage(img);
            }
        }
    } else if (mediaType == 2) {
        if (!sharedPlayer) {
            NSString *effectivePath = videoPath ?: DEFAULT_VIDEO_PATH;
            NSURL *videoURL = [NSURL fileURLWithPath:effectivePath];
            if ([[NSFileManager defaultManager] fileExistsAtPath:effectivePath]) {
                sharedPlayer = [[AVPlayer alloc] initWithURL:videoURL];
                sharedPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
                
                NSDictionary *pixBuffAttributes = @{
                    (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
                };
                sharedVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixBuffAttributes];
                [[sharedPlayer currentItem] addOutput:sharedVideoOutput];
                
                [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                                  object:[sharedPlayer currentItem]
                                                                   queue:[NSOperationQueue mainQueue]
                                                              usingBlock:^(NSNotification *note) {
                    if (sharedPlayer) {
                        [sharedPlayer seekToTime:kCMTimeZero];
                        [sharedPlayer play];
                    }
                }];
                
                [sharedPlayer play];
            }
        }
    }
    
    pthread_mutex_unlock(&mediaLock);
}

static void replaceSampleBuffer(CMSampleBufferRef *sampleBuffer) {
    if (!sampleBuffer || !*sampleBuffer) return;
    
    CVPixelBufferRef pixelBufferToUse = NULL;
    
    pthread_mutex_lock(&mediaLock);
    if (mediaType == 1 && staticImageBuffer) {
        pixelBufferToUse = CVPixelBufferRetain(staticImageBuffer);
    } else if (mediaType == 2 && sharedVideoOutput) {
        CMTime currentTime = [sharedVideoOutput itemTimeForHostTime:CACurrentMediaTime()];
        if ([sharedVideoOutput hasNewPixelBufferForItemTime:currentTime]) {
            pixelBufferToUse = [sharedVideoOutput copyPixelBufferForItemTime:currentTime itemTimeForDisplay:nil];
        } else if (staticImageBuffer) {
            pixelBufferToUse = CVPixelBufferRetain(staticImageBuffer);
        }
    }
    pthread_mutex_unlock(&mediaLock);
    
    if (pixelBufferToUse) {
        CMSampleTimingInfo timingInfo;
        memset(&timingInfo, 0, sizeof(CMSampleTimingInfo));
        OSStatus timeStatus = CMSampleBufferGetSampleTimingInfo(*sampleBuffer, 0, &timingInfo);
        if (timeStatus != noErr) {
            timingInfo.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock());
            timingInfo.decodeTimeStamp = kCMTimeInvalid;
            timingInfo.duration = kCMTimeInvalid;
        }
        
        CMVideoFormatDescriptionRef videoInfo = NULL;
        OSStatus formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBufferToUse, &videoInfo);
        
        if (formatStatus == noErr && videoInfo != NULL) {
            CMSampleBufferRef newSampleBuffer = NULL;
            OSStatus createStatus = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                                                             pixelBufferToUse,
                                                                             videoInfo,
                                                                             &timingInfo,
                                                                             &newSampleBuffer);
            if (createStatus == noErr && newSampleBuffer != NULL) {
                *sampleBuffer = newSampleBuffer;
            }
            CFRelease(videoInfo);
        }
        CVPixelBufferRelease(pixelBufferToUse);
    }
}

// -----------------------------------------------------------------------------
// Hook AVCaptureVideoDataOutput (Video Streaming / Preview / Calls / Social Apps)
// -----------------------------------------------------------------------------
static void (*orig_captureOutput_didOutputSampleBuffer_fromConnection)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *);

static void hook_captureOutput_didOutputSampleBuffer_fromConnection(id self, SEL _cmd, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection) {
    if (isEnabled) {
        setupMediaSourceIfNeeded();
        CMSampleBufferRef fakeBuffer = sampleBuffer;
        replaceSampleBuffer(&fakeBuffer);
        
        orig_captureOutput_didOutputSampleBuffer_fromConnection(self, _cmd, output, fakeBuffer, connection);
        
        if (fakeBuffer != sampleBuffer) {
            CFRelease(fakeBuffer);
        }
    } else {
        orig_captureOutput_didOutputSampleBuffer_fromConnection(self, _cmd, output, sampleBuffer, connection);
    }
}

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    %orig;
    
    if (sampleBufferDelegate) {
        Class delegateClass = [sampleBufferDelegate class];
        SEL targetSelector = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
        
        Method m = class_getInstanceMethod(delegateClass, targetSelector);
        if (m) {
            IMP currentImp = method_getImplementation(m);
            if (currentImp != (IMP)hook_captureOutput_didOutputSampleBuffer_fromConnection) {
                orig_captureOutput_didOutputSampleBuffer_fromConnection = (void *)currentImp;
                method_setImplementation(m, (IMP)hook_captureOutput_didOutputSampleBuffer_fromConnection);
            }
        }
    }
}

%end

// -----------------------------------------------------------------------------
// Hook AVCapturePhotoOutput (Still photo taking in Camera & Third-party apps)
// -----------------------------------------------------------------------------
static void (*orig_photoOutput_didFinishProcessingPhoto_error)(id, SEL, AVCapturePhotoOutput *, AVCapturePhoto *, NSError *);

static void hook_photoOutput_didFinishProcessingPhoto_error(id self, SEL _cmd, AVCapturePhotoOutput *output, AVCapturePhoto *photo, NSError *error) {
    orig_photoOutput_didFinishProcessingPhoto_error(self, _cmd, output, photo, error);
}

%hook AVCapturePhotoOutput

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (isEnabled && delegate) {
        setupMediaSourceIfNeeded();
        Class delegateClass = [delegate class];
        SEL targetSelector = @selector(captureOutput:didFinishProcessingPhoto:error:);
        Method m = class_getInstanceMethod(delegateClass, targetSelector);
        if (m) {
            IMP currentImp = method_getImplementation(m);
            if (currentImp != (IMP)hook_photoOutput_didFinishProcessingPhoto_error) {
                orig_photoOutput_didFinishProcessingPhoto_error = (void *)currentImp;
                method_setImplementation(m, (IMP)hook_photoOutput_didFinishProcessingPhoto_error);
            }
        }
    }
    %orig(settings, delegate);
}

%end

// -----------------------------------------------------------------------------
// Hook AVCapturePhoto to return fake pixel buffer if requested
// -----------------------------------------------------------------------------
%hook AVCapturePhoto

- (CVPixelBufferRef)pixelBuffer {
    if (isEnabled) {
        setupMediaSourceIfNeeded();
        CVPixelBufferRef fakeBuf = NULL;
        pthread_mutex_lock(&mediaLock);
        if (staticImageBuffer) {
            fakeBuf = CVPixelBufferRetain(staticImageBuffer);
        }
        pthread_mutex_unlock(&mediaLock);
        if (fakeBuf) {
            return fakeBuf;
        }
    }
    return %orig;
}

- (NSData *)fileDataRepresentation {
    if (isEnabled) {
        setupMediaSourceIfNeeded();
        NSString *effectivePath = imagePath ?: DEFAULT_IMAGE_PATH;
        NSData *imgData = [NSData dataWithContentsOfFile:effectivePath];
        if (imgData) {
            return imgData;
        }
    }
    return %orig;
}

%end

// -----------------------------------------------------------------------------
// Initializer & Darwin Notification Listener
// -----------------------------------------------------------------------------
%ctor {
    @autoreleasepool {
        loadPreferences();
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)loadPreferences,
            CFSTR("com.weat.fakecamera/prefsupdated"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
}
