include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Bypass
Bypass_FILES = Tweak.xm
Bypass_LOAD_PRIORITY  = 1
Bypass_FRAMEWORKS = Foundation Security
Bypass_PRIVATE_FRAMEWORKS = CydiaSubstrate
Bypass_LIBRARIES = substrate
INSTALL_TARGET_PROCESSES := UnityFramework
Bypass_CFLAGS = -fobjc-arc -std=c++17 -Wunused-variable -Wno-error -Wno-deprecated-declarations -Werror -Wno-unused-but-set-variable
Bypass_IPHONEOS_DEPLOYMENT_TARGET = 16.6.1
ARCHS = arm64
TARGET = iphone:clang:latest:14.0
Bypass_LDFLAGS = -undefined dynamic_lookup
include $(THEOS)/makefiles/tweak.mk
