#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface FloatingBrowser : UIView
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation FloatingBrowser

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor whiteColor];
        self.layer.cornerRadius = 10;
        self.layer.masksToBounds = YES;

        self.webView = [[WKWebView alloc] initWithFrame:self.bounds];
        [self addSubview:self.webView];

        NSURL *url = [NSURL URLWithString:@"https://google.com"];
        [self.webView loadRequest:[NSURLRequest requestWithURL:url]];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.superview];
}

@end

%hook SpringBoard
- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;

    FloatingBrowser *browser = [[FloatingBrowser alloc] initWithFrame:CGRectMake(50, 100, 300, 400)];
    [[UIApplication sharedApplication].keyWindow addSubview:browser];
}
%end
