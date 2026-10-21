#!/usr/bin/env bash
# Build neuro-fpga bitstreams via FuseSoC (requires Xilinx ISE 14.7 on PATH).
set -euo pipefail

usage() {
    echo "Usage: $0 rhs|rhd" >&2
    echo "  Streams ISE/xtclsh output to the terminal and to build/<board>/fuse-build.log." >&2
    echo "  Set FUSE_BUILD_QUIET=1 to disable fusesoc --verbose." >&2
    exit 1
}

board="${1:-}"
[[ -n "$board" ]] || usage

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

if [[ -n "${XILINX_ISE_SETTINGS:-}" && -f "${XILINX_ISE_SETTINGS}" ]]; then
    # shellcheck source=/dev/null
    source "${XILINX_ISE_SETTINGS}"
elif ! command -v xtclsh >/dev/null 2>&1; then
    echo "xtclsh not found. Set XILINX_ISE_SETTINGS to your ISE settings64.sh path." >&2
    exit 1
fi

case "$board" in
    rhs)
        core="paulmthompson:neuro-fpga:rhs_xem6010:0.1.0"
        build_root="build/rhs-xem6010"
        ;;
    rhd)
        core="paulmthompson:neuro-fpga:rhd_xem6310:0.1.0"
        build_root="build/rhd-xem6310"
        ;;
    *)
        usage
        ;;
esac

mkdir -p "$build_root"
log_file="$build_root/fuse-build.log"

fusesoc_args=(run --work-root="$build_root" --target=bitstream "$core")
if [[ "${FUSE_BUILD_QUIET:-0}" != "1" ]]; then
    fusesoc_args=(--verbose "${fusesoc_args[@]}")
fi

echo "FuseSoC + ISE build: $core"
echo "Work directory: $root/$build_root"
echo "Terminal log also written to: $log_file"
echo "---"

set -o pipefail
# Edalize runs make with captured output unless FuseSoC verbose is set.
uv run fusesoc "${fusesoc_args[@]}" 2>&1 | tee "$log_file"

echo "---"
echo "On success, bitstream: $root/$build_root/main.bit"
