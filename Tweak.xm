#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

// AVPlayer: Speed up playback to 100x
%hook AVPlayer

- (void)setRate:(float)rate {
    %orig(100.0); // Force 100x speed
}

- (float)rate {
    return 100.0;
}

%end

// WKWebView: Inject JS to set video playbackRate to 100x
%hook WKWebView

- (void)didMoveToWindow {
    %orig;

    NSString *js = @"setInterval(function(){\
        var vids = document.getElementsByTagName('video');\
        for(var i=0;i<vids.length;i++){\
            vids[i].playbackRate = 100.0;\
        }\
    }, 500);";

    [self evaluateJavaScript:js completionHandler:nil];
}

%end

// CADisplayLink: Optional boost to frame rate
%hook CADisplayLink

- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    %orig(fps * 100); // Boost
}

%end
