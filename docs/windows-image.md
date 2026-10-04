# Windows Server 2025 image validation

Run the fast checks before starting a VM or remote CI:

```sh
pwsh -NoProfile -File tests/windows-script-encoding.ps1
pwsh -NoProfile -File tests/windows-process.ps1
pwsh -NoProfile -File tests/windows-unattend.ps1
bash tests/windows-build-status.sh
packer init targets/windows-2025-runner
packer validate -var headless=true targets/windows-2025-runner
```

Then run `CI=1 just build-windows windows-2025-runner` on a Linux host with
KVM, QEMU, Packer, OVMF and the dependencies listed in the workflow. `CI=1`
only selects the local headless configuration; it does not invoke remote CI.
An already-downloaded Windows ISO can be supplied with `PKR_VAR_iso_url`;
keep checksum verification enabled.

The build is offline: the host downloads payloads, Windows Setup stages the
provision ISO, and **one** FirstLogonCommands entry invokes the provisioner.
Do not query network profiles synchronously during specialize: this blocked
Setup in local Server 2025 testing. The startup-task fallback was removed to
avoid running provisioning concurrently with first logon.

Windows PowerShell 5.1 reads BOM-less files as the system ANSI codepage.
Keep non-ASCII `.ps1` files UTF-8 **with BOM**, as specified by `.editorconfig`.
Parsing the same file with PowerShell 7's default decoder does not catch this
failure; the encoding regression test reproduces the en-US 5.1 decoder.

## Success is more than power-off

`communicator = "none"` observes QEMU exiting, not installer success. The
provisioner now checks process exit codes, required binaries/services, and
waits for Sysprep to exit and create `Sysprep_succeeded.tag`. Only then does
it emit `BUILD_SUCCESS` on COM1. `scripts/check-windows-build.sh`, run as a
Packer post-processor, rejects missing success records or any `BUILD_FAILED`
record. A watchdog shutdown therefore cannot publish a partial image.

PnPUtil's documented `259` (no matching device needs updating) is accepted
only for driver installation, alongside `0` and `3010`; other installers do
not inherit that exception.

After a local build:

```sh
qemu-img check outputs/windows-2025-runner/packer-windows-2025-runner
```

Mount the Windows partition **read-only** using an unused NBD device, or an
equivalent offline inspection tool, then run:

```sh
bash tests/check-windows-image.sh /path/to/windows-mount
```

Finally smoke-boot a disposable snapshot with fresh UEFI variables and a
virtio-scsi disk, without either installation CD. It should reach Windows
OOBE. Never boot the sealed base image directly for this test.

Diagnostics: `windows-2025-runner-serial.log`, `packer-windows.log`, guest
`C:\provision.trace`, and `C:\Windows\System32\Sysprep\Panther\`. The workflow
preserves host logs with its failure screenshots.
