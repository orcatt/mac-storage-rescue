# 实战案例：512MB → 47GB

这是一次真实清理的脱敏记录。机器是一台 245GB 容量的 Mac，清理前数据卷使用约 193GB，只剩 512MB，系统已经接近无法正常写入。

## 初始观察

```text
/dev/disk3s5   228Gi   193Gi   512Mi   100%   /System/Volumes/Data
Container Total Space: 245.1 GB
Container Free Space:  537.2 MB
```

第一层 `du` 看到的主目录：

```text
62G  ~/Library
23G  ~/Desktop
3.1G ~/Movies
2.7G ~/.cache
1.8G ~/Downloads
1.0G ~/Documents
```

但这只能解释约 100GB。继续看数据卷顶层和 APFS：

```text
102G /System/Volumes/Data/Users
29G  /System/Volumes/Data/Applications
22G  /System/Volumes/Data/private
14G  /System/Volumes/Data/System
13G  /System/Volumes/Data/Library

Data:       206.0 GB consumed
Preboot:      9.0 GB
VM:          10.7 GB
System:      12.6 GB
Simulator:   17.1 GB (separate APFS container)
```

结论：这不是“某个软件太大”，而是多类数据叠在一起：应用缓存、Xcode、开发构建产物、浏览器临时文件、卸载残留。

## 找到的七个大头

### 1. Chrome 临时克隆：逻辑 21GB

```text
/private/var/folders/**/X/com.google.Chrome.code_sign_clone/
  15 × code_sign_clone.*，每份约 1.4GB
```

这是 Chrome 的代码签名克隆残留，不是用户文件。删除 14 份、保留最新 1 份后，`du` 看起来释放了约 20GB，但 `df` 实际只增加约 4.4GB。原因是这些副本通过 APFS 克隆共享数据块，`du` 把共享块重复计算了。

### 2. Vite 构建缓存：6.5GB

```text
~/Desktop/项目/某前端项目/frontend/node_modules/.vite   6.5G
```

外层看 `node_modules` 是 7.1GB，但单个依赖最大只有几十 MB。真正的体积藏在隐藏目录 `.vite`。这是纯预构建缓存，删除后下次 `dev` 自动重建。

### 3. Xcode：DerivedData 2.7GB + 旧 DeviceSupport 5.5GB

```text
~/Library/Developer/Xcode/DerivedData                 2.7G
~/Library/Developer/Xcode/iOS DeviceSupport/...26.3.1 5.5G
~/Library/Developer/Xcode/iOS DeviceSupport/...27.2.1 6.8G
```

旧版 DeviceSupport 对应旧 iOS 版本，连接设备时会重新生成；当前在用的 27.2.1 保留。

### 4. 剪映缓存：3.1GB

```text
~/Movies/JianyingPro/User Data/Cache   3.1G
```

纯缓存，项目文件在 `Projects`，没有动。

### 5. 壁纸和卸载残留：约 10GB

```text
~/Library/Application Support/com.apple.wallpaper/aerials   4.7G
/Library/Application Support/Adobe                          4.6G
/Library/Application Support/Logic                          0.9G
```

当前壁纸是系统 `Sequoia Sunrise`，没有使用 aerial 动态壁纸，所以 4.7GB 视频缓存可以删。Adobe 和 Logic 在 `/Applications` 里已经没有对应 App，属于卸载残留。

### 6. Claude Cowork 虚拟机：9.9GB

```text
~/Library/Application Support/Claude/vm_bundles/claudevm.bundle/rootfs.img   9.8G
```

这是 Claude Desktop 的 Cowork 虚拟机，不是 Claude Code。用户确认不用 Cowork、但每天用 Claude Code，因此只删虚拟机，保留：

```text
~/Library/Application Support/Claude/claude-code   949M
~/.claude                                          364M
~/Library/Application Support/Claude/claude-code-vm 348M
```

### 7. 微信本地聊天文件：2.3GB

```text
~/Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files   2.3G
```

用户明确确认可以删，且微信当时未运行。删除的是本地聊天文件/附件缓存；云端记录不受影响。

## 实际执行顺序

1. **只读审计**：`df`、`diskutil apfs list`、`tmutil listlocalsnapshots /`、逐层 `du`。
2. **Tier 1 缓存**：Chrome 旧克隆、DerivedData、旧 DeviceSupport、uv 缓存、更新器缓存、剪映缓存。
3. **确认后 Tier 2/3**：aerial 壁纸、Adobe/Logic 残留、Vite 缓存、Feishu 日志、Claude Cowork VM、微信本地聊天文件。
4. **Git 仓库整理**：对几个仓库执行 `git gc --prune=now`，把松散对象打包。
5. **验证**：每批删除后用 `df` 对比；Chrome、Xcode 保持可启动。

## 结果

| 阶段 | 可用空间 |
| --- | --- |
| 清理前 | 0.5GB |
| Chrome 旧克隆后 | 4.9GB |
| Xcode/剪映/uv 等缓存后 | 17GB |
| 壁纸/Logic/飞书日志后 | 23GB |
| Vite/Git 整理后 | 27GB |
| Adobe + 微信后 | 36GB |
| Claude Cowork VM 后 | 47GB |

最终释放约 **46GB** 实际空间。

清理完成后，Xcode 重新生成了约 3.6GB `DerivedData`，壁纸缓存也重新下载了约 0.9GB，所以当前可用空间回落到约 40GB。**47GB 是刚清完的峰值，40GB 是缓存重建后的稳定值**。这也是为什么报告要区分“本次释放”和“长期可用”。

## 刻意没删的东西

- 当前在用的 iPhone DeviceSupport（6.8GB）：还在真机调试。
- Xcode iOS 26.2 Simulator runtime（17.1GB）：用户可能仍用 Simulator。
- 飞书 `sdk_storage` 和微信 `app_data`：优先让 App 自己清理，避免登录态/插件异常。
- `~/Downloads`、桌面项目源码、`.git` 历史、`~/Documents`：用户数据。
- Claude Code 运行时和 `~/.claude`：用户每天都在用。

## 这次案例的三个教训

1. **“文稿很大”不一定是文档**：桌面项目里的 `node_modules/.vite`、Xcode 缓存和素材都会进入“文稿/系统数据”的分类。
2. **`du` 最大的目录不一定是最大回收项**：APFS 克隆会让 Chrome 临时目录看起来占 21GB，实际只回收 4.4GB。
3. **先分层，再决定**：同样是 `~/Library`，`Caches` 可以清，`Containers` 里的聊天记录不能整目录清。
