#!/bin/sh
# Native ARM64 Docker host; output is a manual-run proof bundle, not a disk image.
set -eu
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
kit_dir=$(dirname "$script_dir")
command -v docker >/dev/null 2>&1 || { echo "error: Docker is required" >&2; exit 1; }
case "$(uname -m)" in aarch64|arm64) ;; *) echo "error: use an ARM64 Docker host" >&2; exit 1 ;; esac
mkdir -p "$kit_dir/build/openauto-proof"
docker run --rm --platform linux/arm64 \
 -v "$kit_dir:/kit:ro" -v "$kit_dir/build/openauto-proof:/output" \
 debian:trixie-slim /bin/sh /kit/openauto-proof/build-container.sh
