%hook AVPlayer

- (void)setRate:(float)rate {
    %orig(100.0);
}

- (float)rate {
    return 100.0;
}

%end

%hook MPMoviePlayerController

- (void)setPlaybackRate:(float)rate {
    %orig(100.0);
}

- (float)playbackRate {
    return 100.0;
}

%end

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

%hook CADisplayLink

- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    %orig(fps * 100);
}

%end
