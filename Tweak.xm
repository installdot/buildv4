Run TWEAK_xm_PATH="./Tweak.xm"
Building tweak with Tweak.xm in directory: .
==> Cleaning…
==> Notice: Build may be slow as Theos isn’t using all available CPU cores on this computer. Consider upgrading GNU Make: https://theos.dev/docs/parallel-building
==> Warning: Building for iOS 7.0, but the current toolchain can’t produce arm64e binaries for iOS earlier than 14.0. More information: https://theos.dev/docs/arm64e-deployment
> Making all for tweak Bypass…
==> Preprocessing Tweak.xm…
==> Compiling Tweak.xm (arm64)…
Tweak.xm:461:17: error: redefinition of 's_BotClosestIdx'
  461 | static int      s_BotClosestIdx      = -1;
      |                 ^
Tweak.xm:146:14: note: previous definition is here
  146 | static int   s_BotClosestIdx     = -1;
      |              ^
Tweak.xm:462:17: error: redefinition of 's_BotDrifting'
  462 | static BOOL     s_BotDrifting        = NO;
      |                 ^
Tweak.xm:147:14: note: previous definition is here
  147 | static BOOL  s_BotDrifting       = NO;
      |              ^
Tweak.xm:463:17: error: redefinition of 's_BotDriftDir'
  463 | static int      s_BotDriftDir        = 0;   
      |                 ^
Tweak.xm:148:14: note: previous definition is here
  148 | static int   s_BotDriftDir       = 0;
      |              ^
3 errors generated.
make[3]: *** [/Users/runner/work/buildv4/buildv4/.theos/obj/debug/arm64/Tweak.xm.288724e5.o] Error 1
rm /Users/runner/work/buildv4/buildv4/.theos/obj/debug/arm64/Tweak.xm.mm
make[2]: *** [/Users/runner/work/buildv4/buildv4/.theos/obj/debug/arm64/Bypass.dylib] Error 2
make[1]: *** [internal-library-all_] Error 2
make: *** [Bypass.all.tweak.variables] Error 2
Error: Process completed with exit code 2.
