// ============================================================
// UnitoreiosDebugBypass — Tweak.xm
//
// The key input alert shows up normally.
// Type ANY string → it will always validate as successful.
//
// HOW IT WORKS:
//   -decryptAESData:key:iv: is the single choke-point every
//   server response passes through (Cheack.php, Cheack2.php,
//   REQ.php).  We replace its output with a fake plaintext JSON
//   built from the device clock right now, so every check passes:
//     ✓ trangthaikey == "successfully"
//     ✓ timer == now  →  |diff| ≈ 0ms  →  ±5s gate passes
//     ✓ encypttimerkey == 99999999  →  ~3 years, never expires
//     ✓ data.statusUDID == 0        →  no UDID required
//
//   +paid: is also hooked so feature blocks run immediately
//   after the first successful "validation" without re-checking
//   the five internal flags.
//
//   detectDebugger() is neutralised so lldb can attach freely.
// ============================================================

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <substrate.h>

// ---- Fake server response builder ----
// Must match the date format the dylib parses: "yyyy-MM-dd HH:mm:ss"
static NSString *makeFakeServerJSON(void) {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *now = [fmt stringFromDate:[NSDate date]];   // device time = 0ms diff

    NSDictionary *payload = @{
        // --- Cheack.php / Cheack2.php shape ---
        @"trangthaikey"   : @"successfully",
        @"timer"          : now,
        @"encypttimerkey" : @(99999999),    // ~3 years remaining
        @"package_name"   : @"DEBUG MODE 🛠️",
        @"messenger"      : @"",
        // --- REQ.php shape ---
        @"data" : @{
            @"statusUDID" : @(0),           // 0 = no UDID required
            @"udid"       : @"",
            @"keyUDID"    : @""
        }
    };

    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    return [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
}

// ============================================================
%hook Unitoreios

// ------------------------------------------------------------------
// HOOK 1 — decryptAESData:key:iv:
//
// The key input alert shows, the user types anything, the dylib
// fires a real HTTP request, gets a real (or failed) response,
// then calls this to decrypt it.  We ignore the raw data entirely
// and hand back the fake success JSON.  The original validation
// logic continues unchanged — it just sees "successfully".
// ------------------------------------------------------------------
- (NSString *)decryptAESData:(NSData *)data key:(NSString *)key iv:(NSString *)iv {
    NSLog(@"[UnitoreiosDebug] decryptAESData → injecting fake success JSON");
    return makeFakeServerJSON();
}

// ------------------------------------------------------------------
// HOOK 2 — +paid:
//
// After validation, every protected feature calls:
//   [Unitoreios paid:^{ ... }];
// The original re-checks five in-memory flags each time.
// We execute the block directly so there's zero chance of a
// flag mismatch causing a false "failed" during debugging.
// ------------------------------------------------------------------
+ (void)paid:(void (^)(void))execute {
    NSLog(@"[UnitoreiosDebug] +paid: → executing block directly");
    if (execute) dispatch_async(dispatch_get_main_queue(), execute);
}

%end

// ------------------------------------------------------------------
// HOOK 3 — detectDebugger()  (C function via MSHookFunction)
//
// The original uses sysctl to detect P_TRACED and calls exit(0).
// Replace with a no-op so lldb / Xcode / frida can attach freely.
// ------------------------------------------------------------------
static void (*orig_detectDebugger)(void);
static void replaced_detectDebugger(void) {
    NSLog(@"[UnitoreiosDebug] detectDebugger() → no-op");
}

%ctor {
    MSHookFunction(
        (void *)MSFindSymbol(NULL, "_detectDebugger"),
        (void *)replaced_detectDebugger,
        (void **)&orig_detectDebugger
    );
    NSLog(@"[UnitoreiosDebug] ✅ loaded — type any key, it will always succeed");
}
