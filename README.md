# Mac 存储急救：把一台 256GB Mac 从 512MB 救回 47GB

> 不是“一键清理大师”，而是一套**先定位、再分级、最后验证**的 macOS 深度清理方法。
> 它把“系统数据”和“文稿”拆开，找出真正吃空间的目录，并且只删可以重建的东西。

这是一个可以直接安装到 Codex 的 Skill，也是一份可以照着在另一台 Mac 上执行的操作手册。

## 这次到底找到了什么

实测机器：245GB 数据卷，清理前只剩 **512MB**。

| 元凶 | 位置 | 处理 |
| --- | --- | --- |
| Chrome 代码签名克隆 | `/private/var/folders/**/X/com.google.Chrome.code_sign_clone` | 15 份副本，保留最新 1 份 |
| Vite 预构建缓存 | `*/node_modules/.vite` | 6.5GB，纯缓存 |
| Xcode 构建/调试产物 | `DerivedData`、旧 `iOS DeviceSupport` | 2.7GB + 5.5GB |
| 剪映缓存 | `~/Movies/JianyingPro/User Data/Cache` | 3.1GB |
| 动态壁纸缓存 | `~/Library/Application Support/com.apple.wallpaper/aerials` | 4.7GB，当前未使用 |
| 卸载残留 | Adobe、Logic 支持文件 | 约 5.5GB |
| Claude Cowork 虚拟机 | `~/Library/Application Support/Claude/vm_bundles` | 9.9GB，不用 Cowork 才删 |
| 微信本地聊天文件 | `xwechat_files` | 2.3GB，用户明确确认 |

最终：**512MB → 47GB 可用空间**，实际回收约 46GB。清理完成时是峰值；Xcode 和壁纸缓存随后重建，当前稳定在约 40GB。

完整复盘见 [`references/case-study.md`](references/case-study.md)。

## 为什么不是 `rm -rf ~/Library/Caches`

因为 macOS 的“系统数据”不是某一个目录，而是：

- `~/Library` 里的应用支持、容器、缓存、Xcode；
- `/Library` 里的系统级应用支持；
- `/private/var` 里的临时文件、诊断日志、VM；
- 模拟器 runtime、Time Machine 本地快照；
- 以及 APFS 克隆造成的“看起来很大、实际共享数据块”的假象。

直接删整个 `Caches` 或 `Containers`，轻则 App 登录态丢失，重则聊天记录、项目依赖一起没了。这个 Skill 的原则是：

> **Tier 1 缓存自动清，Tier 2/3 用户数据逐项确认，Tier 4 系统项先解释再动手。**

## 快速开始

```bash
git clone git@github.com:orcatt/mac-storage-rescue.git
cd mac-storage-rescue

# 1. 只读审计，生成报告
./scripts/audit_mac.sh --output /tmp/mac-storage-audit.md

# 2. 看看 Tier 1 会删什么（默认 dry-run，不删任何东西）
./scripts/clean_safe.sh --projects "$HOME/Desktop"

# 3. 确认后执行
./scripts/clean_safe.sh --apply --yes --projects "$HOME/Desktop"
```

> `--projects` 指向你的代码目录，脚本只会清其中的 `node_modules/.vite`、`.next/cache`、`.turbo`、`.parcel-cache`。

## 安装为 Codex Skill

```bash
cp -R mac-storage-rescue "$HOME/.codex/skills/mac-storage-rescue"
```

之后可以直接对 Codex 说：

> 用 `$mac-storage-rescue` 审计这台 Mac，找出“系统数据”为什么这么大，只清理可以重建的缓存。

## 它会检查什么

- `df` / `diskutil apfs list`：卷级真实占用；
- `tmutil listlocalsnapshots /`：本地快照；
- 主目录、`Library`、`Application Support`、`Containers`、`Developer`、`Caches`；
- Xcode `DerivedData`、`iOS DeviceSupport`、CoreSimulator；
- 项目里的 `node_modules/.vite`、`.next/cache`、`.turbo`；
- Chrome `code_sign_clone` 临时副本；
- Adobe/Logic/剪映/Claude Cowork 等卸载残留或可选项；
- `MobileSync/Backup`、Downloads、Desktop、Documents 和 500MB 以上大文件。

## 安全边界

- 审计脚本**只读**，不会删除任何东西。
- 清理脚本默认 **dry-run**，必须显式 `--apply`。
- 不碰 `~/Documents`、桌面源码、下载文件、照片、邮件、聊天记录。
- 不碰 `~/Library/Containers` 整体，不碰模拟器 runtime，不碰 Claude Code。
- 需要 `sudo` 的项目只给命令和建议，不偷偷提权。
- 每批删除后用 `df` 对比，报告“逻辑大小”和“实际释放”两个数字。

## 仓库结构

```text
mac-storage-rescue/
├── SKILL.md                     # Codex 读取的技能说明
├── README.md                    # 人类阅读的快速开始
├── agents/openai.yaml           # Skill UI 元数据
├── scripts/
│   ├── audit_mac.sh             # 只读审计，输出 Markdown
│   └── clean_safe.sh            # Tier 1 缓存清理，默认 dry-run
└── references/
    ├── methodology.md           # 分层诊断、命令、风险分级、反模式
    └── case-study.md            # 512MB → 47GB 实战复盘
```

## 适合谁

- Mac 只剩几 GB，系统提示“启动磁盘几乎已满”；
- “系统数据”几十 GB，但不知道在哪里；
- 做前端/iOS 开发，`node_modules`、Xcode、模拟器越积越多；
- 想清理，但不想把聊天记录和项目源码一起删掉。

## 不适合谁

- 想要“无脑一键全删”的人；
- 不愿意逐项确认用户数据的人；
- 把清理工具当数据恢复工具的人。

## License

MIT
