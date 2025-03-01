ARCHS = arm64
TARGET = iphone:clang:latest:latest

TWEAK_NAME = DungeonShooter
DungeonShooter_FILES = Tweak.xm
FRAMEWORKS = Foundation UIKit Security CommonCrypto
LIBRARIES = crypto


include $(THEOS)/makefiles/common.mk
include $(THEOS)/makefiles/tweak.mk
