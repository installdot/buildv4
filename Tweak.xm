#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - topVC

static UIWindow* firstWindow() {
    for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) return w;
            }
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static UIViewController* topVC() {
    UIWindow *win = firstWindow();
    UIViewController *root = win.rootViewController;
    while (root.presentedViewController)
        root = root.presentedViewController;
    return root;
}

#pragma mark - List Documents Folder

static NSArray* listDocumentsFiles() {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    NSArray *files = [fm contentsOfDirectoryAtPath:docs error:&err];
    if (err) return @[];
    return files;
}

#pragma mark - Copy File Contents to Clipboard

static void copyFileContents(NSString *fileName) {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *filePath = [docs stringByAppendingPathComponent:fileName];

    NSError *err = nil;
    NSString *content = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&err];

    UIAlertController *alert;
    if (err || !content) {
        alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                    message:@"Cannot read file contents."
                                             preferredStyle:UIAlertControllerStyleAlert];
    } else {
        // Copy to clipboard
        UIPasteboard.generalPasteboard.string = content;
        alert = [UIAlertController alertControllerWithTitle:@"Copied!"
                                                    message:[NSString stringWithFormat:@"%@ copied to clipboard.", fileName]
                                             preferredStyle:UIAlertControllerStyleAlert];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [topVC() presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Show Files Menu

static void showDocumentsMenu() {
    NSArray *files = listDocumentsFiles();
    if (files.count == 0) {
        UIAlertController *empty = [UIAlertController alertControllerWithTitle:@"No Files"
                                                                       message:@"Documents folder is empty."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [empty addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:empty animated:YES completion:nil];
        return;
    }

    UIAlertController *menu =
        [UIAlertController alertControllerWithTitle:@"Documents Folder"
                                            message:@"Select a file to copy its contents"
                                     preferredStyle:UIAlertControllerStyleAlert];

    for (NSString *file in files) {
        [menu addAction:[UIAlertAction actionWithTitle:file
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction * _Nonnull action){
            copyFileContents(file);
        }]];
    }

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:menu animated:YES completion:nil];
}

#pragma mark - Floating Draggable Button

static CGPoint startPoint;
static CGPoint btnStart;

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *win = firstWindow();

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 200, 70, 70);
        btn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        btn.layer.cornerRadius = 35;
        btn.tintColor = UIColor.whiteColor;
        [btn setTitle:@"Docs" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];

        [btn addTarget:nil action:@selector(showDocumentsPressed) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(handlePan:)];
        [btn addGestureRecognizer:pan];

        [win addSubview:btn];
    });
}

%hook UIApplication
%new
- (void)showDocumentsPressed { showDocumentsMenu(); }

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIButton *btn = (UIButton*)pan.view;
    if (pan.state == UIGestureRecognizerStateBegan) {
        startPoint = [pan locationInView:btn.superview];
        btnStart = btn.center;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint pt = [pan locationInView:btn.superview];
        CGFloat dx = pt.x - startPoint.x;
        CGFloat dy = pt.y - startPoint.y;
        btn.center = CGPointMake(btnStart.x + dx, btnStart.y + dy);
    }
}
%end
