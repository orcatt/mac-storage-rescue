#!/bin/bash
#
# Read-only macOS storage audit. Prints a Markdown report and never deletes.
#
set -u

OUTPUT=""
PROJECTS="$HOME/Desktop"
FAST=0

usage() {
  cat <<'EOF'
Usage: audit_mac.sh [options]

Options:
  --output FILE    Also write the Markdown report to FILE
  --projects DIR   Scan DIR for node_modules and build caches (default: ~/Desktop)
  --fast           Skip the large-file scan
  -h, --help       Show this help

The audit is read-only. Review references/methodology.md before interpreting it.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --output)
      OUTPUT="${2:-}"
      shift 2
      ;;
    --projects)
      PROJECTS="${2:-}"
      shift 2
      ;;
    --fast)
      FAST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

DATA_VOL="/System/Volumes/Data"
[ -d "$DATA_VOL" ] || DATA_VOL="/"

section() {
  printf '\n## %s\n\n' "$1"
}

code_start() {
  printf '```text\n'
}

code_end() {
  printf '```\n'
}

print_path_size() {
  local label="$1"
  local path="$2"
  if [ -e "$path" ]; then
    printf -- '- %s: `%s` (%s)\n' "$label" "$path" "$(du -sh "$path" 2>/dev/null | awk '{print $1}')"
  else
    printf -- '- %s: not present\n' "$label"
  fi
}

top_dirs() {
  local dir="$1"
  local count="${2:-12}"
  if [ ! -d "$dir" ]; then
    printf '_Not present: %s_\n' "$dir"
    return
  fi
  du -sxh "$dir"/* "$dir"/.[!.]* 2>/dev/null | sort -hr | head -n "$count"
}

find_dirs_with_sizes() {
  local root="$1"
  local maxdepth="$2"
  shift 2
  find "$root" -maxdepth "$maxdepth" -type d "$@" -prune -print0 2>/dev/null |
    while IFS= read -r -d '' dir; do
      du -sh "$dir" 2>/dev/null
    done |
    sort -hr
}

audit() {
  printf '# macOS Storage Audit\n\n'
  printf -- '- Generated: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
  printf -- '- Host: `%s`\n' "$(hostname)"
  printf -- '- macOS: `%s`\n' "$(sw_vers -productVersion 2>/dev/null)"
  printf -- '- Data volume: `%s`\n' "$DATA_VOL"

  section "Volumes and free space"
  code_start
  df -h / "$DATA_VOL" 2>/dev/null
  code_end

  printf '\n### APFS volumes and snapshots\n\n'
  code_start
  diskutil apfs list 2>/dev/null |
    grep -E 'APFS Volume Disk|Name:|Capacity Consumed|Capacity In Use|Capacity Not Allocated|Snapshot:' |
    head -80
  code_end

  section "Time Machine"
  code_start
  echo "Local snapshots:"
  tmutil listlocalsnapshots / 2>&1 | head -30
  echo
  echo "Destinations:"
  tmutil destinationinfo 2>&1 | head -20
  code_end

  section "Home top-level"
  code_start
  top_dirs "$HOME" 25
  code_end

  section "Library hotspots"
  printf '### ~/Library\n\n'
  code_start
  top_dirs "$HOME/Library" 15
  code_end

  printf '\n### ~/Library/Application Support\n\n'
  code_start
  top_dirs "$HOME/Library/Application Support" 15
  code_end

  printf '\n### ~/Library/Containers\n\n'
  code_start
  top_dirs "$HOME/Library/Containers" 12
  code_end

  printf '\n### ~/Library/Developer\n\n'
  code_start
  top_dirs "$HOME/Library/Developer" 10
  code_end

  printf '\n### ~/Library/Caches\n\n'
  code_start
  top_dirs "$HOME/Library/Caches" 12
  code_end

  section "Xcode and simulator"
  print_path_size "Xcode DerivedData" "$HOME/Library/Developer/Xcode/DerivedData"
  print_path_size "CoreSimulator caches" "/Library/Developer/CoreSimulator/Caches"
  print_path_size "CoreSimulator volumes" "/Library/Developer/CoreSimulator/Volumes"

  printf '\n### iOS DeviceSupport versions\n\n'
  code_start
  if [ -d "$HOME/Library/Developer/Xcode/iOS DeviceSupport" ]; then
    find "$HOME/Library/Developer/Xcode/iOS DeviceSupport" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null |
      while IFS= read -r -d '' dir; do
        du -sh "$dir" 2>/dev/null
      done |
      sort -hr
  else
    echo "not present"
  fi
  code_end

  printf '\n### Installed simulator runtimes\n\n'
  code_start
  xcrun simctl list runtimes 2>/dev/null | head -20
  code_end

  section "Project build caches"
  printf -- '- Scan root: `%s`\n\n' "$PROJECTS"
  code_start
  if [ -d "$PROJECTS" ]; then
    echo "Build caches:"
    find_dirs_with_sizes "$PROJECTS" 6 \
      \( -name .vite -o -name .turbo -o -name .parcel-cache -o -name .next \) |
      head -25
    echo
    echo "node_modules:"
    find_dirs_with_sizes "$PROJECTS" 3 -name node_modules | head -20
  else
    echo "not present"
  fi
  code_end

  section "Temporary files and browser clones"
  printf '### Chrome code-sign clones\n\n'
  code_start
  clone_report=$(
    find /private/var/folders -maxdepth 6 -type d -name com.google.Chrome.code_sign_clone -user "$USER" -print 2>/dev/null |
      while IFS= read -r dir; do
        count=$(find "$dir" -mindepth 1 -maxdepth 1 -type d -name 'code_sign_clone.*' 2>/dev/null | wc -l | tr -d ' ')
        total=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
        printf '%s\n  clones=%s total=%s\n' "$dir" "$count" "$total"
      done
  )
  if [ -n "$clone_report" ]; then
    printf '%s\n' "$clone_report"
  else
    echo "No Chrome code-sign clone directory found."
  fi
  code_end

  printf '\n### Browser and app caches\n\n'
  code_start
  print_path_size "Chrome cache" "$HOME/Library/Caches/Google"
  print_path_size "Codex cache" "$HOME/Library/Caches/Codex"
  print_path_size "ClashX cache" "$HOME/Library/Caches/com.MetaCubeX.ClashX.meta"
  code_end

  section "Review: app data and uninstalled-app leftovers"
  print_path_size "Claude Cowork VM (delete only if unused)" "$HOME/Library/Application Support/Claude/vm_bundles"
  print_path_size "Claude Code runtime (keep if using Claude Code)" "$HOME/Library/Application Support/Claude/claude-code"
  print_path_size "Adobe support files (check if app remains)" "/Library/Application Support/Adobe"
  print_path_size "Logic samples (check if Logic/GarageBand remains)" "/Library/Application Support/Logic"
  print_path_size "Aerial wallpaper cache" "$HOME/Library/Application Support/com.apple.wallpaper/aerials"
  print_path_size "JianyingPro cache" "$HOME/Movies/JianyingPro/User Data/Cache"
  print_path_size "Feishu container" "$HOME/Library/Containers/com.bytedance.macos.feishu"
  print_path_size "WeChat container" "$HOME/Library/Containers/com.tencent.xinWeChat"
  print_path_size "iPhone/iPad backups" "$HOME/Library/Application Support/MobileSync/Backup"
  print_path_size "Downloads" "$HOME/Downloads"
  print_path_size "Documents" "$HOME/Documents"
  print_path_size "Desktop" "$HOME/Desktop"

  printf '\nCurrent wallpaper setting:\n\n'
  code_start
  defaults read com.apple.wallpaper 2>/dev/null | head -20
  code_end

  if [ "$FAST" -eq 0 ]; then
    section "Large files over 500 MB"
    code_start
    find "$HOME" -type f -size +500M \
      -not -path "$HOME/Library/Containers/*" \
      -not -path "$HOME/Library/Application Support/Claude/vm_bundles/*" \
      2>/dev/null -exec du -sh {} + |
      sort -hr |
      head -30
    code_end
  else
    section "Large files over 500 MB"
    printf '_Skipped because --fast was used._\n'
  fi

  section "How to read this report"
  cat <<'EOF'
- `df` is the source of truth for free space.
- `du` reports logical file sizes. APFS clones share blocks, so a folder can look huge while deleting it frees much less.
- `System Data` in macOS Storage is not one folder. It usually combines `~/Library`, `/Library`, `/private/var`, simulators, caches, and app containers.
- Do not compare the sum of `du` outputs with `df` free space. Compare `df` before and after a known deletion.
- A large folder is a candidate, not a verdict. Check whether it is user data, a rebuildable cache, or app state.
EOF
}

if [ -n "$OUTPUT" ]; then
  audit | tee "$OUTPUT"
else
  audit
fi
