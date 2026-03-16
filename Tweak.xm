// Tweak.xm

@interface APIClient : NSObject
- (void) paid:(void (^)(void))execute;
+ (instancetype)sharedAPIClient;
@end

%ctor {
    @autoreleasepool {
        APIClient *API = [APIClient sharedAPIClient];
        [API paid:^{}]; // empty block, the app's original block runs itself
    }
}
