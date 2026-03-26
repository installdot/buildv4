#import <Foundation/Foundation.h>

%hook NSURLSessionTask
- (void)resume {
    if ([[[self currentRequest].URL host] containsString:@"apiunitoreios.site"]) return;
    %orig;
}
%end
