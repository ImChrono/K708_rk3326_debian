#!/bin/sh
# Launch manually from an available local VT after stopping the diagnostic dashboard.
set -eu
bundle_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
state_dir=${OPENAUTO_STATE_DIR:-"${XDG_STATE_HOME:-$HOME/.local/state}/k708-openauto"}
mkdir -p "$state_dir"
if [ ! -e "$state_dir/openauto.ini" ]; then
 cp "$bundle_dir/share/openauto.ini" "$state_dir/openauto.ini"
fi
export LD_LIBRARY_PATH="$bundle_dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-eglfs}
export QT_QPA_EGLFS_INTEGRATION=${QT_QPA_EGLFS_INTEGRATION:-eglfs_kms}
cd "$state_dir"
exec "$bundle_dir/bin/autoapp" "$@"
