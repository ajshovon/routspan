#!/usr/bin/env bash
# Build a debug APK per CPU architecture and copy them into dist/debug-apks/
# with clear names, instead of leaving them buried in build/.
#
# Usage:
#   tool/build_debug_apks.sh                        # all ABIs
#   tool/build_debug_apks.sh arm64-v8a               # only copy this one
#   tool/build_debug_apks.sh arm64-v8a armeabi-v7a   # only copy these
#
# Note: Flutter/Gradle always builds every configured ABI in one pass — you
# can't build a single architecture without editing android/app/build.gradle.kts
# — so passing an ABI here only filters which output(s) get copied to dist/.
set -euo pipefail

readonly ALL_ABIS=(arm64-v8a armeabi-v7a x86_64)

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

if ! command -v flutter >/dev/null 2>&1; then
  echo "error: flutter not found on PATH" >&2
  exit 1
fi

abis=("$@")
if [ "${#abis[@]}" -eq 0 ]; then
  abis=("${ALL_ABIS[@]}")
fi

for abi in "${abis[@]}"; do
  case "$abi" in
    arm64-v8a | armeabi-v7a | x86_64) ;;
    *)
      echo "error: unknown ABI '$abi'. Supported: ${ALL_ABIS[*]}" >&2
      exit 1
      ;;
  esac
done

app_name=$(sed -n 's/^name: *//p' pubspec.yaml | head -n1)
version=$(sed -n 's/^version: *//p' pubspec.yaml | head -n1 | cut -d+ -f1)

out_dir="dist/debug-apks"
mkdir -p "$out_dir"

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build apk --debug --split-per-abi"
flutter build apk --debug --split-per-abi

src_dir="build/app/outputs/flutter-apk"
echo ""
echo "==> Copying requested ABIs to $out_dir/"
for abi in "${abis[@]}"; do
  src="$src_dir/app-${abi}-debug.apk"
  if [ ! -f "$src" ]; then
    echo "  !! missing $src — skipping $abi" >&2
    continue
  fi
  dest="$out_dir/${app_name}-${version}-${abi}-debug.apk"
  cp "$src" "$dest"
  size=$(du -h "$dest" | cut -f1 | tr -d ' ')
  printf '  %-70s %s\n' "$dest" "$size"
done

echo ""
echo "Done. Install one with: adb install -r <path>"
