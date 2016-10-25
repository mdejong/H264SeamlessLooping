//
//  DetailViewController.m
//  H264SeamlessLooping
//
//  Created by Mo DeJong on 4/5/16.
//
//  See license.txt for BSD license terms.
//

#import "DetailViewController.h"

@import AVFoundation;
@import AVKit;

#import "H264Decode.h"
#import "BGDecodeEncode.h"

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
  self.title = @"Loading";
  
  // Setup AVSampleBufferDisplayLayer to display samples from memory
  
  self.sampleBufferLayer = [[AVSampleBufferDisplayLayer alloc] init];
  
  self.sampleBufferLayer.videoGravity = AVLayerVideoGravityResizeAspect;

  self.sampleBufferLayer.backgroundColor = [UIColor redColor].CGColor;
  
  [self.view.layer addSublayer:self.sampleBufferLayer];
  
  [self resizePlayerToViewSize];

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [self loadCoreMediaOnBackgroundThread];
  });

  return;
}

// Decompress CoreMedia sample data directly from a .mov container
// without decompressing the samples.

- (void) loadCoreMediaOnBackgroundThread
{
  NSString *resourceName = self.resourceName;
  NSString* movieFilePath = [[NSBundle mainBundle]
                             pathForResource:resourceName ofType:nil];
  NSAssert(movieFilePath, @"movieFilePath is nil");
  
  // Decode H.264 encoded data from file and then reencode the image data
  // as keyframes that can be access randomly.
  
  float frameDuration = 1.0f/30;
  int aveBitrate = 5000000;
  
  CGSize renderSize = CGSizeMake(1920, 1080);
  
  NSArray *encodedH264Buffers =
  [BGDecodeEncode recompressKeyframesOnBackgroundThread:movieFilePath
                                          frameDuration:frameDuration
                                             renderSize:renderSize
                                             aveBitrate:aveBitrate];

  self.encodedBuffers = [NSArray arrayWithArray:encodedH264Buffers];
  
  // Create timer on main thread
  
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self setupTimer];
  });
  
  return;
}

// Decompress CoreMedia sample data directly from a .mov container
// without decompressing the samples.

- (void) setupTimer
{
  // FIXME: need to decode each frame and then save as a series of images so as to check
  // the quality of the encoded video.
  
  if ((0)) {
    // Display just the first encoded frame
    
    CMSampleBufferRef sampleBufferRef = (__bridge CMSampleBufferRef) self.encodedBuffers[0];
    
    [self.sampleBufferLayer enqueueSampleBuffer:sampleBufferRef];
  }
  
  if ((1)) {
    // Dead simple NSTimer based impl
    
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0/30
                                             target:self
                                           selector:@selector(timerFired:)
                                           userInfo:NULL
                                            repeats:TRUE];
    
    self.displayH264Timer = timer;
    
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    
    self.encodedBufferOffset = 0;
    self.encodedBuffers = [NSArray arrayWithArray:self.encodedBuffers];
    
  }
  
  if ((0)) {
    // Send frames to sampleBufferLayer and use embedded display times to control when to display.
    // Note that this method is broken since it decodes all the H264 data so it is wasteful
    
    assert(self.sampleBufferLayer);
    
    int numSampleBuffers = (int) self.encodedBuffers.count;
    
    for (int i = 0; i < numSampleBuffers; i++ ) {
      CMSampleBufferRef sampleBufferRef = (__bridge CMSampleBufferRef) self.encodedBuffers[i];
      
      [self.sampleBufferLayer enqueueSampleBuffer:sampleBufferRef];
    }
    
    CMTimebaseRef controlTimebase;
    CMTimebaseCreateWithMasterClock(CFAllocatorGetDefault(), CMClockGetHostTimeClock(), &controlTimebase );
    
    self.sampleBufferLayer.controlTimebase = controlTimebase;
    CMTimebaseSetTime(self.sampleBufferLayer.controlTimebase, kCMTimeZero);
    CMTimebaseSetRate(self.sampleBufferLayer.controlTimebase, 1.0);
    
    [self.sampleBufferLayer setNeedsDisplay];
  }

  // Reset the bg color
  
  self.sampleBufferLayer.backgroundColor = [UIColor blackColor].CGColor;
  
  self.title = @"Looping";
  
  return;
}

// Really simplified impl of a repeating timer, just send the frame data to the sampleBufferLayer

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
