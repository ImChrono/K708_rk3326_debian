#!/bin/sh
# Run only in the disposable container created by build-openauto-proof.sh.
set -eu
[ -f /.dockerenv ] && [ "$(dpkg --print-architecture)" = arm64 ] || exit 1
# shellcheck source=configs/openauto-proof.sources
. /kit/configs/openauto-proof.sources
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
 ca-certificates git build-essential cmake ninja-build pkg-config \
 libboost-all-dev libprotobuf-dev protobuf-compiler libusb-1.0-0-dev libssl-dev \
 qtbase5-dev qtmultimedia5-dev qtconnectivity5-dev librtaudio-dev \
 libtag1-dev libblkid-dev libgps-dev libgl1-mesa-dev libgles2-mesa-dev \
 file binutils xz-utils python3
mkdir -p /work
cd /work
fetch() {
 name=$1
 revision=$2
 git init "$name"
 git -C "$name" remote add origin "https://github.com/opencardev/$name.git"
 git -C "$name" fetch --depth 1 origin "$revision"
 git -C "$name" checkout --detach FETCH_HEAD
 [ "$(git -C "$name" rev-parse HEAD)" = "$revision" ]
}
fetch aasdk "$AASDK_COMMIT"
fetch openauto "$OPENAUTO_COMMIT"
cmake -S aasdk -B aasdk-build -G Ninja \
 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DAASDK_TEST=OFF
cmake --build aasdk-build --parallel 2
cmake --install aasdk-build
ldconfig
cmake -S openauto -B openauto-build -G Ninja \
 -DCMAKE_BUILD_TYPE=Release -DNOPI=ON
cmake --build openauto-build --parallel 2
stage=/work/k708-openauto
mkdir -p "$stage/bin" "$stage/lib" "$stage/share"
cp openauto-build/bin/autoapp "$stage/bin/"
cp -a aasdk-build/lib/libaasdk.so* aasdk-build/lib/libaap_protobuf.so* "$stage/lib/"
cp /kit/openauto-proof/run.sh "$stage/"
cp /kit/openauto-proof/openauto.ini "$stage/share/"
cp /kit/configs/openauto-proof.sources "$stage/share/"
cp /kit/docs/OPENAUTO-PROOF.md "$stage/README.md"
# Derive exact runtime packages from the ELF dependencies, not guessed ABI names.
LD_LIBRARY_PATH="$stage/lib" ldd "$stage/bin/autoapp" > /output/ldd.txt
if grep -q 'not found' /output/ldd.txt; then cat /output/ldd.txt; exit 1; fi
readelf -h "$stage/bin/autoapp" > /output/elf.txt
grep -q 'AArch64' /output/elf.txt
if readelf -d "$stage/bin/autoapp" | grep -Eq 'libbcm_host|libopenmaxil|libvchiq'; then
 echo "error: Pi libraries linked despite NOPI" >&2; exit 1
fi
python3 /kit/openauto-proof/runtime-packages.py /output/ldd.txt > "$stage/runtime-packages.txt"
dpkg-query -W > /output/build-packages.txt
cp /output/elf.txt /output/ldd.txt /output/build-packages.txt "$stage/share/"
# Include exact upstream sources and the recipe alongside the experimental binary.
mkdir -p /work/sources
cp -a aasdk openauto /work/sources/
cp -a /kit/openauto-proof /kit/configs/openauto-proof.sources /work/sources/
tar --exclude=.git -cJf /output/openauto-proof-sources.tar.xz -C /work sources
tar -cJf /output/k708-openauto-arm64.tar.xz -C /work k708-openauto
cd /output
sha256sum k708-openauto-arm64.tar.xz openauto-proof-sources.tar.xz > SHA256SUMS
