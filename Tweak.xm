#import <Foundation/Foundation.h>

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    NSString *urlStr = request.URL.absoluteString;
    
    // Check if the URL matches our target endpoints
    if ([urlStr containsString:@"zfighterz.ch/sqlconnect/Super_Saga/launcherResources.php"] ||
        [urlStr containsString:@"zfighterz.ch/sqlconnect/Super_Saga/enterServer.php"] ||
        [urlStr containsString:@"zfighterz.ch/sqlconnect/Super_Saga/playerData.php"] ||
        [urlStr containsString:@"zfighterz.ch/sqlconnect/Super_Saga/inventory_v2.php"]) {
        
        // Wrap the original completion handler to intercept the response data
        void (^customCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            
            if (data && !error) {
                NSError *jsonError;
                // Parse the outer JSON
                NSMutableDictionary *outerDict = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jsonError];
                
                if (!jsonError && outerDict[@"data"]) {
                    // The "data" field is a stringified JSON object. We need to parse it.
                    NSString *innerJsonString = outerDict[@"data"];
                    NSData *innerData = [innerJsonString dataUsingEncoding:NSUTF8StringEncoding];
                    NSMutableDictionary *innerDict = [NSJSONSerialization JSONObjectWithData:innerData options:NSJSONReadingMutableContainers error:nil];
                    
                    if (innerDict) {
                        // 1. Launcher Resources Modification
                        if ([urlStr containsString:@"launcherResources.php"]) {
                            NSMutableDictionary *result = innerDict[@"result"];
                            if (result) {
                                NSMutableArray *serverList = result[@"serverList"];
                                for (NSMutableDictionary *server in serverList) {
                                    if ([server[@"server_id"] intValue] == 15) {
                                        server[@"server_name"] = @"Mochi De Silly";
                                    }
                                }
                            }
                        } 
                        // 2. Player Data, Enter Server, and Inventory Modifications
                        else {
                            NSMutableDictionary *currentStatus = innerDict[@"currentStatus"];
                            if (currentStatus) {
                                currentStatus[@"vip"] = @(69);
                                currentStatus[@"coin"] = @"369 M";
                                currentStatus[@"diamond"] = @"369 M";
                                currentStatus[@"level"] = @(69);
                                currentStatus[@"totalAttack"] = @(369);
                                currentStatus[@"totalDefense"] = @(369);
                                currentStatus[@"diamondInt"] = @(369000);
                                currentStatus[@"coinInt"] = @(369000);
                            }
                        }
                        
                        // Repackage the inner JSON back into a string
                        NSData *modifiedInnerData = [NSJSONSerialization dataWithJSONObject:innerDict options:0 error:nil];
                        NSString *modifiedInnerString = [[NSString alloc] initWithData:modifiedInnerData encoding:NSUTF8StringEncoding];
                        
                        // Update the outer dictionary
                        outerDict[@"data"] = modifiedInnerString;
                        
                        // Repackage the outer dictionary back into NSData
                        NSData *modifiedOuterData = [NSJSONSerialization dataWithJSONObject:outerDict options:0 error:nil];
                        if (modifiedOuterData) {
                            data = modifiedOuterData; // Replace original data with our spoofed data
                        }
                    }
                }
            }
            
            // Pass the (modified) data back to the game's original handler
            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };
        
        // Call the original method but pass our intercepted completion handler
        return %orig(request, customCompletion);
    }
    
    // If it's not a URL we care about, let it process normally
    return %orig;
}

// Also hook the URL variant just in case the app uses dataTaskWithURL instead of Request
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    NSString *urlStr = url.absoluteString;
    
    if ([urlStr containsString:@"zfighterz.ch/sqlconnect/Super_Saga/launcherResources.php"] ||
        [urlStr containsString:@"zfighterz.ch/sqlconnect/Super_Saga/enterServer.php"] ||
        [urlStr containsString:@"zfighterz.ch/sqlconnect/Super_Saga/playerData.php"] ||
        [urlStr containsString:@"zfighterz.ch/sqlconnect/Super_Saga/inventory_v2.php"]) {
        
        void (^customCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            
            if (data && !error) {
                NSError *jsonError;
                NSMutableDictionary *outerDict = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jsonError];
                
                if (!jsonError && outerDict[@"data"]) {
                    NSString *innerJsonString = outerDict[@"data"];
                    NSData *innerData = [innerJsonString dataUsingEncoding:NSUTF8StringEncoding];
                    NSMutableDictionary *innerDict = [NSJSONSerialization JSONObjectWithData:innerData options:NSJSONReadingMutableContainers error:nil];
                    
                    if (innerDict) {
                        if ([urlStr containsString:@"launcherResources.php"]) {
                            NSMutableDictionary *result = innerDict[@"result"];
                            if (result) {
                                NSMutableArray *serverList = result[@"serverList"];
                                for (NSMutableDictionary *server in serverList) {
                                    if ([server[@"server_id"] intValue] == 15) {
                                        server[@"server_name"] = @"Mochi De Silly";
                                    }
                                }
                            }
                        } else {
                            NSMutableDictionary *currentStatus = innerDict[@"currentStatus"];
                            if (currentStatus) {
                                currentStatus[@"vip"] = @(69);
                                currentStatus[@"coin"] = @"369 M";
                                currentStatus[@"diamond"] = @"369 M";
                                currentStatus[@"level"] = @(69);
                                currentStatus[@"totalAttack"] = @(369);
                                currentStatus[@"totalDefense"] = @(369);
                                currentStatus[@"diamondInt"] = @(369000);
                                currentStatus[@"coinInt"] = @(369000);
                            }
                        }
                        
                        NSData *modifiedInnerData = [NSJSONSerialization dataWithJSONObject:innerDict options:0 error:nil];
                        NSString *modifiedInnerString = [[NSString alloc] initWithData:modifiedInnerData encoding:NSUTF8StringEncoding];
                        outerDict[@"data"] = modifiedInnerString;
                        
                        NSData *modifiedOuterData = [NSJSONSerialization dataWithJSONObject:outerDict options:0 error:nil];
                        if (modifiedOuterData) {
                            data = modifiedOuterData;
                        }
                    }
                }
            }
            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };
        return %orig(url, customCompletion);
    }
    
    return %orig;
}

%end
