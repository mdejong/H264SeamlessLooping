//
//  H264FrameEncoder.m
//  MetalBufferProcessing
//
//  Created by Mo DeJong on 4/6/16.
//  Copyright © 2016 HelpURock. All rights reserved.
//

#import "H264FrameEncoder.h"

static
void VideoToolboxCallback(void *outputCallbackRefCon,
                          void *sourceFrameRefCon,
                          OSStatus status,
                          VTEncodeInfoFlags infoFlags,
                          CMSampleBufferRef sampleBuffer );

// Private API

@interface H264FrameEncoder ()
{
  VTCompressionSessionRef session;
}

@end

@implementation H264FrameEncoder

@synthesize sampleBuffer = m_sampleBuffer;

- (void) dealloc
{
  self.sampleBuffer = NULL;

  self.sampleBufferBlock = nil;
  
  [self endSession];
}

- (void) endSession
{
  if (self->session != NULL) {
    VTCompressionSessionInvalidate(self->session);
    CFRelease(self->session);
    self->session = NULL;
  }
}

- (void) setSampleBuffer:(CMSampleBufferRef)cmSampleBuffer
{
  if (m_sampleBuffer) {
    CFRelease(m_sampleBuffer);
  }
  m_sampleBuffer = cmSampleBuffer;
  if (m_sampleBuffer) {
    CFRetain(m_sampleBuffer);
  }
}

// Encode an uncompressed CoreVideo pixel buffer as a compressed CoreMedia buffer

- (BOOL) encodeH264CoreMediaFrame:(CVPixelBufferRef)cvPixelBuffer {
  OSStatus status;
  
  if (self->session == NULL) {
    int width = (int) CVPixelBufferGetWidth(cvPixelBuffer);
    int height = (int) CVPixelBufferGetHeight(cvPixelBuffer);
    
    NSDictionary* pixelBufferOptions = @{
                                         (NSString*) kCVPixelBufferWidthKey : @(width),
                                         (NSString*) kCVPixelBufferHeightKey : @(height),
                                         (NSString*) kCVPixelBufferOpenGLESCompatibilityKey : @YES,
                                         (NSString*) kCVPixelBufferIOSurfacePropertiesKey : @{}};
    
    CFMutableDictionaryRef encoderSpecifications = NULL;
    status = VTCompressionSessionCreate(
                                        kCFAllocatorDefault,
                                        width,
                                        height,
                                        kCMVideoCodecType_H264,
                                        encoderSpecifications,
                                        (__bridge CFDictionaryRef)pixelBufferOptions,
                                        NULL,
                                        (VTCompressionOutputCallback)VideoToolboxCallback,
                                        (__bridge void *)self,
                                        &self->session);
    
    if (status != noErr) {
      NSLog(@"VTCompressionSessionCreate status not `noErr`: %d\n", (int)status);
      return FALSE;
    }
    
    // Configure session parameters
    
    [self configureSessionParameters];
    
    self.frameOffset = 0;
  }
  
  assert(self->session);
  
  int offset = self.frameOffset;
  self.frameOffset += 1;
  
  CMTime pts = CMTimeMake(0, 600);
  CMTime dur = CMTimeMake(600 * offset, 600);
  
  self.sampleBuffer = NULL;
  
  status = VTCompressionSessionEncodeFrame(session, cvPixelBuffer, pts, dur, NULL, NULL, NULL);
  
  if (status != noErr) {
    NSLog(@"VTCompressionSessionEncodeFrame status not `noErr`: %d\n", (int)status);
    return FALSE;
  }
  
  return TRUE;
}

- (void) didReceiveSampleBuffer:(CMSampleBufferRef)cmSampleBuffer
{
  self.sampleBuffer = cmSampleBuffer;
  
  if (self.sampleBufferBlock != nil) {
    if (cmSampleBuffer == NULL) {
      // Error case
      self.sampleBufferBlock(NULL);
    } else {
      // Success
      self.sampleBufferBlock(cmSampleBuffer);
    }
  }
  
  return;
}

- (void) configureSessionParameters
{
  OSStatus status;

  status = VTSessionSetProperty(session,
                                kVTCompressionPropertyKey_RealTime,
                                kCFBooleanTrue);
  
  if (noErr != status) {
    NSLog(@"VTSessionSetProperty: Cannot set kVTCompressionPropertyKey_RealTime.\n");
    return;
  }
  
  status = VTSessionSetProperty(session,
                                kVTCompressionPropertyKey_ProfileLevel,
                                kVTProfileLevel_H264_Main_AutoLevel);
  
  if (noErr != status) {
    NSLog(@"VTSessionSetProperty: Cannot set kVTCompressionPropertyKey_ProfileLevel.\n");
    return;
  }

  status = VTSessionSetProperty(session,
                                kVTCompressionPropertyKey_AllowFrameReordering,
                                kCFBooleanFalse);
  
  if (noErr != status) {
    NSLog(@"VTSessionSetProperty: Cannot set kVTCompressionPropertyKey_AllowFrameReordering.\n");
    return;
  }

  // Must be a keyframe
  
  status = VTSessionSetProperty(session,
                                kVTCompressionPropertyKey_MaxKeyFrameInterval,
                                (__bridge CFNumberRef)@(1));
  
  if (noErr != status) {
    NSLog(@"VTSessionSetProperty: Cannot set kVTCompressionPropertyKey_MaxKeyFrameInterval.\n");
    return;
  }
  
  //NSNumber *bitrate = @(700);
  //NSNumber *bitrate = @(20000); // 400
  
  //NSNumber *bitrate = @(100000); // 1146
  //NSNumber *bitrate = @(200000); // 1332
  //NSNumber *bitrate = @(500000); // 1956
  //NSNumber *bitrate = @(700000); // 2423
  //NSNumber *bitrate = @(1000000); // 2756
  //NSNumber *bitrate = @(1250000); // 3283
  //NSNumber *bitrate = @(1500000); // 3697
  //NSNumber *bitrate = @(2000000); // 4121
  
  NSNumber *bitrate = @(2000000000);

  status = VTSessionSetProperty(session,
                                kVTCompressionPropertyKey_AverageBitRate,
                                (__bridge CFNumberRef)bitrate);
  
  if (noErr != status) {
    NSLog(@"VTSessionSetProperty: Cannot set kVTCompressionPropertyKey_AverageBitRate.\n");
    return;
  }

  //  status = VTSessionSetProperty(session, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)@[800 * 1024 / 8, 1]);
  
  /*
   
  // Not as effective, baselien profile
  
  status = VTSessionSetProperty(session,
                                kVTCompressionPropertyKey_H264EntropyMode,
                                kVTH264EntropyMode_CAVLC);
  
  if (noErr != status) {
    NSLog(@"VTSessionSetProperty: Cannot set kVTCompressionPropertyKey_H264EntropyMode.\n");
    return;
  }
  
  */
  
  // CABAC provides best entropy encoding
  
  status = VTSessionSetProperty(session,
                                kVTCompressionPropertyKey_H264EntropyMode,
                                kVTH264EntropyMode_CABAC);
  
  if (noErr != status) {
    NSLog(@"VTSessionSetProperty: Cannot set kVTCompressionPropertyKey_H264EntropyMode.\n");
    return;
  }
  
  status = VTCompressionSessionPrepareToEncodeFrames(session);
  
  if (noErr != status) {
    NSLog(@"VTCompressionSessionPrepareToEncodeFrames %d\n", (int)status);
    return;
  }
  
}

@end

// Video Toolbox callback

void VideoToolboxCallback(void *outputCallbackRefCon,
                          void *sourceFrameRefCon,
                          OSStatus status,
                          VTEncodeInfoFlags infoFlags,
                          CMSampleBufferRef sampleBuffer )
{
  H264FrameEncoder *obj = (__bridge H264FrameEncoder *)outputCallbackRefCon;
  assert(obj);
  
  if (status != noErr) {
    NSLog(@"Error: %@", [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil]);
    
    [obj didReceiveSampleBuffer:nil];
  } else {
    [obj didReceiveSampleBuffer:sampleBuffer];
  }
  
  return;
}
