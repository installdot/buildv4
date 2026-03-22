#import <Foundation/Foundation.h>

// Target URL to intercept
static NSString *const kOriginalURL = @"https://polcom.de/sdk/iOS10.3.zip";

// Replacement URL
static NSString *const kReplacementURL = @"https://github.com/installdot/buildv4/raw/refs/heads/main/iOS10.3.zip";

static NSURL *redirectURLIfNeeded(NSURL *url) {
    if (url && [[url absoluteString] isEqualToString:kOriginalURL]) {
        return [NSURL URLWithString:kReplacementURL];
    }
    return url;
}

// ─────────────────────────────────────────────
// Hook NSURLRequest initWithURL:
// ─────────────────────────────────────────────
%hook NSURLRequest

- (instancetype)initWithURL:(NSURL *)URL {
    return %orig(redirectURLIfNeeded(URL));
}

- (instancetype)initWithURL:(NSURL *)URL
               cachePolicy:(NSURLRequestCachePolicy)cachePolicy
           timeoutInterval:(NSTimeInterval)timeoutInterval {
    return %orig(redirectURLIfNeeded(URL), cachePolicy, timeoutInterval);
}

%end

// ─────────────────────────────────────────────
// Hook NSMutableURLRequest setURL:
// ─────────────────────────────────────────────
%hook NSMutableURLRequest

- (void)setURL:(NSURL *)URL {
    %orig(redirectURLIfNeeded(URL));
}

%end

// ─────────────────────────────────────────────
// Hook NSURLSession dataTaskWithURL: variants
// ─────────────────────────────────────────────
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    return %orig(redirectURLIfNeeded(url));
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    return %orig(redirectURLIfNeeded(url), completionHandler);
}

- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url {
    return %orig(redirectURLIfNeeded(url));
}

- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url
                                completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler {
    return %orig(redirectURLIfNeeded(url), completionHandler);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData {
    return %orig(request, bodyData);
}

%end

// ─────────────────────────────────────────────
// Hook CFURLRequestCreate (lower-level Core Foundation layer)
// ─────────────────────────────────────────────
%hookf(CFURLRequestRef, CFURLRequestCreate, CFAllocatorRef allocator, CFURLRef url, CFURLRequestCachePolicy cachePolicy, CFTimeInterval timeoutInterval, CFURLRef mainDocumentURL) {
    if (url) {
        NSString *urlString = (__bridge NSString *)CFURLGetString(url);
        if ([urlString isEqualToString:kOriginalURL]) {
            CFURLRef newURL = (__bridge CFURLRef)[NSURL URLWithString:kReplacementURL];
            return %orig(allocator, newURL, cachePolicy, timeoutInterval, mainDocumentURL);
        }
    }
    return %orig(allocator, url, cachePolicy, timeoutInterval, mainDocumentURL);
}
