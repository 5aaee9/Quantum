#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

while IFS= read -r script; do
  test -f "$script"
  bash -n "$script"
done < scripts/github-runner/provisioners.txt
bash -n tests/github-runner-smoke.sh

python3 - <<'PY'
from pathlib import Path
import re
import subprocess

# Exercise the production architecture selectors with a mocked dpkg, without
# installing anything or writing to /opt or /etc on the test host.
expected = {
    '50-setup-github-runner.sh': {'amd64': 'x64', 'arm64': 'arm64'},
    '52-setup-toolchain.sh': {'amd64': 'amd64', 'arm64': 'arm64'},
    '53-setup-forgejo-runner.sh': {
        'amd64': '29dae21e93f0eab5cdf3564008d44603c74770b41a4f4f1aceed172c774bc376',
        'arm64': '4a18a9a2aad9619e61aca5d81d2c69cc624b26af8605118bfc4729ff994d12d3',
    },
    '54-setup-gitlab-runner.sh': {
        'amd64': '5a159b36c5ff54fda9248e00bb0cdfb62c1112ab3741f5282c04a41e94da1306',
        'arm64': '9763a63f7bc2319119f80de41d1d414465b5268d072bcd55266020b989e93ee9',
    },
}
for name, values in expected.items():
    source = Path('scripts/github-runner', name).read_text()
    selector = re.search(r'(?:ARCH=\$\(dpkg --print-architecture\)\n)?case .*?\nesac', source, re.S).group()
    variable = 'RUNNER_ARCH' if name.startswith('50-') else 'ARCH' if name.startswith('52-') else 'RUNNER_SHA256'
    for arch in ('amd64', 'arm64', 'unsupported'):
        code = f'dpkg() {{ echo {arch}; }}\n{selector}\nprintf "%s" "${{{variable}}}"'
        result = subprocess.run(['bash', '-c', code], capture_output=True, text=True)
        if arch == 'unsupported':
            assert result.returncode != 0, (name, arch)
        else:
            assert result.returncode == 0, result.stderr
            assert result.stdout == values[arch], (name, arch, result.stdout)
    # Reject accidental reintroduction of hard-coded x86 download URLs.
    for line in source.splitlines():
        if 'https://' in line or '-linux-' in line or '/bin/linux/' in line:
            assert '-linux-amd64' not in line and '-linux-x64' not in line and '/linux/amd64/' not in line, line

for target in ('github-runner', 'github-runner-arm64'):
    source = Path('targets', target, 'image.pkr.hcl').read_text()
    assert 'file("../../scripts/github-runner/provisioners.txt")' in source
arm = Path('targets/github-runner-arm64/image.pkr.hcl').read_text()
assert 'qemu-system-aarch64' in arm and re.search(r'machine_type\s*=\s*"virt"', arm)
assert 'tests/github-runner-smoke.sh' in arm
assert re.search(r'disk_image\s*=\s*true', arm)
print('Runner architecture selectors and shared provisioning: PASS')
PY
