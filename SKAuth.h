// SKAuth.h — Authentication, device info, settings, and session helpers
// Part of SKFramework · iOS 14+ · ARC · Theos/Logos compatible
//
// Depends on:  SKCrypto.h  (must be imported first)
//
// Provides:
//   • Device model / system version helpers
//   • NSUserDefaults-backed settings (toggle flags)
//   • Per-device expiry cache (UserDefaults)
//   • Session UUID (flat file)
//   • performKeyAuth() — encrypted POST to auth server, replay-guarded
//   • URLSession factory (no caching, 120 s / 600 s timeout)
//   • Multipart body builder
//   • skPost() — generic upload-task POST → NSDictionary callback

#pragma once
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <sys/utsname.h>
#import "SKCrypto.h"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §1  Endpoint URLs — CHANGE to your server
// ─────────────────────────────────────────────────────────────────────────────

/// Base URL for save-data API actions (upload / load).
#define SK_API_BASE   @"https://chillysilly.frfrnocap.men/iske.php"

/// URL for the encrypted key-authentication endpoint.
#define SK_AUTH_BASE  @"https://chillysilly.frfrnocap.men/iskeauth.php"

/// Maximum allowed drift (seconds) between sent timestamp and server-echoed timestamp.
#define SK_MAX_TS_DRIFT  60

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §2  Device info helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the vendor UUID for the current device (falls back to a random UUID).
static NSString *SK_deviceUUID(void) {
    NSString *v = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    return v ?: [[NSUUID UUID] UUIDString];
}

/// Returns the hardware model string (e.g. "iPhone14,2").
static NSString *SK_deviceModel(void) {
    struct utsname info; uname(&info);
    return [NSString stringWithCString:info.machine encoding:NSUTF8StringEncoding]
           ?: [UIDevice currentDevice].model;
}

/// Returns the iOS/iPadOS version string (e.g. "17.4").
static NSString *SK_systemVersion(void) {
    return [UIDevice currentDevice].systemVersion ?: @"?";
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §3  Settings (NSUserDefaults-backed boolean flags)
//
// Keys used by the framework:
//   "autoRij"        — patch OpenRijTest_ flags before upload       (default ON)
//   "autoDetectUID"  — read PlayerId from SdkStateCache#1
//   "autoClose"      — exit() after successful cloud load
//
// You can add your own keys and call SK_getSetting / SK_setSetting freely.
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the filesystem path of the settings plist.
static NSString *SK_settingsFilePath(void) {
    return [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Preferences/SKToolsSettings.plist"];
}

/// Loads the mutable settings dictionary from disk (empty dict if not yet created).
static NSMutableDictionary *SK_loadSettingsDict(void) {
    NSMutableDictionary *d =
        [NSMutableDictionary dictionaryWithContentsOfFile:SK_settingsFilePath()];
    return d ?: [NSMutableDictionary dictionary];
}

/// Persists `d` to the settings plist.
static void SK_persistSettingsDict(NSMutableDictionary *d) {
    [d writeToFile:SK_settingsFilePath() atomically:YES];
}

/// Reads a boolean setting value for `key`.
static BOOL SK_getSetting(NSString *key) {
    return [SK_loadSettingsDict()[key] boolValue];
}

/// Writes a boolean setting value for `key` and persists immediately.
static void SK_setSetting(NSString *key, BOOL val) {
    NSMutableDictionary *d = SK_loadSettingsDict();
    d[key] = @(val);
    SK_persistSettingsDict(d);
}

/// Writes framework defaults if not already set.
/// Call once at startup (e.g. inside injectPanel).
static void SK_initDefaultSettings(void) {
    NSMutableDictionary *d = SK_loadSettingsDict();
    BOOL changed = NO;
    if (!d[@"autoRij"]) { d[@"autoRij"] = @YES; changed = YES; }
    if (changed) SK_persistSettingsDict(d);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §4  Per-device expiry cache
//
// gSKDeviceExpiry and gSKKeyExpiry are in-memory globals set after auth.
// The device expiry is also persisted to NSUserDefaults so it survives relaunches.
// ─────────────────────────────────────────────────────────────────────────────

/// In-memory device expiry timestamp (Unix epoch). Set by performKeyAuth().
static NSTimeInterval gSKDeviceExpiry = 0;

/// In-memory key expiry timestamp (Unix epoch). Set by performKeyAuth().
static NSTimeInterval gSKKeyExpiry    = 0;

/// Whether the welcome notification has already been shown this session.
static BOOL gSKWelcomeShownThisSession = NO;

/// Persists `exp` to NSUserDefaults for use across app relaunches.
static void SK_saveDeviceExpiryLocally(NSTimeInterval exp) {
    [[NSUserDefaults standardUserDefaults] setDouble:exp forKey:@"SKToolsDeviceExpiry"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

/// Returns the last persisted device expiry from NSUserDefaults (0 if not stored).
static NSTimeInterval SK_loadDeviceExpiryLocally(void) {
    return [[NSUserDefaults standardUserDefaults] doubleForKey:@"SKToolsDeviceExpiry"];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §5  Session UUID (cloud session, flat file)
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the filesystem path of the session UUID file.
static NSString *SK_sessionFilePath(void) {
    return [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Preferences/SKToolsSession.txt"];
}

/// Reads the current session UUID. Returns nil if no session is active.
static NSString *SK_loadSessionUUID(void) {
    return [NSString stringWithContentsOfFile:SK_sessionFilePath()
                                     encoding:NSUTF8StringEncoding error:nil];
}

/// Saves `uuid` as the active session UUID.
static void SK_saveSessionUUID(NSString *uuid) {
    [uuid writeToFile:SK_sessionFilePath() atomically:YES
             encoding:NSUTF8StringEncoding error:nil];
}

/// Deletes the session UUID file (call after a successful load to prevent re-use).
static void SK_clearSessionUUID(void) {
    [[NSFileManager defaultManager] removeItemAtPath:SK_sessionFilePath() error:nil];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §6  NSURLSession factory
// ─────────────────────────────────────────────────────────────────────────────

/// Creates a fresh NSURLSession with no caching and generous timeouts.
/// Each logical operation should create its own session via this helper.
static NSURLSession *SK_makeSession(void) {
    NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
    c.timeoutIntervalForRequest  = 120;
    c.timeoutIntervalForResource = 600;
    c.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    return [NSURLSession sessionWithConfiguration:c];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §7  Multipart body builder
// ─────────────────────────────────────────────────────────────────────────────

/// Container for a configured NSMutableURLRequest + body NSData.
typedef struct { NSMutableURLRequest *req; NSData *body; } SKMPRequest;

/// Builds a multipart/form-data POST request targeting SK_API_BASE.
///
/// @param fields     Plain text form fields  { name → value }.
/// @param fileField  Form field name for the file attachment (or nil to skip).
/// @param filename   Filename hint for the attachment (or nil).
/// @param fileData   Raw bytes of the attachment (or nil).
/// @return  Populated SKMPRequest ready for SK_post().
static SKMPRequest SK_buildMP(NSDictionary<NSString *, NSString *> *fields,
                               NSString *fileField,
                               NSString *filename,
                               NSData   *fileData) {
    NSString *boundary = [NSString stringWithFormat:@"----SKBound%08X%08X",
                          arc4random(), arc4random()];
    NSMutableData *body = [NSMutableData dataWithCapacity:fileData ? fileData.length + 1024 : 1024];

    void (^addField)(NSString *, NSString *) = ^(NSString *n, NSString *v) {
        NSString *s = [NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",
            boundary, n, v];
        [body appendData:[s dataUsingEncoding:NSUTF8StringEncoding]];
    };

    for (NSString *k in fields) addField(k, fields[k]);

    if (fileField && filename && fileData) {
        NSString *hdr = [NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n"
             @"Content-Type: text/plain; charset=utf-8\r\n\r\n",
            boundary, fileField, filename];
        [body appendData:[hdr dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:fileData];
        [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }

    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary]
                      dataUsingEncoding:NSUTF8StringEncoding]];

    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:SK_API_BASE]
           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
       timeoutInterval:120];
    req.HTTPMethod = @"POST";
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
       forHTTPHeaderField:@"Content-Type"];

    return (SKMPRequest){ req, body };
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §8  Generic POST helper
// ─────────────────────────────────────────────────────────────────────────────

/// Fires `req` with `body` via `session`, then calls `cb` on the main queue.
/// On success, `cb` receives the decoded JSON dictionary (error field treated as failure).
/// On failure, `cb` receives nil + an NSError.
static void SK_post(NSURLSession *session,
                    NSMutableURLRequest *req,
                    NSData *body,
                    void (^cb)(NSDictionary *json, NSError *err)) {
    [[session uploadTaskWithRequest:req fromData:body
                  completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) { cb(nil, err); return; }
            if (!data.length) {
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:@"Empty server response"}]);
                return;
            }
            NSError *je = nil;
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
            if (je || !j) {
                NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                                ?: @"Non-JSON response";
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:raw}]);
                return;
            }
            if (j[@"error"]) {
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:j[@"error"]}]);
                return;
            }
            cb(j, nil);
        });
    }] resume];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §9  performKeyAuth — encrypted key validation
//
// Flow:
//   1. Build payload: { key, timestamp, device_id, model, sys_ver }
//   2. Encrypt with AES-256-CBC + HMAC-SHA256 → Base64
//   3. POST { "data": <base64> } to SK_AUTH_BASE
//   4. Decrypt response, verify echoed timestamp & replay guard
//   5. Callback with (ok, keyExpiry, deviceExpiry, message)
//
// Security properties:
//   • MITM protection: server echoes back the timestamp we sent;
//     any tampering breaks HMAC and decryption fails.
//   • Replay protection: we compare the echoed TS against the one
//     we just saved to disk; a replayed older response is rejected.
//   • Clock-drift tolerance: SK_MAX_TS_DRIFT seconds (default 60).
// ─────────────────────────────────────────────────────────────────────────────

/// Validates `keyValue` against the remote auth server.
///
/// @param keyValue    The raw key string entered by the user.
/// @param completion  Called on the main queue:
///                      ok          — YES if the key is valid and active.
///                      keyExpiry   — Unix timestamp when the key expires (0 = unknown).
///                      deviceExpiry — Unix timestamp when this device slot expires.
///                      errorMsg    — Human-readable failure reason (nil on success).
static void SK_performKeyAuth(NSString *keyValue,
                              void (^completion)(BOOL ok,
                                                 NSTimeInterval keyExpiry,
                                                 NSTimeInterval deviceExpiry,
                                                 NSString *errorMsg)) {
    NSTimeInterval now    = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval sendTS = floor(now);
    SK_saveLastSentTS(sendTS);

    NSDictionary *payload = @{
        @"key"       : keyValue ?: @"",
        @"timestamp" : @((long long)sendTS),
        @"device_id" : SK_persistentDeviceID(),
        @"model"     : SK_deviceModel(),
        @"sys_ver"   : SK_systemVersion(),
    };

    NSString *encPayload = SK_encryptPayloadToBase64(payload);
    if (!encPayload) {
        completion(NO, 0, 0, @"Encryption failed — check AES key setup.");
        return;
    }

    NSDictionary *bodyDict = @{ @"data" : encPayload };
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:nil];
    if (!bodyData) {
        completion(NO, 0, 0, @"JSON serialization failed.");
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:SK_AUTH_BASE]
           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
       timeoutInterval:20];
    req.HTTPMethod = @"POST";
    req.HTTPBody   = bodyData;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    [[SK_makeSession() dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{

            if (err) {
                completion(NO, 0, 0, [NSString stringWithFormat:@"Network error: %@",
                           err.localizedDescription]);
                return;
            }
            if (!data.length) {
                completion(NO, 0, 0, @"Empty auth response."); return;
            }

            NSError *je = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                  options:0 error:&je];
            if (je || !json) {
                completion(NO, 0, 0, @"Auth server returned invalid JSON."); return;
            }
            if (json[@"error"]) {
                completion(NO, 0, 0, json[@"error"]); return;
            }

            NSString *encResp = json[@"data"];
            if (!encResp.length) {
                completion(NO, 0, 0, @"No data in auth response."); return;
            }

            NSDictionary *respDict = SK_decryptBase64ToDict(encResp);
            if (!respDict) {
                completion(NO, 0, 0, @"Failed to decrypt auth response — possible MITM.");
                return;
            }

            NSTimeInterval echoedTS  = [respDict[@"timestamp"]     doubleValue];
            NSTimeInterval keyExpiry = [respDict[@"expiry"]        doubleValue];
            NSTimeInterval devExpiry = [respDict[@"device_expiry"] doubleValue];
            BOOL           success   = [respDict[@"success"]       boolValue];
            NSString      *message   = respDict[@"message"] ?: @"Unknown error";
            NSTimeInterval currentNow = [[NSDate date] timeIntervalSince1970];

            // --- replay + MITM guards ---
            if (llabs((long long)echoedTS - (long long)sendTS) > 0) {
                SK_clearSavedKey();
                completion(NO, 0, 0, @"Auth response timestamp mismatch — possible MITM.");
                return;
            }
            if (llabs((long long)SK_loadLastSentTS() - (long long)sendTS) > 0) {
                SK_clearSavedKey();
                completion(NO, 0, 0, @"Replay guard triggered — timestamp inconsistency.");
                return;
            }
            if (fabs(currentNow - echoedTS) > SK_MAX_TS_DRIFT) {
                SK_clearSavedKey();
                completion(NO, 0, 0, @"Auth response too old — possible replay attack.");
                return;
            }

            if (!success) {
                SK_clearSavedKey();
                completion(NO, 0, 0, message);
                return;
            }
            completion(YES, keyExpiry, devExpiry, message);
        });
    }] resume];
}
