#!/usr/bin/env bash

set -ex

pacman -S --noconfirm --needed \
  just uv python-pipx go github-cli zig terraform nodejs npm yarn deno ripgrep jujutsu kubectl kustomize fish pnpm cloudflared

curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh

curl -fsSL zagi.sh/install | sh

useradd indexyz \
  --create-home \
  --shell=/bin/fish \
  --uid=1000 \
  --user-group && \

echo "indexyz ALL=(ALL) NOPASSWD:ALL" >>/etc/sudoers.d/nopasswd

runuser() {
  sudo -iu indexyz bash -lc -- $@
}

runuser 'curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
runuser "curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash"
runuser 'mkdir ~/.npm'
runuser 'npm config set prefix "~/.npm"'
runuser 'npm install -g @openai/codex oh-my-codex opencode-ai ocx @anthropic-ai/claude-code @fission-ai/openspec@latest'

runuser 'cargo binstall forgejo-cli -y'

mkdir -p /home/indexyz/.config/fish
cat > /home/indexyz/.config/fish/config.fish <<'EOF'
if status is-interactive
# Commands to run in interactive sessions can go here
end

fish_add_path -a "/home/indexyz/.npm/bin"
source "$HOME/.cargo/env.fish"
EOF

chown -R indexyz:indexyz /home/indexyz/.config/fish

runuser 'git clone https://aur.archlinux.org/yay.git'
runuser 'cd yay; yes | makepkg -si'
runuser 'rm -rf yay'

# Install code-server
runuser 'echo y | LANG=C yay --answerdiff None --answerclean None --mflags "--noconfirm" -S code-server'

sudo systemctl enable --now code-server@indexyz

