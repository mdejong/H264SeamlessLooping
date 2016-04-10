//
//  H264Decode.m
//
//  Created by Mo DeJong on 4/5/16.
//
//  See license.txt for BSD license terms.
//

#import "H264Decode.h"

@import AVFoundation;
@import UIKit;

@import CoreVideo;
@import CoreImage;
@import CoreMedia;
@import CoreGraphics;
@import VideoToolbox;

// Private API

@interface H264Decode ()

@end

// implementation H264Decode

@implementation H264Decode

// Return the movie decode OS type, typically kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
// but could be kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange. In any case, this value
// needs to match in both the encoder and decoder.

+ (OSType) getPixelType
{
//  const OSType movieEncodePixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
  const OSType movieEncodePixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
  return movieEncodePixelFormatType;
}

// Given a .mov generate an array of the frames as CoreVideo buffers.
// This method returns the frames as BGRA pixels or YUV frames.

+ (NSArray*) decodeCoreVideoFramesFromMOV:(NSString*)movPath
                                    asYUV:(BOOL)asYUV
{
  if ([[NSFileManager defaultManager] fileExistsAtPath:movPath] == FALSE) {
    return nil;
  }
  
  // Read H.264 frames and convert from YUV to BGRA on the read
  
  NSURL *assetURL = [NSURL fileURLWithPath:movPath];
  assert(assetURL);
  
  NSDictionary *options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
                                                      forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
  
  AVURLAsset *avUrlAsset = [[AVURLAsset alloc] initWithURL:assetURL options:options];
  
  if (avUrlAsset.hasProtectedContent) {
    NSAssert(FALSE, @"DRM");
  }
  
  if ([avUrlAsset tracks] == 0) {
    NSAssert(FALSE, @"not tracks");
  }
  
  NSError *assetError = nil;
  AVAssetReader *aVAssetReader = [AVAssetReader assetReaderWithAsset:avUrlAsset error:&assetError];
  
  NSAssert(aVAssetReader, @"aVAssetReader");
  
  if (assetError) {
    NSAssert(FALSE, @"AVAssetReader");
  }
  
  NSDictionary *videoSettings;
  
  if (asYUV) {
    videoSettings = [NSDictionary dictionaryWithObject:
                     [NSNumber numberWithUnsignedInt:[self getPixelType]] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
  } else {
    videoSettings = [NSDictionary dictionaryWithObject:
                     [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    
  }
  
  NSArray *videoTracks = [avUrlAsset tracksWithMediaType:AVMediaTypeVideo];
  
  NSAssert([videoTracks count] == 1, @"only 1 video track can be decoded");
  
  AVAssetTrack *videoTrack = [videoTracks objectAtIndex:0];
  
  NSArray *availableMetadataFormats = videoTrack.availableMetadataFormats;
  NSLog(@"availableMetadataFormats %@", availableMetadataFormats);
  
  NSAssert(videoTrack.isSelfContained, @"isSelfContained");
  
  CGSize uncroppedSize = videoTrack.naturalSize;
  
  NSLog(@"video track naturalSize w x h : %d x %d", (int)uncroppedSize.width, (int)uncroppedSize.height);
  
  // Track length in second, should map directly to number of frames
  
  CMTimeRange timeRange = videoTrack.timeRange;
  
  float duration = (float)CMTimeGetSeconds(timeRange.duration);
  
  NSLog(@"video track time duration %0.3f", duration);
  
  // Don't know how many frames at this point
  
  //int numFrames = round(duration);
  //NSLog(@"estimated number of frames %d", numFrames);
  
  AVAssetReaderTrackOutput *aVAssetReaderOutput = [[AVAssetReaderTrackOutput alloc]
                                                   initWithTrack:videoTrack outputSettings:videoSettings];
  
  NSAssert(aVAssetReaderOutput, @"AVAssetReaderVideoCompositionOutput failed");
  
  aVAssetReaderOutput.alwaysCopiesSampleData = FALSE;
  
  [aVAssetReader addOutput:aVAssetReaderOutput];
  
  aVAssetReaderOutput = aVAssetReaderOutput;
  
  // start reading
  
  NSAssert(aVAssetReader, @"aVAssetReader");
  
  BOOL worked = [aVAssetReader startReading];
  
  if (worked == FALSE) {
    AVAssetReaderStatus status = aVAssetReader.status;
    NSError *error = aVAssetReader.error;
    
    NSLog(@"status = %d", (int)status);
    NSLog(@"error = %@", [error description]);
    
    return nil;
  }
  
  // Read N frames as CoreVideo buffers and return as NSArray
  
  NSMutableArray *mArr = [NSMutableArray array];
  
  // Read N frames, convert to BGRA pixels
  
  for ( int i = 0; 1; i++ ) {
  
    CMSampleBufferRef sampleBuffer = NULL;
    sampleBuffer = [aVAssetReaderOutput copyNextSampleBuffer];
    
    if (sampleBuffer == nil) {
      break;
    }
    
    // Process BGRA data in buffer, crop and then read and combine
    
    CVImageBufferRef imageBufferRef = CMSampleBufferGetImageBuffer(sampleBuffer);
    assert(imageBufferRef);
    
    CVPixelBufferRef pixBuffer = imageBufferRef;
    
    [mArr addObject:(__bridge id)pixBuffer];
    
    CFRelease(sampleBuffer);
  }
  
  [aVAssetReader cancelReading];
  
  return [NSArray arrayWithArray:mArr];
}

// Write a .mov that contains the CoreVideo frames in arr

+ (BOOL) encodeCoreVideoFramesAsMOV:(NSString*)movPath
                             frames:(NSArray*)frames
                     completedBlock:(void(^)(void))completedBlock
{
  CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) frames[0];
  
  int videoWidth = (int) CVPixelBufferGetWidth(cvPixelBuffer);
  int videoHeight = (int) CVPixelBufferGetHeight(cvPixelBuffer);
  
  // Delete existing file, since a partial write followed by another attempt to write will fail
  
  if ([[NSFileManager defaultManager] fileExistsAtPath:movPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:movPath error:nil];
    assert(worked);
  }
  
  NSURL *fileURL = [NSURL fileURLWithPath:movPath];
  
  // Render as CoreVideo buffer
  
  NSError *error = nil;
  AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:fileURL fileType:AVFileTypeQuickTimeMovie error:&error];
  NSAssert(error == nil, error.debugDescription);
  
  NSDictionary *videoCleanApertureSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                              @(videoWidth), AVVideoCleanApertureWidthKey,
                                              @(videoHeight), AVVideoCleanApertureHeightKey,
                                              @(0), AVVideoCleanApertureHorizontalOffsetKey,
                                              @(0), AVVideoCleanApertureVerticalOffsetKey,
                                              nil];
  
  NSDictionary *videoAspectRatioSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                            @(1), AVVideoPixelAspectRatioHorizontalSpacingKey,
                                            @(1), AVVideoPixelAspectRatioVerticalSpacingKey,
                                            nil];
  
  // Every frame is a keyframe, really high bitrate, main profile
  
  // [compressionProperties setObject:[NSNumber numberWithInt: 40000000] forKey:AVVideoAverageBitRateKey];
  //                                     AVVideoAverageBitRateKey: @(pixelNumber * 11.4),
  
  NSDictionary* videoCompression = @{
                                     AVVideoMaxKeyFrameIntervalKey: @(1),
                                     //AVVideoAverageBitRateKey: [NSNumber numberWithInt: 40000000],
                                     AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
                                     AVVideoCleanApertureKey: videoCleanApertureSettings,
                                     AVVideoPixelAspectRatioKey: videoAspectRatioSettings,
                                     };
  
  NSDictionary *settings = @{
                             AVVideoCodecKey: AVVideoCodecH264,
                             AVVideoWidthKey: @(videoWidth),
                             AVVideoHeightKey: @(videoHeight),
                             AVVideoCompressionPropertiesKey: videoCompression,
                             //                             AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
                             };
  
  AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
  
  NSDictionary *attributes = @{
//                               (NSString*)kCVPixelBufferPixelFormatTypeKey: @([H264Decode getPixelType]),
                               (NSString*)kCVPixelBufferPixelFormatTypeKey: @(CVPixelBufferGetPixelFormatType(cvPixelBuffer)),
                               (NSString*)kCVPixelBufferWidthKey: @(videoWidth),
                               (NSString*)kCVPixelBufferHeightKey: @(videoHeight)
                               };
  AVAssetWriterInputPixelBufferAdaptor *adapter = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:attributes];
  
  NSParameterAssert([writer canAddInput:input]);
  [writer addInput:input];
  
  input.expectsMediaDataInRealTime = NO;
  
  writer.shouldOptimizeForNetworkUse = TRUE;
  
  // Write frame data
  
  [writer startWriting];
  [writer startSessionAtSourceTime:kCMTimeZero];
  
  CVPixelBufferRef buffer;
  BOOL success;
  
  buffer = (__bridge CVPixelBufferRef) frames[0];
  success = [adapter appendPixelBuffer:buffer withPresentationTime:kCMTimeZero];
  assert(success);
  //CVPixelBufferRelease(buffer);
  
  // Frames
  
  for ( int i = 1; i < (int)[frames count]; i++ ) {
    CMTime present          = CMTimeMake(i * 600, 600);
    
    while (input.readyForMoreMediaData == FALSE) {
      [NSThread sleepForTimeInterval:0.1];
    }
    
    buffer = (__bridge CVPixelBufferRef) frames[i];
    success = [adapter appendPixelBuffer:buffer withPresentationTime:present];
    assert(success);
  }
  
  [input markAsFinished];
  
  [writer finishWritingWithCompletionHandler:completedBlock];
  
  return TRUE;
}

// Convert a buffer of CoreVideo in 4:2:0 full to BGRA, returns a new buffer

+ (CVPixelBufferRef) createBGRACoreVideoBuffer:(CVPixelBufferRef)pixelBuffer
{
  int width = (int) CVPixelBufferGetWidth(pixelBuffer);
  int height = (int) CVPixelBufferGetHeight(pixelBuffer);
  
  // Allocate BGRA buffer
  
  NSDictionary *options = @{
                            (NSString *)kCVPixelBufferCGImageCompatibilityKey: @(YES),
                            (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @(YES)
                            };
  
  CVPixelBufferRef bgraBuffer = NULL;
  CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                        width,
                                        height,
                                        kCVPixelFormatType_32BGRA,
                                        (__bridge CFDictionaryRef) options,
                                        &bgraBuffer);
  
  if (status != kCVReturnSuccess) {
    return nil;
  }

  CIContext *context = [CIContext contextWithOptions:nil];
  
  if (context == nil) {
    return nil;
  }
  
  CIImage *inputImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
  
  [context render:inputImage toCVPixelBuffer:bgraBuffer];
  
  return bgraBuffer;
}

+ (CVPixelBufferRef) pixelBufferFromImage:(UIImage*)image
                               renderSize:(CGSize)renderSize
                                     dump:(BOOL)dump
                                    asYUV:(BOOL)asYUV
{
  CGImageRef cgImage = image.CGImage;
  
  NSDictionary *options = @{
                            (NSString *)kCVPixelBufferCGImageCompatibilityKey: @(YES),
                            (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @(YES)
                            };
  
  int renderWidth = (int) renderSize.width;
  int renderHeight = (int) renderSize.height;
  
  int imageWidth = (int) CGImageGetWidth(cgImage);
  int imageHeight = (int) CGImageGetHeight(cgImage);
  
  assert(imageWidth <= renderWidth);
  assert(imageHeight <= renderHeight);
  
  // FIXME: instead of creating CoreVideo buffers over and over, just create 1 and
  // then keep using it to do the render operations. Could also use a pool, but
  // not really needed either.
  
  CVPixelBufferRef buffer = NULL;
  CVPixelBufferCreate(kCFAllocatorDefault,
                      renderWidth,
                      renderHeight,
                      kCVPixelFormatType_32BGRA,
                      (__bridge CFDictionaryRef)options,
                      &buffer);
  
  size_t bytesPerRow, extraBytes;
  bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
  extraBytes = bytesPerRow - renderWidth*sizeof(uint32_t);
  NSLog(@"bytesPerRow %d extraBytes %d", (int)bytesPerRow, (int)extraBytes);
  
  CVPixelBufferLockBaseAddress(buffer, 0);
  
  void *baseAddress                  = CVPixelBufferGetBaseAddress(buffer);
  
  CGColorSpaceRef colorSpace  = CGColorSpaceCreateDeviceRGB();
  
  //CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
  
  CGContextRef context;
  
  context = CGBitmapContextCreate(baseAddress,
                                  renderWidth,
                                  renderHeight,
                                  8,
                                  CVPixelBufferGetBytesPerRow(buffer),
                                  colorSpace,
                                  kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst);
  
  // Render frame into top left corner at exact size
  
  CGContextClearRect(context, CGRectMake(0.0f, 0.0f, renderWidth, renderHeight));
  
  CGContextDrawImage(context, CGRectMake(0.0f, renderHeight - imageHeight, imageWidth, imageHeight), cgImage);
  
  //CGColorSpaceRelease(colorSpace);
  CGContextRelease(context);
  
  CVPixelBufferUnlockBaseAddress(buffer, 0);
  
  // Convert from BGRA to YUV representation
  
  if (asYUV) {
    CVPixelBufferRef yuv420Buffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          renderWidth,
                                          renderHeight,
                                          [H264Decode getPixelType],
                                          (__bridge CFDictionaryRef) @{
                                                                       (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
                                                                       (__bridge NSString *)kCVPixelFormatOpenGLESCompatibility : @(YES),
                                                                       },
                                          &yuv420Buffer);
    
    CIContext *context = [CIContext contextWithOptions:nil];
    NSAssert(context, @"CIContext");
    
    CIImage *inImage = [CIImage imageWithCVPixelBuffer:buffer];
    
    if (status == kCVReturnSuccess) {
      [context render:inImage toCVPixelBuffer:yuv420Buffer];
    }
    
    CVPixelBufferRelease(buffer);
    
    return yuv420Buffer;
  }
  
  return buffer;
}

// Manually convert a buffer of known kCVPixelFormatType_420YpCbCr8BiPlanarFullRange Y values
// to a BGRA buffer where each Y is converted directly to a grayscale value without
// any range adjustment.

+ (CVPixelBufferRef) createGrayscaleBGRAFromFullRangeYCoreVideoBuffer:(CVPixelBufferRef)fullRangePixelBuffer
{
  int width = (int) CVPixelBufferGetWidth(fullRangePixelBuffer);
  int height = (int) CVPixelBufferGetHeight(fullRangePixelBuffer);
  
  // Allocate BGRA buffer
  
  NSDictionary *options = @{
                            (NSString *)kCVPixelBufferCGImageCompatibilityKey: @(YES),
                            (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @(YES)
                            };
  
  CVPixelBufferRef bgraBuffer = NULL;
  CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                        width,
                                        height,
                                        kCVPixelFormatType_32BGRA,
                                        (__bridge CFDictionaryRef) options,
                                        &bgraBuffer);
  
  if (status != kCVReturnSuccess) {
    return nil;
  }
  
  int numPlanes = (int) CVPixelBufferGetPlaneCount(fullRangePixelBuffer);
  assert(numPlanes <= 2);
  
  CVPixelBufferLockBaseAddress(bgraBuffer, 0);
  CVPixelBufferLockBaseAddress(fullRangePixelBuffer, 0);
  
  uint32_t *bgraPixelPtr = (uint32_t*) CVPixelBufferGetBaseAddress(bgraBuffer);
  
  const uint8_t *planeY = CVPixelBufferGetBaseAddressOfPlane(fullRangePixelBuffer, 0);
  size_t planeY_stride = CVPixelBufferGetBytesPerRowOfPlane(fullRangePixelBuffer, 0);
  
  for (int row = 0; row < height; row++) {
    for (int col = 0; col < width; col++) {
      uint32_t Y = planeY[planeY_stride*row + col];
      uint32_t gray = (Y << 16) | (Y << 8) | Y;
      bgraPixelPtr[row*width + col] = gray;
    }
  }
  
  CVPixelBufferUnlockBaseAddress(bgraBuffer, 0);
  CVPixelBufferUnlockBaseAddress(fullRangePixelBuffer, 0);
  
  return bgraBuffer;
}

@end
