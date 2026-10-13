# Virtual Machien Image

## Support Platforms
- Debian 12
- Debian 13
- Debian Unstable
- Alma Linux 8
- Alma Linux 9
- Alma Linux 10
- Rocky Linux 8
- Rocky Linux 9
- Rocky Linux 10
- Ubuntu 24.04
- Ubuntu 26.04
- Arch Linux
- GitHub Runner (Ubuntu 24.04, AMD64 + ARM64, actions/runner, forgejo-runner, gitlab-runner, Docker, Node.js, Python, gh/kubectl/helm/terraform)
- Windows 2025 Runner (Windows Server 2025 Datacenter Eval, actions/runner, Git, pwsh, Cloudbase-Init)

## ARM64 runner

Build `github-runner-arm64` with `just build github-runner-arm64`. Install
`qemu-system-arm`, `qemu-efi-aarch64`, `qemu-utils` and `xorriso` first.
The target uses the official Ubuntu Noble ARM64 cloud image (ext4), AAVMF
UEFI, and QEMU `virt`. Both runner targets use the same provisioning manifest
(`scripts/github-runner/provisioners.txt`) and architecture-native downloads.
Legacy BIOS and ffsend are omitted on ARM64: upstream ffsend only ships x86-64
binaries. Runner registration remains a deployment-time operation.

CI uses `ubuntu-24.04-arm` with TCG (no nested KVM required). On a local ARM64
host with KVM, use Packer variables `accelerator=kvm` and `cpu_model=host`.
The manually dispatched **Test ARM64 runner** workflow builds the full image,
executes guest smoke tests, checks qcow2 integrity, and saves a short-lived
artifact without publishing to production storage. The regular image matrix
also builds and publishes the ARM64 target.
