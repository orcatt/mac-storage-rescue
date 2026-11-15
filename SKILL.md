---
name: mac-storage-rescue
description: Diagnose and safely reclaim disk space on a nearly full macOS Mac by tracing APFS volume usage, local snapshots, app caches, Xcode and simulator artifacts, dev build caches, and uninstalled-app leftovers. Use when macOS reports huge System Data or Documents usage, free space is critically low, or the user requests a deep cleanup without losing personal files.
metadata:
  short-description: Find hidden macOS disk hogs and reclaim space safely
---

# Mac Storage Rescue

Reclaim space by evidence, not by guessing. Find where the physical bytes went, classify every candidate by reversibility, and delete only at the confirmation level the data deserves.

## Non-negotiable rules

- Start read-only. Record `df` before changing anything.
- Never delete documents, photos, mail, messages, chat history, project source, or Downloads files without explicit user confirmation for that exact category.
- Never delete a whole `~/Library`, `~/Library/Caches`, `~/Library/Containers`, or `/Library` tree. Delete named subdirectories only.
- Check whether an app is running before touching its data. Quit it gracefully first.
- Treat APFS clones as shared blocks: `du` can overstate reclaimable space dramatically. Measure the real result with `df` before and after.
- Use `find "<exact path>" -depth -delete` for cleanup. Keep paths quoted and exact; never glob over the home directory.
- Use `sudo` only with explicit user approval, and show the exact command first.
- Verify the result and report both logical size and actual free-space change.

## Workflow

### 1. Baseline and read-only audit

```bash
df -h / /System/Volumes/Data
diskutil apfs list
tmutil listlocalsnapshots /
```

Run the bundled audit and save a report:

```bash
scripts/audit_mac.sh --output /tmp/mac-storage-audit.md
```

For a quicker pass without the large-file scan:

```bash
scripts/audit_mac.sh --fast --projects "$HOME/Desktop" --output /tmp/mac-storage-audit.md
```

Read `references/methodology.md` before interpreting the numbers. The important distinction is physical allocation versus logical `du` totals.

### 2. Reclaim only Tier 1 artifacts automatically

Dry-run first, then apply:

```bash
scripts/clean_safe.sh --projects "$HOME/Desktop"
scripts/clean_safe.sh --apply --yes --projects "$HOME/Desktop"
```

The safe script is limited to regenerable build/runtime caches. It intentionally does not touch app chat data, simulators, VMs, uninstalled-app support folders, wallpapers, or personal files.

### 3. Propose Tier 2 and Tier 3 items with evidence

Present a short table: path, size, what it is, what breaks if removed, how it regenerates. Ask for explicit approval per category. High-value candidates:

| Candidate | Typical location | Default decision |
| --- | --- | --- |
| Chrome code-sign clones | `/private/var/folders/**/X/com.google.Chrome.code_sign_clone` | Safe: keep newest, delete older copies |
| Vite/Next/Turbo caches | `*/node_modules/.vite`, `.next/cache`, `.turbo` | Safe: rebuilds on next dev/build |
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData` | Safe: rebuilds; first build is slower |
| Old iOS DeviceSupport | `~/Library/Developer/Xcode/iOS DeviceSupport` | Usually safe: regenerates when device connects |
| iOS Simulator runtime | `/Library/Developer/CoreSimulator/Volumes/...` | Ask: 10-20GB; only if Simulator is unused |
| Claude Cowork VM | `~/Library/Application Support/Claude/vm_bundles` | Ask: only if Cowork is unused; Claude Code is separate |
| Feishu/WeChat cache | app containers | Ask: prefer the app's own storage cleaner |
| Uninstalled-app leftovers | `/Library/Application Support/Adobe`, `Logic` | Ask: verify no matching app remains |
| Aerial wallpaper cache | `~/Library/Application Support/com.apple.wallpaper/aerials` | Ask: skip if an aerial wallpaper is active |
| iPhone backups | `~/Library/Application Support/MobileSync/Backup` | Ask: user data |
| Local Time Machine snapshots | `tmutil listlocalsnapshots /` | Ask: only when snapshots exist |
| User files | Desktop, Documents, Downloads | Explicit confirmation per file |

### 4. Verify and report

```bash
df -h /System/Volumes/Data
```

Report:

- before/after free space and actual GB reclaimed;
- categories deleted and why they were safe;
- anything skipped and the exact command or app setting needed to remove it;
- whether Chrome/Xcode/Feishu/WeChat should be restarted or will rebuild caches.

## Useful references

- `references/methodology.md` — layered diagnosis, commands, risk tiers, APFS caveats, and anti-patterns.
- `references/case-study.md` — sanitized 2026-11 case: 512MB free to 47GB free, including what was found and what was deliberately left alone.
- `README.md` — human-facing quick start and install instructions.
