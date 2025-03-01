ARCHS = arm64
TARGET = iphone:clang:latest:latest

TWEAK_NAME = DungeonShooter
DungeonShooter_FILES = Tweak.xm
DungeonShooter_FRAMEWORKS = UIKit Foundation CommonCrypto

include $(THEOS)/makefiles/common.mk
include $(THEOS)/makefiles/tweak.mk
