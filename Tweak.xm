// ============================================================
// UnitoreiosDebugBypass — Tweak.xm
//
// Hooks the Unitoreios license system so every validation
// call returns "success" instantly, without touching source.
//
// HOW IT WORKS:
//   All server responses pass through -decryptAESData:key:iv:
//   before the rest of the validation logic runs.
//   We hook that single method to return a hand-crafted
//   plaintext JSON that satisfies every check the dylib makes:
//     ✓ trangthaikey == "successfully"
//     ✓ timer == current device time  (±5s check always passes)
//     ✓ encypttimerkey > 0            (huge value → never expires)
//     ✓ statusUDID == 0               (REQ.php path: no UDID needed)
//
//   Additionally we hook:
//     -checkKey          → auto-injects a fake key so the alert
//                          never appears even on first launch
//     -canUseCachedSession       → always YES
//     -hasStrictValidatedKeySession → always YES
//     -isNetworkAvailable        → always YES (skip offline path)
// ============================================================

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ---- Shared fake key used across hooks ----
static NSString * const kDebugKey = @"bypass1ngaythoi";

// ---- Build the fake decrypted JSON string ----
// This one response satisfies BOTH endpoint shapes:
//   Cheack.php  → checks trangthaikey / timer / encypttimerkey
//   REQ.php     → checks data.statusUDID  (missing key → integerValue 0 = no UDID)
static NSString *makeFakeServerJSON(void) {
    // Match the exact date format the dylib uses: "yyyy-MM-dd HH:mm:ss"
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    // Use the local timezone that the server clock would use
    // (doesn't matter — the dylib compares device time to this value
    //  and we generate it from the device clock right now, so diff ≈ 0ms)
    NSString *now = [fmt stringFromDate:[NSDate date]];

    NSDictionary *payload = @{
        // ---------- Cheack.php shape ----------
        @"trangthaikey"   : @"successfully",   // ← exact string the dylib checks
        @"timer"          : now,               // ← current time → ±5s check always 0
        @"encypttimerkey" : @(99999999),        // ← ~3 years, countdown timer happy
        @"package_name"   : @"DEBUG MODE 🛠️",
        @"messenger"      : @"",

        // ---------- REQ.php shape (nested under "data") ----------
        // If data key is missing → statusUDID integerValue = 0 → no UDID required
        // We include it explicitly to be safe:
        @"data" : @{
            @"statusUDID" : @(0),   // 0 = package does NOT require UDID
            @"udid"       : @"",
            @"keyUDID"    : @""
        }
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload
                                                       options:0
                                                         error:nil];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}


%hook Unitoreios

// ------------------------------------------------------------------
// HOOK 1: decryptAESData:key:iv:
//
// Every server response (Cheack.php, Cheack2.php, REQ.php) is
// decrypted here before any logic runs.  Return our fake JSON
// instead — the rest of the original code runs unchanged.
// ------------------------------------------------------------------
- (NSString *)decryptAESData:(NSData *)data key:(NSString *)key iv:(NSString *)iv {
    NSString *fakeJSON = makeFakeServerJSON();
    NSLog(@"[UnitoreiosDebug] decryptAESData hooked → returning fake success JSON");
    return fakeJSON;
}

// ------------------------------------------------------------------
// HOOK 2: checkKey
//
// On first launch there is no savedKey, so the original code calls
// presentKeyInputAlert (60-second countdown dialog).
// We inject our fake key into NSUserDefaults before super runs,
// so checkKeyExistence: is called directly instead.
// ------------------------------------------------------------------
- (void)checkKey {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *saved = [ud objectForKey:@"savedKey"];
    if (!saved || saved.length == 0) {
        NSLog(@"[UnitoreiosDebug] checkKey: injecting fake savedKey");
        [ud setObject:kDebugKey forKey:@"savedKey"];
        [ud synchronize];
    }
    %orig;   // call original — it now sees a saved key and skips the alert
}

// ------------------------------------------------------------------
// HOOK 3: canUseCachedSession
//
// Returns YES so the offline early-exit path never blocks us,
// and the "use cached session" gate in checkKey stays open.
// ------------------------------------------------------------------
- (BOOL)canUseCachedSession {
    return YES;
}

// ------------------------------------------------------------------
// HOOK 4: hasStrictValidatedKeySession
//
// The "Liên hệ" (contact) button and several internal guards call
// this.  Returning YES keeps them all happy immediately.
// ------------------------------------------------------------------
- (BOOL)hasStrictValidatedKeySession {
    return YES;
}

// ------------------------------------------------------------------
// HOOK 5: isNetworkAvailable
//
// Always report network up so the offline-notice path is skipped
// and requests always fire (then get intercepted by hook 1).
// ------------------------------------------------------------------
- (BOOL)isNetworkAvailable {
    return YES;
}

%end


// ------------------------------------------------------------------
// HOOK 6: +paid: class method
//
// This is the gate every "protected" feature goes through:
//   [Unitoreios paid:^{ /* feature code */ }];
//
// We bypass all the internal flag checks and execute the block
// immediately, every time.
// ------------------------------------------------------------------
%hook Unitoreios

+ (void)paid:(void (^)(void))execute {
    NSLog(@"[UnitoreiosDebug] +paid: bypassed → executing directly");
    if (execute) {
        dispatch_async(dispatch_get_main_queue(), execute);
    }
}

%end


// ------------------------------------------------------------------
// HOOK 7: detectDebugger  (C function — use MSHookFunction)
//
// The original calls exit(0) if a debugger is attached.
// Replace the entire function with a no-op so lldb / Xcode works.
// ------------------------------------------------------------------
#import <substrate.h>

static void (*orig_detectDebugger)(void);
static void replaced_detectDebugger(void) {
    NSLog(@"[UnitoreiosDebug] detectDebugger() → no-op");
    // do nothing
}

%ctor {
    // Hook the C function by symbol name.
    // If the function is inlined or stripped, MSHookFunction
    // will silently fail — that's fine, the Logos hooks above
    // are what matter for key validation.
    MSHookFunction(
        (void *)MSFindSymbol(NULL, "_detectDebugger"),
        (void *)replaced_detectDebugger,
        (void **)&orig_detectDebugger
    );

    NSLog(@"[UnitoreiosDebug] ✅ Debug bypass loaded — all Unitoreios checks patched");
}
