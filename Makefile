# Theos makefile for building the DungeonShooter tweak

SDKVERSION = 17.5
TARGET = iphone:clang:latest:latest

# Name of the tweak
TWEAK_NAME = DungeonShooter
DungeonShooter_FILES = Tweak.xm

# Frameworks to link
FRAMEWORKS = Foundation UIKit Security CommonCrypto

# Architecture for the tweak
ARCHS = arm64

# Include the common makefiles from Theos
include $(THEOS)/makefiles/common.mk

# Define clean rule (make sure we can clean previous builds)
clean::
	@echo "Cleaning build files..."
	@rm -rf $(THEOS_OBJ_DIR)
	@rm -rf $(THEOS_BUILD_DIR)
