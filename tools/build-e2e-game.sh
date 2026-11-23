#!/usr/bin/env bash
# Build a game that carries TWO mods: this port and the harness receiver it proves the generator's
# energy push against (`tools/harness-receiver/README.md`), then point the export
# `launcher-game.sh env rftoolspower` reads at that build.
#
#   ports/tools/launcher-game.sh build rftoolspower     # once: launcher, Nightly, instance, export
#   ports/rftoolspower/tools/build-e2e-game.sh          # rebuild the export with both mods
#   eval "$(ports/tools/launcher-game.sh env rftoolspower)"
#
# The launcher refuses nested package paths inside a mod folder, so the receiver's source is kept
# as `.in` files and materialised here, under the launcher's own scratch root (never /tmp).
set -Eeuo pipefail
CLONE=$(cd "$(dirname "$0")/../../.." && pwd)
ROOT=$CLONE/ports
PORT=$ROOT/rftoolspower
PIN=0a875da
E2E_ROOT=${HORIZON_E2E_ROOT:-$HOME/.cache/horizon-e2e}
LAUNCHER_VERSION=0.2.92
LAUNCHER=$ROOT/_shared/bin/launcher-$LAUNCHER_VERSION/horizon-launcher
DATA=$E2E_ROOT/root/data
CONFIG=$E2E_ROOT/root/config
HOME_DIR=$E2E_ROOT/root/home
VERSIONS=$DATA/horizon-launcher/versions
INSTANCE=${HORIZON_E2E_INSTANCE:-e2e}
MODSET=$E2E_ROOT/modset
EXPORT=$E2E_ROOT/$PIN/rftoolspower

say() { printf '%s: %s\n' "${0##*/}" "$*" >&2; }
die() { say "$*"; exit "${2:-1}"; }

[ -x "$LAUNCHER" ] || die "launcher not installed; run: ports/tools/launcher-game.sh ensure" 2
[ -x "$EXPORT/horizon-client" ] || die "no exported game; run: ports/tools/launcher-game.sh build rftoolspower" 2
[ -d "$VERSIONS" ] || die "no launcher versions under $VERSIONS" 3

rm -rf "$MODSET"
mkdir -p "$MODSET/rfpowerharness/src" "$MODSET/rfpowerharness/data/rfpowerharness/horizon/block"
rsync -a --delete \
    --exclude 'target' --exclude '*.hmod' --exclude 'tools/harness-receiver' \
    --exclude '__pycache__' \
    "$PORT/" "$MODSET/rftoolspower/"
cp -a "$PORT/.horizon" "$MODSET/rfpowerharness/.horizon"
cp -a "$PORT/tools/harness-receiver/flat/horizon-mod.toml.in" "$MODSET/rfpowerharness/horizon-mod.toml"
cp -a "$PORT/tools/harness-receiver/flat/Cargo.toml.in" "$MODSET/rfpowerharness/Cargo.toml"
cp -a "$PORT/tools/harness-receiver/flat/lib.rs.in" "$MODSET/rfpowerharness/src/lib.rs"
cp -a "$PORT/tools/harness-receiver/flat/receiver.json" \
      "$MODSET/rfpowerharness/data/rfpowerharness/horizon/block/receiver.json"

before=$(ls -1 "$VERSIONS" 2>/dev/null | tr '\n' ' ')
built_json=$(env XDG_DATA_HOME="$DATA" XDG_CONFIG_HOME="$CONFIG" HOME="$HOME_DIR" \
    "$LAUNCHER" native-build "$MODSET" --instance "$INSTANCE" --trust-native-code --json 2>&1) \
    || die "native-build of the two-mod set failed" 10
# The launcher *names* the build it selected ("native-… built and selected for its instance"), and
# that is the one matching these sources — also when it answers "Up to date (no build needed)".
# Picking by directory age instead once exported a newer build of *older* sources (the diagnostic
# build was tested as if it were the current one).
built=$(printf '%s\n' "$built_json" \
    | sed -n 's/^\(native-[0-9a-z-]*\) built and selected.*/\1/p' | tail -1)
if [ -z "$built" ]; then
    for tag in "$VERSIONS"/native-*; do
        [ -d "$tag" ] || continue
        tag=${tag##*/}
        case " $before " in *" $tag "*) ;; *) built=$tag ;; esac
    done
fi
[ -n "$built" ] || die "native-build reported success but no two-mod version exists" 10

rm -rf "$EXPORT/horizon-native-mods"
cp -a "$VERSIONS/$built/horizon-native-mods" "$EXPORT/horizon-native-mods"
cp -a "$VERSIONS/$built/native-mods.json" "$EXPORT/native-mods.json"
# The mods themselves are cdylibs beside the game binary, as `launcher-game.sh`'s export copies.
# The launcher hard-links a build's libraries, so an export that already points at one of them has a
# second name for the same inode and `cp -a` refuses ("are the same file"); `ln -f` replaces the
# name in place, which is the same bytes without a copy.
for lib in "$VERSIONS/$built"/lib*.so; do
    [ -e "$lib" ] || continue
    ln -f "$lib" "$EXPORT/${lib##*/}" 2>/dev/null || cp -a "$lib" "$EXPORT/"
done
say "built $built; export now carries: $(python3 - "$EXPORT/native-mods.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
mods = data.get("mods", data if isinstance(data, list) else [])
print(", ".join(m.get("id", "?") for m in mods) or data)
PY
)"
