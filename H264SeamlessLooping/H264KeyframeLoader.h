//
//  H264KeyframeLoader.h
//  H264SeamlessLooping
//
//  Created by Mo DeJong on 4/8/16.
//  Copyright © 2016 HelpURock. All rights reserved.
//
//  This class implements a H264 video file reader that is able to load
//  generic H264 video content in a way that makes it possible to treat
//  each frame as a keyframe.

#import <UIKit/UIKit.h>

@interface H264KeyframeLoader : NSObject

+ (H264KeyframeLoader*) h264KeyframeLoader;

@end

