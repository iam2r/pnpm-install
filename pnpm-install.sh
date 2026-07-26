#!/bin/sh
#
# pnpm-install — npm-registry-based pnpm installer
#
# A drop-in replacement for pnpm's official install.sh that downloads
# from npm registry instead of GitHub releases. Supports Intel Mac pnpm v11
# (which the official installer aborts on) and all other platforms.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/iam2r/pnpm-install/main/pnpm-install.sh | sh
#   curl -fsSL ... | env PNPM_VERSION=11.17.0 sh
#   pnpm use <version>
#
# License: MIT
# Repository: https://github.com/iam2r/pnpm-install
# From https://github.com/Homebrew/install/blob/master/install.sh
abort() {
  printf "%s\n" "$@"
  exit 1
}

# string formatters
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

is_glibc_compatible() {
  getconf GNU_LIBC_VERSION >/dev/null 2>&1 || ldd --version >/dev/null 2>&1 || return 1
}

platform_pkg() {
  # 映射当前平台到 @pnpm/exe.{platform}-{arch}[+-musl]
  local platform arch libc
  platform="$(detect_platform)"
  arch="$(detect_arch)"
  case "${platform}" in
    darwin) printf '@pnpm/exe.darwin-%s' "$arch" ;;
    linux)
      if is_glibc_compatible; then
        printf '@pnpm/exe.linux-%s' "$arch"
      else
        printf '@pnpm/exe.linux-%s-musl' "$arch"
      fi
      ;;
    win32) printf '@pnpm/exe.win32-%s' "$arch" ;;
  esac
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

# 下载 pnpm npm 包并解压到版本目录
install_version() {
  local version="$1"
  ohai "Downloading pnpm binaries ${version}"

  local tmp_dir tarball install_dir
  tmp_dir="$(mktemp -d)" || abort "Tmpdir Error!"
  trap "rm -rf '$tmp_dir'" EXIT INT TERM HUP

  (cd "$tmp_dir" && npm pack "pnpm@${version}" --pack-destination "$tmp_dir" >/dev/null 2>&1) || return 1
  tarball="$(ls "$tmp_dir"/pnpm-*.tgz 2>/dev/null | head -1)" || return 1

  install_dir="$PNPM_HOME/versions/$version"
  mkdir -p "$install_dir"
  tar -xzf "$tarball" -C "$install_dir"

  local major_version
  major_version="$(printf '%s' "$version" | sed -E 's/^v//; s/^([0-9]+).*/\1/')"

  # pnpm v12: 切换到临时目录执行，避免 packageManager 自检报错
  if [ -f "$install_dir/package/bin/pnpm.mjs" ]; then
    # pnpm v11-: 入口在 bin/pnpm.mjs
    chmod +x "$install_dir/package/bin/pnpm.mjs" "$install_dir/package/bin/pnpx.mjs" 2>/dev/null || true
    ln -sf "../versions/$version/package/bin/pnpm.mjs" "$PNPM_HOME/bin/pnpm-v$version"
    ln -sf "../versions/$version/package/bin/pnpx.mjs" "$PNPM_HOME/bin/pnpx-v$version"
  # pnpm v12+: package/pnpm 是占位文件，需要从 @pnpm/exe 包下载原生二进制
  else
    exe_pkg="$(platform_pkg)"
    ohai "Downloading native binary from ${exe_pkg}@${version}"
    (cd "$tmp_dir" && npm pack "${exe_pkg}@${version}" --pack-destination "$tmp_dir" >/dev/null 2>&1) || return 1
    local exe_tarball
    exe_tarball="$(ls "$tmp_dir"/pnpm*.tgz 2>/dev/null | grep -v '/pnpm-[0-9]' | head -1)" || return 1

    # 解压出二进制替换占位文件
    local exe_extract_dir="$tmp_dir/exe-extract"
    mkdir -p "$exe_extract_dir"
    tar -xzf "$exe_tarball" -C "$exe_extract_dir"
    cp "$exe_extract_dir/package/pnpm" "$install_dir/package/pnpm"
    chmod +x "$install_dir/package/pnpm"

    ln -sf "../versions/$version/package/pnpm" "$PNPM_HOME/bin/pnpm-v$version"
    ln -sf "../versions/$version/package/pnpm" "$PNPM_HOME/bin/pnpx-v$version"
  fi
  mkdir -p "$PNPM_HOME/bin"
  rm -rf "$tmp_dir"
  trap '' EXIT INT TERM HUP
}

# 写入 pnpm wrapper（处理 use 子命令）
write_wrapper() {
  ohai "Writing pnpm wrapper to $PNPM_HOME/bin/pnpm"
  cat > "$PNPM_HOME/bin/pnpm" << WRAPPER_EOF
#!/usr/bin/env bash
set -e

PNPM_HOME="\${PNPM_HOME:-\$HOME/.pnpm}"
CURRENT="\$PNPM_HOME/current"

# handle "use" subcommand
if [ "\${1:-}" = "use" ] && [ -n "\${2:-}" ]; then
  VERSION="\$2"
  INSTALL_DIR="\$PNPM_HOME/versions/\$VERSION"
  if [ ! -d "\$INSTALL_DIR" ]; then
    echo "Installing pnpm@\$VERSION ..."
    TMPDIR="\$(mktemp -d)"
    (cd "\$TMPDIR" && npm pack "pnpm@\$VERSION" --pack-destination "\$TMPDIR" >/dev/null 2>&1) || {
      echo "Error: pnpm@\$VERSION not found in registry" >&2; rm -rf "\$TMPDIR"; exit 1
    }
    TARBALL="\$(ls "\$TMPDIR"/pnpm-*.tgz 2>/dev/null | head -1)" || {
      echo "Error: download failed for pnpm@\$VERSION" >&2; rm -rf "\$TMPDIR"; exit 1
    }
    mkdir -p "\$INSTALL_DIR"
    tar -xzf "\$TARBALL" -C "\$INSTALL_DIR"
    if [ -f "\$INSTALL_DIR/package/bin/pnpm.mjs" ]; then
      chmod +x "\$INSTALL_DIR/package/bin/pnpm.mjs" "\$INSTALL_DIR/package/bin/pnpx.mjs" 2>/dev/null || true
      ln -sf "../versions/\$VERSION/package/bin/pnpm.mjs" "\$PNPM_HOME/bin/pnpm-v\$VERSION"
      ln -sf "../versions/\$VERSION/package/bin/pnpx.mjs" "\$PNPM_HOME/bin/pnpx-v\$VERSION"
    else
      # v12+: download native binary and replace placeholder
      MAJOR="\$(printf '%s' "\$VERSION" | sed -E 's/^v//; s/^([0-9]+).*/\1/')"
      EXE_PKG="\$(PNPM_HOME="\$PNPM_HOME" sh "\$0" --detect-exe-pkg 2>/dev/null || echo '@pnpm/exe.darwin-x64')"
      (cd "\$TMPDIR" && npm pack "\${EXE_PKG}@\$VERSION" --pack-destination "\$TMPDIR" >/dev/null 2>&1) || {
        echo "Error: native binary not found for pnpm@\$VERSION" >&2; rm -rf "\$TMPDIR"; exit 1
      }
      EXE_TAR="\$(ls "\$TMPDIR"/pnpm*.tgz 2>/dev/null | grep -v '/pnpm-[0-9]' | head -1)"
      mkdir -p "\$TMPDIR/exe-extract"
      tar -xzf "\$EXE_TAR" -C "\$TMPDIR/exe-extract"
      cp "\$TMPDIR/exe-extract/package/pnpm" "\$INSTALL_DIR/package/pnpm"
      chmod +x "\$INSTALL_DIR/package/pnpm"
      ln -sf "../versions/\$VERSION/package/pnpm" "\$PNPM_HOME/bin/pnpm-v\$VERSION"
      ln -sf "../versions/\$VERSION/package/pnpm" "\$PNPM_HOME/bin/pnpx-v\$VERSION"
    fi
    rm -rf "\$TMPDIR"
    echo "pnpm@\$VERSION installed"
  fi
  ln -sfn "versions/\$VERSION" "\$CURRENT"
  echo "Switched to pnpm@\$VERSION"
  # detect entry point
  BIN_V="\$CURRENT/package/bin/pnpm.mjs"
  [ ! -f "\$BIN_V" ] && BIN_V="\$CURRENT/package/pnpm"
  "\$BIN_V" --version
  exit 0
fi

# fallback to first installed version
if [ ! -L "\$CURRENT" ]; then
  FIRST="\$(ls "\$PNPM_HOME/versions/" 2>/dev/null | head -1)"
  if [ -z "\$FIRST" ]; then
    echo "Error: no pnpm version installed." >&2; exit 1
  fi
  ln -sfn "versions/\$FIRST" "\$CURRENT"
fi

BIN="\$CURRENT/package/bin/pnpm.mjs"
[ -f "\$BIN" ] || BIN="\$CURRENT/package/pnpm"
exec "\$BIN" "\$@"
WRAPPER_EOF
  chmod +x "$PNPM_HOME/bin/pnpm"
}

write_pnpx_wrapper() {
  cat > "$PNPM_HOME/bin/pnpx" << 'PNPX_EOF'
#!/usr/bin/env bash
set -e
PNPM_HOME="${PNPM_HOME:-$HOME/.pnpm}"
CURRENT="$PNPM_HOME/current"
if [ ! -L "$CURRENT" ]; then
  echo "Error: no active pnpm version." >&2; exit 1
fi
BIN="$CURRENT/package/bin/pnpx.mjs"
[ -f "$BIN" ] || BIN="$CURRENT/package/pnpx"
exec "$BIN" "$@"
PNPX_EOF
  chmod +x "$PNPM_HOME/bin/pnpx"
}

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

# ================ entry ================
detect_platform >/dev/null
detect_arch >/dev/null

# Internal: print the platform-specific @pnpm/exe package name
if [ "${1:-}" = "--detect-exe-pkg" ]; then
  platform_pkg
  exit 0
fi

if [ -z "${PNPM_VERSION}" ]; then
  version_json="$(download "https://registry.npmjs.org/pnpm")" || abort "Download Error!"
  PNPM_VERSION="$(echo "$version_json" | grep -o '"latest":[[:space:]]*"[0-9.]*"' | grep -o '[0-9.]*')"
fi

: "${PNPM_HOME:=$HOME/.pnpm}"
mkdir -p "$PNPM_HOME"

install_version "$PNPM_VERSION" || abort "Install Error!"
write_wrapper
write_pnpx_wrapper
ln -sfn "versions/$PNPM_VERSION" "$PNPM_HOME/current"
setup_shell

ohai "pnpm@${PNPM_VERSION} installed. Restart your terminal or run:"
printf "  export PNPM_HOME=\"%s\"\n" "$PNPM_HOME"
printf "  export PATH=\"\$PNPM_HOME/bin:\$PATH\"\n"
