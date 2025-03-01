ARCHS = arm64
TARGET = iphone:clang:latest:latest

TWEAK_NAME = DungeonShooter
FRAMEWORKS = Tweak.xm
FRAMEWORKS = Foundation UIKit Security CommonCrypto

include $(THEOS)/makefiles/common.mk
include $(THEOS)/makefiles/tweak.mk
