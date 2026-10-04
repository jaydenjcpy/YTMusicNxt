ifeq ($(ROOTLESS),1)
THEOS_PACKAGE_SCHEME = rootless
else ifeq ($(ROOTHIDE),1)
THEOS_PACKAGE_SCHEME = roothide
endif

ARCHS = arm64
INSTALL_TARGET_PROCESSES = YouTubeMusic
TARGET = iphone:clang:16.5:13.0
PACKAGE_VERSION = 2.4.1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YTMusicUltimate
$(TWEAK_NAME)_FILES = $(filter-out Source/Sideloading.x, $(shell find Source \( -name '*.x' -o -name '*.xm' -o -name '*.m' \)))
# -fno-cxx-modules: theos unconditionally appends -fmodules -fcxx-modules, and
# cxx-module building is broken for the .xm (ObjC++) sources when theos' iOS 16.5
# SDK is compiled with a modern Xcode clang ("could not build module 'std'" /
# '_Builtin_intrinsics', cascading up into UIKit/Foundation/MediaPlayer). None of
# our ObjC++ sources actually use C++ modules, so dropping that one flag is enough.
# It has to be stripped from MODULESFLAGS (not added to CFLAGS) because theos puts
# MODULESFLAGS *after* the per-target CFLAGS, where a later -fcxx-modules wins.
MODULESFLAGS := $(filter-out -fcxx-modules,$(MODULESFLAGS))

$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -DTWEAK_VERSION=$(PACKAGE_VERSION)
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation AVFoundation AudioToolbox VideoToolbox
$(TWEAK_NAME)_OBJ_FILES = $(shell find Source/Utils/lib -name '*.a')
$(TWEAK_NAME)_LIBRARIES = bz2 c++ iconv z
ifeq ($(SIDELOADING),1)
$(TWEAK_NAME)_FILES += Source/Sideloading.x
endif

include $(THEOS_MAKE_PATH)/tweak.mk
