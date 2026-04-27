include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Bypass
Bypass_FILES = Tweak.xm 
Bypass_LOAD_PRIORITY  = 1
FRAMEWORKS = Network Foundation UIKit Security DeviceCheck UserNotifications OpenGLES GLKit AVFoundation
LIBRARIES = crypto
Bypass_CFLAGS = -fobjc-arc -Wunused-variable -Wno-error -Wno-deprecated-declarations -Werror -Wno-unused-but-set-variable
Bypass_IPHONEOS_DEPLOYMENT_TARGET = 16.6.1
ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/tweak.mk
