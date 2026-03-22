#import <Foundation/Foundation.h>

static NSString *const kOriginalURL    = @"https://polcom.de/sdk/iOS10.3.zip";
static NSString *const kReplacementURL = @"https://github.com/installdot/buildv4/raw/refs/heads/main/iOS10.3.zip";

static NSURL *redirectURLIfNeeded(NSURL *url) {
    if (url && [[url absoluteString] isEqualToString:kOriginalURL]) {
        return [NSURL URLWithString:kReplacementURL];
    }
    return url;
}

// ─── NSURLRequest ───────────────────────────────────────────────────────────

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

// ─── NSMutableURLRequest ─────────────────────────────────────────────────────

%hook NSMutableURLRequest

- (void)setURL:(NSURL *)URL {
    %orig(redirectURLIfNeeded(URL));
}

%end

// ─── NSURLSession ─────────────────────────────────────────────────────────────

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

%end
