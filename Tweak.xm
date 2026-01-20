#import <UIKit/UIKit.h>

#define TARGET_URL @"api.locketcamera.com/fetchUserV2"

static UIButton *stopButton;
static BOOL capturing = YES;

// uid -> "First Last"
static NSMutableDictionary<NSString *, NSString *> *capturedUsers;

#pragma mark - Export

void exportToClipboard(void) {
    NSMutableString *output = [NSMutableString string];

    [output appendFormat:@"Captured Users: %lu\n\n",
        (unsigned long)capturedUsers.count];

    for (NSString *uid in capturedUsers) {
        [output appendFormat:@"%@ | %@\n", uid, capturedUsers[uid]];
    }

    UIPasteboard.generalPasteboard.string = output;

    UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:@"Capture Stopped"
                                          message:[NSString stringWithFormat:
                                            @"Total captured: %lu\n\nCopied to clipboard.",
                                            (unsigned long)capturedUsers.count]
                                   preferredStyle:UIAlertControllerStyleAlert];

    UIWindow *w = UIApplication.sharedApplication.keyWindow;
    [w.rootViewController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Button

void stopCapture(void) {
    capturing = NO;
    exportToClipboard();
    stopButton.hidden = YES;
}

void addButton(void) {
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if (!window || stopButton) return;

    stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    stopButton.frame = CGRectMake(20, 150, 180, 44);
    stopButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    stopButton.layer.cornerRadius = 8;

    [stopButton setTitle:@"Stop & Copy" forState:UIControlStateNormal];
    [stopButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];

    [stopButton addTarget:nil
                   action:@selector(stopButtonPressed)
         forControlEvents:UIControlEventTouchUpInside];

    [window addSubview:stopButton];
}

%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    addButton();
}
%end

@interface NSObject (StopButton)
- (void)stopButtonPressed;
@end

@implementation NSObject (StopButton)
- (void)stopButtonPressed {
    stopCapture();
}
@end

#pragma mark - Network Hook

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) =
    ^(NSData *data, NSURLResponse *response, NSError *error) {

        if (capturing &&
            data &&
            [request.URL.absoluteString containsString:TARGET_URL]) {

            NSDictionary *json =
              [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];

            NSDictionary *dataObj = json[@"result"][@"data"];

            if ([dataObj isKindOfClass:NSDictionary.class]) {
                NSString *uid = dataObj[@"uid"];
                NSString *first = dataObj[@"first_name"] ?: @"";
                NSString *last = dataObj[@"last_name"] ?: @"";

                if (uid.length > 0 && !capturedUsers[uid]) {
                    capturedUsers[uid] =
                      [NSString stringWithFormat:@"%@ %@", first, last];
                }
            }
        }

        completionHandler(data, response, error);
    };

    return %orig(request, wrappedHandler);
}

%end

#pragma mark - Init

%ctor {
    capturedUsers = [NSMutableDictionary dictionary];
}
