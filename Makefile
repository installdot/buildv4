include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DungeonShooter
DungeonShooter_FILES = Tweak.xm imgui_impl_ios.mm imgui.cpp imgui_draw.cpp imgui_widgets.cpp imgui_tables.cpp imgui_impl_opengl3.cpp
FRAMEWORKS = Foundation UIKit Security DeviceCheck UserNotifications OpenGLES GLKit
LIBRARIES = crypto
DungeonShooter_CFLAGS = -fobjc-arc -Wno-error
DungeonShooter_IPHONEOS_DEPLOYMENT_TARGET = 16.6.1
ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/tweak.mk
