#!/bin/bash 
xcodebuild -sdk iphonesimulator4.3 -target Hello\ World
/usr/local/bin/ios-sim launch build/Release-iphonesimulator/Hello\ World.app

