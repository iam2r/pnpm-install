# pnpm-install

模拟 pnpm 官方 `install.sh` 的一键安装脚本，唯一区别是从 npm registry 下载包而非 GitHub releases。

**解决的问题**：pnpm v11 官方独立二进制在 Intel macOS 上因 Node.js SEA bug 无法使用（官方 install.sh 会直接 abort）。本脚本用 npm tarball + 平台原生二进制（`@pnpm/exe`）实现等价安装，让 Intel Mac 也能用上 `pnpm use` 多版本管理。ARM Mac 和其他 Linux 平台安装官方独立二进制没有问题，本脚本对他们而言是完整替代品。

## 一键安装

```bash
# 安装最新版
curl -fsSL https://raw.githubusercontent.com/iam2r/pnpm-install/main/pnpm-install.sh | sh

# 安装指定版本
curl -fsSL https://raw.githubusercontent.com/iam2r/pnpm-install/main/pnpm-install.sh | env PNPM_VERSION=11.17.0 sh
```

## 日常使用

```bash
# 切换版本（如果未安装会自动下载）
pnpm use 11.17.0
pnpm use 12.0.0-alpha.21

# 多版本共存
# $PNPM_HOME/bin/pnpm          ← 当前激活的版本
# $PNPM_HOME/bin/pnpm-v11.17.0 ← 版本特定入口
# $PNPM_HOME/bin/pnpm-v12.0.0  ← 另一个版本
```

## 与官方 install.sh 的区别

| 特性 | 官方 install.sh | pnpm-install.sh |
|------|----------------|-----------------|
| 包来源 | GitHub Releases 独立二进制 | npm registry（npm pack） |
| pnpm 11 Intel Mac | ❌ 直接 abort | ✅ 正常安装运行 |
| `pnpm use` 多版本 | ✅ | ✅ |
| `$PNPM_HOME` 目录结构 | `bin/`, `versions/` | 完全一致 |
| pnpm 12+ 原生二进制 | GitHub Releases | `@pnpm/exe` npm 包 |

## 环境要求

- Node.js（`npm` 命令可用）
- `curl` 或 `wget`

## 运行方式

```bash
# 本地运行
sh pnpm-install.sh

# 指定版本
PNPM_VERSION=11.17.0 sh pnpm-install.sh
```
