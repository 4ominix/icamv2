export THEOS_DEVICE_IP = 127.0.0.1
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:14.0

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FakeCameraWeat
FakeCameraWeat_FILES = Tweak.x
FakeCameraWeat_CFLAGS = -fobjc-arc
FakeCameraWeat_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += FakeCameraPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
