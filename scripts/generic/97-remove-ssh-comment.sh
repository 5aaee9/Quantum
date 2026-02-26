#!/usr/bin/env bash

set -ex

# 傻逼魔方云
sed -i -E "/^(#.*)$/d" /etc/ssh/sshd_config
