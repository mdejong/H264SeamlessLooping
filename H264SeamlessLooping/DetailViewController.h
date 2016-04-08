//
//  DetailViewController.h
//  H264SeamlessLooping
//
//  Created by Mo DeJong on 4/8/16.
//  Copyright © 2016 HelpURock. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DetailViewController : UIViewController

@property (strong, nonatomic) id detailItem;
@property (weak, nonatomic) IBOutlet UILabel *detailDescriptionLabel;

@end

