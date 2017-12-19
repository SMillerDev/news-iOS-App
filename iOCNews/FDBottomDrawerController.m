//
//  FDDrawerController.m
//  FeedDeck
//
//  Created by Peter Hedlund on 5/31/14.
//
//

#import <MMDrawerController/MMDrawerVisualState.h>
#import "FDBottomDrawerController.h"

@interface FDBottomDrawerController ()

@end

@implementation FDBottomDrawerController

//@synthesize feedListController;
//@synthesize articleListController;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [self setOpenDrawerGestureModeMask:MMOpenDrawerGestureModeAll];
    [self setCloseDrawerGestureModeMask:MMCloseDrawerGestureModePanningCenterView | MMCloseDrawerGestureModePanningNavigationBar | MMCloseDrawerGestureModeTapCenterView | MMCloseDrawerGestureModeTapNavigationBar];
    self.showsShadow = NO;
    [self setDrawerVisualStateBlock:^(MMDrawerController *drawerController, MMDrawerSide drawerSide, CGFloat percentVisible) {
        MMDrawerControllerDrawerVisualStateBlock block = [MMDrawerVisualState parallaxVisualStateBlockWithParallaxFactor:2.0];
        if (block){
            block(drawerController, drawerSide, percentVisible);
        }
    }];
    [self willRotateToInterfaceOrientation:[UIApplication sharedApplication].statusBarOrientation duration:0];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    
    if ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)) {
        self.maximumLeftDrawerWidth = 320.0f;
    } else {
        float width;
        if (UIInterfaceOrientationIsLandscape(toInterfaceOrientation)) {
            width = CGRectGetHeight([UIScreen mainScreen].bounds);
        } else {
            width = CGRectGetWidth([UIScreen mainScreen].bounds);
        }
        self.maximumLeftDrawerWidth = width;
    }
}

- (void)openDrawerSide:(MMDrawerSide)drawerSide animated:(BOOL)animated velocity:(CGFloat)velocity animationOptions:(UIViewAnimationOptions)options completion:(void (^)(BOOL))completion
{
    [super openDrawerSide:drawerSide animated:animated velocity:velocity animationOptions:options completion:completion];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DrawerOpened" object:self];
}

- (void)closeDrawerAnimated:(BOOL)animated velocity:(CGFloat)velocity animationOptions:(UIViewAnimationOptions)options completion:(void (^)(BOOL))completion
{
    [super closeDrawerAnimated:animated velocity:velocity animationOptions:options completion:completion];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DrawerClosed" object:self];
}

@end
