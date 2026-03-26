#import <Foundation/Foundation.h>

%hook NSURLSessionTask

- (void)resume {
    NSURL *url = nil;

    if ([self respondsToSelector:@selector(currentRequest)]) {
        url = [[self currentRequest] URL];
    }

    if (url && [url.host containsString:@"apiunitoreios.site"]) {
        NSLog(@"[BLOCKED] %@", url);
        return; // chặn như mất mạng
    }

    %orig;
}

%end
