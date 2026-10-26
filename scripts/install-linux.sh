#!/usr/bin/env bash
# Per-user installer for a release bundle or a built source checkout.
# Installs executable files only; the catalog is never removed.
set -euo pipefail
prefix="${HOME}/.local"
uninstall=false
while (($#)); do
  case "$1" in
    --prefix) [[ $# -ge 2 ]] || { echo 'Missing --prefix path' >&2; exit 2; }; prefix=$2; shift 2 ;;
    --uninstall) uninstall=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ $prefix == /* && $prefix != / ]] || { echo 'Use an absolute, non-root installation prefix.' >&2; exit 2; }
app_id=io.github.sudharamachandranrajeev.vastra
dest="$prefix/lib/vastra"
bin="$prefix/bin/vastra"
desktop="$prefix/share/applications/$app_id.desktop"
icon="$prefix/share/icons/hicolor/512x512/apps/$app_id.png"
if [[ -e $dest && ! -f $dest/.vastra-install ]]; then
  echo "Refusing to replace an unmanaged directory: $dest" >&2; exit 1
fi
if [[ -e $bin || -L $bin ]]; then
  [[ -L $bin && $(readlink "$bin") == "$dest/vastra" ]] || { echo "Refusing to replace an existing launcher: $bin" >&2; exit 1; }
fi
if [[ -e $desktop ]] && ! grep -q '^X-Vastra-Managed=true$' "$desktop"; then
  echo "Refusing to replace an unmanaged desktop entry: $desktop" >&2; exit 1
fi
if $uninstall; then
  [[ ! -e $dest ]] || rm -rf -- "$dest"
  rm -f -- "$bin" "$desktop" "$icon"
  command -v update-desktop-database >/dev/null && update-desktop-database -q "$prefix/share/applications" || true
  echo 'Vastra removed. Your catalog and collections have been kept.'
  exit 0
fi
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x $here/vastra ]]; then
  bundle="$here"; png="$here/vastra.png"
else
  root="$(cd -- "$here/.." && pwd)"
  bundle="$root/native/build/linux/x64/release/bundle"; png="$root/branding/vastra-512.png"
fi
[[ -x $bundle/vastra && -d $bundle/lib && -d $bundle/data && -f $png ]] || { echo 'No complete build found. Run: cd native && flutter build linux --release' >&2; exit 1; }
mkdir -p -- "$prefix/lib" "$prefix/bin" "$prefix/share/applications" "$(dirname -- "$icon")"
staging="$(mktemp -d "$prefix/lib/.vastra-stage.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
cp -a -- "$bundle/vastra" "$bundle/lib" "$bundle/data" "$staging/"
touch "$staging/.vastra-install"
old=""
if [[ -e $dest ]]; then old="$(mktemp -d "$prefix/lib/.vastra-old.XXXXXX")"; rmdir "$old"; mv -- "$dest" "$old"; fi
if ! mv -- "$staging" "$dest"; then [[ -z $old ]] || mv -- "$old" "$dest"; exit 1; fi
trap - EXIT
[[ -z $old ]] || rm -rf -- "$old"
ln -sfn -- "$dest/vastra" "$bin"
cp -- "$png" "$icon"
# Desktop Exec uses its own quoting rules, including literal percent escaping.
exec_path=${dest//\\/\\\\}; exec_path=${exec_path//\"/\\\"}; exec_path=${exec_path//\$/\\\$}; exec_path=${exec_path//\`/\\\`}; exec_path=${exec_path//%/%%}
cat > "$desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Vastra
GenericName=Fashion discovery
Comment=Discover fashion and beauty; collect and compare product finds
Exec="$exec_path/vastra"
Icon=$app_id
Terminal=false
Categories=Utility;
Keywords=fashion;clothing;beauty;fragrance;shopping;catalog;
StartupWMClass=$app_id
X-Vastra-Managed=true
DESKTOP
command -v update-desktop-database >/dev/null && update-desktop-database -q "$prefix/share/applications" || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q "$prefix/share/icons/hicolor" 2>/dev/null || true
echo "Vastra installed. Open it from your launcher, or run: $bin"
