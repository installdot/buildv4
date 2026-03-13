# SKFramework
**iOS 14+ · Theos/Logos · ARC · Objective-C**

A builder-style UI framework. Nothing is preset — you call methods to add
exactly what you want. One import, zero configuration required for just the UI.

---

## Files

| File | What it gives you |
|------|------------------|
| `SKTypes.h` | Color palette, layout constants, `SKSym()` / `SKSymView()` helpers |
| `SKButton.h` | `SKButton` — standalone button with SF Symbol |
| `SKSettingsMenu.h` | `SKSettingsMenu` — add toggles + button rows dynamically |
| `SKPanel.h` | `SKPanel` — draggable floating panel, add buttons/labels/dividers |
| `SKOverlays.h` | `SKProgressOverlay`, `SKAlert` helpers |
| `SKFramework.h` | **Umbrella** — import just this one file |

---

## Setup

```
YourTweak/
├── Makefile
├── Tweak.xm
├── SKFramework.h
├── SKTypes.h
├── SKButton.h
├── SKSettingsMenu.h
├── SKPanel.h
└── SKOverlays.h
```

```objc
// Tweak.xm
#import "SKFramework.h"
```

```makefile
# Makefile
MyTweak_FRAMEWORKS = UIKit Foundation Security
```

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
- Frameworks: `UIKit`, `Foundation`
