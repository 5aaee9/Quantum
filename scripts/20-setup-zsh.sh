#!/usr/bin/env bash

set -ex

chsh -s /usr/bin/zsh
echo "" | sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

export ZSH_CUSTOM=/root/.zsh/custom
git clone https://github.com/denysdovhan/spaceship-prompt.git "$ZSH_CUSTOM/themes/spaceship-prompt" --depth=1

ln -s "$ZSH_CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" "$ZSH_CUSTOM/themes/spaceship.zsh-theme"
sed -i "s/^ZSH_THEME=.*/ZSH_THEME=\"spaceship\"/g" /root/.zshrc
