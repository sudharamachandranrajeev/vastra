#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
version=${1:-0.2.0}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Use a numeric semantic version.' >&2; exit 2; }
bundle="$root/native/build/linux/x64/release/bundle"
[[ -x $bundle/vastra ]] || { echo 'Build the Linux app first.' >&2; exit 1; }
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
name="vastra-$version-linux-x64"
mkdir -p "$stage/$name" "$root/outputs/native"
cp -a "$bundle/." "$stage/$name/"
cp "$root/branding/vastra-512.png" "$stage/$name/vastra.png"
cp "$root/scripts/install-linux.sh" "$stage/$name/install.sh"
cat > "$stage/$name/README.txt" <<'README'
Vastra for Linux x86-64. Requires GTK 3 and the system OpenGL libraries.
./vastra                  run from this folder
./install.sh              install for your user, including launcher and icon
./install.sh --uninstall  remove the program; your catalog remains
Native data is local and separate from the hosted web catalog.
README
tar -czf "$root/outputs/native/Vastra-$version-linux-x64.tar.gz" -C "$stage" "$name"
sha=$(sha256sum "$root/outputs/native/Vastra-$version-linux-x64.tar.gz" | cut -d ' ' -f1)
sed -e "s/@VERSION@/$version/g" -e "s/@SHA256@/$sha/g" "$root/packaging/arch/PKGBUILD.in" > "$root/outputs/native/PKGBUILD"
echo "Packaged Vastra $version for Linux, with a checksum-pinned Arch PKGBUILD."
