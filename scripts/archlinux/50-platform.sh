#!/usr/bin/env bash

set -ex

sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="net.ifnames=0 console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 consoleblank=0"/' /etc/default/grub
if ! grep -q '^GRUB_RECORDFAIL_TIMEOUT=3$' /etc/default/grub; then
  echo 'GRUB_RECORDFAIL_TIMEOUT=3' >> /etc/default/grub
fi

grub-mkconfig -o /boot/grub/grub.cfg
