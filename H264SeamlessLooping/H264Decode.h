//
//  H264Decode.h
//
//  Created by Mo DeJong on 4/5/16.
//
//  See license.txt for BSD license terms.
//
//  Util module that wraps .mov decoding logic to CoreVideo frames.

@import Foundation;
@import UIKit;
@import CoreVideo;

@interface H264Decode : NSObject

// Render

+ (CVPixelBufferRef) pixelBufferFromImage:(UIImage*)image
                               renderSize:(CGSize)renderSize
                                     dump:(BOOL)dump
                                    asYUV:(BOOL)asYUV;

// Convert a buffer of CoreVideo in 4:2:0 full to BGRA, returns a new buffer

+ (CVPixelBufferRef) createBGRACoreVideoBuffer:(CVPixelBufferRef)pixelBuffer;

// Manually convert a buffer of known kCVPixelFormatType_420YpCbCr8BiPlanarFullRange Y values
// to a BGRA buffer where each Y is converted directly to a grayscale value without
// any range adjustment.

+ (CVPixelBufferRef) createGrayscaleBGRAFromFullRangeYCoreVideoBuffer:(CVPixelBufferRef)fullRangePixelBuffer;

@end
