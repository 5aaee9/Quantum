#!/usr/bin/env bash

set -ex

# 傻逼魔方云
chattr +i /etc/ssh/sshd_config

cat > /usr/local/after-cloud-init-scripts <<EOF
#!/usr/bin/env bash

set -ex

# fix idcsmart modify sshd config
chattr -i /etc/ssh/sshd_config
EOF

chmod +x /usr/local/after-cloud-init-scripts

cat > /etc/systemd/system/after-cloud-init.service <<EOF
[Unit]
After=cloud-init.target
DefaultDependencies=no
AssertFileIsExecutable=/usr/local/after-cloud-init-scripts

[Service]
Type=simple
ExecStart=/usr/local/after-cloud-init-scripts
SuccessExitStatus=0

[Install]
WantedBy=default.target
EOF

systemctl enable after-cloud-init.service