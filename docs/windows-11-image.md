# Windows 11 Enterprise template

Target: `windows-11`, x64, en-US, Enterprise (not LTSC), no GitHub runner.
Installs Cloudbase-Init 1.1.8, OpenSSH, VirtIO drivers and QEMU Guest Agent.
Windows licensing/activation is the deployer's responsibility; the answer file
uses Microsoft's public Enterprise KMS client setup key, not an activation license.

## 1. Generate the ISO on Windows

Use an elevated Windows PowerShell on a modern Windows installation, with at
least 40 GB free space and internet access:

```powershell
.\scripts\build-windows-11-iso.ps1 -WorkDirectory C:\uup-windows-11
```

The directory must not already exist and must not contain spaces. The script:

1. Queries the official UUP dump `fetchupd.php?arch=amd64&ring=Retail` endpoint
   (the homepage's **Latest Public Release** option).
2. Selects the newest Windows 11 x64 feature build in that response, excluding
   Insider, Preview and cumulative-only entries. If the JSON API fails, it
   queries the same official Latest Public Release HTML page. If neither returns
   a complete Retail build, it fails rather than using an old/search result.
3. Downloads the official Pro conversion package, enables updates and the
   Enterprise virtual edition, and retains Windows 11 apps.
4. Runs the Windows converter with a bounded timeout, verifies the ISO contains
   `Windows 11 Enterprise` and the requested image version, and writes:
   `windows-11.iso`, `windows-11.iso.sha256`, `windows-11.json`.

Upstream documentation:
<https://git.uupdump.net/uup-dump/misc/src/branch/master/FAQ.md>

**Do not use the Linux converter for current Windows 11.** It cannot integrate
updates correctly and may omit required apps. Installing PowerShell on Linux
does not satisfy the Windows DISM/conversion requirement.

## 2. Build qcow2 on Linux/KVM

Transfer the ISO and its `.sha256` sidecar together. From the repository root:

```sh
# Debian/Ubuntu host prerequisites (plus Packer and optionally just):
sudo apt-get install qemu-system-x86 qemu-utils ovmf swtpm libarchive-tools xorriso curl
just build-windows-11 /path/to/windows-11.iso
# Or: bash scripts/build-windows-11.sh /path/to/windows-11.iso
```

The user needs access to `/dev/kvm`. The wrapper verifies the ISO hash, stages
Windows 11 drivers and only the required payloads, starts an isolated TPM 2.0
emulator, and builds using UEFI + SATA. It refuses to overwrite existing outputs.
Provisioning stages VirtIO storage drivers for deployment, installs Cloudbase-Init
and QEMU Guest Agent, restores UAC, removes the temporary account/SSH host keys,
and generalizes with Sysprep. Cloudbase-Init runs as LocalSystem and is enabled
by SetupComplete, after Windows has finished setting its computer name. Clone
specialize enables Administrator with a fresh random password; metadata then
replaces it. Ubuntu builds use Secure-Boot-capable OVMF, not its plain firmware. Packer requires the serial `BUILD_SUCCESS` marker.
The result is `windows-11.qcow2`; both intermediate and compressed disks receive
`qemu-img check`. TPM state is build-only and must not be reused for clones.

## Deployment

Use q35, UEFI, a fresh EFI disk and TPM 2.0 per VM, at least 4 GB memory and a
VirtIO SCSI controller. Attach a Proxmox `cloudinit` disk with
`--citype configdrive2`, `--ciuser Administrator`, an individual password and/or
SSH keys. Cloudbase-Init supports ConfigDrive and NoCloud metadata. Never expose
a clone before confirming its credentials have been replaced. The installed
Windows image is not preactivated.

## CI and verification status

`.github/workflows/windows-11.yaml` is **manual-only**: Windows generates
and validates the ISO, then Ubuntu/KVM builds the qcow2. An `always()` cleanup
job deletes this run's intermediate ISO artifact after the build, including
failures; one-day expiration is only a fallback if cleanup cannot run. Conversion
and Linux workspaces are also cleaned after use. Download one local ISO backup
while the qcow2 job is running if debugging is needed. qcow2 artifacts expire
after three days. It does not publish to Alist or
change the existing weekly build matrix until end-to-end verification passes.

The workflow gates the qcow2 artifact on `tests/windows-11-smoke.sh`: a disposable
fresh-UEFI/TPM, virtio-scsi ConfigDrive boot, including key and password SSH login.
The test removes its metadata ISO (including its random test password) on exit.

Local checks:

```sh
pwsh -NoProfile -File tests/windows-11-uup.ps1
bash -n scripts/build-windows-11.sh scripts/fetch-windows-drivers.sh
```

A real UUP-generated 25H2 / 26200.9807 Enterprise ISO passed local Packer and
fresh-clone checks: hostname, password/key authentication, VirtIO network/storage,
Guest Agent, UAC, TPM, and absence of runner/packer accounts and runner payloads.
Rerun `bash tests/windows-11-smoke.sh windows-11.qcow2` for each new image.
Static tests and the build success marker do not replace this first-boot test.
