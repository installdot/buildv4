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
        self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:self.webView];

        NSURL *url = [NSURL URLWithString:@"https://google.com"];
        [self.webView loadRequest:[NSURLRequest requestWithURL:url]];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];

        UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        closeButton.frame = CGRectMake(self.bounds.size.width - 30, 5, 25, 25);
        closeButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
        [closeButton setTitle:@"X" forState:UIControlStateNormal];
        [closeButton addTarget:self action:@selector(closeBrowser) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeButton];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.superview];
}

- (void)closeBrowser {
    [self removeFromSuperview];
}

@end

%hook SpringBoard
- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;

    UIWindow *keyWindow = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            keyWindow = scene.windows.firstObject;
            break;
        }
    }

    if (keyWindow) {
        FloatingBrowser *browser = [[FloatingBrowser alloc] initWithFrame:CGRectMake(50, 100, 300, 400)];
        [keyWindow addSubview:browser];
    }
}
%end
