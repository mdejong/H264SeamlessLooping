//
//  H264FrameDecoder.m
//  MetalBufferProcessing
//
//  Created by Mo DeJong on 4/6/16.
//  Copyright © 2016 HelpURock. All rights reserved.
//

#import "H264FrameDecoder.h"

void VideoToolboxCallback(
                          void* decompressionOutputRefCon,
                          void* sourceFrameRefCon,
                          OSStatus status,
                          VTDecodeInfoFlags info,
                          CVImageBufferRef imageBuffer,
                          CMTime presentationTimeStamp,
                          CMTime presentationDuration);

// Private API

@interface H264FrameDecoder ()
{
  VTDecompressionSessionRef session;
}

@end

@implementation H264FrameDecoder

@synthesize pixelBuffer = m_pixelBuffer;

- (void) dealloc
{
  self.pixelBuffer = NULL;

  self.pixelBufferBlock = nil;
  
  [self endSession];
}

- (void) endSession
{
  if (self->session != NULL) {
    VTDecompressionSessionInvalidate(self->session);
    CFRelease(self->session);
    self->session = NULL;
  }
}

- (void) setPixelBuffer:(CVPixelBufferRef)cvPixelBuffer
{
  if (m_pixelBuffer) {
    CFRelease(m_pixelBuffer);
  }
  m_pixelBuffer = cvPixelBuffer;
  if (m_pixelBuffer) {
    CFRetain(m_pixelBuffer);
  }
}

- (BOOL) decodeH264CoreMediaFrame:(CMSampleBufferRef)cmSampleBuffer {
  OSStatus status;
  
  VTDecompressionOutputCallbackRecord cb = { VideoToolboxCallback, (__bridge void *) self };
  CMVideoFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(cmSampleBuffer);
  
  if (self->session == NULL) {
    NSDictionary* pixelBufferOptions = @{
                                         // Output pixel type required here since it would default to video range
                                         (NSString*) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                                         (NSString*) kCVPixelBufferOpenGLESCompatibilityKey : @YES,
                                         (NSString*) kCVPixelBufferIOSurfacePropertiesKey : @{}};
    
    status = VTDecompressionSessionCreate(
                                          kCFAllocatorDefault,
                                          formatDesc,
                                          NULL,
                                          (__bridge CFDictionaryRef)pixelBufferOptions,
                                          &cb,
                                          &session);
    
    if (status != noErr) {
      NSLog(@"VTDecompressionSessionCreate status not `noErr`: %d\n", (int)status);
      return FALSE;
    }
    
    // Configure session parameters
    
    [self configureSessionParameters];
  }
  
  assert(self->session);
  
  VTDecodeInfoFlags decodedFlags;
  
  status = VTDecompressionSessionDecodeFrame(session,
                                             cmSampleBuffer,
                                             kVTDecodeFrame_EnableAsynchronousDecompression,
                                             NULL,
                                             &decodedFlags);
  
  if (status != noErr) {
    NSLog(@"VTDecompressionSessionDecodeFrame status not `noErr`: %d\n", (int)status);
    return FALSE;
  }
  
  return TRUE;
}

- (void) didReceiveImageBuffer:(CVImageBufferRef)imageBuffer
{
  CVPixelBufferRef cvPixelBufferRef = (CVPixelBufferRef) imageBuffer;
  
  self.pixelBuffer = cvPixelBufferRef;
  
  if (self.pixelBuffer != nil) {
    if (cvPixelBufferRef == NULL) {
      // Error case
      self.pixelBufferBlock(NULL);
    } else {
      // Success
      self.pixelBufferBlock(cvPixelBufferRef);
    }
  }
  
  return;
}

- (void) configureSessionParameters
{  
}

- (void) waitForFrame
{
  // Flush in-process frames.
  VTDecompressionSessionFinishDelayedFrames(session);
  // Block until our callback has been called with the last frame.
  VTDecompressionSessionWaitForAsynchronousFrames(session);
}

@end

// Video Toolbox callback

void VideoToolboxCallback(
                          void* decompressionOutputRefCon,
                          void* sourceFrameRefCon,
                          OSStatus status,
                          VTDecodeInfoFlags info,
                          CVImageBufferRef imageBuffer,
                          CMTime presentationTimeStamp,
                          CMTime presentationDuration)
{
  H264FrameDecoder *obj = (__bridge H264FrameDecoder *)decompressionOutputRefCon;
  assert(obj);
  
  if (status != noErr) {
    NSLog(@"Error: %@", [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil]);
    
    [obj didReceiveImageBuffer:nil];
  } else {
    [obj didReceiveImageBuffer:imageBuffer];
  }
  
  return;
  
  /*
  
  if (status != noErr || !imageBuffer) {
    fprintf(stderr, "Error %d decoding frame!\n", status);
    return;
  }
  
  fprintf(stdout, "Got frame data.\n");
   
  */
}
