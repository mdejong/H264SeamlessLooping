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
  
  NSArray *coreMediaSamplesArr = [H264Decode decodeCoreMediaFramesFromMOV:movieFilePath];
  
  NSLog(@"num samples %d", (int)coreMediaSamplesArr.count);
  
  // Setup AVSampleBufferDisplayLayer to display samples from memory
  
  self.sampleBufferLayer = [[AVSampleBufferDisplayLayer alloc] init];
  
  self.sampleBufferLayer.frame = self.view.layer.frame;
  
  self.sampleBufferLayer.backgroundColor = [UIColor redColor].CGColor;
  
  [self.view.layer addSublayer:self.sampleBufferLayer];
  
  CMTimebaseRef controlTimebase;
  CMTimebaseCreateWithMasterClock(CFAllocatorGetDefault(), CMClockGetHostTimeClock(), &controlTimebase );
  
  self.sampleBufferLayer.controlTimebase = controlTimebase;
  CMTimebaseSetTime(self.sampleBufferLayer.controlTimebase, CMTimeMake(5, 1));
  CMTimebaseSetRate(self.sampleBufferLayer.controlTimebase, 1.0);
  
  int numSampleBuffers = (int) coreMediaSamplesArr.count;
  
  for (int i = 0; i < numSampleBuffers; i++ ) {
    CMSampleBufferRef sampleBufferRef = (__bridge CMSampleBufferRef) coreMediaSamplesArr[i];
    
    CMVideoFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBufferRef);
    
    if (formatDesc) {
      [self.sampleBufferLayer enqueueSampleBuffer:sampleBufferRef];
    } else {
      NSLog(@"skip CMSampleBufferRef at offset %d", i);
    }
    
    // Print time now
    
    //CMTimeShow(CMTimebaseGetTime(self.sampleBufferLayer.controlTimebase));
  }
  
  [self.sampleBufferLayer setNeedsDisplay];
  
  return;
}

@end
