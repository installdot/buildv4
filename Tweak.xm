// Required Imports
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>

// Optional class forward declarations
@class AVPlayer;
@class MPMoviePlayerController;
@class WKWebView;
@class CADisplayLink;

// AVPlayer: Speed up playback to 100x
%hook AVPlayer

- (void)setRate:(float)rate {
    %orig(100.0); // Force 100x speed
}

- (float)rate {
    return 100.0;
}

%end

// MPMoviePlayerController: Legacy API (some apps still use it)
%hook MPMoviePlayerController

- (void)setPlaybackRate:(float)rate {
    %orig(100.0);
}

- (float)playbackRate {
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

// CADisplayLink: Boost frame rate rendering (optional visual boost)
%hook CADisplayLink

- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    %orig(fps * 100); // Force 100x frame rate
}

%end
