//
//  H264FrameEncoder.h
//
//  Created by Mo DeJong on 4/5/16.
//
//  See license.txt for BSD license terms.
//
//  This module makes it easy to encode a single CoreVideo frame
//  as H264 wrapped as a CoreMedia sample buffer object.

@import Foundation;

@import AVFoundation;
@import CoreVideo;
@import CoreImage;
@import CoreMedia;
@import VideoToolbox;

@interface H264FrameEncoder : NSObject

// Approx frame duration, will default to 30 FPS by default

@property (nonatomic, assign) float frameDuration;


// Bitrate provides a way to dial the encoded quality up or down

// LOW   =  100000
// MED   = 2000000
// HIGH  = 5000000
// CRAZY = 2000000000

@property (nonatomic, assign) int aveBitrate;

@property (nonatomic, assign) int frameOffset;

@property (nonatomic, assign) CMSampleBufferRef sampleBuffer;

@property (nonatomic, copy) void (^sampleBufferBlock)(CMSampleBufferRef);

// Invoke to encode the pixel buffer, the result is assigned to
// self.sampleBuffer via async callback.

- (BOOL) encodeH264CoreMediaFrame:(CVPixelBufferRef)cvPixelBuffer;

// Optional method to indicate that session is completed, is also
// invoked on dealloc

- (void) endSession;

// If the caller wants to explicitly block until the frame decode operation
// is finished then this method can be invoked. Don't invoke in the main
// thread, or else!

- (void) waitForFrame;

@end
