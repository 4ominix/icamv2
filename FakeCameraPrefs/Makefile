TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = FakeCameraPrefs
FakeCameraPrefs_FILES = FakeCameraPrefsRootListController.m
FakeCameraPrefs_FRAMEWORKS = UIKit MobileCoreServices AVFoundation Photos
FakeCameraPrefs_PRIVATE_FRAMEWORKS = Preferences
FakeCameraPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
