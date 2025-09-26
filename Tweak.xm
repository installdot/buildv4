// Tweak.xm
// Logos/Theos tweak - floating Record / Done buttons that log UIControl actions
// Place into a Theos tweak project and build normally.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// Globals for recording state and storage
static BOOL gIsRecording = NO;
static NSMutableArray *gRecords = nil;

// Helper to get short timestamp string
static NSString *ShortTimestamp() {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    return [fmt stringFromDate:[NSDate date]];
}

// Append a record safely (main thread)
static void AppendRecord(NSDictionary *rec) {
    if (!gRecords) gRecords = [NSMutableArray array];
    @synchronized(gRecords) {
        [gRecords addObject:rec];
    }
}

// Build export text for all records
static NSString *ExportAllRecordsText() {
    NSMutableString *out = [NSMutableString string];
    @synchronized(gRecords) {
        [out appendFormat:@"Recorded %lu actions\n\n", (unsigned long)gRecords.count];
        NSUInteger idx = 0;
        for (NSDictionary *r in gRecords) {
            idx++;
            [out appendFormat:@"[%lu] time: %@\n", (unsigned long)idx, r[@"time"]];
            [out appendFormat:@"    selector: %@\n", r[@"selector"]];
            [out appendFormat:@"    target: %@\n", r[@"targetClass"]];
            [out appendFormat:@"    sender: %@\n", r[@"senderClass"]];
            [out appendFormat:@"    event: %@\n", r[@"eventDesc"]];
            NSArray *stack = r[@"stack"];
            if (stack && stack.count > 0) {
                [out appendString:@"    stack:\n"];
                NSUInteger n = MIN(6, stack.count);
                for (NSUInteger i=0;i<n;i++) {
                    [out appendFormat:@"      %@\n", stack[i]];
                }
            }
            [out appendString:@"\n"];
        }
    }
    return out;
}

// Helper: show UIAlert on topmost view controller
static void ShowAlertMainThread(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = UIApplication.sharedApplication.keyWindow ?: UIApplication.sharedApplication.windows.firstObject;
        UIViewController *root = w.rootViewController;
        UIViewController *presenter = root;
        while (presenter.presentedViewController) presenter = presenter.presentedViewController;

        UIAlertController *ac = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [presenter presentViewController:ac animated:YES completion:nil];
    });
}


// ---------- UI overlay injection ----------

%hook UIWindow (RecordingOverlay)

- (void)layoutSubviews {
    %orig;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            // container view so we can move both buttons if we like
            CGFloat btnSize = 64;
            CGFloat miniSize = 36;

            UIView *container = [[UIView alloc] initWithFrame:CGRectMake(16, [UIScreen mainScreen].bounds.size.height - btnSize - 80, btnSize, btnSize)];
            container.layer.cornerRadius = 10;
            container.backgroundColor = [UIColor clearColor];
            container.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;

            // Record toggle button
            UIButton *recordBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            recordBtn.frame = CGRectMake(0, 0, btnSize, btnSize);
            recordBtn.layer.cornerRadius = btnSize/2;
            recordBtn.clipsToBounds = YES;
            recordBtn.backgroundColor = [UIColor colorWithRed:0.85 green:0.0 blue:0.0 alpha:0.85];
            recordBtn.tintColor = [UIColor whiteColor];
            recordBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
            [recordBtn setTitle:@"REC" forState:UIControlStateNormal];
            recordBtn.accessibilityIdentifier = @"RecordingOverlay_RecordButton";

            // Done small button
            UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            doneBtn.frame = CGRectMake(btnSize - miniSize/2, -miniSize/2, miniSize, miniSize);
            doneBtn.layer.cornerRadius = miniSize/2;
            doneBtn.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.85];
            doneBtn.tintColor = [UIColor whiteColor];
            doneBtn.titleLabel.font = [UIFont systemFontOfSize:12];
            [doneBtn setTitle:@"Done" forState:UIControlStateNormal];
            doneBtn.accessibilityIdentifier = @"RecordingOverlay_DoneButton";

            // Pan gesture to move overlay
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:container action:@selector(handlePan:)];
            [container addGestureRecognizer:pan];

            // Add actions
            [recordBtn addTarget:recordBtn action:@selector(recordTapped:) forControlEvents:UIControlEventTouchUpInside];
            [doneBtn addTarget:doneBtn action:@selector(doneTapped:) forControlEvents:UIControlEventTouchUpInside];

            // Add as associated objects so methods can find them later
            objc_setAssociatedObject(container, "recordBtn", recordBtn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(container, "doneBtn", doneBtn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [container addSubview:recordBtn];
            [container addSubview:doneBtn];

            // Add small shadow
            container.layer.shadowColor = [UIColor blackColor].CGColor;
            container.layer.shadowOpacity = 0.4;
            container.layer.shadowRadius = 5;
            container.layer.shadowOffset = CGSizeMake(0,2);

            // Add to window
            [self addSubview:container];

            // Add helper selectors on the buttons using blocks via objc_setAssociatedObject wrappers
        });
    });
}

%end

// Extend UIView for pan handling and button actions (helpers)
@interface UIView (RecordingHelpers)
- (void)handlePan:(UIPanGestureRecognizer *)g;
- (void)recordTapped:(id)sender;
- (void)doneTapped:(id)sender;
@end

@implementation UIView (RecordingHelpers)

- (void)handlePan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    CGPoint trans = [g translationInView:v.superview];
    if (g.state == UIGestureRecognizerStateChanged || g.state == UIGestureRecognizerStateEnded) {
        CGRect f = v.frame;
        f.origin.x += trans.x;
        f.origin.y += trans.y;
        // clamp to screen
        CGRect bounds = [UIScreen mainScreen].bounds;
        f.origin.x = MAX(4, MIN(f.origin.x, bounds.size.width - f.size.width - 4));
        f.origin.y = MAX(4, MIN(f.origin.y, bounds.size.height - f.size.height - 4));
        v.frame = f;
        [g setTranslation:CGPointZero inView:v.superview];
    }
}

- (void)recordTapped:(id)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIButton *btn = (UIButton *)sender;
        gIsRecording = !gIsRecording;
        if (gIsRecording) {
            // start a fresh session (clear previous)
            @synchronized(gRecords) { gRecords = [NSMutableArray array]; }
            btn.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.0 alpha:0.9]; // green while recording
            [btn setTitle:@"REC✓" forState:UIControlStateNormal];
            NSLog(@"[TweakRecorder] Recording STARTED");
            ShowAlertMainThread(@"Recording", @"Action recording started.");
        } else {
            btn.backgroundColor = [UIColor colorWithRed:0.85 green:0.0 blue:0.0 alpha:0.85];
            [btn setTitle:@"REC" forState:UIControlStateNormal];
            NSLog(@"[TweakRecorder] Recording PAUSED");
            ShowAlertMainThread(@"Recording", @"Recording paused (tap Done to export).");
        }
    });
}

- (void)doneTapped:(id)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        // stop recording
        BOOL wasRecording = gIsRecording;
        gIsRecording = NO;
        UIButton *recordBtn = objc_getAssociatedObject(self.superview, "recordBtn");
        if ([recordBtn isKindOfClass:[UIButton class]]) {
            recordBtn.backgroundColor = [UIColor colorWithRed:0.85 green:0.0 blue:0.0 alpha:0.85];
            [recordBtn setTitle:@"REC" forState:UIControlStateNormal];
        }

        // Export text
        NSString *out = ExportAllRecordsText();
        if (!out) out = @"<no-records>";

        // Copy to pasteboard
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                UIPasteboard *pb = [UIPasteboard generalPasteboard];
                pb.strings = @[out]; // strings array to be safer
            } @catch (NSException *ex) {
                // fallback
                @try {
                    [UIPasteboard generalPasteboard].string = out;
                } @catch (NSException *e2) {}
            }
        });

        // Optionally also NSLog to syslog
        NSLog(@"[TweakRecorder] Exported %lu records, copied to clipboard.", (unsigned long)(gRecords ? gRecords.count : 0));
        ShowAlertMainThread(@"Exported", [NSString stringWithFormat:@"Exported %lu actions (copied to clipboard).", (unsigned long)(gRecords ? gRecords.count : 0)]);
    });
}

@end


// ---------- Hook UIControl sendAction:to:forEvent: to capture actions ----------

%hook UIControl

- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    // Capture only when recording
    if (gIsRecording) {
        @try {
            NSString *selName = action ? NSStringFromSelector(action) : @"<nil>";
            NSString *targetClass = target ? NSStringFromClass([target class]) : @"<nil>";
            NSString *senderClass = NSStringFromClass([self class]);
            NSString *time = ShortTimestamp();

            // Basic event description
            NSString *eventDesc = @"<event>";
            if ([event respondsToSelector:@selector(type)]) {
                UIEventType t = [event type];
                eventDesc = [NSString stringWithFormat:@"type=%ld", (long)t];
            }

            // Short stack
            NSArray *stack = [NSThread callStackSymbols];
            // Keep only first N lines to reduce size
            NSUInteger keep = MIN(40, stack.count);
            NSArray *shortStack = [stack subarrayWithRange:NSMakeRange(0, keep)];

            NSDictionary *rec = @{
                @"selector": selName ?: @"<nil>",
                @"targetClass": targetClass ?: @"<nil>",
                @"senderClass": senderClass ?: @"<nil>",
                @"time": time ?: @"",
                @"eventDesc": eventDesc ?: @"",
                @"stack": shortStack ?: @[]
            };

            AppendRecord(rec);
        } @catch (NSException *ex) {
            NSLog(@"[TweakRecorder] Exception while capturing action: %@", ex);
        }
    }

    // Always call original so behavior is unchanged
    %orig(action, target, event);
}

%end


// ensure categories and runtime-loaded objects compile cleanly
%ctor {
    // initialize record array
    gRecords = [NSMutableArray array];
    gIsRecording = NO;
    NSLog(@"[TweakRecorder] loaded and ready.");
}
