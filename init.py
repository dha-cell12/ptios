import os
import spur

ip_addr = "192.168.0.19"


#os.system("cp -r /Users/jason/Library/Developer/Xcode/DerivedData/TLinkauto-hbsjteiysuzetgbhemilfxatkcdd/Build/Products/Debug-iphoneos/TLinkauto.app /Users/jason/Code/ioscontrol/TLinkauto-xcode-install/Applications/")
os.system("codesign --entitlements /Users/jason/Code/ioscontrol/TLinkauto-xcode-install/entitlements.plist -f -s \"Apple Development: jiz176@pitt.edu (L8FGNSF6R4)\" /Users/jason/Code/ioscontrol/layout/Applications/TLinkauto.app")

'''
os.system("dpkg-deb -Zgzip -b /Users/jason/Code/ioscontrol/TLinkauto-xcode-install/")

os.system("scp /Users/jason/Code/ioscontrol/TLinkauto-xcode-install.deb root@" + ip_addr + ":/TLinkauto.deb")


# install on ios devices
print("start installing")
shell = spur.SshShell(hostname=ip_addr, username="root", password="xuan32546")
result = shell.run(["dpkg", "-i", "/TLinkauto.deb"])
result = shell.run(["killall", "TLinkauto"])
'''
