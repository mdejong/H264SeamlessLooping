//
//  DetailViewController.h
//  H264SeamlessLooping
//
//  Created by Mo DeJong on 4/8/16.
//  Copyright © 2016 HelpURock. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DetailViewController : UIViewController

@property (nonatomic, copy) NSString* tag;
@property (weak, nonatomic) IBOutlet UILabel *detailDescriptionLabel;

- (void)configureView;

@end

