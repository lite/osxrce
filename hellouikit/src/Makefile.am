## SDK
SDKVER    = 4.3

## iPhone SDK
IPHONESDK = /Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS$(SDKVER).sdk

# /Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS4.3.sdk/usr/bin/arm-apple-darwin10-

PREFIX  = $(IPHONESDK)/usr/bin/arm-apple-darwin10-

###/////////////////////////////////////////////////////////////
###                      Executable files
###/////////////////////////////////////////////////////////////

CC      = $(PREFIX)gcc
CXX     = $(PREFIX)g++
LD      = $(CC)
AR      = $(PREFIX)ar
STRIP   = $(PREFIX)strip
OBJCOPY = $(PREFIX)objcopy

####################################################################################

##
INCPATH = 
INCPATH += -I"$(IPHONESDK)/usr/include"
INCPATH += -I"/Developer/Platforms/iPhoneOS.platform/Developer/usr/lib/gcc/arm-apple-darwin10/4.2/include/"
INCPATH += -I"/Developer/Platforms/iPhoneOS.platform/Developer/usr/include/"
INCPATH += -I"/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator$(SDKVER).sdk/usr/include"

##
AM_LDFLAGS =
AM_LDFLAGS += -lobjc \
            -bind_at_load \
            -multiply_defined suppress \
            -w

AM_LDFLAGS += -framework CoreFoundation
AM_LDFLAGS += -framework Foundation
AM_LDFLAGS += -framework UIKit
AM_LDFLAGS += -framework CoreGraphics
#AM_LDFLAGS += -framework AddressBookUI
#AM_LDFLAGS += -framework AddressBook
#AM_LDFLAGS += -framework QuartzCore
#AM_LDFLAGS += -framework GraphicsServices
#AM_LDFLAGS += -framework CoreSurface
#AM_LDFLAGS += -framework CoreAudio
#AM_LDFLAGS += -framework Celestial
#AM_LDFLAGS += -framework AudioToolbox
#AM_LDFLAGS += -framework WebCore
#AM_LDFLAGS += -framework WebKit
#AM_LDFLAGS += -framework SystemConfiguration
#AM_LDFLAGS += -framework CFNetwork
#AM_LDFLAGS += -framework MediaPlayer
#AM_LDFLAGS += -framework OpenGLES
#AM_LDFLAGS += -framework OpenAL

AM_LDFLAGS += -F"$(IPHONESDK)/System/Library/Frameworks"
AM_LDFLAGS += -F"$(IPHONESDK)/System/Library/PrivateFrameworks"

## 
AM_CFLAGS =
AM_CFLAGS  += $(INCPATH) \
        -std=c99 \
        -W -Wall \
        -funroll-loops \
        -Diphoneos_version_min=2.0 \
        -Wno-unused-parameter \
        -Wno-sign-compare

AM_CFLAGS  += -O0 -g -DDEBUG_MUTEX
# AM_CFLAGS  += -O3 -DNDEBUG

AM_CFLAGS += -F"$(IPHONESDK)/System/Library/Frameworks"
AM_CFLAGS += -F"$(IPHONESDK)/System/Library/PrivateFrameworks"

bin_PROGRAMS = ihello

ihello_SOURCES = SampleApp.m mainapp.m
ihello_CFLAGS = $(AM_CFLAGS)
ihello_LDFLAGS = $(AM_LDFLAGS)

