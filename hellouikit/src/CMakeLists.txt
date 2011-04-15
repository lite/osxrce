PROJECT(ihello)
set(NAME ihello) 
CMAKE_MINIMUM_REQUIRED(VERSION 2.6)

# SET(GCC_THUMB_SUPPORT NO)
SET(IPHONE_SDKVER "4.3")

#set either the device sdk or the simulator sdk. Can't find away to separate these in the same project
# SET(IPHONE_DEVROOT "/Developer/Platforms/iPhoneOS.platform/Developer")
# SET(IPHONE_SDKROOT "${IPHONE_DEVROOT}/SDKs/iPhoneOS${IPHONE_SDKVER}.sdk")
SET(IPHONE_DEVROOT "/Developer/Platforms/iPhoneSimulator.platform/Developer")
SET(IPHONE_SDKROOT "${IPHONE_DEVROOT}/SDKs/iPhoneSimulator${IPHONE_SDKVER}.sdk")

#set iphone arch and flags taken from http://sites.google.com/site/michaelsafyan/coding/resources/how-to-guides/cross-compile-for-the-iphone/how-to-cross-compile-for-the-iphone-using-cmake
# SET(CMAKE_CXX_COMPILER "${IPHONE_DEVROOT}/usr/bin/arm-apple-darwin-g++") 
# SET(CMAKE_C_COMPILER "${IPHONE_DEVROOT}/usr/bin/arm-apple-darwin-gcc") 
# SET(CMAKE_OSX_ARCHITECTURES "armv6;armv7")
# SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -miphoneos-version-min=3.1 -mno-thumb -arch armv6 -pipe -no-cpp-precomp")

#simulator uses i386 architectures
# SET(CMAKE_OSX_ARCHITECTURES "i386")

##
SET(CMAKE_CXX_COMPILER "${IPHONE_DEVROOT}/usr/bin/llvm-g++") 
SET(CMAKE_C_COMPILER "${IPHONE_DEVROOT}/usr/bin/llvm-gcc") 

SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -I${IPHONE_DEVROOT}/usr/include")
SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -I${IPHONE_SDKROOT}/usr/include")
SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c99 -W -Wall -arch i386 -pipe -no-cpp-precomp")
SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O0 -g -DDEBUG_MUTEX")
# SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}  "-O3 -DNDEBUG")

#here we set the specific iphone sdk version. We can only set either device or simulator sdk. So if you want both you currently have to have two seperate projects
SET(CMAKE_OSX_SYSROOT "${IPHONE_SDKROOT}")

#hack, force link to opengles
SET(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -F${IPHONE_SDKROOT}/System/Library/Frameworks -F${IPHONE_SDKROOT}/System/Library/PrivateFrameworks")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -lobjc -framework Foundation -framework UIKit -framework CoreFoundation")

file(GLOB headers *.h)
file(GLOB sources *.m)

set(MACOSX_BUNDLE_GUI_IDENTIFIER "com.mycompany.\${PRODUCT_NAME:identifier}")
set(APP_TYPE MACOSX_BUNDLE)

add_executable(${NAME} 
    ${APP_TYPE}
    ${headers}
    ${sources}
)

# code signing
set_target_properties(${NAME} PROPERTIES XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "iPhone Developer: My Name")

# copy resource phase 
set(APP_NAME \${TARGET_BUILD_DIR}/\${FULL_PRODUCT_NAME}) 
set(RES_DIR ${test_SOURCE_DIR}/data) 
add_custom_command( 
    TARGET ${NAME} 
    POST_BUILD 
    COMMAND /Developer/Library/PrivateFrameworks/DevToolsCore.framework/Resources/pbxcp -exclude .DS_Store -exclude CVS -exclude .svn -resolve-src-symlinks ${RES_DIR} ${APP_NAME} 
)