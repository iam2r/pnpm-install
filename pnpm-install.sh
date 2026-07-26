#!/bin/sh
#
# pnpm-install — pnpm installer with Intel Mac pnpm v11 workaround
#
# Always patches the pnpm wrapper (post-setup) to intercept `pnpm self-update`
# and delegate to this installer script, which resolves the target version
# and chooses the correct install path:
#
#   darwin-x64 + v11 → npm-pack fallback (native SEA binary segfaults)
#   everything else  → GitHub release tarball (official flow)
#
# License: MIT
# https://github.com/iam2r/pnpm-install

# From https://github.com/Homebrew/install/blob/master/install.sh
abort() {
  printf "%s\n" "$@"
  exit 1
}

if [ -t 1 ]; then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_blue="$(tty_mkbold 34)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"

ohai() {
  printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$1"
}
# End from https://github.com/Homebrew/install/blob/master/install.sh

download() {
  if command -v curl > /dev/null 2>&1; then
    curl -fsSL "$1"
  else
    wget -qO- "$1"
  fi
}

is_glibc_compatible() {
  getconf GNU_LIBC_VERSION >/dev/null 2>&1 || ldd --version >/dev/null 2>&1 || return 1
}

detect_platform() {
  local platform
  platform="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "${platform}" in
    linux)  platform="linux" ;;
    darwin) platform="darwin" ;;
    mingw*|msys*|cygwin*) platform="win32" ;;
    windows*) platform="win32" ;;
  esac
  printf '%s' "${platform}"
}

detect_libc_suffix() {
  if [ "$(detect_platform)" = 'linux' ] && ! is_glibc_compatible; then
    printf -- '-musl'
  fi
}

use_legacy_assets() {
  local version="$1"
  local major
  major="$(echo "$version" | cut -d. -f1)"
  if [ "$major" -lt 11 ] 2>/dev/null; then
    return 0
  fi
  case "$version" in
    11.0.0-rc.1|11.0.0-rc.2) return 0 ;;
    *) return 1 ;;
  esac
}

legacy_asset_basename() {
  local platform arch libc_suffix
  platform="$1"; arch="$2"; libc_suffix="$3"
  case "${platform}:${libc_suffix}" in
    'darwin:')   printf 'pnpm-macos-%s' "$arch" ;;
    'win32:')    printf 'pnpm-win-%s' "$arch" ;;
    'linux:-musl') printf 'pnpm-linuxstatic-%s' "$arch" ;;
    *)           printf 'pnpm-%s-%s%s' "$platform" "$arch" "$libc_suffix" ;;
  esac
}

asset_basename() {
  local version platform arch libc_suffix
  version="$1"; platform="$2"; arch="$3"; libc_suffix="$4"
  if use_legacy_assets "$version"; then
    legacy_asset_basename "$platform" "$arch" "$libc_suffix"
  else
    printf 'pnpm-%s-%s%s' "$platform" "$arch" "$libc_suffix"
  fi
}

detect_arch() {
  local arch
  arch="$(uname -m | tr '[:upper:]' '[:lower:]')"
  case "${arch}" in
    x86_64 | amd64) arch="x64" ;;
    armv*) arch="arm" ;;
    arm64 | aarch64) arch="arm64" ;;
  esac
  if [ "${arch}" = "x64" ] && [ "$(getconf LONG_BIT)" -eq 32 ]; then arch=i686
  elif [ "${arch}" = "arm64" ] && [ "$(getconf LONG_BIT)" -eq 32 ]; then arch=arm
  fi
  case "$arch" in x64* | arm64*) ;; *) return 1 ;; esac
  printf '%s' "${arch}"
}

# ==============================
# Wrapper writers
# ==============================

# Generic pnpm-install wrapper: intercepts self-update, delegates to installer.
# $1 — the entry to exec (binary path, or "prefix entry_path" for JS).
# When it contains a space the first word is used as the interpreter.
write_pnpm_install_wrapper() {
  local entry="$1"
  local exec_prefix="" exec_target

  # Detect if it's "node /path/to/pnpm.mjs" (JS entry) vs "/path/to/binary"
  case "$entry" in
    *" "*)
      exec_prefix="${entry%% *}"   # first word
      exec_target="${entry#* }"    # rest
      ;;
    *)
      exec_prefix=""
      exec_target="$entry"
      ;;
  esac

  ohai "Writing pnpm wrapper (Intel Mac — self-update aware) to $PNPM_HOME/bin/pnpm"
  cat > "$PNPM_HOME/bin/pnpm" <<- WRAPPER
	#!/usr/bin/env bash
	set -e

	PNPM_HOME="\${PNPM_HOME:-${PNPM_HOME}}"

	# self-update: delegate to the installer script which resolves
	# the target version and picks the right path (npm-pack for v11
	# on Intel Mac, GitHub release otherwise)
	if [ "\${1:-}" = "self-update" ]; then
	  INSTALLER="\$PNPM_HOME/pnpm-install.sh"
	  if [ -f "\$INSTALLER" ]; then
	    shift
	    case "\${1:-}" in
	      --help|-h)
	        echo "Updates pnpm to the latest version (or the one specified)"
	        echo ""
	        echo "Usage:"
	        echo "  pnpm self-update               Install latest"
	        echo "  pnpm self-update 9             Install latest v9"
	        echo "  pnpm self-update next-10       Install latest v10 from next tag"
	        echo "  pnpm self-update 11.17.0       Install exact version"
	        exit 0
	        ;;
	      *)
	        PNPM_VERSION="\${1:-}" ${PNPM_NPM_PACK:+PNPM_NPM_PACK=true} sh "\$INSTALLER"
	        exit \$?
	        ;;
	    esac
	  else
	    echo "Error: pnpm-install.sh not found at \$INSTALLER" >&2
	    echo "Reinstall: curl -fsSL https://raw.githubusercontent.com/iam2r/pnpm-install/main/pnpm-install.sh | sh" >&2
	    exit 1
	  fi
	fi

	exec ${exec_prefix:+$exec_prefix }"${exec_target}" "\$@"
	WRAPPER
  chmod +x "$PNPM_HOME/bin/pnpm"

  write_passthrough_wrappers
}

write_passthrough_wrappers() {
  cat > "$PNPM_HOME/bin/pnpx" <<- 'PNPX_EOF'
	#!/usr/bin/env bash
	set -e
	exec pnpm dlx "$@"
	PNPX_EOF
  chmod +x "$PNPM_HOME/bin/pnpx"

  cat > "$PNPM_HOME/bin/pn" <<- 'PN_EOF'
	#!/usr/bin/env bash
	set -e
	exec pnpm "$@"
	PN_EOF
  chmod +x "$PNPM_HOME/bin/pn"
}

# ==============================
# Shell setup
# ==============================

setup_shell() {
  local rc_file
  if [ -n "${ZSH_VERSION-}" ]; then
    rc_file="$HOME/.zshrc"
  elif [ -n "${BASH_VERSION-}" ]; then
    rc_file="$HOME/.bashrc"
  else
    rc_file="$HOME/.profile"
  fi
  local pnpm_home_line="export PNPM_HOME=\"${PNPM_HOME}\""
  local path_line='export PATH="$PNPM_HOME/bin:$PATH"'
  if [ -f "$rc_file" ]; then
    grep -q "PNPM_HOME" "$rc_file" 2>/dev/null || {
      printf "\n# pnpm\n%s\n%s\n# pnpm end\n" "$pnpm_home_line" "$path_line" >> "$rc_file"
      ohai "Appended pnpm to $rc_file"
    }
  else
    printf "%s\n%s\n" "$pnpm_home_line" "$path_line" > "$rc_file"
    ohai "Created $rc_file with pnpm PATH"
  fi
}

# ==============================
# Install methods
# ==============================

# Extract the actual pnpm executable path after setup --force.
# Works for both v11+ ($PNPM_HOME/bin/pnpm wrapper) and
# v10- ($PNPM_HOME/pnpm direct binary/script).
extract_native_bin() {
  local bin

  # v11+: $PNPM_HOME/bin/pnpm is a wrapper script. Parse cmd-shim-target.
  if [ -f "$PNPM_HOME/bin/pnpm" ]; then
    bin="$(grep 'cmd-shim-target=' "$PNPM_HOME/bin/pnpm" 2>/dev/null | sed 's/.*=//')"
    if [ -z "$bin" ] || [ ! -f "$bin" ]; then
      bin="$(grep -o 'exec "[^"]*pnpm"' "$PNPM_HOME/bin/pnpm" 2>/dev/null | grep -o '"[^"]*"' | head -1 | tr -d '"')"
    fi
    if [ -z "$bin" ] || [ ! -f "$bin" ]; then
      bin="$(find "$PNPM_HOME/global" -name 'pnpm' -type f 2>/dev/null | grep '/@pnpm/exe/pnpm$' | head -1)"
    fi
  fi

  # v10-: $PNPM_HOME/pnpm is the binary itself
  if [ -z "$bin" ] || [ ! -f "$bin" ]; then
    if [ -f "$PNPM_HOME/pnpm" ]; then
      # Check in .tools (v10 layout) or direct
      bin="$(find "$PNPM_HOME/.tools" -name 'pnpm' -type f 2>/dev/null | grep '/pnpm$' | head -1)"
      [ -z "$bin" ] && [ -f "$PNPM_HOME/pnpm" ] && bin="$PNPM_HOME/pnpm"
    fi
  fi

  printf '%s' "$bin"
}

# Standard: GitHub release tarball → pnpm setup --force
install_via_github_release() {
  local version="$1" platform="$2" arch="$3" libc_suffix="$4"
  local major_version asset_base tmp_dir native_bin

  major_version="$(printf '%s' "$version" | sed -E 's/^v//; s/^([0-9]+).*/\1/')"
  asset_base="$(asset_basename "$version" "$platform" "$arch" "$libc_suffix")"
  tmp_dir="$(mktemp -d)" || abort "Tmpdir Error!"
  trap "rm -rf '$tmp_dir'" EXIT INT TERM HUP

  ohai "Downloading pnpm binaries ${version}"

  if [ "$major_version" -ge 11 ]; then
    if [ "${platform}" = "win32" ]; then
      download "https://github.com/pnpm/pnpm/releases/download/v${version}/${asset_base}.zip" > "$tmp_dir/pnpm.zip" || return 1
      unzip -q "$tmp_dir/pnpm.zip" -d "$tmp_dir" || return 1
      SHELL="$SHELL" "$tmp_dir/pnpm.exe" setup --force || return 1
    else
      download "https://github.com/pnpm/pnpm/releases/download/v${version}/${asset_base}.tar.gz" > "$tmp_dir/pnpm.tar.gz" || return 1
      tar -xzf "$tmp_dir/pnpm.tar.gz" -C "$tmp_dir" || return 1
      chmod +x "$tmp_dir/pnpm"
      SHELL="$SHELL" "$tmp_dir/pnpm" setup --force || return 1
    fi
  else
    local archive_url="https://github.com/pnpm/pnpm/releases/download/v${version}/${asset_base}"
    [ "${platform}" = "win32" ] && archive_url="${archive_url}.exe"
    download "$archive_url" > "$tmp_dir/pnpm" || return 1
    chmod +x "$tmp_dir/pnpm"
    SHELL="$SHELL" "$tmp_dir/pnpm" setup --force || return 1
  fi

  rm -rf "$tmp_dir"
  trap '' EXIT INT TERM HUP

  # Patch wrapper so self-update goes through our installer
  native_bin="$(extract_native_bin)"
  if [ -n "$native_bin" ] && [ -f "$native_bin" ]; then
    write_pnpm_install_wrapper "$native_bin"
  fi
}

# Fallback (Intel Mac + v11): npm pack from registry, run setup --force,
# then patch the wrapper to use the JS entry point instead of the
# native binary (which segfaults on darwin-x64).
install_via_npm_registry() {
  local version="$1"
  local tmp_dir install_dir

  ohai "Downloading pnpm ${version} from npm registry"
  tmp_dir="$(mktemp -d)" || abort "Tmpdir Error!"
  trap "rm -rf '$tmp_dir'" EXIT INT TERM HUP

  (cd "$tmp_dir" && npm pack "pnpm@${version}" --pack-destination "$tmp_dir" >/dev/null 2>&1) || return 1
  local tarball
  tarball="$(ls "$tmp_dir"/pnpm-*.tgz 2>/dev/null | head -1)" || return 1

  # Extract to a permanent location under PNPM_HOME (npm-versions, not
  # "pnpm" — v9/v8's setup --force puts a pnpm binary at $PNPM_HOME/pnpm)
  local pnpm_js_dir="$PNPM_HOME/npm-versions/$version"
  mkdir -p "$pnpm_js_dir"
  tar -xzf "$tarball" -C "$pnpm_js_dir"

  # Resolve the JS entry point from the package's own bin field.
  # This handles any layout: v8-v10 use pnpm.cjs, v11+ uses pnpm.mjs,
  # future versions may change without this script needing updates.
  local pnpm_js="$(node -e "
    const pkg = require('${pnpm_js_dir}/package/package.json');
    console.log('${pnpm_js_dir}/package/' + (pkg.bin?.pnpm || 'bin/pnpm.mjs'));
  " 2>/dev/null)"
  [ -n "$pnpm_js" ] && [ -f "$pnpm_js" ] || pnpm_js="$pnpm_js_dir/package/bin/pnpm.mjs"
  [ -f "$pnpm_js" ] || pnpm_js="$pnpm_js_dir/package/bin/pnpm.cjs"

  # Run setup --force via JS entry to create the full official layout:
  #   store, global dir, shell rc, wrappers, PNPM_HOME configuration
  ohai "Running pnpm setup --force"
  SHELL="$SHELL" node "$pnpm_js" setup --force || abort "pnpm setup failed!"

  # setup --force created a standard wrapper pointing at the native binary.
  # On Intel Mac that binary segfaults, so replace the wrapper with one
  # pointing at the permanent JS entry point.
  write_pnpm_install_wrapper "node $pnpm_js"

  rm -rf "$tmp_dir"
  trap '' EXIT INT TERM HUP
}

# ==============================
# Entry point
# ==============================

: "${PNPM_HOME:=$HOME/.local/share/pnpm}"
mkdir -p "$PNPM_HOME" "$PNPM_HOME/bin"

# Dev/test: PNPM_NPM_PACK=true forces npm registry path (only effective when
# the resolved version is v11, to simulate Intel Mac fallback).
# Pipe-friendly: curl ... | env PNPM_NPM_PACK=true PNPM_VERSION=11.17.0 sh -

# Resolve version
# PNPM_VERSION can be: exact ("11.17.0"), major range ("11"), dist-tag ("next-10", "latest")
# Always resolve to an exact semver before proceeding.
if [ -z "${PNPM_VERSION}" ]; then
  PNPM_VERSION="latest"
fi

# Check if already an exact semver (x.y.z or vx.y.z)
pp_major_version=""
case "$PNPM_VERSION" in
  [0-9]*.[0-9]*.[0-9]*|v[0-9]*.[0-9]*.[0-9]*)
    pp_major_version="$(printf '%s' "$PNPM_VERSION" | sed -E 's/^v//; s/^([0-9]+).*/\1/')"
    ;;
esac

# Not an exact version → resolve via npm registry
if [ -z "$pp_major_version" ]; then
  if [ "${PNPM_VERSION}" != "latest" ]; then
    ohai "Resolving pnpm@${PNPM_VERSION}"
  fi
  # Try npm view first (needs npm), fall back to direct registry API
  pp_resolved="$(npm view "pnpm@${PNPM_VERSION}" version 2>/dev/null)"
  if [ -z "$pp_resolved" ]; then
    pp_encoded="$(printf '%s' "$PNPM_VERSION" | sed 's|/|%2F|g')"
    pp_json="$(download "https://registry.npmjs.org/pnpm/${pp_encoded}" 2>/dev/null)" || abort "Download Error!"
    pp_resolved="$(echo "$pp_json" | grep -o '"version":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')"
  fi
  [ -n "$pp_resolved" ] || abort "Error: could not resolve pnpm@${PNPM_VERSION}"
  PNPM_VERSION="$pp_resolved"
  pp_major_version="$(printf '%s' "$PNPM_VERSION" | sed -E 's/^v//; s/^([0-9]+).*/\1/')"
fi
[ -n "$pp_major_version" ] || abort "Invalid resolved version: $PNPM_VERSION"

platform="$(detect_platform)"
arch="$(detect_arch)"

# === Intel Mac + pnpm v11 gate ===
# The native SEA binary segfaults on darwin-x64 due to an upstream Node.js bug.
# Fall back to npm pack for the JS entry point.
# See https://github.com/pnpm/pnpm/issues/11423
if { [ "${platform}" = "darwin" ] && [ "${arch}" = "x64" ] && [ "$pp_major_version" -eq 11 ]; } || \
   { [ "${PNPM_NPM_PACK}" = "true" ] && [ "$pp_major_version" -eq 11 ]; }; then
  if [ "${PNPM_NPM_PACK}" = "true" ]; then
    ohai "npm-pack mode — using npm registry"
  else
    ohai "Intel Mac detected — using npm registry (native SEA binary is broken on this platform)"
  fi
  install_via_npm_registry "$PNPM_VERSION" || abort "Install Error!"
else
  install_via_github_release "$PNPM_VERSION" "$platform" "$arch" "$(detect_libc_suffix)" || abort "Install Error!"
fi

# Copy installer to PNPM_HOME for self-update support
cp "$0" "$PNPM_HOME/pnpm-install.sh" 2>/dev/null || {
  ohai "Warning: could not copy installer to PNPM_HOME (piped install)"
  ohai "self-update will redirect users to reinstall manually"
}
setup_shell

ohai "pnpm@${PNPM_VERSION} installed. Restart your terminal or run:"
printf "  export PNPM_HOME=\"%s\"\n" "$PNPM_HOME"
printf "  export PATH=\"\$PNPM_HOME/bin:\$PATH\"\n"
