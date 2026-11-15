# 方法论：把“系统数据”拆开看

## 0. 先分清三个数字

macOS 的“储存空间”是一个分类视图，不是目录视图。`系统数据`、`文稿` 都可能是很多目录的合集。真正定位问题时，先分清：

| 数字 | 含义 | 用途 |
| --- | --- | --- |
| `df -h` | 文件系统可用空间 | 唯一可信的“还剩多少” |
| `du -sh` | 文件逻辑大小 | 找候选目录，不等同于可回收空间 |
| APFS 实际分配 | 共享块、克隆、快照后的物理占用 | 解释为什么删了 20GB，`df` 只多 4GB |

APFS 的 `clonefile` 会让多个文件共享同一批数据块。`du` 会把每个文件都算一遍，所以“15 份 1.4GB 的 Chrome 副本”看起来是 21GB，实际可能只占 4-5GB。判断清理效果，必须看 `df` 的前后差值。

## 1. 分层定位，不要一上来就删

按“卷 → 数据卷顶层 → 用户目录 → Library → App 容器 → 项目 → 单文件”逐层收敛：

```bash
df -h / /System/Volumes/Data
diskutil apfs list
tmutil listlocalsnapshots /
du -sxh "$HOME"/* "$HOME"/.[!.]* 2>/dev/null | sort -hr | head -30
du -sxh "$HOME/Library"/* 2>/dev/null | sort -hr | head -20
du -sxh "$HOME/Library/Application Support"/* 2>/dev/null | sort -hr | head -20
du -sxh "$HOME/Library/Containers"/* 2>/dev/null | sort -hr | head -20
```

关键观察点：

1. **先看 APFS 卷**：Data、System、Preboot、VM、Recovery 各占多少；有没有额外的 Simulator 卷。
2. **再看数据卷顶层**：`/Users`、`/Applications`、`/Library`、`/private`、`/System`。只看 `~` 会漏掉系统级缓存和模拟器。
3. **再看用户目录**：`Library` 通常是最大项，其次是 Desktop/Downloads。
4. **最后看单文件**：安装包、视频、`.zip`、虚拟机磁盘、旧备份。

## 2. 必查清单

| 检查项 | 命令 | 典型结论 |
| --- | --- | --- |
| 本地快照 | `tmutil listlocalsnapshots /` | 为空则没有可删快照；有则再用 `sudo tmutil deletelocalsnapshots /` |
| APFS 卷 | `diskutil apfs list` | 看 Data/VM/Preboot/Simulator 各占多少 |
| 主目录 | `du -sxh ~/* ~/.[!.]* \| sort -hr` | 找 Library、Desktop、Downloads 的大头 |
| 应用支持 | `du -sxh ~/Library/Application\ Support/* \| sort -hr` | Claude、Cursor、Steam、微信开发者工具等 |
| 容器 | `du -sxh ~/Library/Containers/* \| sort -hr` | 飞书、微信、钉钉、Office |
| 缓存 | `du -sxh ~/Library/Caches/* \| sort -hr` | Chrome、Codex、ClashX；通常不是最大头 |
| Xcode | `du -sh ~/Library/Developer/Xcode/*` | DeviceSupport、DerivedData |
| 模拟器 | `du -sh /Library/Developer/CoreSimulator/*` | 一个 iOS runtime 可能 15-20GB |
| 浏览器临时目录 | `find /private/var/folders -name com.google.Chrome.code_sign_clone` | Chrome 的克隆副本可能堆积几十 GB |
| 开发缓存 | `find ~/Desktop -path '*/node_modules/.vite' -prune` | Vite 缓存可能比依赖本身还大 |
| 旧 iPhone 备份 | `du -sh ~/Library/Application\ Support/MobileSync/Backup` | 不存在或很小就跳过 |
| 大文件 | `find ~ -type f -size +500M` | 安装包、视频、虚拟机镜像、压缩包 |
| 卸载残留 | 对比 `/Applications` 与 `/Library/Application Support` | Adobe、Logic 等可能 App 没了但支持文件还在 |

`du -x` 的 `-x` 很重要：它避免跨文件系统统计，防止把挂载卷重复算进来。

## 3. 六类高频“隐形占用”

### 3.1 临时目录里的浏览器克隆

Chrome 在 macOS 上会为代码签名创建 `code_sign_clone.*`。正常情况用完即删，但某些版本会残留：

```text
/private/var/folders/**/X/com.google.Chrome.code_sign_clone/
  code_sign_clone.xxxxxx/Google Chrome.app   # 每份约 1.4GB
```

判断方法：数一下 `code_sign_clone.*` 的个数；只保留最新一份，删其余。Chrome 正在运行时也可以删旧副本，但保留最新一份更稳。

### 3.2 前端构建缓存

Vite 的 `node_modules/.vite` 会缓存预构建依赖，可能达到数 GB；`.next/cache`、`.turbo`、`.parcel-cache` 同理。它们是纯缓存，删掉后下次 `dev/build` 会重建。

```bash
find ~/Desktop -type d -path '*/node_modules/.vite' -prune -exec du -sh {} +
```

注意：不要把整个 `node_modules` 当成缓存随便删。删除后项目需要重新安装依赖，离线时可能无法恢复。

### 3.3 Xcode 与模拟器

三个不同层级：

| 目录 | 作用 | 删除代价 |
| --- | --- | --- |
| `~/Library/Developer/Xcode/DerivedData` | 编译中间产物 | 下次编译变慢 |
| `~/Library/Developer/Xcode/iOS DeviceSupport` | 真机调试符号 | 连接设备时重新生成 |
| `/Library/Developer/CoreSimulator/Volumes/...` | iOS Simulator runtime | 需要重新下载，通常 15-20GB |

如果只用真机、不用 Simulator，模拟器 runtime 是最大的一块可回收空间。删除前确认 `xcrun simctl list runtimes` 和最近是否用过 Simulator。

### 3.4 App 容器与聊天缓存

飞书、微信、钉钉等 Electron/原生混合应用会把缓存、日志、图片、附件放在 `~/Library/Containers/...`。这里既有缓存，也有聊天记录，不能整目录删。

优先顺序：

1. 用 App 自己的“存储空间/清理缓存”功能；
2. 退出 App 后，只删明确的 `Cache`、`log`、临时目录；
3. 聊天记录/附件只有在用户明确同意后才删。

### 3.5 卸载残留

App 被拖进废纸篓，不等于支持文件消失。典型：

- `/Library/Application Support/Adobe`：Photoshop 卸载后仍可能保留数 GB；
- `/Library/Application Support/Logic`：Logic/GarageBand 的音色采样；
- `~/Movies/JianyingPro/User Data/Cache`：剪映缓存；
- `~/Library/Application Support/Claude/vm_bundles`：Claude Cowork 的虚拟机镜像，和 Claude Code 是两套东西。

判断“是不是残留”：看 `/Applications` 是否还有对应 App，再看最近使用时间。不要只凭文件夹名字删。

### 3.6 用户文件与备份

- `~/Downloads`：安装包、视频、压缩包，通常最容易堆；
- `~/Desktop`：项目目录、素材、导出文件；
- `~/Documents`：正式文稿；
- `~/Library/Application Support/MobileSync/Backup`：旧 iPhone/iPad 备份；
- Time Machine 本地快照：`tmutil listlocalsnapshots /`。

这些属于用户数据，必须逐个确认，不能按“缓存”处理。

## 4. 删除风险分级

| 等级 | 类型 | 例子 | 处理方式 |
| --- | --- | --- | --- |
| Tier 0 | 只读审计 | `df`、`du`、`tmutil listlocalsnapshots` | 随时可做 |
| Tier 1 | 可重建缓存 | DerivedData、Vite、uv、Chrome 旧克隆、更新器缓存 | 可自动清理，先 dry-run |
| Tier 2 | App 状态/缓存 | 飞书/微信缓存、Cursor 快照、浏览器缓存 | 退出 App，优先用 App 内清理 |
| Tier 3 | 用户数据 | 下载、桌面、文稿、聊天记录、iPhone 备份 | 逐项明确确认 |
| Tier 4 | 系统/管理员 | 模拟器 runtime、`/Library` 残留、sleepimage | 解释影响，用户授权后执行 |

核心原则：**删除的不可逆程度越高，确认要求越高。**

## 5. 判断“这个目录能不能删”的四个问题

1. 它是缓存/构建产物，还是用户创建的内容？
2. 删除后能否自动重建？重建需要下载吗？需要多久？
3. 对应 App 是否还在使用？是否正在运行？
4. 删掉会影响登录、聊天记录、项目运行或系统启动吗？

四个问题里只要有一个答案不确定，就先不要删，改为报告候选。

## 6. 验证

每次批量删除前后都记录：

```bash
df -h /System/Volumes/Data
```

然后：

- 重新打开 Chrome，确认能正常启动；
- 打开 Xcode，确认能编译（第一次会重建 DerivedData）；
- 打开飞书/微信，确认能登录、历史记录符合预期；
- 如果删了模拟器 runtime，确认 `xcrun simctl list runtimes` 状态；
- 如果删了壁纸缓存，确认当前壁纸没有变成黑屏。

报告时同时写“逻辑大小”和“`df` 实际变化”，不要只报 `du` 的数字。

## 7. 常见反模式

- `rm -rf ~/Library/Caches/*`：可能删掉 App 正在使用的状态文件，也可能因权限留下半套目录。
- `sudo tmutil deletelocalsnapshots /` 不看有没有快照：没有快照时是空操作，没必要输密码。
- 把 `du` 总和当成可回收空间：APFS 克隆/快照会让数字严重偏高。
- 删除整个 `~/Library/Containers`：等于删掉多个 App 的登录态和本地数据。
- 反复删 `/private/var/vm/sleepimage`：系统会重建，且可能影响休眠。
- 为了清空间关闭 SIP：风险远大于收益。
- 用“清理大师”一键扫描后全选删除：它不知道你的项目依赖和聊天记录是否重要。

## 8. 一页流程

```text
1. df + diskutil apfs list + tmutil listlocalsnapshots
2. 数据卷顶层 → 用户目录 → Library → App 容器 → 项目 → 大文件
3. 标记 Tier 1 / 2 / 3 / 4
4. Tier 1 先 dry-run，再 apply
5. Tier 2/3/4 逐项说明影响并确认
6. df 前后对比，重启关键 App 验证
7. 输出：删了什么、为什么安全、还有什么没删、怎么删
```
