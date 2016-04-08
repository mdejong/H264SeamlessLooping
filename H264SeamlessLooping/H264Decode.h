//
//  H264Decode.h
//  MetalBufferProcessing
//
//  Created by Mo DeJong on 4/5/16.
//  Copyright © 2016 HelpURock. All rights reserved.
//
//  Util module that wraps .mov decoding logic to CoreVideo frames.

@import Foundation;
@import CoreVideo;

@interface H264Decode : NSObject

// Return the movie decode OS type, typically kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
// but could be kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange. In any case, this value
// needs to match in both the encoder and decoder.

+ (OSType) getPixelType;

// Given a .mov generate an array of the frames as CoreVideo buffers.
// This method returns the frames as BGRA pixels or YUV frames.

+ (NSArray*) decodeCoreVideoFramesFromMOV:(NSString*)movPath
                                    asYUV:(BOOL)asYUV;

// Write a .mov that contains the CoreVideo frames in arr

+ (BOOL) encodeCoreVideoFramesAsMOV:(NSString*)movPath
                             frames:(NSArray*)frames
                     completedBlock:(void(^)(void))completedBlock;

// Convert a buffer of CoreVideo in 4:2:0 full to BGRA, returns a new buffer

+ (CVPixelBufferRef) createBGRACoreVideoBuffer:(CVPixelBufferRef)pixelBuffer;

// Manually convert a buffer of known kCVPixelFormatType_420YpCbCr8BiPlanarFullRange Y values
// to a BGRA buffer where each Y is converted directly to a grayscale value without
// any range adjustment.

+ (CVPixelBufferRef) createGrayscaleBGRAFromFullRangeYCoreVideoBuffer:(CVPixelBufferRef)fullRangePixelBuffer;

@end
