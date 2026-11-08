#!/usr/bin/env bash
# Cross-compile javcli and write release archives plus SHA256SUMS to dest.
set -euo pipefail

tag="${1:?usage: build_release_assets.sh vX.Y.Z [destdir]}"
dest="${2:-dist}"

if ! [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
  echo "version tag must look like v1.2.3 or v1.2.3-rc.1" >&2
  exit 1
fi

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"

case "$dest" in
  /*) ;;
  *) dest="$root/$dest" ;;
esac
if [[ "$dest" == "/" || "$dest" == "$root" ]]; then
  echo "refusing to use $dest as the output directory" >&2
  exit 1
fi

commit=$(git rev-parse --short=12 HEAD)
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ldflags="-s -w -X github.com/taichi/javcli/cmd.version=${tag} -X github.com/taichi/javcli/cmd.commit=${commit} -X github.com/taichi/javcli/cmd.date=${built_at}"

rm -rf "$dest"
mkdir -p "$dest"

targets=(
  "linux amd64"
  "linux arm64"
  "darwin amd64"
  "darwin arm64"
  "windows amd64"
  "windows arm64"
)

for pair in "${targets[@]}"; do
  read -r goos goarch <<<"$pair"
  bin="javcli"
  if [[ "$goos" == "windows" ]]; then
    bin="javcli.exe"
  fi
  work=$(mktemp -d)
  CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
    go build -trimpath -ldflags "$ldflags" -o "$work/$bin" .
  archive_base="$dest/javcli_${tag}_${goos}_${goarch}"
  if [[ "$goos" == "windows" ]]; then
    python3 - "$archive_base.zip" "$work/$bin" "$bin" <<'PY'
import sys
import zipfile

dest, src, name = sys.argv[1:]
with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    archive.write(src, arcname=name)
PY
  else
    tar -C "$work" -czf "$archive_base.tar.gz" "$bin"
  fi
  rm -rf "$work"
done

(
  cd "$dest"
  files=()
  while IFS= read -r file; do
    files+=("$file")
  done < <(find . -type f ! -name SHA256SUMS | sort)
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${files[@]}" > SHA256SUMS
  else
    shasum -a 256 "${files[@]}" > SHA256SUMS
  fi
)

echo "wrote release assets to $dest"
