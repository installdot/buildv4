// SKFramework.h — Umbrella import
// Import this single file to get the entire framework.
//
// Import order matters — do NOT reorder these.

#pragma once

// ── Layer 1: Crypto + Keychain ──────────────────────────────────────────────
#import "SKCrypto.h"      // AES-256-CBC, HMAC-SHA256, Keychain, device UUID

// ── Layer 2: Auth + Network + Settings ─────────────────────────────────────
#import "SKAuth.h"        // performKeyAuth, session, NSURLSession, multipart POST

// ── Layer 3: UI ─────────────────────────────────────────────────────────────
#import "SKTypes.h"       // Color palette, layout constants, SF Symbol helpers
#import "SKButton.h"      // SKButton builder
#import "SKSettingsMenu.h"// SKSettingsMenu dynamic toggle/button menu
#import "SKPanel.h"       // SKPanel draggable floating panel
#import "SKOverlays.h"    // SKProgressOverlay, SKAlert
