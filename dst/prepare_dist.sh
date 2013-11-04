#!/bin/bash
sudo rm -rf ./dstResources/Wiiji.app ./dstResources/virtualhid.kext
sudo cp -R ../../VirtualHID/build/Release/virtualhid.kext ./dstResources
sudo cp -R ../../Wiiji/build/Release/Wiiji.app ./dstResources
sudo chown -R root:admin ./dstResources/Wiiji.app
sudo chown -R root:wheel ./dstResources/virtualhid.kext 
sudo chmod -R 775 ./dstResources/Wiiji.app
sudo chmod -R 755 ./dstResources/virtualhid.kext 
