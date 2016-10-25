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

+ (OSType) getPixelType
{
  //  const OSType movieEncodePixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
  const OSType movieEncodePixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
  return movieEncodePixelFormatType;
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
