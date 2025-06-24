include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DungeonShooter
DungeonShooter_FILES = Tweak.xm
FRAMEWORKS = Foundation UIKit Security CommonCrypto AVFoundation MediaPlayer WebKit QuartzCore IOKit
LIBRARIES = crypto
DungeonShooter_CFLAGS = -fobjc-arc -Wno-error
DungeonShooter_IPHONEOS_DEPLOYMENT_TARGET = 16.6.1
ARCHS = arm64
TARGET = iphone:clang:latest:16.6.1

include $(THEOS)/makefiles/tweak.mk
