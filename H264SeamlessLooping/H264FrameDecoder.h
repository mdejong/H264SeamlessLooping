//
//  H264FrameDecoder.h
//
//  Created by Mo DeJong on 4/6/16.
//  Copyright © 2016 HelpURock. All rights reserved.
//
//  This module makes it easy to decode a CoreVideo frame
//  given an encoded CoreMedia frame.

@import Foundation;

@import AVFoundation;
@import CoreVideo;
@import CoreImage;
@import CoreMedia;
@import VideoToolbox;

@interface H264FrameDecoder : NSObject

@property (nonatomic, assign) CVPixelBufferRef pixelBuffer;

@property (nonatomic, copy) void (^pixelBufferBlock)(CVPixelBufferRef);

// Invoke to encode the pixel buffer, the result is assigned to
// self.sampleBuffer via async callback.

- (BOOL) decodeH264CoreMediaFrame:(CMSampleBufferRef)cmSampleBuffer;

// Optional method to indicate that session is completed, is also
// invoked on dealloc

- (void) endSession;

// If the caller wants to explicitly block until the frame decode operation
// is finished then this method can be invoked. Don't invoke in the main
// thread, or else!

- (void) waitForFrame;
  
@end
