#!/bin/bash
#killall -9 Wiiji
#sleep 2
# should I delete the kext too?
if [ -d /System/Library/Extensions/virtualhid.kext ]
then
	/sbin/kextload /System/Library/Extensions/virtualhid.kext
fi
