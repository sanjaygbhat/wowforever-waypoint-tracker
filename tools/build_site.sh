#!/bin/sh
# Builds the GitHub Pages site (site/ plus the README's images) into _site,
# or the folder given. The version comes from the addon's .toc.
set -eu
out=${1:-_site}
version=$(sed -n 's/^## Version: *//p' WaypointTracker/WaypointTracker.toc | tr -d '\r')
date=$(git log -1 --format=%cs 2>/dev/null || date -u +%F)
rm -rf "$out"
mkdir -p "$out/img"
cp docs/images/arrow-demo.gif docs/screenshots/*.jpg docs/release/social-preview.png docs/release/logo-400.png "$out/img/"
for f in site/*; do
  sed -e "s/@VERSION@/$version/g" -e "s/@DATE@/$date/g" "$f" > "$out/$(basename "$f")"
done
if grep -rl '@VERSION@\|@DATE@' "$out" >/dev/null; then
  echo "placeholders left in $out"; exit 1
fi
echo "built $out (version $version, $date)"
