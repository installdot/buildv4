# SKFramework
**iOS 14+ · Theos/Logos · ARC · Objective-C**

A builder-style UI framework. Nothing is preset — you call methods to add
exactly what you want. One import, zero configuration required for just the UI.

---

## Files

| File | Layer | What it gives you |
|------|-------|------------------|
| `SKFramework.h` | Umbrella | **Import just this one file** |
| `SKCrypto.h` | 1 — Crypto | AES-256-CBC encrypt/decrypt, HMAC-SHA256, Keychain read/write, persistent device UUID, replay-guard timestamps |
| `SKAuth.h` | 2 — Network | `SK_performKeyAuth()`, session UUID, settings flags, `SK_post()`, multipart builder, device info |
| `SKTypes.h` | 3 — UI | Color palette, layout constants, `SKSym()` / `SKSymView()` helpers |
| `SKButton.h` | 3 — UI | `SKButton` — standalone button with SF Symbol |
| `SKSettingsMenu.h` | 3 — UI | `SKSettingsMenu` — add toggles + button rows dynamically |
| `SKPanel.h` | 3 — UI | `SKPanel` — draggable floating panel, add buttons/labels/dividers |
| `SKOverlays.h` | 3 — UI | `SKProgressOverlay`, `SKAlert` helpers |

---

## Setup

```
YourTweak/
├── Makefile
├── Tweak.xm
├── SKFramework.h      ← drop all these in
├── SKCrypto.h
├── SKAuth.h
├── SKTypes.h
├── SKButton.h
├── SKSettingsMenu.h
├── SKPanel.h
└── SKOverlays.h
```

```objc
// Tweak.xm — one import, that's it
#import "SKFramework.h"
```

```makefile
# Makefile — Security needed for Keychain + CommonCrypto
MyTweak_FRAMEWORKS = UIKit Foundation Security
```

### Required configuration before building

Open **`SKCrypto.h`** and replace both placeholder key strings with your own 64-character hex secrets:

```objc
static NSString *authAESKeyHex(void) {
    return @"YOUR_64_HEX_CHAR_AES_KEY_HERE";   // 32 bytes = 64 hex chars
}
static NSString *authHMACKeyHex(void) {
    return @"YOUR_64_HEX_CHAR_HMAC_KEY_HERE";  // must be different from AES key
}
```

Open **`SKAuth.h`** and point both URLs at your server:

```objc
#define SK_API_BASE   @"https://your-server.com/api.php"    // upload / load
#define SK_AUTH_BASE  @"https://your-server.com/auth.php"   // key validation
```

> If you are only using the UI components (panel, settings, buttons) and **not** the auth/crypto system, you can skip this step entirely — the UI headers have no dependency on these values.

---

## SKCrypto — Encryption & Keychain

### Encrypt / Decrypt a payload

```objc
NSData *aesKey  = SK_dataFromHexString(authAESKeyHex());
NSData *hmacKey = SK_dataFromHexString(authHMACKeyHex());

// Encrypt any NSData → IV (16) + ciphertext + HMAC-SHA256 (32) blob
NSData *box   = SK_encryptBox(plainData, aesKey, hmacKey);

// Decrypt + verify HMAC in one call. Returns nil if tampered.
NSData *plain = SK_decryptBox(box, aesKey, hmacKey);
```

### Encrypt a dictionary as a Base64 string (used for auth requests)

```objc
NSDictionary *payload = @{
    @"key"       : @"ABCD-1234-EFGH-5678",
    @"timestamp" : @((long long)[[NSDate date] timeIntervalSince1970]),
    @"device_id" : SK_persistentDeviceID(),
};

NSString *base64 = SK_encryptPayloadToBase64(payload);  // ready to POST
// Decrypt the server's encrypted response:
NSDictionary *response = SK_decryptBase64ToDict(serverBase64String);
```

### Keychain — save / load / clear the auth key

```objc
// Save after successful auth
SK_saveSavedKey(@"ABCD-1234-EFGH-5678");

// Load on next launch — returns nil if nothing saved
NSString *savedKey = SK_loadSavedKey();

// Clear on failure / logout
SK_clearSavedKey();
```

### Persistent device UUID (survives app reinstalls)

```objc
// Generated once, stored in Keychain forever
NSString *deviceID = SK_persistentDeviceID();
```

---

## SKAuth — Key Authentication

### Validate a key against your server

```objc
SK_performKeyAuth(@"ABCD-1234-EFGH-5678", ^(BOOL ok,
                                              NSTimeInterval keyExpiry,
                                              NSTimeInterval deviceExpiry,
                                              NSString *errorMsg) {
    if (ok) {
        // Store expiry globals for the panel countdown timer
        gSKKeyExpiry    = keyExpiry;
        gSKDeviceExpiry = deviceExpiry;
        SK_saveDeviceExpiryLocally(deviceExpiry);

        // Show your panel
        showMainPanel(root);
    } else {
        // errorMsg explains why (expired, wrong device, MITM detected, etc.)
        SK_clearSavedKey();
        NSLog(@"Auth failed: %@", errorMsg);
    }
});
```

`SK_performKeyAuth` handles everything internally:
- Encrypts the payload with AES-256-CBC + HMAC-SHA256
- POSTs `{ "data": "<base64>" }` to `SK_AUTH_BASE`
- Decrypts and verifies the server's encrypted response
- Checks echoed timestamp against what was sent (MITM guard)
- Checks the replay-guard file (prevents replayed responses)
- Rejects responses older than `SK_MAX_TS_DRIFT` seconds (default 60)

### Session management

```objc
// Save the cloud session UUID after a successful upload
SK_saveSessionUUID(uuid);

// Load it before a download/load operation
NSString *uuid = SK_loadSessionUUID();  // nil if none

// Clear after a successful load (prevents re-use)
SK_clearSessionUUID();
```

### Settings flags (NSUserDefaults-backed)

```objc
// Write a default once at startup
SK_initDefaultSettings();   // sets autoRij = YES if not already set

// Read / write any boolean flag
BOOL shouldClose = SK_getSetting(@"autoClose");
SK_setSetting(@"autoRij", YES);
```

### Generic POST helper

```objc
// Build a multipart/form-data request
SKMPRequest mp = SK_buildMP(
    @{ @"action": @"upload", @"uuid": uuid, @"playerpref": plistXML },
    @"datafile",      // file field name (nil to skip)
    @"game.data",     // filename hint
    fileData          // NSData (nil to skip)
);

// Fire it
NSURLSession *ses = SK_makeSession();
SK_post(ses, mp.req, mp.body, ^(NSDictionary *json, NSError *err) {
    if (err) { NSLog(@"failed: %@", err.localizedDescription); return; }
    NSString *link = json[@"link"];
    NSLog(@"uploaded: %@", link);
});
```

### Full auth + panel injection pattern

```objc
static void injectPanel(UIView *root, UIWindow *win) {
    NSString *savedKey = SK_loadSavedKey();

    if (savedKey.length) {
        // Re-validate saved key silently on every launch
        SK_performKeyAuth(savedKey, ^(BOOL ok, NSTimeInterval ke,
                                      NSTimeInterval de, NSString *err) {
            if (ok) {
                gSKKeyExpiry    = ke;
                gSKDeviceExpiry = de;
                SK_saveDeviceExpiryLocally(de);
                buildAndShowPanel(root);
            } else {
                SK_clearSavedKey();
                // Prompt for a new key
                UIViewController *vc = win.rootViewController;
                while (vc.presentedViewController) vc = vc.presentedViewController;
                UIAlertController *alert = [UIAlertController
                    alertControllerWithTitle:@"Key Invalid"
                                     message:err ?: @"Please enter a valid key."
                              preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Enter Key"
                    style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                        // Show your key entry UI here
                    }]];
                [alert addAction:[UIAlertAction actionWithTitle:@"Exit"
                    style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
                        exit(0);
                    }]];
                [vc presentViewController:alert animated:YES completion:nil];
            }
        });
    } else {
        // No saved key — show key entry UI straight away
        // (implement your own key-entry view or use SKKeyAuthOverlay from v1)
    }
}
```

### Security summary

| Threat | How SKFramework handles it |
|--------|---------------------------|
| Network eavesdropping | AES-256-CBC + HMAC-SHA256 on every auth payload |
| Response tampering (MITM) | Server echoes the exact timestamp sent; HMAC failure = reject |
| Replay attacks | Sent timestamp saved to disk; echoed value must match exactly |
| Clock drift | `SK_MAX_TS_DRIFT` (default 60 s) tolerance window |
| Key reuse across devices | Device UUID baked into payload; server enforces per-device slots |
| Keychain theft across installs | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` + `kSecAttrSynchronizable:NO` |

---

## SKPanel — Build a floating panel

```objc
SKPanel *panel = [SKPanel new];
panel.panelTitle = @"My Tool";           // bar title
panel.panelWidth = 260;                  // optional, default 258

// ── Add full-width buttons ──
[panel addButton:@"Upload"
          symbol:@"icloud.and.arrow.up"
           color:SKColorBlue()
          action:^{
    NSLog(@"upload tapped");
}];

[panel addButton:@"Load"
          symbol:@"icloud.and.arrow.down"
           color:SKColorGreen()
          action:^{
    NSLog(@"load tapped");
}];

// ── Add a divider ──
[panel addDivider];

// ── Add a row of small side-by-side buttons ──
[panel addSmallButtonsRow:@[
    [SKButton buttonWithTitle:@"Settings"
                       symbol:@"gearshape"
                        color:SKColorGray()
                       action:^{ /* open menu */ }],
    [SKButton buttonWithTitle:@"Hide"
                       symbol:@"eye.slash"
                        color:SKColorRed()
                       action:^{ [panel hide]; }],
]];

// ── Add info labels ──
SKPanelLabel *statusLabel = [panel addLabel:@"status" text:@"No session"];
SKPanelLabel *uidLabel    = [panel addLabel:@"uid"    text:@""];

// ── Show ──
[panel showInView:rootView];

// ── Update a label later ──
[panel setLabelText:@"Session: abc123…" forKey:@"status"];
```

---

## SKSettingsMenu — Build a settings card

```objc
SKSettingsMenu *menu = [SKSettingsMenu new];
menu.menuTitle  = @"Options";
menu.footerText = @"MyTweak v1.0";

// ── Section header (optional) ──
[menu addSectionHeader:@"Behaviour"];

// ── Toggle rows ──
// Value is auto-read/written from NSUserDefaults using the key.

[menu addToggle:@"autoClose"
          title:@"Auto Close"
    description:@"Exit the app automatically after loading from cloud."
         symbol:@"power"
    defaultValue:NO
        onChange:^(BOOL on) {
    NSLog(@"autoClose is now %d", on);
}];

[menu addToggle:@"autoRij"
          title:@"Auto Rij"
    description:@"Patches OpenRijTest_ flags to 0 before uploading."
         symbol:@"wand.and.stars"
    defaultValue:YES
        onChange:nil];    // nil = just persist, no extra callback

// ── Section header ──
[menu addSectionHeader:@"Account"];

// ── Button rows (non-toggle action buttons inside the settings card) ──
[menu addButtonRow:@"clearData"
             title:@"Clear Saved Data"
            symbol:@"trash"
             color:SKColorRed()
            action:^{
    NSLog(@"clear tapped");
}];

// ── Read / write values programmatically ──
BOOL shouldClose = [menu boolForKey:@"autoClose"];
[menu setBool:YES forKey:@"autoRij"];    // also flips the UISwitch visually

// ── Show (call after all rows have been added) ──
[menu showInView:rootView];

// ── Spotlight a specific row (e.g. for a tutorial) ──
UIView *rijRow = [menu rowViewForKey:@"autoRij"];
```

### Wiring the panel Settings button to a menu

```objc
SKSettingsMenu *menu = [SKSettingsMenu new];
// … add toggles …

// addSettingsButton: creates the button AND wires it to show the menu
[panel addSettingsButton:@"Settings" menu:menu];
```

---

## SKButton — Standalone button

```objc
// Create
SKButton *btn = [SKButton buttonWithTitle:@"Upload"
                                   symbol:@"icloud.and.arrow.up"
                                    color:SKColorBlue()
                                   action:^{ NSLog(@"upload"); }];

// Add to any view at a specific frame
btn.view.frame = CGRectMake(20, 100, 220, 44);
[self.view addSubview:btn.view];

// Disable at runtime
btn.disabled = YES;

// Change label at runtime and refresh
btn.title = @"Uploading…";
btn.color = SKColorGray();
[btn refresh];
```

---

## SKProgressOverlay — Animated progress card

```objc
// Show
SKProgressOverlay *ov = [SKProgressOverlay showInView:rootView title:@"Uploading…"];

// Update during work
[ov setProgress:0.3 label:@"30%"];
[ov appendLog:@"Reading PlayerPrefs…"];
[ov appendLog:@"Uploading game.data (12,400 chars)"];
[ov setProgress:0.9 label:@"90%"];

// Finish — shows Close button; non-empty link shows "Open Link in Browser"
[ov finish:YES message:@"Upload complete." link:@"https://your-server.com/view/abc"];
[ov finish:NO  message:@"Network error."   link:nil];
```

---

## SKAlert — Quick alert helpers

```objc
// Simple OK alert
[SKAlert showTitle:@"No Session" message:@"Upload first."];

// Destructive confirmation
[SKAlert showConfirmTitle:@"Reset Data"
                  message:@"This will wipe all saved data."
             confirmTitle:@"Reset"
                onConfirm:^{
    // user confirmed
}];
```

---

## Color palette

| Function | Color | Typical use |
|----------|-------|-------------|
| `SKColorBlue()` | #2485EB | Upload / action |
| `SKColorGreen()` | #2EB36B | Load / confirm |
| `SKColorRed()` | #BF2D2D | Destructive / error |
| `SKColorGray()` | #38384C | Secondary / settings |
| `SKColorAmber()` | #D9B233 | Warnings / expiry |
| `SKColorAccent()` | #59E58D | Status text, switch tint |
| `SKColorBackground()` | near-black | Card backgrounds |
| `SKColorRowBg()` | dark grey | Settings row background |

---

## SF Symbol helpers

```objc
// UIImage
UIImage *img = SKSym(@"icloud.and.arrow.up", 20);

// UIImageView (auto-layout ready, tinted)
UIImageView *v = SKSymView(@"checkmark.circle", 18, SKColorGreen());
```

---

## Full example tweak

```objc
#import "SKFramework.h"

static SKPanel         *gPanel = nil;
static SKSettingsMenu  *gMenu  = nil;

static void buildAndShowPanel(UIView *root) {
    if (gPanel) return;

    // ── 1. Settings menu ──────────────────────────────────────────────────────
    gMenu = [SKSettingsMenu new];
    gMenu.menuTitle  = @"MyTweak Settings";
    gMenu.footerText = @"MyTweak v1.0";

    [gMenu addToggle:@"autoClose"
               title:@"Auto Close"
         description:@"Exit app after loading."
              symbol:@"power"
         defaultValue:NO
             onChange:nil];

    [gMenu addToggle:@"autoRij"
               title:@"Auto Rij"
         description:@"Set all OpenRijTest_ flags to 0."
              symbol:@"wand.and.stars"
         defaultValue:YES
             onChange:nil];

    [gMenu addSectionHeader:@"Danger Zone"];
    [gMenu addButtonRow:@"resetAll"
                  title:@"Reset All Settings"
                 symbol:@"trash"
                  color:SKColorRed()
                 action:^{
        [SKAlert showConfirmTitle:@"Reset?" message:@"This cannot be undone."
              confirmTitle:@"Reset" onConfirm:^{
            NSLog(@"reset!");
        }];
    }];

    // ── 2. Panel ──────────────────────────────────────────────────────────────
    gPanel = [SKPanel new];
    gPanel.panelTitle = @"MyTweak";

    // Status info label
    [gPanel addLabel:@"status" text:@"Ready"];

    [gPanel addButton:@"Upload Save"
               symbol:@"icloud.and.arrow.up"
                color:SKColorBlue()
               action:^{
        SKProgressOverlay *ov = [SKProgressOverlay showInView:root title:@"Uploading…"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
            [ov finish:YES message:@"Done!" link:@"https://example.com/view/abc"];
            [gPanel setLabelText:@"Uploaded" forKey:@"status"];
        });
    }];

    [gPanel addButton:@"Load Save"
               symbol:@"icloud.and.arrow.down"
                color:SKColorGreen()
               action:^{
        NSLog(@"load");
    }];

    [gPanel addDivider];

    // Settings button wired directly to menu
    [gPanel addSettingsButton:@"Settings" menu:gMenu];

    // Hide button alongside settings
    [gPanel addSmallButtonsRow:@[
        [SKButton buttonWithTitle:@"Hide" symbol:@"eye.slash"
                            color:SKColorRed() action:^{ [gPanel hide]; }],
    ]];

    [gPanel showInView:root];
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                UIWindow *win = nil;
                for (UIWindow *w in UIApplication.sharedApplication.windows)
                    if (!w.isHidden && w.alpha > 0) { win = w; break; }
                if (!win) return;
                buildAndShowPanel(win.rootViewController.view ?: win);
            });
    });
}
%end
```

---

## Requirements

- iOS 14+ (SF Symbols require iOS 13+)
- Theos with Logos preprocessor
- ARC enabled (`-fobjc-arc`)
- Frameworks: `UIKit`, `Foundation`, `Security`, `CommonCrypto` (implicit on iOS)
