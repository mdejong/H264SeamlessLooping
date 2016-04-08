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

@interface DetailViewController ()

@property (nonatomic, retain) AVPlayerViewController* avPlayerViewController;

@end

@implementation DetailViewController

@synthesize tag = m_tag;

#pragma mark - Managing the detail item

- (void) dealloc {
  NSLog(@"DetailViewController : dealloc %p with tag \"%@\"", self, self.tag);
}

- (void)configureView {
  // Update the user interface for the detail item.
  if (self.tag) {
      self.detailDescriptionLabel.text = [self.tag description];
  }
  
  if ([self.tag isEqualToString:@"AVPlayer"]) {
    [self loadAVPlayerLayer];
  }
}

- (void) loadAVPlayerLayer
{
  [super viewDidLoad];
  UIView *view = self.view;
  NSString *resourceName = @"CarOverWhiteBG.m4v";
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
}

- (void) resizePlayerToViewSize
{
  CGRect frame = self.view.frame;
  
  NSLog(@" avPlayerViewController set to frame size %d, %d", (int)frame.size.width, (int)frame.size.height);
  
  self.avPlayerViewController.view.frame = frame;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  // Do any additional setup after loading the view, typically from a nib.
  [self configureView];
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Dispose of any resources that can be recreated.
}

@end
