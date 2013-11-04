#!/bin/bash
/usr/bin/killall -9 Wiiji
/bin/sleep 1
# and if it is loaded
if [ -d /System/Library/Extensions/virtualhid.kext ]
then
	if /usr/sbin/kextstat | grep virtualhid
	then
		/sbin/kextunload /System/Library/Extensions/virtualhid.kext > /dev/null
	fi
fi
