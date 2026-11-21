#!/usr/bin/env bash
# One gate per invocation, each printing the package it ran against (the campaign's rule: a log
# must name the bytes it proves).
#
#   tools/gates.sh test|clippy|fmt|check|fits|build
#
# Written for a build-slot lease: `build-slot.sh run --job W1-rftoolspower --port ports/rftoolspower
# --step <step> -- bash ports/rftoolspower/tools/gates.sh <step>` (or with `env BUILD_LOCAL=1`, since
# `cargo horizon-mod` is installed on this box only).
set -uo pipefail
cd "$(dirname "$0")/.."

PACKAGE=rftoolspower.hmod
step=${1:?usage: gates.sh test|clippy|fmt|check|fits|build}
if [ -f "$PACKAGE" ]; then
    echo "PACKAGE $PACKAGE sha256=$(sha256sum "$PACKAGE" | cut -d' ' -f1) bytes=$(stat -c%s "$PACKAGE")"
else
    echo "PACKAGE $PACKAGE absent (a build writes it)"
fi

case "$step" in
    test)
        rm -f Cargo.lock
        CARGO_INCREMENTAL=0 cargo test --offline
        ;;
    clippy)
        CARGO_INCREMENTAL=0 cargo clippy --all-targets --offline -- -D warnings
        ;;
    fmt)
        cargo fmt --check
        ;;
    check)
        cargo horizon-mod check "$PACKAGE"
        ;;
    fits)
        cargo horizon-mod fits "$PACKAGE" --build 0a875da
        cargo horizon-mod fits "$PACKAGE" --build 0b14f8a
        ;;
    build)
        rm -f Cargo.lock
        CARGO_INCREMENTAL=0 cargo horizon-mod build
        cp -f target/horizon-mod/"$PACKAGE" "$PACKAGE"
        echo "PACKAGE $PACKAGE sha256=$(sha256sum "$PACKAGE" | cut -d' ' -f1) bytes=$(stat -c%s "$PACKAGE")"
        ;;
    *)
        echo "unknown gate: $step" >&2
        exit 64
        ;;
esac
