#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <substrate.h>

// Hook UnityEngine.TextAsset
@interface TextAsset : NSObject
@property (nonatomic, readonly) NSString *text;
@end

%hook TextAsset
- (NSString *)text {
    NSString *originalText = %orig;
    
    // Save to a file
    NSString *path = [NSString stringWithFormat:@"/var/mobile/Documents/%@.txt", [[NSUUID UUID] UUIDString]];
    [originalText writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];

    return originalText;
}
%end
