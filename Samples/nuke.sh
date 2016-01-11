#!/bin/bash 

echo Cleaning out the project
rm -rf Pods && rm -rf PerchRTC.xcworkspace && pod install
