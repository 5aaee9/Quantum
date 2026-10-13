#!/usr/bin/env bash

CONSOLE=ttyS0
if [ "$(dpkg --print-architecture)" = arm64 ]; then
  CONSOLE=ttyAMA0
fi
sed -i "s#GRUB_CMDLINE_LINUX_DEFAULT=.*#GRUB_CMDLINE_LINUX_DEFAULT=\"net.ifnames=0 console=tty0 console=${CONSOLE},115200 consoleblank=0\"#g" /etc/default/grub
echo GRUB_RECORDFAIL_TIMEOUT=3 >> /etc/default/grub

update-grub
