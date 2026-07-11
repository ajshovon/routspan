#!/usr/bin/env bash
# Build a release APK per CPU architecture and copy them into
# dist/release-apks/ with clear names. Mirrors tool/build_debug_apks.sh, but
# release builds are AOT-compiled + tree-shaken, so these are much smaller
# (tens of MB total vs. one debug ABI alone) — see README for a size comparison.
#
# Usage:
#   tool/build_release_apks.sh                        # all ABIs
#   tool/build_release_apks.sh arm64-v8a               # only copy this one
#   tool/build_release_apks.sh arm64-v8a armeabi-v7a   # only copy these
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

# Signing is only real if a release signingConfig is wired up. As shipped,
# android/app/build.gradle.kts falls back to the debug keystore for release
# builds (see the TODO there) — fine for sideloading/testing, NOT for
# publishing to a store or handing out as a trusted "official" build.
if grep -q 'signingConfigs.getByName("debug")' android/app/build.gradle.kts 2>/dev/null; then
  echo "!! NOTE: release builds are currently signed with the DEBUG keystore"
  echo "   (android/app/build.gradle.kts has a TODO to add a real release"
  echo "   signingConfig). Fine for local testing; do not publish/distribute"
  echo "   these as an official release until that's fixed."
  echo ""
fi

app_name=$(sed -n 's/^name: *//p' pubspec.yaml | head -n1)
version=$(sed -n 's/^version: *//p' pubspec.yaml | head -n1 | cut -d+ -f1)

out_dir="dist/release-apks"
mkdir -p "$out_dir"

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build apk --release --split-per-abi"
flutter build apk --release --split-per-abi

src_dir="build/app/outputs/flutter-apk"
echo ""
echo "==> Copying requested ABIs to $out_dir/"
for abi in "${abis[@]}"; do
  src="$src_dir/app-${abi}-release.apk"
  if [ ! -f "$src" ]; then
    echo "  !! missing $src — skipping $abi" >&2
    continue
  fi
  dest="$out_dir/${app_name}-${version}-${abi}-release.apk"
  cp "$src" "$dest"
  size=$(du -h "$dest" | cut -f1 | tr -d ' ')
  printf '  %-70s %s\n' "$dest" "$size"
done

echo ""
echo "Done. Install one with: adb install -r <path>"
