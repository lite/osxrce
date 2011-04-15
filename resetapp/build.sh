./configure --enable-cross-compile --cross-prefix=/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/ --cc=/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/arm-apple-darwin9-gcc-4.0.1 --prefix=/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS2.0.sdk/usr --extra-cflags="-isysroot /Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS2.0.sdk" --extra-ldflags="-isysroot /Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS2.0.sdk -Wl,-syslibroot /Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS2.0.sdk" --arch=armv6 --enable-armv6 --enable-gpl --enable-shared --disable-ipv6 --enable-swscale --enable-zlib --enable-bzlib --disable-ffmpeg --disable-ffplay --disable-ffserver --disable-vhook

make

make install

