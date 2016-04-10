//
//  DetailViewController.m
//  H264SeamlessLooping
//
//  Created by Mo DeJong on 4/8/16.
//  Copyright © 2016 HelpURock. All rights reserved.
//

#import "DetailViewController.h"

@import AVFoundation;
@import AVKit;

#import "H264Decode.h"

#import "H264FrameEncoder.h"
#import "H264FrameDecoder.h"

static int dumpFramesImages = 0;

@interface DetailViewController ()

@property (nonatomic, copy) NSString *resourceName;

@property (nonatomic, retain) AVPlayerViewController* avPlayerViewController;

@property (nonatomic, retain) AVSampleBufferDisplayLayer *sampleBufferLayer;

@property (nonatomic, retain) NSTimer *displayH264Timer;

@property (nonatomic, assign) BOOL isWaitingToPlay;

@property (nonatomic, copy) NSArray *encodedBuffers;
@property (nonatomic, assign) int encodedBufferOffset;

@end

@implementation DetailViewController

@synthesize tag = m_tag;

#pragma mark - Managing the detail item

- (void) dealloc {
  NSLog(@"DetailViewController : dealloc %p with tag \"%@\"", self, self.tag);
  
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)configureView {
  // Update the user interface for the detail item.
  if (self.tag) {
      self.detailDescriptionLabel.text = [self.tag description];
  }
}

- (void) loadAVPlayerLayer
{
  [super viewDidLoad];
  UIView *view = self.view;
  NSString *resourceName = self.resourceName;
  NSString* movieFilePath = [[NSBundle mainBundle]
                             pathForResource:resourceName ofType:nil];
  NSAssert(movieFilePath, @"movieFilePath is nil");
  NSURL *fileURL = [NSURL fileURLWithPath:movieFilePath];
  
  AVPlayerViewController *playerViewController = [[AVPlayerViewController alloc] init];
  playerViewController.player = [AVPlayer playerWithURL:fileURL];
  self.avPlayerViewController = playerViewController;
  [self resizePlayerToViewSize];
  [view addSubview:playerViewController.view];
  view.autoresizesSubviews = TRUE;
  
  // Deliver notification on movie play end
  
  AVPlayerItem *playerItem = playerViewController.player.currentItem;
  assert(playerItem);
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(aVPlayerViewControllerDonePlaying:)
                                               name:AVPlayerItemDidPlayToEndTimeNotification
                                             object:playerItem];
  
  [self addObserverForTimeRanges];
  
  self.isWaitingToPlay = TRUE;
}

- (void)viewDidLayoutSubviews {
  // Adjust buffer dimensions
  [self resizePlayerToViewSize];
}

- (void) resizePlayerToViewSize
{
  CGRect frame = self.view.frame;
  
  NSLog(@" avPlayerViewController set to frame size %d, %d", (int)frame.size.width, (int)frame.size.height);
  
  self.avPlayerViewController.view.frame = frame;
  
  self.sampleBufferLayer.frame = frame;
  self.sampleBufferLayer.position = CGPointMake(CGRectGetMidX(self.sampleBufferLayer.bounds), CGRectGetMidY(self.sampleBufferLayer.bounds));
}

- (void) aVPlayerViewControllerDonePlaying:(NSNotification*)notification
{
  AVPlayer *player = self.avPlayerViewController.player;
  assert(player);
  AVPlayerItem *playerItem = player.currentItem;
  assert(playerItem);
  [playerItem seekToTime:kCMTimeZero];
  [player play];
}

// Check for avPlayerViewController ready to play

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  AVPlayer *player = self.avPlayerViewController.player;
  
  if (object == player && [keyPath isEqualToString:@"currentItem.loadedTimeRanges"]) {
    NSArray *timeRanges = (NSArray*)[change objectForKey:NSKeyValueChangeNewKey];
    if (timeRanges && [timeRanges count]) {
      CMTimeRange timerange=[[timeRanges objectAtIndex:0]CMTimeRangeValue];
      float currentBufferDuration = CMTimeGetSeconds(CMTimeAdd(timerange.start, timerange.duration));
      CMTime duration = player.currentItem.asset.duration;
      float seconds = CMTimeGetSeconds(duration);
      
      //I think that 2 seconds is enough to know if you're ready or not
      if (self.isWaitingToPlay && (currentBufferDuration > 2 || currentBufferDuration == seconds)) {
        
        [self removeObserverForTimesRanges];
        self.isWaitingToPlay = FALSE;
        
        // Start at zero
        
        [self aVPlayerViewControllerDonePlaying:nil];
      }
    } else {
      [[[UIAlertView alloc] initWithTitle:@"Alert!" message:@"Error trying to play the clip. Please try again" delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil, nil] show];
    }
  }
}

- (void) addObserverForTimeRanges
{
  AVPlayer *player = self.avPlayerViewController.player;
  if (player) {
    [player addObserver:self forKeyPath:@"currentItem.loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
  }
}

- (void)removeObserverForTimesRanges
{
  AVPlayer *player = self.avPlayerViewController.player;
  if (player) {
    @try {
      [player removeObserver:self forKeyPath:@"currentItem.loadedTimeRanges"];
    } @catch(id anException){
      NSLog(@"excepcion remove observer == %@. Remove previously or never added observer.",anException);
      //do nothing, obviously it wasn't attached because an exception was thrown
    }
  }
}

- (void)viewDidLoad {
  [super viewDidLoad];
  
  self.resourceName = @"CarOverWhiteBG.m4v";
  
  if ([self.tag hasPrefix:@"AVPlayer"]) {
    [self loadAVPlayerLayer];
  } else if ([self.tag hasPrefix:@"CoreMedia"]) {
    [self loadCoreMedia];
  } else if (self.tag == nil || [self.tag isEqualToString:@""]) {
    // nop
  } else {
    NSAssert(0, @"unsupported tag \"%@\"", self.tag);
  }
}

- (void) viewDidDisappear:(BOOL)animated
{
  [super viewDidDisappear:animated];
  [self removeObserverForTimesRanges];
  
  [self.displayH264Timer invalidate];
  self.displayH264Timer = nil;
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Dispose of any resources that can be recreated.
}

// Decompress CoreMedia sample data directly from a .mov container
// without decompressing the samples.

- (void) loadCoreMedia
{
  NSString *resourceName = self.resourceName;
  NSString* movieFilePath = [[NSBundle mainBundle]
                             pathForResource:resourceName ofType:nil];
  NSAssert(movieFilePath, @"movieFilePath is nil");
  
  // Setup AVSampleBufferDisplayLayer to display samples from memory
  
  self.sampleBufferLayer = [[AVSampleBufferDisplayLayer alloc] init];
  
  self.sampleBufferLayer.videoGravity = AVLayerVideoGravityResizeAspect;
  
  self.sampleBufferLayer.backgroundColor = [UIColor blackColor].CGColor;
  
  [self.view.layer addSublayer:self.sampleBufferLayer];
  
  [self resizePlayerToViewSize];
  
  // Decode H.264 encoded data from file and then reencode the image data
  // as keyframes that can be access randomly.

  // FIXME: Using BGRA here, but should keep as YUV for max perf
  
  NSArray *coreVideoSamplesArr = [H264Decode decodeCoreVideoFramesFromMOV:movieFilePath asYUV:TRUE];
  
  H264FrameEncoder *frameEncoder = [[H264FrameEncoder alloc] init];
  
  // Begin to decode frames
  
  NSMutableArray *encodedH264Buffers = [NSMutableArray array];
  
  int numSampleBuffers = (int) coreVideoSamplesArr.count;
  
  __block int totalEncodeNumBytes = 0;
  
  for (int i = 0; i < numSampleBuffers; i++ ) @autoreleasepool {
    // use VTCreateCGImageFromCVPixelBuffer() ?
    
    CVPixelBufferRef pixBuffer = (__bridge CVPixelBufferRef) coreVideoSamplesArr[i];
    
    int width = (int) CVPixelBufferGetWidth(pixBuffer);
    int height = (int) CVPixelBufferGetHeight(pixBuffer);
    
    CGSize imgSize = CGSizeMake(width, height);
    
    // 1920 x 1080 is Full HD and the upper limit of H264 render size for iPad devices.
    // When the size of the input and the output exactly match, use input buffer (much faster)
    
    CGSize renderSize = CGSizeMake(1920, 1080);
    //int renderWidth = (int) renderSize.width;
    //int renderHeight = (int) renderSize.height;
    
    // Render CoreVideo to a NxN square so that square pixels do not distort
    
    NSLog(@"encode input dimensions %4d x %4d", width, height);

    CVPixelBufferRef largerBuffer;
    
    if (CGSizeEqualToSize(imgSize, renderSize)) {
      // No resize needed
      largerBuffer = pixBuffer;
      
      CVPixelBufferRetain(largerBuffer);
    } else {
      CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixBuffer];
      
      UIGraphicsBeginImageContext(renderSize);
      CGRect rect;
      rect.origin = CGPointZero;
      rect.size   = imgSize;
      UIImage *remImage = [UIImage imageWithCIImage:ciImage];
      [remImage drawInRect:rect];
      UIImage *rerenderedInputImg = UIGraphicsGetImageFromCurrentImageContext();
      UIGraphicsEndImageContext();
      
      if (dumpFramesImages)
      {
        NSString *dumpFilename = [NSString stringWithFormat:@"rerendered_frame%d.png", i];
        NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:dumpFilename];
        
        NSData *pngData = UIImagePNGRepresentation(rerenderedInputImg);
        [pngData writeToFile:tmpPath atomically:TRUE];
        
        NSLog(@"wrote \"%@\" at size %d x %d", tmpPath, (int)rerenderedInputImg.size.width, (int)rerenderedInputImg.size.height);
      }
      
      largerBuffer = [H264Decode pixelBufferFromImage:rerenderedInputImg
                                           renderSize:renderSize
                                                 dump:FALSE
                                                asYUV:TRUE];
    }
    
    if (dumpFramesImages)
    {
      CIImage *largerCiImage = [CIImage imageWithCVPixelBuffer:largerBuffer];
      
      UIGraphicsBeginImageContext(renderSize);
      CGRect rect;
      rect.origin = CGPointZero;
      rect.size   = renderSize;
      UIImage *remLargerImage = [UIImage imageWithCIImage:largerCiImage];
      [remLargerImage drawInRect:rect];
      UIImage *largerRenderedImg = UIGraphicsGetImageFromCurrentImageContext();
      UIGraphicsEndImageContext();
      
      NSString *dumpFilename = [NSString stringWithFormat:@"larger_frame%d.png", i];
      NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:dumpFilename];
      
      NSData *pngData = UIImagePNGRepresentation(largerRenderedImg);
      [pngData writeToFile:tmpPath atomically:TRUE];
      
      NSLog(@"wrote \"%@\" at size %d x %d", tmpPath, (int)largerRenderedImg.size.width, (int)largerRenderedImg.size.height);
    }
    
    int largerWidth = (int) CVPixelBufferGetWidth(largerBuffer);
    int largerHeight = (int) CVPixelBufferGetHeight(largerBuffer);
    
    // Render CoreVideo to a NxN square so that square pixels do not distort
    
    NSLog(@"encode output dimensions %4d x %4d", largerWidth, largerHeight);
    
    //NSLog(@"CVPixelBufferRef: %@", pixBuffer);

    frameEncoder.sampleBufferBlock = ^(CMSampleBufferRef sampleBuffer) {
      [encodedH264Buffers addObject:(__bridge id)sampleBuffer];
      
      int numBytes = (int) CMSampleBufferGetSampleSize(sampleBuffer, 0);
      
      NSLog(@"encoded buffer as %6d H264 bytes", numBytes);
      
      totalEncodeNumBytes += numBytes;
    };

    OSType bufferPixelType = CVPixelBufferGetPixelFormatType(largerBuffer);
    
    assert(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange == bufferPixelType);
    
    [frameEncoder encodeH264CoreMediaFrame:largerBuffer];

    [frameEncoder waitForFrame];
    
    CVPixelBufferRelease(largerBuffer);
  }
  
  [frameEncoder endSession];

  NSLog(@"total encoded num bytes %d", totalEncodeNumBytes);
  
  // FIXME: need to decode each frame and then save as a series of images so as to check
  // the quality of the encoded video.
  
  // Display first encoded frame
  
//  CMSampleBufferRef sampleBufferRef = (__bridge CMSampleBufferRef) encodedH264Buffers[0];
  
//  [self.sampleBufferLayer enqueueSampleBuffer:sampleBufferRef];
  
  NSTimer *timer = [NSTimer timerWithTimeInterval:1.0/30
                                           target:self
                                         selector:@selector(timerFired:)
                                         userInfo:NULL
                                          repeats:TRUE];
  
  self.displayH264Timer = timer;
  
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];

  self.encodedBufferOffset = 0;
  self.encodedBuffers = [NSArray arrayWithArray:encodedH264Buffers];
  
//  NSMutableArray *encodedH264Buffers = [NSMutableArray array];

  // Display all frames
  
//  for (int i = 0; i < numSampleBuffers; i++ ) {
//    CMSampleBufferRef sampleBufferRef = (__bridge CMSampleBufferRef) encodedH264Buffers[i];
//    
//    [self.sampleBufferLayer enqueueSampleBuffer:sampleBufferRef];
//  }
//
//  CMTimebaseRef controlTimebase;
//  CMTimebaseCreateWithMasterClock(CFAllocatorGetDefault(), CMClockGetHostTimeClock(), &controlTimebase );
//  
//  self.sampleBufferLayer.controlTimebase = controlTimebase;
//  CMTimebaseSetTime(self.sampleBufferLayer.controlTimebase, kCMTimeZero);
//  CMTimebaseSetRate(self.sampleBufferLayer.controlTimebase, 1.0);
  
//  [self.sampleBufferLayer setNeedsDisplay];
  
  return;
}
                    
- (void) timerFired:(id)timer {
  int offset = self.encodedBufferOffset;
  
#if defined(DEBUG)
  NSLog(@"timerFired %d", offset);
#endif // DEBUG
  
  assert(self.encodedBuffers);
  
  CMSampleBufferRef sampleBufferRef = (__bridge CMSampleBufferRef) self.encodedBuffers[offset];
  
  // Force display as soon as possible
  
  CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBufferRef, YES);
  CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
  CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
  
  [self.sampleBufferLayer enqueueSampleBuffer:sampleBufferRef];
  
  [self.sampleBufferLayer setNeedsDisplay];
  
  self.encodedBufferOffset = self.encodedBufferOffset + 1;
  
  if (self.encodedBufferOffset >= self.encodedBuffers.count) {
//    [timer invalidate];
    
    // Keep looping
    
    self.encodedBufferOffset = 0;
  }
  
  // Manually decode the frame data and emit the pixels as PNG
  
  if (dumpFramesImages) {
    NSString *dumpFilename = [NSString stringWithFormat:@"dump_decoded_%0d.png", offset];
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:dumpFilename];
    
    H264FrameDecoder *frameDecoder = [[H264FrameDecoder alloc] init];
    
    frameDecoder.pixelType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    
    frameDecoder.pixelBufferBlock = ^(CVPixelBufferRef pixBuffer){
      CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixBuffer];
      
      int width = (int) CVPixelBufferGetWidth(pixBuffer);
      int height = (int) CVPixelBufferGetHeight(pixBuffer);
      
      CGSize imgSize = CGSizeMake(width, height);
      
      UIGraphicsBeginImageContext(imgSize);
      CGRect rect;
      rect.origin = CGPointZero;
      rect.size   = imgSize;
      UIImage *remImage = [UIImage imageWithCIImage:ciImage];
      [remImage drawInRect:rect];
      UIImage *outputImg = UIGraphicsGetImageFromCurrentImageContext();
      UIGraphicsEndImageContext();
      
      NSData *pngData = UIImagePNGRepresentation(outputImg);
      [pngData writeToFile:tmpPath atomically:TRUE];
      
      NSLog(@"wrote \"%@\"", tmpPath);
    };
    
    [frameDecoder decodeH264CoreMediaFrame:sampleBufferRef];
    
    [frameDecoder waitForFrame];
    
    [frameDecoder endSession];
  }
  
  return;
}

@end
