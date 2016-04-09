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

@interface DetailViewController ()

@property (nonatomic, copy) NSString *resourceName;

@property (nonatomic, retain) AVPlayerViewController* avPlayerViewController;

@property (nonatomic, retain) AVSampleBufferDisplayLayer *sampleBufferLayer;

@property (nonatomic, assign) BOOL isWaitingToPlay;

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

- (void) resizePlayerToViewSize
{
  CGRect frame = self.view.frame;
  
  NSLog(@" avPlayerViewController set to frame size %d, %d", (int)frame.size.width, (int)frame.size.height);
  
  self.avPlayerViewController.view.frame = frame;
  self.sampleBufferLayer.frame = frame;
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
  
  self.sampleBufferLayer.frame = self.view.layer.frame;
  
  self.sampleBufferLayer.position = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
  
  self.sampleBufferLayer.videoGravity = AVLayerVideoGravityResizeAspect;
  
  self.sampleBufferLayer.backgroundColor = [UIColor redColor].CGColor;
  
  [self.view.layer addSublayer:self.sampleBufferLayer];
  
  // Decode H.264 encoded data from file and then reencode the image data
  // as keyframes that can be access randomly.

  // FIXME: Using BGRA here, but should keep as YUV for max perf
  
  NSArray *coreVideoSamplesArr = [H264Decode decodeCoreVideoFramesFromMOV:movieFilePath asYUV:TRUE];
  
  H264FrameEncoder *frameEncoder = [[H264FrameEncoder alloc] init];
  
  // Begin to decode frames
  
  //H264FrameDecoder *frameDecoder = [[H264FrameDecoder alloc] init];
  
  NSMutableArray *encodedH264Buffers = [NSMutableArray array];
  
  int numSampleBuffers = (int) coreVideoSamplesArr.count;
  
  for (int i = 0; i < numSampleBuffers; i++ ) @autoreleasepool {
    CVPixelBufferRef pixBuffer = (__bridge CVPixelBufferRef) coreVideoSamplesArr[i];
    
    NSLog(@"CVPixelBufferRef: %@", pixBuffer);
    
    [frameEncoder encodeH264CoreMediaFrame:pixBuffer];
    
    while (frameEncoder.sampleBuffer == nil) {
        NSLog(@"sleep 0.10: at frame %d", i);
      [NSThread sleepForTimeInterval:0.01];
    }
    
    CMSampleBufferRef encodedH264Buffer = frameEncoder.sampleBuffer;
    
    [encodedH264Buffers addObject:(__bridge id)encodedH264Buffer];
    
    int width = (int) CVPixelBufferGetWidth(pixBuffer);
    int height = (int) CVPixelBufferGetHeight(pixBuffer);
    
    int numBytes = (int) CMSampleBufferGetSampleSize(encodedH264Buffer, 0);
    
    NSLog(@"encoded buffer at dims %4d x %4d as %d H264 bytes", width, height, numBytes);
  }
  
  [frameEncoder endSession];

  // Display first encoded frame
  
  CMSampleBufferRef sampleBufferRef = (__bridge CMSampleBufferRef) encodedH264Buffers[0];
  [self.sampleBufferLayer enqueueSampleBuffer:sampleBufferRef];

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
  
  [self.sampleBufferLayer setNeedsDisplay];
  
  return;
}

@end
