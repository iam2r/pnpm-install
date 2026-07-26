# pnpm-install

[![CI](https://github.com/iam2r/pnpm-install/actions/workflows/test.yml/badge.svg)](https://github.com/iam2r/pnpm-install/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A drop-in replacement for pnpm's official `get.pnpm.io/install.sh` that downloads from npm registry instead of GitHub releases.

## Problem

[pnpm v11](https://github.com/pnpm/pnpm/issues/11423) does not provide a working standalone binary for **Intel macOS** (darwin-x64) due to [an upstream Node.js SEA bug](https://github.com/nodejs/node/issues/62893) that the Node.js team has decided not to fix. The official installer aborts on this platform with:

```
pnpm v11 does not provide a working binary for Intel macOS (darwin-x64)
```

This script solves it by downloading pnpm from npm registry — no standalone binary needed.

## Quick Install

```bash
# Latest version (no arguments needed)
curl -fsSL https://raw.githubusercontent.com/iam2r/pnpm-install/main/pnpm-install.sh | sh

# Specific version
curl -fsSL https://raw.githubusercontent.com/iam2r/pnpm-install/main/pnpm-install.sh | env PNPM_VERSION=11.17.0 sh

# Install latest pnpm 12 (native binary included)
curl -fsSL https://raw.githubusercontent.com/iam2r/pnpm-install/main/pnpm-install.sh | env PNPM_VERSION=12.0.0 sh
```

## Usage

After installation, `pnpm` is available in your shell (restart terminal or follow the on-screen instructions).

```bash
# Switch versions on the fly (auto-installs if missing)
pnpm use 11.17.0
pnpm use 12.0.0-alpha.21

# Version-specific binaries preserved for rollback
$PNPM_HOME/bin/pnpm         # current active version
$PNPM_HOME/bin/pnpm-v11.17.0  # pinned v11
$PNPM_HOME/bin/pnpm-v12.0.0   # pinned v12
```

## How It Works

| Step | Official `install.sh` | `pnpm-install.sh` |
|------|----------------------|-------------------|
| Package source | GitHub Releases | npm registry (`npm pack`) |
| pnpm v11 on Intel Mac | ❌ Aborts | ✅ Runs via JS entry |
| pnpm v12+ native binary | GitHub Release binary | `@pnpm/exe` npm package |
| `pnpm use` version switching | ✅ | ✅ |
| `$PNPM_HOME` directory layout | `bin/`, `versions/` | ✅ Identical |
| Shell rc setup (`~/.zshrc` / `~/.bashrc`) | ✅ | ✅ |

## Requirements

- **Node.js** with `npm` available on `PATH`
- `curl` or `wget`

## Local Development

```bash
git clone https://github.com/iam2r/pnpm-install.git
cd pnpm-install

# Test install latest
sh pnpm-install.sh

# Test install specific version
PNPM_VERSION=11.17.0 sh pnpm-install.sh
```

## License

MIT
