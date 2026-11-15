#!/bin/bash
#
# Tier-1 cleanup only: regenerable caches that can be rebuilt without user data.
# Dry-run by default. Nothing is deleted until --apply is supplied.
#
set -u

APPLY=0
YES=0
PROJECTS=""
WALLPAPER=0

usage() {
  cat <<'EOF'
Usage: clean_safe.sh [options]

Options:
  --projects DIR       Also clear Vite/Next/Turbo caches under DIR
  --wallpaper-cache    Clear aerial wallpaper cache only when it is not active
  --apply              Delete the listed targets (default is dry-run)
  --yes                Skip the interactive confirmation with --apply
  -h, --help           Show this help

This script never touches Documents, Desktop files, Downloads, chat history,
Photos, Mail, app containers, simulator runtimes, or VMs.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --projects)
      PROJECTS="${2:-}"
      shift 2
      ;;
    --wallpaper-cache)
      WALLPAPER=1
      shift
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    --yes)
      YES=1
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

LIST_FILE=$(mktemp -t mac-storage-rescue)
trap 'find "$LIST_FILE" -delete 2>/dev/null || true' EXIT

add_target() {
  local label="$1"
  local path="$2"
  [ -e "$path" ] || return 0
  local size
  size=$(du -sh "$path" 2>/dev/null | awk '{print $1}')
  printf '%s\t%s\t%s\n' "$label" "$size" "$path" >> "$LIST_FILE"
}

add_chrome_clones() {
  find /private/var/folders -maxdepth 6 -type d -name com.google.Chrome.code_sign_clone -user "$USER" -print 2>/dev/null |
    while IFS= read -r root; do
      find "$root" -mindepth 1 -maxdepth 1 -type d -name 'code_sign_clone.*' -print0 2>/dev/null |
        while IFS= read -r -d '' dir; do
          printf '%s\t%s\n' "$(stat -f '%m' "$dir" 2>/dev/null)" "$dir"
        done |
        sort -rn |
        tail -n +2 |
        cut -f2- |
        while IFS= read -r dir; do
          add_target "Chrome code-sign clone (non-newest)" "$dir"
        done
    done
}

add_project_caches() {
  [ -n "$PROJECTS" ] && [ -d "$PROJECTS" ] || return 0
  find "$PROJECTS" -maxdepth 8 -type d \
    \( -path '*/node_modules/.vite' -o -path '*/.next/cache' -o -name .turbo -o -name .parcel-cache \) \
    -prune -print0 2>/dev/null |
    while IFS= read -r -d '' dir; do
      add_target "Project build cache" "$dir"
    done
}

add_chrome_clones
add_target "Xcode DerivedData" "$HOME/Library/Developer/Xcode/DerivedData"
add_target "uv package cache" "$HOME/.cache/uv"
add_target "JianyingPro cache" "$HOME/Movies/JianyingPro/User Data/Cache"

for dir in "$HOME"/Library/Caches/com.todesktop.*.ShipIt; do
  [ -d "$dir" ] && add_target "Desktop app updater cache" "$dir"
done

add_project_caches

if [ "$WALLPAPER" -eq 1 ]; then
  wallpaper_setting=$(defaults read com.apple.wallpaper 2>/dev/null || true)
  case "$wallpaper_setting" in
    *aerials*)
      echo "Skipping aerial wallpaper cache: an aerial wallpaper appears to be active." >&2
      ;;
    *)
      add_target "Aerial wallpaper cache" "$HOME/Library/Application Support/com.apple.wallpaper/aerials"
      ;;
  esac
fi

if [ ! -s "$LIST_FILE" ]; then
  echo "No Tier-1 cleanup targets found."
  exit 0
fi

echo "Tier-1 cleanup plan (regenerable caches only):"
echo
while IFS=$'\t' read -r label size path; do
  printf '  %-8s %s\n           %s\n' "$size" "$label" "$path"
done < "$LIST_FILE"
echo

if [ "$APPLY" -eq 0 ]; then
  echo "Dry run only. Re-run with:"
  echo "  $0 --apply --yes${PROJECTS:+ --projects \"$PROJECTS\"}"
  exit 0
fi

if [ "$YES" -ne 1 ]; then
  printf 'Delete these Tier-1 caches? [y/N] '
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
fi

before=$(df -k /System/Volumes/Data 2>/dev/null | awk 'NR==2 {print $4}')
failed=0

while IFS=$'\t' read -r label size path; do
  if [ -e "$path" ]; then
    printf 'Deleting %s (%s)...\n' "$label" "$size"
    if ! find "$path" -depth -delete 2>/dev/null; then
      echo "  Failed or partially blocked: $path" >&2
      failed=1
    fi
  fi
done < "$LIST_FILE"

after=$(df -k /System/Volumes/Data 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "${before:-}" ] && [ -n "${after:-}" ]; then
  freed_mb=$(( (after - before) / 1024 ))
  echo
  echo "Actual free-space change: ${freed_mb} MB"
fi

if [ "$failed" -eq 1 ]; then
  echo "Some targets could not be fully removed. Check permissions or whether an app is using them." >&2
fi

df -h /System/Volumes/Data 2>/dev/null
