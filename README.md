# pnpm-install

[![CI](https://github.com/iam2r/pnpm-install/actions/workflows/test.yml/badge.svg)](https://github.com/iam2r/pnpm-install/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A drop-in pnpm installer that works around the [Intel Mac pnpm v11 SEA segfault](https://github.com/pnpm/pnpm/issues/11423).

On non-Intel-Mac platforms the install behavior is identical to the official
`get.pnpm.io/install.sh` — just with `pnpm self-update` always intercepted
so the Intel Mac v11 fix stays reachable from any version.

## Problem

pnpm v11's standalone binary (built via Node.js SEA) segfaults at startup on
**Intel macOS** (darwin-x64) due to [an upstream Node.js bug](https://github.com/nodejs/node/issues/62893).
The official installer aborts on this platform.

This script detects the scenario and falls back to running pnpm via its JS
entry point (`node pnpm.mjs`) instead.

## Quick Install

```bash
# Latest version
curl -fsSL https://raw.githubusercontent.com/iam2r/pnpm-install/main/pnpm-install.sh | sh

# Specific version
curl -fsSL https://raw.githubusercontent.com/iam2r/pnpm-install/main/pnpm-install.sh | env PNPM_VERSION=11.17.0 sh

# Version range or dist-tag
curl -fsSL https://raw.githubusercontent.com/iam2r/pnpm-install/main/pnpm-install.sh | env PNPM_VERSION=next-10 sh
```

## How It Works

The script always:

1. Resolves the target version (exact semver, range, or dist-tag)
2. Installs via the official GitHub release tarball (`pnpm setup --force`)
3. Patches the `$PNPM_HOME/bin/pnpm` wrapper to intercept `pnpm self-update`

**On Intel Mac + pnpm v11 only:** the official GitHub release binary would
segfault, so it instead downloads the `pnpm` npm package and runs
`node pnpm.mjs setup --force` — producing an identical directory layout.

### Install path matrix

| Scenario | Install source | Entry point |
|----------|--------------|-------------|
| darwin-x64 + v11 | `npm pack pnpm` from registry | `node pnpm.mjs` |
| Everything else | GitHub release tarball | Native binary |

After install, `pnpm self-update` on any version delegates to this installer,
which re-evaluates the target version and picks the correct path.

### Testing the npm-pack fallback (on any platform)

```bash
PNPM_NPM_PACK=true PNPM_VERSION=11.17.0 sh pnpm-install.sh
```

This forces the npm-pack fallback path, simulating the Intel Mac v11 scenario
for CI or local testing.

## Requirements

- **Node.js** with `npm` available on `PATH` (for npm-pack fallback only)
- `curl` or `wget`

## Local Development

```bash
git clone https://github.com/iam2r/pnpm-install.git
cd pnpm-install

# Test install latest
sh pnpm-install.sh

# Test with specific version
PNPM_VERSION=11.15.0 sh pnpm-install.sh

# Test npm-pack fallback (simulates Intel Mac)
PNPM_NPM_PACK=true PNPM_VERSION=11.17.0 sh pnpm-install.sh

# Test self-update chain
PNPM_NPM_PACK=true PNPM_VERSION=9.15.9 sh pnpm-install.sh
pnpm self-update 11.17.0
```

## License

MIT
