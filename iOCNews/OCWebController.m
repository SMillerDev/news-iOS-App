//
//  WebController.m
//  iOCNews
//

/************************************************************************
 
 Copyright 2012-2013 Peter Hedlund peter.hedlund@me.com
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 
 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 *************************************************************************/

#import "OCWebController.h"
#import "OCAPIClient.h"
#import "OCNewsHelper.h"
#import "OCSharingProvider.h"
#import <MMDrawerController/UIViewController+MMDrawerController.h>
#import <TUSafariActivity/TUSafariActivity.h>
#import <HTMLKit/HTMLKit.h>
#import "FDTopDrawerController.h"
#import "readable.h"

#define MIN_FONT_SIZE (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 11 : 9)
#define MAX_FONT_SIZE 30

#define MIN_LINE_HEIGHT 1.2f
#define MAX_LINE_HEIGHT 2.6f

#define MIN_WIDTH (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 380 : 150)
#define MAX_WIDTH (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 700 : 300)

const int SWIPE_NEXT = 0;
const int SWIPE_PREVIOUS = 1;

@interface OCWebController () <WKNavigationDelegate, WKUIDelegate> {
    BOOL _menuIsOpen;
    int _swipeDirection;
    BOOL loadingComplete;
    BOOL loadingSummary;
}

- (void)configureView;
- (void) writeAndLoadHtml:(NSString*)html;
- (NSString *)replaceYTIframe:(NSString *)html;
- (NSString *)extractYoutubeVideoID:(NSString *)urlYoutube;
- (UIColor*)myBackgroundColor;

@end

@implementation OCWebController

@synthesize menuBarButtonItem;
@synthesize backBarButtonItem, forwardBarButtonItem, refreshBarButtonItem, stopBarButtonItem, actionBarButtonItem, textBarButtonItem, starBarButtonItem, unstarBarButtonItem;
@synthesize nextArticleRecognizer;
@synthesize previousArticleRecognizer;
@synthesize item = _item;
@synthesize menuController;
@synthesize keepUnread;
@synthesize star;
@synthesize backgroundMenuRow;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - Managing the detail item

- (void)setItem:(Item*)newItem
{
    Item *myItem = (Item*)[[OCNewsHelper sharedHelper].context objectWithID:[newItem objectID]];
    if (myItem) {
        if (_item != myItem) {
            _item = myItem;
            // Update the view.
            [self configureView];
        }
    }
}

- (void)configureView
{
    @try {
        if (self.item) {
            if (self.mm_drawerController.openSide != MMDrawerSideNone) {
                if (self.webView != nil) {
                    [self.menuController.view removeFromSuperview];
                    [self.webView removeFromSuperview];
                    self.webView.navigationDelegate =nil;
                    self.webView.UIDelegate = nil;
                    self.webView = nil;
                }
                
                CGFloat topBarOffset = self.topLayoutGuide.length;
                CGRect frame = self.view.frame;
                self.webView = [[WKWebView alloc] initWithFrame:CGRectMake(frame.origin.x, topBarOffset, frame.size.width, frame.size.height - topBarOffset)];
                self.automaticallyAdjustsScrollViewInsets = NO;
                self.webView.scrollView.backgroundColor = [self myBackgroundColor];
                self.webView.navigationDelegate = self;
                self.webView.UIDelegate = self;
                self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [self.view insertSubview:self.webView atIndex:0];
                [self.webView addSubview:self.menuController.view];
                
            } else {
                __block UIView *imageView = [[UIScreen mainScreen] snapshotViewAfterScreenUpdates:YES];
                [self.view insertSubview:imageView atIndex:0];
                [self.view setNeedsDisplay];
                
                float width = self.view.frame.size.width;
                float height = self.view.frame.size.height;
                
                if (self.webView != nil) {
                    [self.menuController.view removeFromSuperview];
                    [self.webView removeFromSuperview];
                    self.webView.navigationDelegate = nil;
                    self.webView.UIDelegate = nil;
                    self.webView = nil;
                }
                __block CGFloat topBarOffset = self.topLayoutGuide.length;
                
                self.automaticallyAdjustsScrollViewInsets = NO;
                
                if (_swipeDirection == SWIPE_NEXT) {
                    self.webView = [[WKWebView alloc] initWithFrame:CGRectMake(width, topBarOffset, width, height - topBarOffset)];
                } else {
                    self.webView = [[WKWebView alloc] initWithFrame:CGRectMake(-width, topBarOffset, width, height - topBarOffset)];
                }
                self.webView.scrollView.backgroundColor = [self myBackgroundColor];
                self.webView.navigationDelegate = self;
                self.webView.UIDelegate = self;
                self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [self.webView addSubview:self.menuController.view];
                [self.view insertSubview:self.webView belowSubview:imageView];
                
                [UIView animateWithDuration:0.3f
                                      delay:0.0f
                                    options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction
                                 animations:^{
                                     [self.webView setFrame:CGRectMake(0.0, topBarOffset, width, height - topBarOffset)];
                                     if (_swipeDirection == SWIPE_NEXT) {
                                         [imageView setFrame:CGRectMake(-width, 0.0, width, height)];
                                     } else {
                                         [imageView setFrame:CGRectMake(width, 0.0, width, height)];
                                     }
                                 }
                                 completion:^(BOOL finished){
                                     // do whatever post processing you want (such as resetting what is "current" and what is "next")
                                     [imageView removeFromSuperview];
                                     [self.view.layer displayIfNeeded];
                                     imageView = nil;
                                 }];
            }
            
            [self.webView addGestureRecognizer:self.nextArticleRecognizer];
            [self.webView addGestureRecognizer:self.previousArticleRecognizer];
            [self updateNavigationItemTitle];
            
            Feed *feed = [[OCNewsHelper sharedHelper] feedWithId:self.item.feedId];
            
            if (feed.preferWebValue) {
                if (feed.useReaderValue) {
                    if (self.item.readable) {
                        [self writeAndLoadHtml:self.item.readable];
                    } else {
                        [OCAPIClient sharedClient].requestSerializer = [OCAPIClient httpRequestSerializer];
                        [[OCAPIClient sharedClient] GET:self.item.url parameters:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
                            NSString *html;
                            if (responseObject) {
                                html = [[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
                                char *article;
                                article = readable([html cStringUsingEncoding:NSUTF8StringEncoding],
                                                   [[[task.response URL] absoluteString] cStringUsingEncoding:NSUTF8StringEncoding],
                                                   "UTF-8",
                                                   READABLE_OPTIONS_DEFAULT);
                                if (article == NULL) {
                                    html = @"<p style='color: #CC6600;'><i>(An article could not be extracted. Showing summary instead.)</i></p>";
                                    html = [html stringByAppendingString:self.item.body];
                                } else {
                                    html = [NSString stringWithCString:article encoding:NSUTF8StringEncoding];
                                    html = [self fixRelativeUrl:html
                                                  baseUrlString:[NSString stringWithFormat:@"%@://%@/%@", [[task.response URL] scheme], [[task.response URL] host], [[task.response URL] path]]];
                                }
                                self.item.readable = html;
                                [[OCNewsHelper sharedHelper] saveContext];
                            } else {
                                html = @"<p style='color: #CC6600;'><i>(An article could not be extracted. Showing summary instead.)</i></p>";
                                html = [html stringByAppendingString:self.item.body];
                            }
                            [self writeAndLoadHtml:html];
                            
                        } failure:^(NSURLSessionDataTask *task, NSError *error) {
                            NSString *html = @"<p style='color: #CC6600;'><i>(There was an error downloading the article. Showing summary instead.)</i></p>";
                            if (self.item.body != nil) {
                                html = [html stringByAppendingString:self.item.body];
                            }
                            [self writeAndLoadHtml:html];
                        }];
                    }
                } else {
                    loadingSummary = NO;
                    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:self.item.url]]];
                }
            } else {
                NSString *html = self.item.body;
                NSURL *itemURL = [NSURL URLWithString:self.item.url];
                NSString *baseString = [NSString stringWithFormat:@"%@://%@", [itemURL scheme], [itemURL host]];
                html = [self fixRelativeUrl:html baseUrlString:baseString];
                [self writeAndLoadHtml:html];
            }
            if (self.mm_drawerController.openSide != MMDrawerSideNone) {
                [self.mm_drawerController closeDrawerAnimated:YES completion:nil];
            }
            [self updateToolbar];
        }
        
    }
    @catch (NSException *exception) {
        //
    }
    @finally {
        //
    }
}

- (void)writeAndLoadHtml:(NSString *)html {
    html = [self replaceYTIframe:html];
    NSURL *source = [[NSBundle mainBundle] URLForResource:@"rss" withExtension:@"html" subdirectory:nil];
    NSString *objectHtml = [NSString stringWithContentsOfURL:source encoding:NSUTF8StringEncoding error:nil];
    
    NSString *dateText = @"";
    NSNumber *dateNumber = self.item.pubDate;
    if (![dateNumber isKindOfClass:[NSNull class]]) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[dateNumber doubleValue]];
        if (date) {
            NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
            dateFormat.dateStyle = NSDateFormatterMediumStyle;
            dateFormat.timeStyle = NSDateFormatterShortStyle;
            dateText = [dateText stringByAppendingString:[dateFormat stringFromDate:date]];
        }
    }
    
    Feed *feed = [[OCNewsHelper sharedHelper] feedWithId:self.item.feedId];
    if (feed && feed.title) {
        objectHtml = [objectHtml stringByReplacingOccurrencesOfString:@"$FeedTitle$" withString:feed.title];
    }
    if (dateText) {
        objectHtml = [objectHtml stringByReplacingOccurrencesOfString:@"$ArticleDate$" withString:dateText];
    }
    if (self.item.title) {
        objectHtml = [objectHtml stringByReplacingOccurrencesOfString:@"$ArticleTitle$" withString:self.item.title];
    }
    if (self.item.url) {
        objectHtml = [objectHtml stringByReplacingOccurrencesOfString:@"$ArticleLink$" withString:self.item.url];
    }
    NSString *author = self.item.author;
    if (![author isKindOfClass:[NSNull class]]) {
        if (author.length > 0) {
            author = [NSString stringWithFormat:@"By %@", author];
        }
    } else {
        author = @"";
    }
    if (author) {
        objectHtml = [objectHtml stringByReplacingOccurrencesOfString:@"$ArticleAuthor$" withString:author];
    }
    if (html) {
        objectHtml = [objectHtml stringByReplacingOccurrencesOfString:@"$ArticleSummary$" withString:html];
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *paths = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *docDir = [paths objectAtIndex:0];
    NSURL *objectSaveURL = [docDir  URLByAppendingPathComponent:@"summary.html"];
    [objectHtml writeToURL:objectSaveURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
    loadingComplete = NO;
    loadingSummary = YES;
    [self.webView loadFileURL:objectSaveURL allowingReadAccessToURL:docDir];
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    CALayer *border = [CALayer layer];
    border.backgroundColor = [UIColor lightGrayColor].CGColor;
    border.frame = CGRectMake(0, 0, 1, 1024);
    [self.mm_drawerController.centerViewController.view.layer addSublayer:border];
    FDTopDrawerController *myDrawerController = (FDTopDrawerController*)self.mm_drawerController;
    myDrawerController.webController = self;
    
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceOrientationDidChange:) name:UIDeviceOrientationDidChangeNotification object:nil];
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"defaults" withExtension:@"plist"]]];
    [[NSUserDefaults standardUserDefaults] synchronize];
    _menuIsOpen = NO;
    [self writeCss];
    [self updateToolbar];
    [self.mm_drawerController openDrawerSide:MMDrawerSideLeft animated:YES completion:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
}

- (void)dealloc
{
    [self.webView stopLoading];
 	[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
    self.webView.navigationDelegate = nil;
    self.webView.UIDelegate = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
	return YES;
}

- (IBAction)onMenu:(id)sender {
    [self.mm_drawerController toggleDrawerSide:MMDrawerSideLeft animated:YES completion:nil];
}

- (IBAction)doGoBack:(id)sender
{
    if ([[self webView] canGoBack]) {
        [[self webView] goBack];
    }
}

- (IBAction)doGoForward:(id)sender
{
    if ([[self webView] canGoForward]) {
        [[self webView] goForward];
    }
}


- (IBAction)doReload:(id)sender {
    [self.webView reload];
}

- (IBAction)doStop:(id)sender {
    [self.webView stopLoading];
	[self updateToolbar];
}

- (IBAction)doInfo:(id)sender {
    @try {
        NSURL *url = self.webView.URL;
        NSString *subject = self.webView.title;
        if ([[url absoluteString] hasSuffix:@"Documents/summary.html"]) {
            url = [NSURL URLWithString:self.item.url];
            subject = self.item.title;
        }
        if (!url) {
            return;
        }
        
        TUSafariActivity *sa = [[TUSafariActivity alloc] init];
        NSArray *activities = @[sa];
        
        OCSharingProvider *sharingProvider = [[OCSharingProvider alloc] initWithPlaceholderItem:url subject:subject];
        
        UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[sharingProvider] applicationActivities:activities];
        activityViewController.modalPresentationStyle = UIModalPresentationPopover;
        [self presentViewController:activityViewController animated:YES completion:nil];
        // Get the popover presentation controller and configure it.
        UIPopoverPresentationController *presentationController = [activityViewController popoverPresentationController];
        presentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
        presentationController.barButtonItem = self.actionBarButtonItem;
    }
    @catch (NSException *exception) {
        //
    }
    @finally {
        //
    }
}

- (IBAction)doText:(id)sender event:(UIEvent*)event {
    if (_menuIsOpen) {
        [self.menuController close];
        [self.backgroundMenuRow setColumns:nil];
        [self.backgroundMenuRow setIsModal:NO];
        [self.backgroundMenuRow setHideOnExpand:NO];
//        self.backgroundMenuRow.isMoreButton = YES;
        [self.backgroundMenuRow.button setImage:[UIImage imageNamed:@"down"] forState:UIControlStateNormal];
        [[self.menuController.rows objectAtIndex:2 + 1] button].hidden = YES;
        [[self.menuController.rows objectAtIndex:2 + 2] button].hidden = YES;
        [[self.menuController.rows objectAtIndex:2 + 3] button].hidden = YES;
    } else {
        @try {
            self.keepUnread.button.selected = self.item.unreadValue;
            self.star.button.selected = self.item.starredValue;
        }
        @catch (NSException *exception) {
            //
        }
        @finally {
            [self.menuController open];
        }
    }
    _menuIsOpen = !_menuIsOpen;
}

- (IBAction)doStar:(id)sender {
    if ([sender isEqual:self.starBarButtonItem]) {
        self.item.starredValue = YES;
        [[OCNewsHelper sharedHelper] starItemOffline:self.item.myId];
    }
    if ([sender isEqual:self.unstarBarButtonItem]) {
        self.item.starredValue = NO;
        [[OCNewsHelper sharedHelper] unstarItemOffline:self.item.myId];
    }
    [self updateToolbar];
}

#pragma mark - WKWbView delegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    if ([self.webView.URL.scheme isEqualToString:@"file"]) {
        if ([navigationAction.request.URL.absoluteString rangeOfString:@"itunes.apple.com"].location != NSNotFound) {
            [[UIApplication sharedApplication] openURL:navigationAction.request.URL];
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }
    }
    if (![[navigationAction.request.URL absoluteString] hasSuffix:@"Documents/summary.html"]) {
        [self.menuController close];
    }
    
    if (navigationAction.navigationType != WKNavigationTypeOther) {
        loadingSummary = [navigationAction.request.URL.scheme isEqualToString:@"file"] || [navigationAction.request.URL.scheme isEqualToString:@"about"];
    }
    decisionHandler(WKNavigationActionPolicyAllow);
    loadingComplete = NO;
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation
{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    [self updateToolbar];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    [self updateToolbar];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    [self updateToolbar];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    [webView evaluateJavaScript:@"document.readyState" completionHandler:^(NSString * _Nullable response, NSError * _Nullable error) {
        if (response != nil) {
            if ([response isEqualToString:@"complete"]) {
                [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                loadingComplete = YES;
                [self updateNavigationItemTitle];
            }
        }
        [self updateToolbar];
    }];
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures
{
    if (!navigationAction.targetFrame.isMainFrame) {
        [webView loadRequest:navigationAction.request];
    }
    
    return nil;
}

- (BOOL)isShowingASummary {
    BOOL result = NO;
    if (self.webView) {
        result = [self.webView.URL.scheme isEqualToString:@"file"] || [self.webView.URL.scheme isEqualToString:@"about"];
    }
    return result;
}

#pragma mark - JCGridMenuController Delegate

- (void)jcGridMenuRowSelected:(NSInteger)indexTag indexRow:(NSInteger)indexRow isExpand:(BOOL)isExpand
{
//    if (isExpand) {
//        NSLog(@"jcGridMenuRowSelected %li %li isExpand", (long)indexTag, (long)indexRow);
//    } else {
//        NSLog(@"jcGridMenuRowSelected %li %li !isExpand", (long)indexTag, (long)indexRow);
//    }
    
    if (indexTag==1002) {
        JCGridMenuRow *rowSelected = (JCGridMenuRow *)[self.menuController.rows objectAtIndex:indexRow];
        
        if ([rowSelected.columns count]==0) {
            // If there are no more columns, we can use this button as an on/off switch
            
            switch (indexRow) {
                case 0: // Keep unread
                    @try {
                        if (!self.item.unreadValue) {
                            self.item.unreadValue = YES;
                            [[OCNewsHelper sharedHelper] markItemUnreadOffline:self.item.myId];
                            [[rowSelected button] setSelected:YES];
                        } else {
                            self.item.unreadValue = NO;
                            [[OCNewsHelper sharedHelper] markItemsReadOffline:[NSMutableSet setWithObject:self.item.myId]];
                            [[rowSelected button] setSelected:NO];
                        }
                    }
                    @catch (NSException *exception) {
                        //
                    }
                    @finally {
                        break;
                    }
                case 1: // Star
                    @try {
                        if (!self.item.starredValue) {
                            self.item.starredValue = YES;
                            [[OCNewsHelper sharedHelper] starItemOffline:self.item.myId];
                            [[rowSelected button] setSelected:YES];
                        } else {
                            self.item.starredValue = NO;
                            [[OCNewsHelper sharedHelper] unstarItemOffline:self.item.myId];
                            [[rowSelected button] setSelected:NO];
                        }
                    }
                    @catch (NSException *exception) {
                        //
                    }
                    @finally {
                        break;
                    }
                case 2: // Expand
                    [[rowSelected button] setSelected:NO];
                    break;
            }

        } else {
            //This changes the icon to Close
            [[[[self.menuController rows] objectAtIndex:indexRow] button] setSelected:isExpand];
        }
    }
    
}

- (void)jcDidSelectGridMenuRow:(NSInteger)tag indexRow:(NSInteger)indexRow isExpand:(BOOL)isExpand {
    if (tag==1002) {
        JCGridMenuRow *rowSelected = (JCGridMenuRow *)[self.menuController.rows objectAtIndex:indexRow];
        
        if ([rowSelected.columns count]==0) {
            // If there are no more columns, we can use this button as an on/off switch
            //[[rowSelected button] setSelected:![rowSelected button].selected];
            switch (indexRow) {
                case 0: // Keep unread
                    //[[rowSelected button] setSelected:YES];
                    break;
                case 1: // Star
                    //[[rowSelected button] setSelected:YES];
                    break;
                case 2: // Expand
                    [[self.menuController.rows objectAtIndex:indexRow + 1] button].hidden = NO;
                    [[self.menuController.rows objectAtIndex:indexRow + 2] button].hidden = NO;
                    [[self.menuController.rows objectAtIndex:indexRow + 3] button].hidden = NO;
                    
                    // Background
                    JCGridMenuColumn *backgroundWhite = [[JCGridMenuColumn alloc]
                                                         initWithButtonAndImages:CGRectMake(0, 0, 44, 44)
                                                         normal:@"background1"
                                                         selected:@"background1"
                                                         highlighted:@"background1"
                                                         disabled:@"background1"];
                    [backgroundWhite.button setBackgroundColor:[UIColor colorWithWhite:0.90f alpha:0.95f]];
                    backgroundWhite.closeOnSelect = NO;
                    
                    JCGridMenuColumn *backgroundSepia = [[JCGridMenuColumn alloc]
                                                         initWithButtonAndImages:CGRectMake(0, 0, 44, 44)
                                                         normal:@"background2"
                                                         selected:@"background2"
                                                         highlighted:@"background2"
                                                         disabled:@"background2"];
                    [backgroundSepia.button setBackgroundColor:[UIColor colorWithWhite:0.90f alpha:0.95f]];
                    backgroundSepia.closeOnSelect = NO;
                    
                    [self.backgroundMenuRow setColumns:[NSMutableArray arrayWithArray:@[backgroundWhite, backgroundSepia]]];
//                    [self.backgroundMenuRow setIsMoreButton:NO];
                    [self.backgroundMenuRow setIsModal:YES];
                    [self.backgroundMenuRow.button setImage:[UIImage imageNamed:@"background1"] forState:UIControlStateNormal];
                    break;
            }
            
        }
    }
}

- (void)jcGridMenuColumnSelected:(NSInteger)indexTag indexRow:(NSInteger)indexRow indexColumn:(NSInteger)indexColumn
{
    if (indexTag==1002) {
        [self.menuController setIsRowModal:YES];
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        long currentValue;
        double currentLineSpacing;
        switch (indexRow) {
            case 0: // Keep
                //Will not happen
                break;
            case 1: // Star
                //Will not happen
                break;
            case 2: //Background
                switch (indexColumn) {
                    case 0: // White
                        [prefs setInteger:0 forKey:@"Background"];
                        break;
                    case 1: // Sepia
                        [prefs setInteger:1 forKey:@"Background"];
                        break;
                }
                break;
            case 3: //Font size
                switch (indexColumn) {
                    case 0: // Smaller
                        currentValue = [[prefs valueForKey:@"FontSize"] integerValue];
                        if (currentValue > MIN_FONT_SIZE) {
                            --currentValue;
                        }
                        [prefs setInteger:currentValue forKey:@"FontSize"];
                        break;
                    case 1: // Larger
                        currentValue = [[prefs valueForKey:@"FontSize"] integerValue];
                        if (currentValue < MAX_FONT_SIZE) {
                            ++currentValue;
                        }
                        [prefs setInteger:currentValue forKey:@"FontSize"];
                        break;
                }
                break;
            case 4: //Line spacing
                switch (indexColumn) {
                    case 0: // Smaller
                        currentLineSpacing = [[prefs valueForKey:@"LineHeight"] doubleValue];
                        if (currentLineSpacing > MIN_LINE_HEIGHT) {
                            currentLineSpacing = currentLineSpacing - 0.2f;
                        }
                        [prefs setDouble:currentLineSpacing forKey:@"LineHeight"];
                        break;
                    case 1: // Larger
                        currentLineSpacing = [[prefs valueForKey:@"LineHeight"] doubleValue];
                        if (currentLineSpacing < MAX_LINE_HEIGHT) {
                            currentLineSpacing = currentLineSpacing + 0.2f;
                        }
                        [prefs setDouble:currentLineSpacing forKey:@"LineHeight"];
                        break;
                }
                break;
            case 5: //Margin
                switch (indexColumn) {
                    case 0: // Narrower
                        currentValue = [[prefs valueForKey:@"Margin"] integerValue];
                        if (currentValue < MAX_WIDTH) {
                            currentValue = currentValue + 20;
                        }
                        [prefs setInteger:currentValue forKey:@"Margin"];
                        break;
                    case 1: // Wider
                        currentValue = [[prefs valueForKey:@"Margin"] integerValue];
                        
                        if (currentValue > MIN_WIDTH) {
                            currentValue = currentValue - 20;
                        }
                        [prefs setInteger:currentValue forKey:@"Margin"];
                        break;
                }
                break;
        }
        [self settingsChanged:Nil newValue:0];
    }
}


#pragma mark - Toolbar buttons

- (UIBarButtonItem *)menuBarButtonItem {
    if (!menuBarButtonItem) {
        menuBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"sideMenu"] style:UIBarButtonItemStylePlain target:self action:@selector(onMenu:)];
        menuBarButtonItem.imageInsets = UIEdgeInsetsMake(2.0f, 0.0f, -2.0f, 0.0f);
    }
    return menuBarButtonItem;
}

- (UIBarButtonItem *)backBarButtonItem {
    
    if (!backBarButtonItem) {
        backBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"back"] style:UIBarButtonItemStylePlain target:self action:@selector(doGoBack:)];
        backBarButtonItem.imageInsets = UIEdgeInsetsMake(2.0f, 0.0f, -2.0f, 0.0f);
    }
    return backBarButtonItem;
}

- (UIBarButtonItem *)forwardBarButtonItem {
    
    if (!forwardBarButtonItem) {
        forwardBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"forward"] style:UIBarButtonItemStylePlain target:self action:@selector(doGoForward:)];
        forwardBarButtonItem.imageInsets = UIEdgeInsetsMake(2.0f, 0.0f, -2.0f, 0.0f);
    }
    return forwardBarButtonItem;
}

- (UIBarButtonItem *)refreshBarButtonItem {
    
    if (!refreshBarButtonItem) {
        refreshBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(doReload:)];
    }
    
    return refreshBarButtonItem;
}

- (UIBarButtonItem *)stopBarButtonItem {
    
    if (!stopBarButtonItem) {
        stopBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop target:self action:@selector(doStop:)];
    }
    return stopBarButtonItem;
}

- (UIBarButtonItem *)actionBarButtonItem {
    if (!actionBarButtonItem) {
        actionBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(doInfo:)];
    }
    return actionBarButtonItem;
}

- (UIBarButtonItem *)textBarButtonItem {
    
    if (!textBarButtonItem) {
        textBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"menu"] style:UIBarButtonItemStylePlain target:self action:@selector(doText:event:)];
        textBarButtonItem.imageInsets = UIEdgeInsetsMake(2.0f, 0.0f, -2.0f, 0.0f);
    }
    return textBarButtonItem;
}

- (UIBarButtonItem *)starBarButtonItem {
    if (!starBarButtonItem) {
        starBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"star_open"] style:UIBarButtonItemStylePlain target:self action:@selector(doStar:)];
        starBarButtonItem.imageInsets = UIEdgeInsetsMake(2.0f, 0.0f, -2.0f, 0.0f);
    }
    return starBarButtonItem;
}

- (UIBarButtonItem *)unstarBarButtonItem {
    if (!unstarBarButtonItem) {
        unstarBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"star_filled"] style:UIBarButtonItemStylePlain target:self action:@selector(doStar:)];
        unstarBarButtonItem.imageInsets = UIEdgeInsetsMake(2.0f, 0.0f, -2.0f, 0.0f);
    }
    return unstarBarButtonItem;
}

- (JCGridMenuRow *)keepUnread {
    if (!keepUnread) {
        // Keep Unread
        keepUnread = [[JCGridMenuRow alloc] initWithImages:@"keep_blue" selected:@"keep_green" highlighted:@"keep_green" disabled:@"keep_blue"];
        [keepUnread setHideAlpha:1.0f];
        [keepUnread setIsModal:NO];
        [keepUnread.button setBackgroundColor:[UIColor colorWithWhite:0.97f alpha:0.95f]];
    }
    return keepUnread;
}

- (JCGridMenuRow *)star {
    if (!star) {
        // Star
        star = [[JCGridMenuRow alloc] initWithImages:@"star_blue_open" selected:@"star_blue_filled" highlighted:@"star_blue_filled" disabled:@"star_blue_open"];
        [star setIsSeperated:NO];
        [star setIsSelected:NO];
        [star setHideAlpha:1.0f];
        [star setIsModal:NO];
        [star.button setBackgroundColor:[UIColor colorWithWhite:0.97f alpha:0.95f]];
    }
    return star;
}

- (JCGridMenuRow *)backgroundMenuRow {
    if (!backgroundMenuRow) {
        backgroundMenuRow = [[JCGridMenuRow alloc] initWithImages:@"down" selected:@"close_blue" highlighted:@"background1" disabled:@"background1"];
        [backgroundMenuRow setColumns:nil];
        [backgroundMenuRow setIsModal:NO];
        [backgroundMenuRow setHideOnExpand:NO];
        [backgroundMenuRow.button setBackgroundColor:[UIColor colorWithWhite:0.97f alpha:0.95f]];
//        backgroundMenuRow.isMoreButton = YES;
    }
    return backgroundMenuRow;
}

- (JCGridMenuController *)menuController {
    if (!menuController) {
        // Background
        // Handled above
        
        // Font
        JCGridMenuColumn *fontSmaller = [[JCGridMenuColumn alloc]
                                         initWithButtonAndImages:CGRectMake(0, 0, 44, 44)
                                         normal:@"fontsizes"
                                         selected:@"fontsizes"
                                         highlighted:@"fontsizes"
                                         disabled:@"fontsizes"];
        [fontSmaller.button setBackgroundColor:[UIColor colorWithWhite:0.90f alpha:0.95f]];
        fontSmaller.closeOnSelect = NO;
        
        JCGridMenuColumn *fontLarger = [[JCGridMenuColumn alloc]
                                        initWithButtonAndImages:CGRectMake(0, 0, 44, 44)
                                        normal:@"fontsizel"
                                        selected:@"fontsizel"
                                        highlighted:@"fontsizel"
                                        disabled:@"fontsizel"];
        [fontLarger.button setBackgroundColor:[UIColor colorWithWhite:0.90f alpha:0.95f]];
        fontLarger.closeOnSelect = NO;
        
        JCGridMenuRow *font = [[JCGridMenuRow alloc] initWithImages:@"fontsizem" selected:@"close_blue" highlighted:@"fontsizem" disabled:@"fontsizem"];
        [font setColumns:[NSMutableArray arrayWithArray:@[fontSmaller, fontLarger]]];
        [font setIsModal:YES];
        [font setHideOnExpand:NO];
        [font.button setBackgroundColor:[UIColor colorWithWhite:0.97f alpha:0.95f]];
        font.button.hidden = YES;
        // Line Spacing
        JCGridMenuColumn *spacingSmaller = [[JCGridMenuColumn alloc]
                                            initWithButtonAndImages:CGRectMake(0, 0, 44, 44)
                                            normal:@"lineheight1"
                                            selected:@"lineheight1"
                                            highlighted:@"lineheight1"
                                            disabled:@"lineheight1"];
        [spacingSmaller.button setBackgroundColor:[UIColor colorWithWhite:0.90f alpha:0.95f]];
        spacingSmaller.closeOnSelect = NO;
        
        JCGridMenuColumn *spacingLarger = [[JCGridMenuColumn alloc]
                                           initWithButtonAndImages:CGRectMake(0, 0, 44, 44)
                                           normal:@"lineheight3"
                                           selected:@"lineheight3"
                                           highlighted:@"lineheight3"
                                           disabled:@"lineheight3"];
        [spacingLarger.button setBackgroundColor:[UIColor colorWithWhite:0.90f alpha:0.95f]];
        spacingLarger.closeOnSelect = NO;
        
        JCGridMenuRow *spacing = [[JCGridMenuRow alloc] initWithImages:@"lineheight2" selected:@"close_blue" highlighted:@"lineheight2" disabled:@"lineheight2"];
        [spacing setColumns:[NSMutableArray arrayWithArray:@[spacingSmaller, spacingLarger]]];
        [spacing setIsModal:YES];
        [spacing setHideOnExpand:NO];
        [spacing.button setBackgroundColor:[UIColor colorWithWhite:0.97f alpha:0.95f]];
        spacing.button.hidden = YES;
        // Margin
        JCGridMenuColumn *marginSmaller = [[JCGridMenuColumn alloc]
                                           initWithButtonAndImages:CGRectMake(0, 0, 44, 44)
                                           normal:@"margin1"
                                           selected:@"margin1"
                                           highlighted:@"margin1"
                                           disabled:@"margin1"];
        [marginSmaller.button setBackgroundColor:[UIColor colorWithWhite:0.90f alpha:0.95f]];
        marginSmaller.closeOnSelect = NO;
        
        JCGridMenuColumn *marginLarger = [[JCGridMenuColumn alloc]
                                          initWithButtonAndImages:CGRectMake(0, 0, 44, 44)
                                          normal:@"margin3"
                                          selected:@"margin3"
                                          highlighted:@"margin3"
                                          disabled:@"margin3"];
        [marginLarger.button setBackgroundColor:[UIColor colorWithWhite:0.90f alpha:0.95f]];
        marginLarger.closeOnSelect = NO;
        
        JCGridMenuRow *margin = [[JCGridMenuRow alloc] initWithImages:@"margin2" selected:@"close_blue" highlighted:@"margin2" disabled:@"margin2"];
        [margin setColumns:[NSMutableArray arrayWithArray:@[marginSmaller, marginLarger]]];
        [margin setIsModal:YES];
        [margin setHideOnExpand:NO];
        [margin.button setBackgroundColor:[UIColor colorWithWhite:0.97f alpha:0.95f]];
        margin.button.hidden = YES;
        // Rows
        NSArray *rows = @[self.keepUnread, self.star, self.backgroundMenuRow, font, spacing, margin];
        menuController = [[JCGridMenuController alloc] initWithFrame:CGRectMake(0, 5, self.view.frame.size.width - 5, self.view.frame.size.height - 5) rows:rows tag:1002];
        [menuController setDelegate:self];
    }
    return menuController;
}

#pragma mark - Toolbar

- (void)updateToolbar {
    self.backBarButtonItem.enabled = self.webView.canGoBack;
    self.forwardBarButtonItem.enabled = self.webView.canGoForward;
    UIBarButtonItem *refreshStopBarButtonItem = loadingComplete ? self.refreshBarButtonItem : self.stopBarButtonItem;
    if ((self.item != nil)) {
        self.actionBarButtonItem.enabled = loadingComplete;
        self.textBarButtonItem.enabled = loadingComplete;
        self.starBarButtonItem.enabled = loadingComplete;
        self.unstarBarButtonItem.enabled = loadingComplete;
        refreshStopBarButtonItem.enabled = YES;
        self.keepUnread.button.selected = self.item.unreadValue;
        self.star.button.selected = self.item.starredValue;
    } else {
        self.actionBarButtonItem.enabled = NO;
        self.textBarButtonItem.enabled = NO;
        self.starBarButtonItem.enabled = NO;
        self.unstarBarButtonItem.enabled = NO;
        refreshStopBarButtonItem.enabled = NO;
    }
    self.navigationItem.leftBarButtonItems = @[self.menuBarButtonItem, self.backBarButtonItem, self.forwardBarButtonItem, refreshStopBarButtonItem];
    self.navigationItem.rightBarButtonItems = @[self.textBarButtonItem, self.actionBarButtonItem];
}

- (NSString *) fixRelativeUrl:(NSString *)htmlString baseUrlString:(NSString*)base {
    __block NSString *result = [htmlString copy];
    HTMLParser *parser = [[HTMLParser alloc] initWithString:htmlString];

    //parse body
    HTMLNode *bodyNode = [parser document].body;

    NSArray *inputNodes = [bodyNode elementsMatchingSelector:[CSSSelector selectorWithString:@"img"]];
    [inputNodes enumerateObjectsUsingBlock:^(HTMLElement *inputNode, NSUInteger idx, BOOL *stop) {
        if (inputNode) {
            NSString *src = inputNode.attributes[@"src"];
            if (src != nil) {
                NSURL *url = [NSURL URLWithString:src relativeToURL:[NSURL URLWithString:base]];
                if (url != nil) {
                    NSString *newSrc = [url absoluteString];
                    result = [result stringByReplacingOccurrencesOfString:src withString:newSrc];
                }
            }
        }
    }];
    
    inputNodes = [bodyNode elementsMatchingSelector:[CSSSelector selectorWithString:@"a"]];
    [inputNodes enumerateObjectsUsingBlock:^(HTMLElement *inputNode, NSUInteger idx, BOOL *stop) {
        if (inputNode) {
            NSString *src = inputNode.attributes[@"href"];
            if (src != nil) {
                NSURL *url = [NSURL URLWithString:src relativeToURL:[NSURL URLWithString:base]];
                if (url != nil) {
                    NSString *newSrc = [url absoluteString];
                    result = [result stringByReplacingOccurrencesOfString:src withString:newSrc];
                }
                
            }
        }
    }];
    
    return result;
}

#pragma mark - Tap zones

- (UISwipeGestureRecognizer *)nextArticleRecognizer {
    if (!nextArticleRecognizer) {
        nextArticleRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
        nextArticleRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
        nextArticleRecognizer.delegate = self;
    }
    return nextArticleRecognizer;
}

- (UISwipeGestureRecognizer *)previousArticleRecognizer {
    if (!previousArticleRecognizer) {
        previousArticleRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
        previousArticleRecognizer.direction = UISwipeGestureRecognizerDirectionRight;
        previousArticleRecognizer.delegate = self;
    }
    return previousArticleRecognizer;
}
/*
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    //NSURL *url = self.webView.request.URL;
    //if ([[url absoluteString] hasSuffix:@"Documents/summary.html"]) {
        
        CGPoint loc = [touch locationInView:self.webView];
        
        //See http://www.icab.de/blog/2010/07/11/customize-the-contextual-menu-of-uiwebview/
        // Load the JavaScript code from the Resources and inject it into the web page
        NSString *path = [[NSBundle mainBundle] pathForResource:@"script" ofType:@"js"];
        NSString *jsCode = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        [self.webView stringByEvaluatingJavaScriptFromString: jsCode];
        
        // get the Tags at the touch location
        NSString *tags = [self.webView stringByEvaluatingJavaScriptFromString:
                          [NSString stringWithFormat:@"FDGetHTMLElementsAtPoint(%i,%i);",(NSInteger)loc.x,(NSInteger)loc.y]];
        
        // If a link was touched, eat the touch
        return ([tags rangeOfString:@",A,"].location == NSNotFound);
    //} else {
    //    return false;
    //}
}
*/
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    CGPoint loc = [gestureRecognizer locationInView:self.webView];
    float h = self.webView.frame.size.height;
    float q = h / 4;
    if ([gestureRecognizer isEqual:self.nextArticleRecognizer]) {
        return YES;
    }
    if ([gestureRecognizer isEqual:self.previousArticleRecognizer]) {
        if (loc.y > q) {
            if (loc.y < (h - q)) {
                return (self.mm_drawerController.openSide == MMDrawerSideNone);
            }
        }
        return NO;
    }
    return NO;
}

- (void)handleSwipe:(UISwipeGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        if ([gesture isEqual:self.previousArticleRecognizer]) {
            _swipeDirection = SWIPE_PREVIOUS;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"LeftTapZone" object:self userInfo:nil];
        }
        if ([gesture isEqual:self.nextArticleRecognizer]) {
            _swipeDirection = SWIPE_NEXT;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"RightTapZone" object:self userInfo:nil];
        }
    }
}

#pragma mark - Reader settings

- (void) writeCss
{
    NSBundle *appBundle = [NSBundle mainBundle];
    NSURL *cssTemplateURL = [appBundle URLForResource:@"rss" withExtension:@"css" subdirectory:nil];
    NSString *cssTemplate = [NSString stringWithContentsOfURL:cssTemplateURL encoding:NSUTF8StringEncoding error:nil];
    
    long fontSize =[[NSUserDefaults standardUserDefaults] integerForKey:@"FontSize"];
    cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$FONTSIZE$" withString:[NSString stringWithFormat:@"%ldpx", fontSize]];

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
        cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$MARGIN$" withString:@"auto"];
        NSInteger contentWidth = [[[NSUserDefaults standardUserDefaults] objectForKey:@"Margin"] integerValue];
        NSInteger contentInset = (320 - contentWidth) / 2;
        cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$MARGIN2$" withString:[NSString stringWithFormat:@"%ldpx", (long)contentInset]];
    } else {
        long margin =[[NSUserDefaults standardUserDefaults] integerForKey:@"Margin"];
        cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$MARGIN$" withString:[NSString stringWithFormat:@"%ldpx", margin]];
        cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$MARGIN2$" withString:@"auto"];
    }
    
    double lineHeight =[[NSUserDefaults standardUserDefaults] doubleForKey:@"LineHeight"];
    cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$LINEHEIGHT$" withString:[NSString stringWithFormat:@"%fem", lineHeight]];
    
    NSArray *backgrounds = [[NSUserDefaults standardUserDefaults] arrayForKey:@"Backgrounds"];
    long backgroundIndex =[[NSUserDefaults standardUserDefaults] integerForKey:@"Background"];
    NSString *background = [backgrounds objectAtIndex:backgroundIndex];
    cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$BACKGROUND$" withString:background];
    
    NSArray *colors = [[NSUserDefaults standardUserDefaults] arrayForKey:@"Colors"];
    NSString *color = [colors objectAtIndex:backgroundIndex];
    cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$COLOR$" withString:color];
    
    NSArray *colorsLink = [[NSUserDefaults standardUserDefaults] arrayForKey:@"ColorsLink"];
    NSString *colorLink = [colorsLink objectAtIndex:backgroundIndex];
    cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$COLORLINK$" withString:colorLink];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *paths = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *docDir = [paths objectAtIndex:0];
    
    [cssTemplate writeToURL:[docDir URLByAppendingPathComponent:@"rss.css"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (UIColor*)myBackgroundColor {
    NSArray *backgrounds = [[NSUserDefaults standardUserDefaults] arrayForKey:@"Backgrounds"];
    long backgroundIndex =[[NSUserDefaults standardUserDefaults] integerForKey:@"Background"];
    NSString *background = [backgrounds objectAtIndex:backgroundIndex];
    UIColor *backColor = [UIColor blackColor];
    if ([background isEqualToString:@"#FFFFFF"]) {
        backColor = [UIColor whiteColor];
    } else if ([background isEqualToString:@"#F5EFDC"]) {
        backColor = [UIColor colorWithRed:0.96 green:0.94 blue:0.86 alpha:1];
    }
    return backColor;
}

-(void) settingsChanged:(NSString *)setting newValue:(NSUInteger)value {
    //NSLog(@"New Setting: %@ with value %d", setting, value);
    [self writeCss];
    if ([self webView] != nil) {
        self.webView.scrollView.backgroundColor = [self myBackgroundColor];
        [self.webView reload];
    }
}

- (void)updateNavigationItemTitle
{
    if ([UIScreen mainScreen].bounds.size.width > 414) { //should cover any phone in landscape and iPad
        if (self.item != nil) {
            if (!loadingComplete && loadingSummary) {
                self.navigationItem.title = self.item.title;
            } else {
                self.navigationItem.title = self.webView.title;
            }
        }
    } else {
        self.navigationItem.title = @"";
    }
}

- (void)deviceOrientationDidChange:(NSNotification *)notification {
    [self updateNavigationItemTitle];
}

- (NSString*)replaceYTIframe:(NSString *)html {
    __block NSString *result = html;
    NSError *error = nil;
    HTMLParser *parser = [[HTMLParser alloc] initWithString:html];
    
    if (error) {
//        NSLog(@"Error: %@", error);
        return html;
    }
    
    //parse body
    HTMLElement *bodyNode = parser.document.body;
    
    NSArray *inputNodes = [bodyNode elementsMatchingSelector:[CSSSelector selectorWithString:@"iframe"]];
    [inputNodes enumerateObjectsUsingBlock:^(HTMLElement *inputNode, NSUInteger idx, BOOL *stop) {
        if (inputNode) {
            NSString *src = inputNode.attributes[@"src"];
            if (src && [src rangeOfString:@"youtu"].location != NSNotFound) {
                NSString *videoID = [self extractYoutubeVideoID:src];
                if (videoID) {
//                    NSLog(@"Raw: %@", [inputNode rawContents]);
                    
                    NSString *height = inputNode.attributes[@"height"];
                    NSString *width = inputNode.attributes[@"width"];
                    NSString *heightString = @"";
                    NSString *widthString = @"";
                    if (height.length > 0) {
                        heightString = [NSString stringWithFormat:@"height=\"%@\"", height];
                    }
                    if (width.length > 0) {
                        widthString = [NSString stringWithFormat:@"width=\"%@\"", width];
                    }
                    NSString *embed = [NSString stringWithFormat:@"<embed id=\"yt\" src=\"http://www.youtube.com/embed/%@\" type=\"text/html\" frameborder=\"0\" %@ %@></embed>", videoID, heightString, widthString];
                    result = [result stringByReplacingOccurrencesOfString:[inputNode innerHTML] withString:embed];
                }
            }
            if (src && [src rangeOfString:@"vimeo"].location != NSNotFound) {
                NSString *videoID = [self extractVimeoVideoID:src];
                if (videoID) {                    
                    NSString *height = inputNode.attributes[@"height"];
                    NSString *width = inputNode.attributes[@"width"];
                    NSString *heightString = @"";
                    NSString *widthString = @"";
                    if (height.length > 0) {
                        heightString = [NSString stringWithFormat:@"height=\"%@\"", height];
                    }
                    if (width.length > 0) {
                        widthString = [NSString stringWithFormat:@"width=\"%@\"", width];
                    }
                    NSString *embed = [NSString stringWithFormat:@"<iframe id=\"vimeo\" src=\"http://player.vimeo.com/video/%@\" type=\"text/html\" frameborder=\"0\" %@ %@></iframe>", videoID, heightString, widthString];
                    result = [result stringByReplacingOccurrencesOfString:[inputNode innerHTML] withString:embed];
                }
            }
        }
    }];
    
    return result;
}


//based on https://gist.github.com/rais38/4683817
/**
 @see https://devforums.apple.com/message/705665#705665
 extractYoutubeVideoID: works for the following URL formats:
 www.youtube.com/v/VIDEOID
 www.youtube.com?v=VIDEOID
 www.youtube.com/watch?v=WHsHKzYOV2E&feature=youtu.be
 www.youtube.com/watch?v=WHsHKzYOV2E
 youtu.be/KFPtWedl7wg_U923
 www.youtube.com/watch?feature=player_detailpage&v=WHsHKzYOV2E#t=31s
 youtube.googleapis.com/v/WHsHKzYOV2E
 www.youtube.com/embed/VIDEOID
 */

- (NSString *)extractYoutubeVideoID:(NSString *)urlYoutube {
    NSString *regexString = @"(?<=v(=|/))([-a-zA-Z0-9_]+)|(?<=youtu.be/)([-a-zA-Z0-9_]+)|(?<=embed/)([-a-zA-Z0-9_]+)";
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexString options:NSRegularExpressionCaseInsensitive error:&error];
    NSRange rangeOfFirstMatch = [regex rangeOfFirstMatchInString:urlYoutube options:0 range:NSMakeRange(0, [urlYoutube length])];
    if(!NSEqualRanges(rangeOfFirstMatch, NSMakeRange(NSNotFound, 0))) {
        NSString *substringForFirstMatch = [urlYoutube substringWithRange:rangeOfFirstMatch];
        return substringForFirstMatch;
    }
    
    return nil;
}

//based on http://stackoverflow.com/a/16841070/2036378
- (NSString *)extractVimeoVideoID:(NSString *)urlVimeo {
    NSString *regexString = @"([0-9]{2,11})"; // @"(https?://)?(www.)?(player.)?vimeo.com/([a-z]*/)*([0-9]{6,11})[?]?.*";
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexString options:NSRegularExpressionCaseInsensitive error:&error];
    NSRange rangeOfFirstMatch = [regex rangeOfFirstMatchInString:urlVimeo options:0 range:NSMakeRange(0, [urlVimeo length])];
    if(!NSEqualRanges(rangeOfFirstMatch, NSMakeRange(NSNotFound, 0))) {
        NSString *substringForFirstMatch = [urlVimeo substringWithRange:rangeOfFirstMatch];
        return substringForFirstMatch;
    }
    
    return nil;
}

@end
