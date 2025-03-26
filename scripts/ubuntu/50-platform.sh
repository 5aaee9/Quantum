#!/usr/bin/env bash

sed -i 's#GRUB_CMDLINE_LINUX_DEFAULT=.*#GRUB_CMDLINE_LINUX_DEFAULT="net.ifnames=0 console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 consoleblank=0"#g' /etc/default/grub
echo GRUB_RECORDFAIL_TIMEOUT=3 >> /etc/default/grub

update-grub
