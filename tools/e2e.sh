#!/usr/bin/env bash
# In-game check for RFTools Power slice 1 — the coal generator.
#
# Upstream's `CoalGeneratorTileEntity` (1.21-7.0.6) burns one coal for 600 ticks at 60 FE a
# tick (a coal block nine times as long) into a 500,000 FE buffer, lights its front while it
# burns, takes fuel from an input slot and gives its store out through the energy capability.
# This leg proves those rules in a real game and nothing else.
#
# Mod commands are typed with `ctl chat "/cmd"`: the chat path reaches the dispatcher the SDK's
# `register_commands`/`run_mod_command` register into.
#
# The End, in the void at x=300 (an empty level: no ambient item entities, no terrain in the
# way). The arena floor is y=100; machines stand at y=101.
#
# GAME must be a game built with THIS package (flat SDK `.hmod`, mod API 0.2):
#   ports/tools/launcher-game.sh build rftoolspower
#   eval "$(ports/tools/launcher-game.sh env rftoolspower)"
#   bash ports/rftoolspower/tools/e2e.sh
#
# Phases:
#  A  a generator placed from its item is empty: 0/500,000 FE, burning 0/0, lit false, and the
#     block's own `lit` state is false
#  B  a right click with one coal puts it in the fuel slot, spends it from the hand, starts a
#     600-tick burn and lights the block (`lit=true`)
#  C  while it burns, FE rises by exactly 60 a tick: over N ticks `Δenergy == 60 * Δburn`
#  D  the burn runs out: burning 0/0, the block is dark again, and FE stops rising (the
#     differential: no fuel, no FE)
#  E  a non-fuel (stone) is refused: the slot stays empty, the hand keeps the stone
#  F  charcoal is fuel: a 600-tick burn
#  G  a coal block is one item and a 5,400-tick burn
#  H  the buffer clamps at 500,000 FE, and a full generator still burns
#  I  a hopper over the generator feeds its slot (the container declaration)
#  J  the store survives save + quit + relaunch
#  K  a broken generator's item carries the store, and placing it restores it; a doctored
#     +999,999 FE item is clamped to the capacity
#  L  an unknown item id is refused (the block is `rftoolspower:coalgenerator`, nothing else)
#  M  the carried recipe cannot be crafted in this build: its centre cell names
#     `rftoolsbase:machine_frame`, and the same pattern with any other block crafts nothing
#     (upstream's recipe, blocked on the parent — the `rftoolsstorage` precedent)
#  N  a monitor placed with its read side against a 250,000 FE generator shows level 3 and no
#     alarm; a redstone lamp on its display side stays dark
#  O  the same against an empty generator: level 1, no alarm, lamp dark (the differential)
#  P  the same against `minecraft:stone`: level 0, "not an energy block"
#  Q  the alarm band: 40..60 at 50 % lights the lamp, 90..100 puts it out
#  R  the generator pushes its store into an adjacent energy block (the harness receiver): the
#     receiver ends full and the generator empty, and the monitor facing the receiver reads 5
#  S  a monitor item's `block_entity_data` band is restored when it is placed
#  T  the monitor's carried recipe needs `rftoolsbase:machine_base`; without it, nothing crafts
#  U  a fresh cell1 is empty, one cell in its network, and its six faces are NONE
#  V  that fresh cell refuses the generator's push (the differential for W)
#  W  with its west face INPUT it takes exactly 250 FE a tick (tier1MaxRFPerTick) and the
#     generator's store falls by the same amount
#  X  a second cell1 beside it shares one network (stored and capacity), while a cell with a gap
#     does not
#  Y  a cell2 beside a cell1 joins the same network (upstream gates the network on adjacency, not
#     on tier) and a cell2 with a gap does not
#  Z  an OUTPUT face pushes the network's 250 a tick into a neighbour (the harness receiver)
#  AA the cell's store and its face modes survive save + relaunch
#  AB a broken cell carries its own store on its item and placing it gives it back
#  AC the power core crafts and is consumed; cell1's recipe crafts nothing without the parent's
#     machine frame
#  AD the `side` command's refusals are parsed replies, not the command's (always 0) status
#  AE a generator, a destination three blocks away and the injector that feeds the link all place
#     and read back; the link is 2 ticks ((int)(3/3)+1) and both generators start empty
#  AF a pearl fired inside the destination's 1..15 charging window pays rfPerHit[mode] x 2, and
#     the store is exactly what the generator gained minus what holding spent
#  AG the same shot with the destination left idle: the pearl is lost and nothing is paid (the
#     differential for AF)
#  AH a generator with no injector charges through the window and stays at 0 FE
#  AI the generator pushes its store into a neighbour and keeps exactly its 2,000 FE reserve
#  AJ a broken endergenic carries its store (and only its store) on its item
#  AK both carried recipes need the parent's machine frame, so neither crafts here
#  AL the enderlink command's refusals are parsed replies (a stone, a 5-tick link, no generator)
#  AM the store and the link survive save + relaunch
#
#  AN an ender monitor placed on a generator's side reads the default `lost` mode, and the
#     `endermonitor` command sets each of the three modes (arrived on the destination, lost and a
#     mis-facing one beside it, fired on the source); a broken monitor's item carries its mode and
#     placing it restores it
#  AO one pearl fired across the link pulses the destination's `arrived` monitor for exactly one
#     tick (a per-tick sample of its `lit` state and of the lamp on its display face) and the
#     source's `fired` monitor; the `lost` and the mis-facing monitors never pulse
#  AP the differential: the same shot with that monitor's mode set to `lost` does not pulse it,
#     while the shot still lands and is recorded as an arrival (an attempt where upstream's random
#     pearl discard fired the lost monitor is named and retried; the arrival itself must not)
#  AQ a pearl that lands while the destination is idle pulses the `arrived` monitor (upstream
#     fires it before the miss) and the `lost` monitor, and the generator records the loss
#  AR the `endermonitor` command's refusals are parsed replies, and a refused mode changes nothing
#  AS the ender monitor's carried recipe needs `rftoolsbase:machine_base`, so it crafts nothing here
#
# SELFTEST=1 inverts phase V (the cell's NONE face must have taken the generator's FE) and exits
# non-zero, proving the face-mode assertion can fail; SELFTEST_MONITOR=1 keeps slice 2's inversion
# of O; SELFTEST_GENERATOR=1 keeps slice 1's inversion of C; SELFTEST_ENDER=1 inverts AF;
# SELFTEST_ENDERMON=1 inverts AO (the monitor must not have lit);
# SELFTEST_POWERLEVEL=1 inverts the power level's 5 (it asserts the brief's mistaken 4).
# CONTROL=1 runs phase A on the Nightly WITHOUT this package (CONTROL_GAME, exported by
# launcher-game.sh): the generator item does not exist, so A fails and the log says why.
set -Eeuo pipefail
export LC_ALL=C

CLONE=/home/adlf/Desktop/all_the_mods_10_rust_rewrite
PORT=$CLONE/ports/rftoolspower
CTL=${CTL:-}
GAME=${GAME:-}
RES=${RES:-${HORIZON_RES:-/home/adlf/Desktop/horizon/.local/horizon-client/26.3}}
TMP=${E2E_TMP:-/tmp/opencode}
SOCK=${SOCK:-$TMP/rftoolspower-e2e.sock}
SELFTEST=${SELFTEST:-0}
SELFTEST_MONITOR=${SELFTEST_MONITOR:-0}
SELFTEST_ENDERMON=${SELFTEST_ENDERMON:-0}
SELFTEST_POWERLEVEL=${SELFTEST_POWERLEVEL:-0}
CONTROL=${CONTROL:-0}
KEEP=${KEEP:-0}
WORLD=RFToolsPowerE2E
X0=300
SX=$((X0 + 2))
CAPACITY=500000
PER_TICK=60
TICKS_PER_COAL=600
TICKS_PER_COAL_BLOCK=5400
BLOCK=rftoolspower:coalgenerator
MONITOR=rftoolspower:power_monitor
POWER_LEVEL=rftoolspower:power_level
DUST=minecraft:redstone_wire
CELL=rftoolspower:cell1
CELL2=rftoolspower:cell2
CORE=rftoolspower:power_core1
RECEIVER=rfpowerharness:receiver
COAL=minecraft:coal
CHARCOAL=minecraft:charcoal
COAL_BLOCK=minecraft:coal_block
STONE=minecraft:stone

[ -n "$CTL" ] || { echo "set CTL= to the horizon-ctl of this pin (launcher-game.sh env)" >&2; exit 1; }
[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -n "$GAME" ] || { echo "set GAME= to a game built with this package (launcher-game.sh env)" >&2; exit 1; }
if [ "$CONTROL" = 1 ]; then
    [ -n "${CONTROL_GAME:-}" ] || { echo "set CONTROL_GAME= to the unmodded Nightly game" >&2; exit 1; }
    GAME=$CONTROL_GAME
fi
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }
# Name the delivered bytes this leg proves (the campaign's rule: a log names the package it ran
# against). The control leg does not load the package, so it says nothing.
if [ "$CONTROL" = 0 ] && [ -f "$PORT/rftoolspower.hmod" ]; then
    echo "PACKAGE rftoolspower.hmod sha256=$(sha256sum "$PORT/rftoolspower.hmod" | cut -d' ' -f1) bytes=$(stat -c%s "$PORT/rftoolspower.hmod")"
fi

SCRATCH=$(mktemp -d "$TMP/rftoolspower-home.XXXXXX")
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")" "$XDG_CONFIG_HOME" "$HORIZON_HOME" "$HORIZON_LAUNCHER_HOME"
rm -f "$SOCK"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
say() { ctl chat "/$1" >/dev/null; }
fail() { echo "FAIL: $*" >&2; ctl logs --lines 60 >&2 || true; exit 1; }
on_error() { echo "FAIL: line $1: '$2' exited $?" >&2; ctl logs --lines 40 >&2 || true; }
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

cleanup() {
    local status=$?
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    if [ "$KEEP" = 1 ]; then
        echo "kept scratch: $SCRATCH" >&2
    else
        rm -rf "$SCRATCH" 2>/dev/null || true
    fi
    echo "EXIT:$status"
}
trap cleanup EXIT

launch() { # launch [WORLD]
    local world=${1:-$WORLD}
    rm -f "$SOCK"
    cd "$SCRATCH"
    local args=(--game "$GAME" --world "$world" --seed 20261105 --creative --offscreen
                --wait --resources "$RES")
    "$CTL" --socket "$SOCK" launch "${args[@]}" >/dev/null
    ctl wait-ready 180
    ctl wait 40
}

# `ctl block` answers {pos, block, state, loaded}; the state is a string such as
# `rftoolspower:coalgenerator[facing=north,lit=false]`.
block_name() { ctl block "$1" "$2" "$3" | jq -r '.block // empty'; }
block_lit() { ctl block "$1" "$2" "$3" | jq -r '.state // empty' | sed -n 's/.*lit=\(true\|false\).*/\1/p'; }

arena() {
    ctl command "execute in minecraft:the_end run tp @s $X0.5 104 0.5" >/dev/null
    local loaded=false
    for _ in $(seq 1 120); do
        ctl wait 5 >/dev/null
        if [ "$(ctl block "$X0" 100 0 | jq -r '.loaded // false')" = true ]; then
            loaded=true
            break
        fi
    done
    [ "$loaded" = true ] || fail "the End arena chunk never loaded"
    # The fill spans several chunks and `loaded` above only checks one of them, so a first fill
    # can answer "That position is not loaded"; retry the floor until it is really there.
    local attempt
    for attempt in 1 2 3 4 5; do
        ctl command "execute in minecraft:the_end run fill $((X0 - 4)) 100 -24 $((X0 + 6)) 100 48 minecraft:stone" >/dev/null
        ctl wait 6 >/dev/null
        [ "$(block_name "$X0" 100 0)" = "minecraft:stone" ] && break
        echo "  the arena floor fill did not land (attempt $attempt); waiting for the chunks" >&2
        ctl wait 40 >/dev/null
    done
    ctl command "execute in minecraft:the_end run fill $((X0 - 4)) 101 -24 $((X0 + 6)) 108 48 minecraft:air" >/dev/null
    ctl wait 6 >/dev/null
    ctl command "execute in minecraft:the_end run kill @e[type=!player]" >/dev/null
    ctl command "execute in minecraft:the_end run tp @s $X0.5 101 0.5" >/dev/null
    ctl wait 20
    [ "$(block_name "$X0" 100 0)" = "minecraft:stone" ] || fail "the arena floor is not stone"
    [ "$(block_name "$X0" 101 0)" = "minecraft:air" ] || fail "the arena air above the floor is not air"
}

# The newest chat line matching PATTERN, waiting up to ~3 s for it to arrive. A command's reply
# comes back on the chat path, so it can miss the first read under load; this is a bounded wait
# on a message, never a build-slot poll.
await_line() { # await_line PATTERN
    local line=""
    for _ in 1 2 3 4 5 6; do
        line=$(ctl messages 20 | jq -r '.chat[]' | grep -m1 "$1" || true)
        [ -n "$line" ] && break
        ctl wait 5 >/dev/null
    done
    printf '%s\n' "$line"
}

# `/rftoolspower info X Y Z`: the line, then the parsed fields.
NONCE_TAG=""
info() { # info X Y Z
    NONCE=$(( ${NONCE:-0} + 1 ))
    NONCE_TAG=$NONCE
    local line
    say "rftoolspower info $1 $2 $3 $NONCE"
    line=$(await_line "nonce=$NONCE")
    [ -n "$line" ] || fail "no fresh /rftoolspower info reply for nonce $NONCE: $(ctl messages 8 | jq -c '.chat')"
    ev=$(python3 "$PORT/tools/parse_info.py" "$line")
    eval "$ev"
    [ "${ok:-0}" = 1 ] || fail "the info line did not parse: $line"
    echo "  $line" >&2
    echo "  parsed: energy=$ENERGY/$CAPACITY burn=$BURN/$BURN_MAX lit=$LIT fuel=$FUEL_ITEM x$FUEL_COUNT" >&2
}

expect_energy() { [ "$ENERGY" = "$1" ] || fail "the generator holds $ENERGY FE, expected $1"; }
expect_burn() { [ "$BURN" = "$1" ] || fail "the burn is $BURN ticks, expected $1"; }
expect_burn_max() { [ "$BURN_MAX" = "$1" ] || fail "the burn bar's denominator is $BURN_MAX, expected $1"; }
expect_lit() { [ "$LIT" = "$1" ] || fail "the readout says lit=$LIT, expected $1"; }
expect_fuel() {
    [ "$FUEL_ITEM" = "$1" ] && [ "$FUEL_COUNT" = "$2" ] \
        || fail "the fuel slot holds $FUEL_ITEM x$FUEL_COUNT, expected $1 x$2"
}
expect_block_lit() { # expect_block_lit X Y Z true|false
    local got
    got=$(block_lit "$1" "$2" "$3")
    [ "$got" = "$4" ] || fail "the block state at $1,$2,$3 has lit='$got', expected $4"
}

# Hold one item in the first hotbar slot and select it.
hold() { # hold ITEM [COUNT]
    ctl command "item replace entity @s hotbar.0 with $1 ${2:-1}" >/dev/null
    ctl wait 4 >/dev/null
    ctl select 1 >/dev/null
    ctl wait 2 >/dev/null
}

held_count() { # held_count ITEM -> how many of ITEM the inventory holds
    ctl inventory | jq -r --arg i "$1" '[.hotbar[], .main[] | select(.item == $i) | .count] | add // 0'
}

# A mob standing in a position blocks a placement (the End spawns endermen while the earlier
# phases run), so clear every non-player entity before one and retry once after clearing again.
clear_mobs() {
    ctl command "execute in minecraft:the_end run kill @e[type=!player]" >/dev/null 2>&1 || true
    ctl wait 2 >/dev/null
}

# Open a crafting table at X Y Z for the player standing beside it. `ctl interact` races the
# teleport under load (this run's first attempt answered "0 grid slots" once), so the table is
# re-set and the click retried; a block that is really there and a click that landed opens the grid.
open_crafting_table() { # X Y Z
    local x=$1 y=$2 z=$3 attempt grid
    for attempt in 1 2 3; do
        ctl close >/dev/null 2>&1 || true
        ctl setblock "$x" "$y" "$z" minecraft:air >/dev/null
        ctl setblock "$x" "$y" "$z" minecraft:crafting_table >/dev/null
        ctl wait 2 >/dev/null
        if [ "$(block_name "$x" "$y" "$z")" != "minecraft:crafting_table" ]; then
            echo "  the crafting table at $x,$y,$z did not place (attempt $attempt)" >&2
            ctl wait 20 >/dev/null
            continue
        fi
        ctl command "execute in minecraft:the_end run tp @s $((x - 1)).5 $y $((z)).5" >/dev/null
        ctl wait 4 >/dev/null
        ctl interact "$x" "$y" "$z" >/dev/null || fail "the crafting table did not take the click"
        ctl wait 6 >/dev/null
        grid=$(ctl screen | jq '[.slots[]? | select(.slot >= 100)] | length')
        [ "$grid" = 10 ] && return 0
        echo "  the crafting table's grid did not open ($grid grid slots, attempt $attempt)" >&2
    done
    fail "the crafting table at $x,$y,$z never opened its grid"
}


place_block() { # place_block X Y Z ITEM
    local x=$1 y=$2 z=$3 item=$4
    clear_mobs
    PLACE_REPLY=$(ctl place "$x" "$y" "$z" --item "$item" 2>&1) && return 0
    clear_mobs
    PLACE_REPLY=$(ctl place "$x" "$y" "$z" --item "$item" 2>&1) && return 0
    return 1
}

place_generator() { # place_generator X Y Z
    local x=$1 y=$2 z=$3
    ctl command "execute in minecraft:the_end run tp @s $((x - 2)).5 $y $z.5" >/dev/null
    ctl wait 6 >/dev/null
    hold "$BLOCK"
    local aim reply
    aim=$(ctl look-at-block "$x" $((y - 1)) "$z" up 2>&1) \
        || fail "cannot aim at the floor under $x,$y,$z: $aim"
    place_block "$x" "$y" "$z" "$BLOCK" \
        || fail "ctl place at $x,$y,$z failed: $PLACE_REPLY"
    ctl wait 6 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$BLOCK" ] || fail "the generator did not place at $x,$y,$z"
}

# Right-click the generator from two blocks away, holding ITEM.
click_with() { # click_with X Y Z ITEM [COUNT]
    local x=$1 y=$2 z=$3
    ctl command "execute in minecraft:the_end run tp @s $((x - 2)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    hold "$4" "${5:-1}"
    ctl interact "$x" "$y" "$z" >/dev/null
    ctl wait 12 >/dev/null
}

# A survival break: `block_drops` does not fire for a creative break, so the store-on-the-item
# phase switches the player to survival and holds the generator's own tool.
break_block() { # break_block X Y Z TOOL
    local x=$1 y=$2 z=$3
    ctl command "execute in minecraft:the_end run tp @s $((x - 2)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    hold "$4"
    ctl break "$x" "$y" "$z" >/dev/null || fail "ctl break at $x,$y,$z failed"
    ctl wait 10 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "minecraft:air" ] || fail "the block at $x,$y,$z is not air after the break"
}

# The chat line `/data get entity @s SelectedItem` replies for the generator in hand.
held_item_line() {
    ctl select "$BLOCK" >/dev/null
    ctl wait 4 >/dev/null
    ctl command "data get entity @s SelectedItem" >/dev/null
    ctl wait 6 >/dev/null
    ctl messages 8 | jq -r '.chat[]' | grep -m1 'has the following entity data' || true
}

pick_up() { # pick_up X Y Z
    ctl collect 8 >/dev/null 2>&1 || true
    ctl wait 10 >/dev/null
    if [ "$(held_count "$BLOCK")" = 0 ]; then
        ctl command "execute in minecraft:the_end run tp @s $1.5 $2 $3.5" >/dev/null
        ctl wait 20 >/dev/null
    fi
    [ "$(held_count "$BLOCK")" != 0 ] \
        || fail "the broken generator's item was not picked up: $(ctl inventory | jq -c '{hotbar,main}')"
}

place_kept() { # place_kept X Y Z — place the generator item the player already carries
    local x=$1 y=$2 z=$3
    ctl command "execute in minecraft:the_end run tp @s $((x - 2)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    ctl select "$BLOCK" >/dev/null
    ctl wait 2 >/dev/null
    ctl look-at-block "$x" $((y - 1)) "$z" up >/dev/null
    place_block "$x" "$y" "$z" "$BLOCK" \
        || fail "ctl place at $x,$y,$z failed: $PLACE_REPLY"
    ctl wait 6 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$BLOCK" ] || fail "the carried generator did not place at $x,$y,$z"
}

# `/rftoolspower monitor X Y Z`: the line, then the parsed fields.
monitor() { # monitor X Y Z
    NONCE=$(( ${NONCE:-0} + 1 ))
    local line
    say "rftoolspower monitor $1 $2 $3 $NONCE"
    line=$(await_line "nonce=$NONCE")
    [ -n "$line" ] || fail "no fresh /rftoolspower monitor reply for nonce $NONCE: $(ctl messages 8 | jq -c '.chat')"
    eval "$(python3 "$PORT/tools/parse_monitor.py" "$line")"
    [ "${ok:-0}" = 1 ] || fail "the monitor line did not parse: $line"
    echo "  $line" >&2
    echo "  parsed: level=$LEVEL band=$MIN..$MAX unset=$UNSET target=$TARGET energy=$IS_ENERGY stored=$STORED/$MAXE alarm=$ALARM" >&2
}

expect_level() { [ "$LEVEL" = "$1" ] || fail "the monitor reads level $LEVEL, expected $1"; }
expect_alarm() { [ "$ALARM" = "$1" ] || fail "the monitor's alarm is $ALARM, expected $1"; }
expect_monitor_band() {
    [ "$MIN" = "$1" ] && [ "$MAX" = "$2" ] \
        || fail "the monitor's band is $MIN..$MAX, expected $1..$2"
}
expect_target() {
    [ "$TARGET" = "$1" ] || fail "the monitor faces $TARGET, expected $1"
}
expect_stored() { [ "$STORED" = "$1" ] || fail "the monitor reads $STORED FE, expected $1"; }

# The `level` and `lit` properties of a monitor's block state.
block_level() { ctl block "$1" "$2" "$3" | jq -r '.state // empty' | sed -n 's/.*level=\([0-9]*\).*/\1/p'; }
block_lit() { ctl block "$1" "$2" "$3" | jq -r '.state // empty' | sed -n 's/.*lit=\(true\|false\).*/\1/p'; }
expect_block_level() { # expect_block_level X Y Z N
    local got; got=$(block_level "$1" "$2" "$3")
    [ "$got" = "$4" ] || fail "the monitor block at $1,$2,$3 has level='$got', expected $4"
}
expect_lamp() { # expect_lamp X Y Z true|false
    local got; got=$(block_lit "$1" "$2" "$3")
    [ "$got" = "$4" ] || fail "the redstone lamp at $1,$2,$3 has lit='$got', expected $4 (state $(ctl block "$1" "$2" "$3" | jq -r '.state'))"
}

# The `energy` int in a block entity's saved compound (`/data get block`).
energy_of() { # energy_of X Y Z -> the amount
    ctl command "data get block $1 $2 $3 energy" >/dev/null
    ctl wait 4 >/dev/null
    local line
    line=$(await_line 'has the following block data')
    [ -n "$line" ] || fail "no /data get block reply for $1,$2,$3: $(ctl messages 8 | jq -c '.chat')"
    echo "  data get $1,$2,$3: $line" >&2
    eval "$(python3 "$PORT/tools/parse_data_energy.py" "$line")"
    [ "${ok:-0}" = 1 ] || fail "the data reply at $1,$2,$3 carries no energy: $line"
    echo "$ENERGY"
}

# Place a block from the hotbar with the player east of it. A monitor's `facing` is its display
# front, set facing the placer (as a furnace's is); it reads the block behind it, so a monitor
# placed this way watches the block to its west.
place_facing_player() { # place_facing_player X Y Z ITEM
    local x=$1 y=$2 z=$3 item=$4
    ctl command "execute in minecraft:the_end run tp @s $((x + 3)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    ctl select "$item" >/dev/null
    ctl wait 2 >/dev/null
    ctl look-at "$x.5" "$y.5" "$z.5" >/dev/null || fail "cannot aim at $x,$y,$z"
    place_block "$x" "$y" "$z" "$item" \
        || fail "ctl place $item at $x,$y,$z failed: $PLACE_REPLY"
    ctl wait 6 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$item" ] || fail "$item did not place at $x,$y,$z"
    echo "  placed: $(ctl block "$x" "$y" "$z" | jq -r '.state')" >&2
}

# The harness cannot drive the placer's yaw `ctl place` reports (it is the game's placement
# context, not the player's look), so the direction-sensitive phases set the monitor's display
# face explicitly once it is placed. `facing` is the display front; the monitor reads the block
# behind it, so `facing=east` reads the block to its west.
aim_monitor() { # aim_monitor X Y Z FACE
    ctl command "execute in minecraft:the_end run setblock $1 $2 $3 $MONITOR[facing=$4,level=0,lit=false]" >/dev/null \
        || fail "cannot set the monitor's facing at $1,$2,$3"
    ctl wait 4 >/dev/null
    [ "$(block_name "$1" "$2" "$3")" = "$MONITOR" ] || fail "the monitor vanished from $1,$2,$3"
}

place_monitor() { # place_monitor X Y Z — a fresh monitor from the hotbar, watching the block west
    hold "$MONITOR"
    place_facing_player "$1" "$2" "$3" "$MONITOR"
}

# `/rftoolspower powerlevel X Y Z <nonce>`: the line, then the parsed fields.
powerlevel() { # powerlevel X Y Z
    NONCE=$(( ${NONCE:-0} + 1 ))
    local line
    say "rftoolspower powerlevel $1 $2 $3 $NONCE"
    line=$(await_line "nonce=$NONCE")
    [ -n "$line" ] || fail "no fresh /rftoolspower powerlevel reply for nonce $NONCE: $(ctl messages 8 | jq -c '.chat')"
    eval "$(python3 "$PORT/tools/parse_powerlevel.py" "$line")"
    [ "${ok:-0}" = 1 ] || fail "the power level line did not parse: $line"
    echo "  $line" >&2
    echo "  parsed: power=$POWER facing=$FACING target=$TARGET energy=$IS_ENERGY stored=$STORED/$MAXE" >&2
}

expect_power() { [ "$POWER" = "$1" ] || fail "the power level reads power=$POWER, expected $1"; }

# The `power` property of a redstone wire: what the wire beside the display face actually sees.
dust_power() { ctl block "$1" "$2" "$3" | jq -r '.state // empty' | sed -n 's/.*power=\([0-9]*\).*/\1/p'; }

# A power level placed from its item (so `state_for_placement` runs), then its display face pinned:
# `ctl place`'s yaw is the game's, not the player's (the monitor/ender-monitor trap).
place_powerlevel() { # place_powerlevel X Y Z FACE
    local x=$1 y=$2 z=$3 face=$4 dx=2 aim
    [ "$face" = west ] && dx=-2
    ctl command "execute in minecraft:the_end run setblock $x $y $z minecraft:air" >/dev/null
    ctl wait 4 >/dev/null
    ctl command "execute in minecraft:the_end run tp @s $((x + dx)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    hold "$POWER_LEVEL"
    ctl wait 2 >/dev/null
    aim=$(ctl look-at-block "$x" $((y - 1)) "$z" up 2>&1) \
        || fail "cannot aim at the floor under $x,$y,$z: $aim"
    place_block "$x" "$y" "$z" "$POWER_LEVEL" \
        || fail "ctl place $POWER_LEVEL at $x,$y,$z failed: $PLACE_REPLY"
    ctl wait 4 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$POWER_LEVEL" ] || fail "the power level is not at $x,$y,$z"
}

aim_powerlevel() { # aim_powerlevel X Y Z FACE
    ctl command "execute in minecraft:the_end run setblock $1 $2 $3 $POWER_LEVEL[facing=$4,power=0]" >/dev/null \
        || fail "cannot set the power level's facing at $1,$2,$3"
    ctl wait 4 >/dev/null
    [ "$(block_name "$1" "$2" "$3")" = "$POWER_LEVEL" ] || fail "the power level vanished from $1,$2,$3"
}

echo "== launch (The End arena, the package's own content and code) =="
launch
arena
# Survival from here: vanilla's creative rule keeps a container stack in the hand
# (`ItemPlace`), so the fuel a click moves would never leave it. The mod's mechanic is the
# survival one, and a survival break is also what fires `block_drops`.
ctl command "gamemode survival" >/dev/null
ctl wait 4 >/dev/null

echo "== A: a generator placed from its item is empty and dark =="
place_generator "$SX" 101 0
info "$SX" 101 0
expect_energy 0
expect_burn 0
expect_fuel empty 0
expect_lit false
expect_block_lit "$SX" 101 0 false
echo "  block $(ctl block "$SX" 101 0 | jq -r '.state')"

echo "== B: one coal in the fuel slot starts a 600-tick burn and lights the block =="
click_with "$SX" 101 0 "$COAL" 1
info "$SX" 101 0
[ "$BURN" -gt 0 ] || fail "the generator is not burning after a coal was inserted"
expect_burn_max "$TICKS_PER_COAL"
expect_fuel empty 0
expect_lit true
expect_block_lit "$SX" 101 0 true
[ "$(held_count "$COAL")" = 0 ] || fail "the hand still holds $(held_count "$COAL") coal after the click"
echo "  the coal left the hand, the tick loaded it: burning $BURN/$BURN_MAX, lit=true"

echo "== C: while it burns, FE rises by exactly 60 a tick =="
info "$SX" 101 0
E0=$ENERGY; B0=$BURN
ctl wait 40 >/dev/null
info "$SX" 101 0
E1=$ENERGY; B1=$BURN
dE=$((E1 - E0)); dB=$((B0 - B1))
echo "  over $dB burn ticks: $E0 -> $E1 FE (+$dE)"
[ "$dB" -ge 20 ] || fail "only $dB burn ticks passed; the window is too small to assert"
if [ "${SELFTEST_GENERATOR:-0}" = 1 ]; then
    echo "(selftest: asserting the generator made no FE while burning)"
    [ "$dE" = 0 ] || fail "selftest: the generator made $dE FE in $dB ticks, so the assertion is alive"
fi
[ "$dE" = $((PER_TICK * dB)) ] || fail "FE rose $dE over $dB ticks, expected $((PER_TICK * dB)) (60 a tick)"
echo "  $dE FE in $dB ticks: exactly $PER_TICK a tick"

echo "== D: the burn runs out, the block goes dark and FE stops rising =="
ctl wait 620 >/dev/null
info "$SX" 101 0
expect_burn 0
expect_burn_max 0
expect_lit false
expect_block_lit "$SX" 101 0 false
STOPPED=$ENERGY
ctl wait 20 >/dev/null
info "$SX" 101 0
[ "$ENERGY" = "$STOPPED" ] || fail "with no fuel the store still moved: $STOPPED -> $ENERGY"
expect_fuel empty 0
echo "  no fuel, no FE: $ENERGY FE held and unchanged over 20 ticks"

echo "== E: a stone is refused as fuel =="
click_with "$SX" 101 0 "$STONE" 1
info "$SX" 101 0
expect_fuel empty 0
expect_burn 0
[ "$(held_count "$STONE")" -ge 1 ] || fail "the stone left the hand; a non-fuel click must change nothing"
echo "  the stone stayed in the hand and the slot stayed empty"

echo "== F: charcoal is fuel =="
click_with "$SX" 101 0 "$CHARCOAL" 1
info "$SX" 101 0
expect_fuel empty 0
expect_burn_max "$TICKS_PER_COAL"
[ "$BURN" -gt 0 ] || fail "charcoal did not start a burn"
echo "  charcoal: burning $BURN/$BURN_MAX"

echo "== G: a coal block is one item and a 5,400-tick burn =="
ctl command "execute in minecraft:the_end run setblock $SX 101 -6 minecraft:air" >/dev/null
place_generator "$SX" 101 -6
click_with "$SX" 101 -6 "$COAL_BLOCK" 1
info "$SX" 101 -6
expect_fuel empty 0
expect_burn_max "$TICKS_PER_COAL_BLOCK"
[ "$BURN" -gt 5000 ] || fail "a coal block started a $BURN-tick burn, expected 5,400"
echo "  one coal block: burning $BURN/$BURN_MAX"

echo "== H: the buffer clamps at 500,000 FE and a full generator keeps burning =="
ctl command "give @s $BLOCK[minecraft:block_entity_data={id:\"rftoolspower:coalgenerator_block_entity\",burn:600,burn_max:600,energy:499950}]" >/dev/null
ctl wait 8 >/dev/null
place_kept "$SX" 101 6
info "$SX" 101 6
echo "  placed from a doctored item at $ENERGY FE, burning $BURN"
[ "$ENERGY" -ge 499950 ] || fail "the item's store did not arrive: $ENERGY FE"
ctl wait 20 >/dev/null
info "$SX" 101 6
expect_energy "$CAPACITY"
[ "$BURN" -gt 0 ] || fail "the full generator stopped burning"
[ "$BURN" -lt 600 ] || fail "the burn did not advance at a full buffer"
echo "  499,950 + 50 FE of room: $ENERGY/$CAPACITY and still burning ($BURN left)"

echo "== I: a hopper over the generator feeds its slot =="
ctl command "execute in minecraft:the_end run setblock $SX 101 -12 minecraft:air" >/dev/null
place_generator "$SX" 101 -12
ctl command "execute in minecraft:the_end run setblock $SX 102 -12 minecraft:hopper[facing=down]" >/dev/null
ctl wait 4 >/dev/null
[ "$(block_name "$SX" 102 -12)" = "minecraft:hopper" ] || fail "the hopper did not place over the generator"
info "$SX" 101 -12
expect_energy 0
ctl command "item replace block $SX 102 -12 container.0 with $COAL 2" >/dev/null
ctl wait 8 >/dev/null
ctl wait 60 >/dev/null
info "$SX" 101 -12
[ "$ENERGY" -gt 0 ] || fail "the hopper never fed the generator: still $ENERGY FE with no click"
echo "  the hopper fed the slot with no click: $ENERGY FE, fuel $FUEL_ITEM x$FUEL_COUNT"

echo "== J: the store survives save and relaunch =="
ctl command "execute in minecraft:the_end run setblock $SX 102 -12 minecraft:air" >/dev/null
info "$SX" 101 6
SAVED=$ENERGY
ctl save >/dev/null
ctl wait 10 >/dev/null
ctl quit >/dev/null 2>&1 || true
sleep 2
launch
ctl command "execute in minecraft:the_end run tp @s $((SX - 2)).5 101 0.5" >/dev/null
ctl wait 40 >/dev/null
[ "$(block_name "$SX" 101 6)" = "$BLOCK" ] || fail "the generator did not survive the relaunch"
info "$SX" 101 6
[ "$ENERGY" -ge "$SAVED" ] || fail "after the relaunch the store is $ENERGY, was $SAVED before save"
echo "  after save + relaunch: $ENERGY/$CAPACITY FE (was $SAVED)"

echo "== K: a broken generator carries its store, and a doctored item is clamped =="
ctl command "gamemode survival" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 6 >/dev/null
ctl command "give @s $BLOCK[minecraft:block_entity_data={id:\"rftoolspower:coalgenerator_block_entity\",burn:0,burn_max:0,energy:3000}]" >/dev/null
ctl wait 8 >/dev/null
place_kept "$SX" 101 12
info "$SX" 101 12
expect_energy 3000
break_block "$SX" 101 12 minecraft:iron_pickaxe
pick_up "$SX" 101 12
DROP_LINE=$(held_item_line)
[ -n "$DROP_LINE" ] || fail "no /data get reply for the picked-up generator: $(ctl messages 8 | jq -c '.chat')"
echo "  $DROP_LINE" >&2
DROP=$(python3 "$PORT/tools/parse_drop.py" "$DROP_LINE" 3000) || true
eval "$DROP"
[ "${ok:-0}" = 1 ] || fail "the dropped generator does not carry 3,000 FE: $DROP_LINE"
echo "  the item carries $carried FE (burn $burn)"
place_kept "$SX" 101 12
info "$SX" 101 12
[ "$ENERGY" -ge 3000 ] || fail "the placed-back generator holds $ENERGY FE, expected at least 3,000"
echo "  placed back at $ENERGY FE"

ctl command "give @s $BLOCK[minecraft:block_entity_data={id:\"rftoolspower:coalgenerator_block_entity\",burn:0,energy:999999}]" >/dev/null
ctl wait 8 >/dev/null
place_kept "$SX" 101 -18
info "$SX" 101 -18
expect_energy "$CAPACITY"
echo "  999,999 FE asked by the item, $ENERGY held after placement"

echo "== L: an unknown id is refused =="
ctl command "clear @s" >/dev/null
ctl wait 4 >/dev/null
ctl command "item replace entity @s hotbar.0 with rftoolspower:coal_generatore" >/dev/null || true
ctl wait 6 >/dev/null
UNKNOWN=$(ctl inventory | jq -r '[.hotbar[], .main[] | select(.item == "rftoolspower:coal_generatore")] | length')
[ "$UNKNOWN" = 0 ] || fail "an unknown id found its way into the inventory"
ctl messages 8 | jq -r '.chat[]' | grep -qi "unknown item\|No such item\|Unknown item" \
    || fail "the game did not refuse the unknown id: $(ctl messages 8 | jq -c '.chat')"
echo "  rftoolspower:coal_generatore is refused and the slot stays empty"

echo "== M: the carried recipe needs the parent's machine frame =="
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
for item in "$COAL" "$STONE" minecraft:redstone_torch; do
    ctl command "give @s $item 16" >/dev/null
done
ctl wait 8 >/dev/null
TX=$((SX + 4)); TY=101; TZ=0
open_crafting_table "$TX" "$TY" "$TZ"
# "cTc" / "cFc" / "cTc" on the table's grid (100..108): coals at 100,102,103,105,106,108,
# redstone torches at 101 and 107, and a stone where `rftoolsbase:machine_frame` belongs (104).
place_one() { # place_one ITEM CELL
    local item=$1 cell=$2 src
    src=$(ctl screen | jq -r --arg i "$item" '[.slots[]? | select(.slot < 36 and .item == $i) | .slot] | first // ""')
    [ -n "$src" ] || fail "no $item in the inventory for the recipe"
    ctl click-slot "$src" >/dev/null
    ctl wait 1 >/dev/null
    ctl click-slot "$cell" right >/dev/null
    ctl wait 1 >/dev/null
    ctl click-slot "$src" >/dev/null
    ctl wait 1 >/dev/null
}
place_one "$COAL" 100
place_one minecraft:redstone_torch 101
place_one "$COAL" 102
place_one "$COAL" 103
place_one "$STONE" 104
place_one "$COAL" 105
place_one "$COAL" 106
place_one minecraft:redstone_torch 107
place_one "$COAL" 108
RESULT=$(ctl screen | jq -r '[.slots[]? | select(.slot == 200) | .item] | first // "empty"')
echo "  the generator recipe with a stone where rftoolsbase:machine_frame belongs: '$RESULT'" >&2
[ "$RESULT" = "empty" ] || fail "a stone in the frame's cell crafted $RESULT"
ctl close >/dev/null 2>&1 || true
ctl wait 4 >/dev/null
echo "  the frame is what the recipe needs and RFToolsBase is not in this build (blocked, not dead data)"

# --- the power monitor ---------------------------------------------------
# The unit test pins the ratio: 1 + stored * 5 / capacity, integer, clamped to 1..=5. A
# generator doctored to 250,000 of 500,000 FE must therefore show level 3 before the leg runs.
echo "== N: a monitor facing a 250,000 FE generator reads level 3 =="
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
for z in 18 24 30 36 42; do
    ctl command "execute in minecraft:the_end run fill $((SX - 1)) 101 $z $((SX + 4)) 101 $z minecraft:air" >/dev/null
done
ctl wait 6 >/dev/null
ctl command "give @s $BLOCK[minecraft:block_entity_data={id:\"rftoolspower:coalgenerator_block_entity\",burn:0,burn_max:0,energy:250000}]" >/dev/null
ctl wait 8 >/dev/null
place_kept "$SX" 101 18
info "$SX" 101 18
expect_energy 250000
place_monitor "$((SX + 1))" 101 18
aim_monitor "$((SX + 1))" 101 18 east
ctl command "execute in minecraft:the_end run setblock $((SX + 2)) 101 18 minecraft:redstone_lamp" >/dev/null
ctl wait 40 >/dev/null
monitor "$((SX + 1))" 101 18
expect_level 3
expect_monitor_band 0 0
expect_alarm 0
expect_target "$BLOCK"
expect_stored 250000
[ "$MAXE" = "$CAPACITY" ] || fail "the monitor reads capacity $MAXE, expected $CAPACITY"
expect_block_level "$((SX + 1))" 101 18 3
expect_block_lit "$((SX + 1))" 101 18 false
expect_lamp "$((SX + 2))" 101 18 false
echo "  250,000/500,000 FE reads level 3, the unset band is silent and the lamp is dark"

echo "== O: an empty generator reads level 1 and still no alarm (the differential) =="
place_generator "$SX" 101 24
place_monitor "$((SX + 1))" 101 24
aim_monitor "$((SX + 1))" 101 24 east
ctl command "execute in minecraft:the_end run setblock $((SX + 2)) 101 24 minecraft:redstone_lamp" >/dev/null
ctl wait 40 >/dev/null
info "$SX" 101 24
expect_energy 0
monitor "$((SX + 1))" 101 24
expect_target "$BLOCK"
expect_stored 0
expect_level 1
expect_alarm 0
expect_block_level "$((SX + 1))" 101 24 1
expect_lamp "$((SX + 2))" 101 24 false
if [ "$SELFTEST_MONITOR" = 1 ]; then
    echo "(selftest: asserting the empty generator reads the charged level)"
    [ "$LEVEL" = 3 ] || fail "selftest: the empty generator reads level $LEVEL, not the charged 3, so the assertion is alive"
fi
echo "  an empty generator is level 1, not 3: the level follows the store"

echo "== P: a monitor facing stone reads level 0, not an energy block =="
ctl command "execute in minecraft:the_end run setblock $SX 101 30 minecraft:stone" >/dev/null
ctl wait 4 >/dev/null
place_monitor "$((SX + 1))" 101 30
aim_monitor "$((SX + 1))" 101 30 east
ctl wait 40 >/dev/null
monitor "$((SX + 1))" 101 30
expect_level 0
expect_target minecraft:stone
[ "$IS_ENERGY" = 0 ] || fail "a stone answered the energy capability"
expect_alarm 0
expect_block_level "$((SX + 1))" 101 30 0
echo "  stone: level 0 and 'not an energy block' — the monitor is not reading a phantom battery"

echo "== Q: the alarm band lights the lamp at 50 % and puts it out above it =="
say "rftoolspower band $((SX + 1)) 101 18 40 60"
ctl wait 8 >/dev/null
ctl wait 40 >/dev/null
monitor "$((SX + 1))" 101 18
expect_monitor_band 40 60
[ "$UNSET" = 0 ] || fail "the band 40..60 reads as unset"
expect_alarm 1
expect_block_lit "$((SX + 1))" 101 18 true
expect_lamp "$((SX + 2))" 101 18 true
echo "  50 % inside 40..60: alarm true, the monitor's display face gives 15 and the lamp is lit"
say "rftoolspower band $((SX + 1)) 101 18 90 100"
ctl wait 8 >/dev/null
ctl wait 40 >/dev/null
monitor "$((SX + 1))" 101 18
expect_monitor_band 90 100
expect_alarm 0
expect_block_lit "$((SX + 1))" 101 18 false
expect_lamp "$((SX + 2))" 101 18 false
echo "  50 % outside 90..100: the alarm and the lamp go out (the signal is not stuck)"

echo "== R: the generator pushes 2,000 FE a tick into an adjacent energy block =="
ctl command "clear @s" >/dev/null
ctl command "give @s $BLOCK[minecraft:block_entity_data={id:\"rftoolspower:coalgenerator_block_entity\",burn:0,burn_max:0,energy:100000}]" >/dev/null
ctl wait 8 >/dev/null
place_kept "$((SX - 1))" 101 36
info "$((SX - 1))" 101 36
expect_energy 100000
# An air step first: a re-run leaves the previous run's receiver standing with its store, and a
# `setblock` of the same block keeps the block entity's data (the receiver must start empty).
ctl command "execute in minecraft:the_end run setblock $SX 101 36 minecraft:air" >/dev/null
ctl wait 4 >/dev/null
ctl command "execute in minecraft:the_end run setblock $SX 101 36 $RECEIVER" >/dev/null
ctl wait 4 >/dev/null
[ "$(block_name "$SX" 101 36)" = "$RECEIVER" ] || fail "the harness receiver did not place at $SX,101,36"
# Sample at once: 100,000 at 2,000 a tick fills a 100,000 receiver in fifty ticks, so a later
# sample would catch the transfer already finished (and a full receiver accepts nothing).
G0=$(energy_of "$((SX - 1))" 101 36); R0=$(energy_of "$SX" 101 36)
echo "  before: generator $G0 FE, receiver $R0 FE"
[ "$R0" -lt 100000 ] || fail "the receiver was already full ($R0 FE) before the window: the sample is too late"
ctl wait 100 >/dev/null
G1=$(energy_of "$((SX - 1))" 101 36); R1=$(energy_of "$SX" 101 36)
echo "  after 100 ticks: generator $G1 FE, receiver $R1 FE"
[ "$R1" -gt "$R0" ] || fail "the generator never pushed: the receiver still holds $R1 FE"
[ "$G1" = 0 ] || fail "the generator still holds $G1 FE after pushing into a receiver with room"
[ "$R1" = 100000 ] || fail "the receiver holds $R1 FE, expected its full 100,000"
[ $(((R1 - R0) % 2000)) = 0 ] \
    || fail "the receiver gained $((R1 - R0)) FE, not a multiple of the 2,000 a tick a push moves"
echo "  the generator's 100,000 FE moved into the receiver in 2,000-FE pushes (it ends full, the generator empty)"
place_monitor "$((SX + 1))" 101 36
aim_monitor "$((SX + 1))" 101 36 east
ctl wait 30 >/dev/null
monitor "$((SX + 1))" 101 36
expect_target "$RECEIVER"
expect_stored 100000
[ "$MAXE" = 100000 ] || fail "the monitor reads the receiver's capacity as $MAXE, expected 100,000"
expect_level 5
expect_block_level "$((SX + 1))" 101 36 5
echo "  the monitor facing the receiver reads its full store: level 5"

echo "== S: a monitor item's band is restored when it is placed =="
ctl command "clear @s" >/dev/null
ctl command "give @s $MONITOR[minecraft:block_entity_data={id:\"rftoolspower:power_monitor_block_entity\",level:0,minimum:80,maximum:90,alarm:0b,counter:20}]" >/dev/null
ctl wait 8 >/dev/null
place_facing_player "$((SX + 1))" 101 42 "$MONITOR"
ctl wait 8 >/dev/null
monitor "$((SX + 1))" 101 42
expect_monitor_band 80 90
[ "$UNSET" = 0 ] || fail "the item's 80..90 band read as unset"
echo "  the placed monitor kept the item's 80..90 band"

echo "== T: the monitor's carried recipe needs the parent's machine base =="
ctl command "clear @s" >/dev/null
for item in minecraft:comparator minecraft:redstone minecraft:redstone_block "$STONE"; do
    ctl command "give @s $item 16" >/dev/null
done
ctl wait 8 >/dev/null
TX=$((SX + 4)); TY=101; TZ=42
open_crafting_table "$TX" "$TY" "$TZ"
# " P " / "rAr" / " R " with a stone where `rftoolsbase:machine_base` belongs.
place_one minecraft:comparator 101
place_one minecraft:redstone 103
place_one "$STONE" 104
place_one minecraft:redstone 105
place_one minecraft:redstone_block 107
RESULT=$(ctl screen | jq -r '[.slots[]? | select(.slot == 200) | .item] | first // "empty"')
echo "  the monitor recipe with a stone where rftoolsbase:machine_base belongs: '$RESULT'" >&2
[ "$RESULT" = "empty" ] || fail "a stone in the machine base's cell crafted $RESULT"
ctl close >/dev/null 2>&1 || true
ctl wait 4 >/dev/null
echo "  the machine base is what the monitor's recipe needs and RFToolsBase is not in this build"


# --- the powercell -------------------------------------------------------
# Everything above has used rows z=0..42. The cells get their own floor and rows (44..90).
# The cell rows reach z=90, further than the slice-1/2 arena, so stand in them first: a fill that
# spans unloaded chunks answers "That position is not loaded" and lands nothing.
ctl command "execute in minecraft:the_end run tp @s $((SX)).5 101 68.5" >/dev/null
ctl wait 40 >/dev/null
for attempt in 1 2 3; do
    ctl command "execute in minecraft:the_end run fill $((SX - 4)) 100 44 $((SX + 6)) 100 90 minecraft:stone" >/dev/null
    ctl wait 6 >/dev/null
    [ "$(block_name "$SX" 100 68)" = "minecraft:stone" ] && break
    echo "  the cell arena floor fill did not land (attempt $attempt); waiting for the chunks" >&2
    ctl wait 40 >/dev/null
done
[ "$(block_name "$SX" 100 68)" = "minecraft:stone" ] || fail "the cell arena floor is not stone"
ctl command "execute in minecraft:the_end run fill $((SX - 4)) 101 44 $((SX + 6)) 108 90 minecraft:air" >/dev/null
ctl wait 8 >/dev/null
[ "$(block_name "$SX" 101 68)" = "minecraft:air" ] || fail "the cell arena air fill did not land"
ctl command "gamemode creative" >/dev/null

# A cell item, optionally doctored to carry ENERGY (`minecraft:block_entity_data`, the same
# carrier the generator uses; `TypedEntityData.loadInto` needs the id to match the type).
give_cell() { # give_cell ITEM [ENERGY]
    local item=$1 energy=${2:-} type
    ctl command "clear @s" >/dev/null
    if [ -n "$energy" ]; then
        type=rftoolspower:cell1_block_entity
        [ "$item" = "$CELL2" ] && type=rftoolspower:cell2_block_entity
        ctl command "give @s $item[minecraft:block_entity_data={id:\"$type\",energy:$energy}]" >/dev/null
    else
        ctl command "give @s $item" >/dev/null
    fi
    ctl wait 8 >/dev/null
}

place_held() { # place_held X Y Z ITEM — place the item the player already carries
    local x=$1 y=$2 z=$3 item=$4
    ctl command "execute in minecraft:the_end run tp @s $((x - 2)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    ctl select "$item" >/dev/null
    ctl wait 2 >/dev/null
    ctl look-at-block "$x" $((y - 1)) "$z" up >/dev/null \
        || fail "cannot aim at the floor under $x,$y,$z"
    place_block "$x" "$y" "$z" "$item" \
        || fail "ctl place $item at $x,$y,$z failed: $PLACE_REPLY"
    ctl wait 6 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$item" ] || fail "$item did not place at $x,$y,$z"
}

pick_up_item() { # pick_up_item X Y Z ITEM
    ctl collect 8 >/dev/null 2>&1 || true
    ctl wait 10 >/dev/null
    if [ "$(held_count "$4")" = 0 ]; then
        ctl command "execute in minecraft:the_end run tp @s $1.5 $2 $3.5" >/dev/null
        ctl wait 20 >/dev/null
    fi
    [ "$(held_count "$4")" != 0 ] \
        || fail "the broken $4 was not picked up: $(ctl inventory | jq -c '{hotbar,main}')"
}

held_item_line_for() { # held_item_line_for ITEM
    ctl select "$1" >/dev/null
    ctl wait 4 >/dev/null
    ctl command "data get entity @s SelectedItem" >/dev/null
    ctl wait 6 >/dev/null
    ctl messages 8 | jq -r '.chat[]' | grep -m1 'has the following entity data' || true
}

cell_state() { # cell_state X Y Z — the `/rftoolspower cell` line, parsed
    NONCE=$(( ${NONCE:-0} + 1 ))
    local line
    say "rftoolspower cell $1 $2 $3 $NONCE"
    line=$(await_line "nonce=$NONCE")
    [ -n "$line" ] || fail "no fresh /rftoolspower cell reply for nonce $NONCE: $(ctl messages 8 | jq -c '.chat')"
    eval "$(python3 "$PORT/tools/parse_cell.py" "$line" --nonce "$NONCE")"
    [ "${ok:-0}" = 1 ] || fail "the cell line did not parse: $line"
    echo "  $line" >&2
}

side_set() { # side_set X Y Z FACE MODE
    local line
    say "rftoolspower side $1 $2 $3 $4 $5"
    line=$(await_line "Power Cell side at $1,$2,$3: $4 $5")
    [ -n "$line" ] || fail "no 'Power Cell side' reply for $4 $5: $(ctl messages 8 | jq -c '.chat')"
    eval "$(python3 "$PORT/tools/parse_side.py" "$line")"
    [ "${ok:-0}" = 1 ] || fail "the side reply did not parse: $line"
    [ "$REFUSAL" = none ] && [ "$FACE" = "$4" ] && [ "$MODE" = "$5" ] \
        || fail "the side command answered $REFUSAL/$FACE/$MODE for $4 $5: $line"
    echo "  $line" >&2
}

side_refused() { # side_refused X Y Z FACE MODE KIND WORD
    local line
    say "rftoolspower side $1 $2 $3 $4 $5"
    line=$(await_line "unknown $6 '$7'")
    [ -n "$line" ] || fail "no 'unknown $6' refusal for $4 $5: $(ctl messages 8 | jq -c '.chat')"
    eval "$(python3 "$PORT/tools/parse_side.py" "$line")"
    [ "${ok:-0}" = 1 ] || fail "the refusal did not parse: $line"
    [ "$REFUSAL" = "$6" ] && [ "$WORD" = "$7" ] \
        || fail "expected a $6 refusal naming '$7', got $REFUSAL/${WORD:-none}: $line"
    echo "  $line" >&2
}

expect_tier() { [ "$TIER" = "$1" ] || fail "the cell is tier $TIER, expected $1"; }
expect_cells() { [ "$CELLS" = "$1" ] || fail "the network holds $CELLS cells, expected $1"; }
expect_local() { [ "$LOCAL" = "$1" ] || fail "the cell holds $LOCAL FE locally, expected $1"; }
expect_network() {
    [ "$NETWORK" = "$1" ] && [ "$NCAP" = "$2" ] \
        || fail "the network reads $NETWORK/$NCAP FE, expected $1/$2"
}
expect_sides() { [ "$SIDES" = "$1" ] || fail "the cell's faces are $SIDES, expected $1"; }

echo "== U: a fresh cell1 is empty, alone in its network, and all six faces are NONE =="
give_cell "$CELL" 0
place_held "$SX" 101 48 "$CELL"
cell_state "$SX" 101 48
expect_tier 1
expect_cells 1
expect_local 0
expect_network 0 500000
expect_sides "none,none,none,none,none,none"
[ "$(energy_of "$SX" 101 48)" = 0 ] || fail "a fresh cell's saved energy is not 0"
echo "  a fresh cell1: local 0/500000, one cell in the network, six NONE faces"

echo "== V: a fresh cell refuses the push (its west face is NONE) =="
ctl command "give @s $BLOCK[minecraft:block_entity_data={id:\"rftoolspower:coalgenerator_block_entity\",burn:0,burn_max:0,energy:100000}]" >/dev/null
ctl wait 8 >/dev/null
place_held "$((SX - 1))" 101 48 "$BLOCK"
info "$((SX - 1))" 101 48
expect_energy 100000
ctl wait 40 >/dev/null
cell_state "$SX" 101 48
expect_local 0
info "$((SX - 1))" 101 48
expect_energy 100000
if [ "$SELFTEST" = 1 ]; then
    echo "(selftest: asserting the NONE face took the generator's FE)"
    [ "$LOCAL" != 0 ] || fail "selftest: the cell's NONE face took nothing in 40 ticks, so the assertion is alive"
fi
echo "  40 ticks against a 100,000 FE generator: the cell still holds 0 and the generator 100,000"

echo "== W: with its west face INPUT the cell takes exactly 250 FE a tick =="
side_set "$SX" 101 48 west input
expect_sides "none,none,none,none,input,none"
cell_state "$SX" 101 48
T0=$T; E0=$LOCAL
info "$((SX - 1))" 101 48
GT0=$T; GE0=$ENERGY
ctl wait 20 >/dev/null
cell_state "$SX" 101 48
DT=$((T - T0))
DE=$((LOCAL - E0))
echo "  over $DT ticks: cell $E0 -> $LOCAL FE (+$DE)"
[ "$DT" -ge 10 ] || fail "only $DT ticks passed; the window is too small to assert"
[ "$DE" = $((250 * DT)) ] \
    || fail "the cell took $DE FE over $DT ticks, expected exactly $((250 * DT)): tier1MaxRFPerTick is 250 a side a tick, not the generator's 2,000"
info "$((SX - 1))" 101 48
GDT=$((T - GT0)); GDROP=$((GE0 - ENERGY))
echo "  over $GDT ticks: generator $GE0 -> $ENERGY FE (-$GDROP)"
[ "$GDT" -ge 10 ] || fail "only $GDT generator ticks passed; the window is too small to assert"
[ "$GDROP" = $((250 * GDT)) ] \
    || fail "the generator lost $GDROP FE over $GDT ticks, expected $((250 * GDT)): it keeps the 1,750 a tick the cell refuses"
echo "  the tier-1 cap is upstream's: 250 a tick reaches the cell, the rest stays in the generator"
ctl wait 420 >/dev/null
cell_state "$SX" 101 48
expect_local 100000
info "$((SX - 1))" 101 48
expect_energy 0
echo "  the generator's 100,000 FE arrived: cell 100,000, generator 0"

echo "== X: a second cell1 beside it shares one network; a cell with a gap does not =="
give_cell "$CELL" 1000
place_held "$SX" 101 54 "$CELL"
give_cell "$CELL" 2000
place_held "$SX" 101 55 "$CELL"
cell_state "$SX" 101 54
expect_cells 2
expect_local 1000
expect_network 3000 1000000
cell_state "$SX" 101 55
expect_cells 2
expect_local 2000
expect_network 3000 1000000
give_cell "$CELL" 4000
place_held "$SX" 101 57 "$CELL"
cell_state "$SX" 101 57
expect_cells 1
expect_local 4000
expect_network 4000 500000
echo "  adjacent (54/55): both read the 3,000/1,000,000 network; with a gap (57): its own 4,000/500,000"

echo "== Y: a cell2 beside a cell1 joins the same network (adjacency, not tier) =="
give_cell "$CELL" 5000
place_held "$SX" 101 60 "$CELL"
give_cell "$CELL2"
place_held "$SX" 101 61 "$CELL2"
cell_state "$SX" 101 60
expect_cells 2
expect_local 5000
expect_network 5000 4500000
cell_state "$SX" 101 61
expect_cells 2
expect_local 0
expect_network 5000 4500000
give_cell "$CELL2"
place_held "$SX" 101 63 "$CELL2"
cell_state "$SX" 101 63
expect_cells 1
expect_local 0
expect_network 0 4000000
echo "  cell1+cell2 share 5,000/4,500,000; the cell2 with a gap is its own 4,000,000"

echo "== Z: an OUTPUT face pushes the network's FE into a neighbour =="
give_cell "$CELL" 100000
place_held "$SX" 101 68 "$CELL"
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 68 minecraft:air" >/dev/null
ctl wait 4 >/dev/null
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 68 $RECEIVER" >/dev/null
ctl wait 4 >/dev/null
[ "$(block_name "$((SX + 1))" 101 68)" = "$RECEIVER" ] || fail "the harness receiver did not place at $((SX + 1)),101,68"
side_set "$SX" 101 68 east output
expect_sides "none,none,none,none,none,output"
cell_state "$SX" 101 68
T0=$T; E0=$LOCAL
ctl wait 20 >/dev/null
cell_state "$SX" 101 68
DT=$((T - T0))
DE=$((E0 - LOCAL))
echo "  over $DT ticks: cell $E0 -> $LOCAL FE (-$DE)"
[ "$DT" -ge 10 ] || fail "only $DT ticks passed; the window is too small to assert"
[ "$DE" = $((250 * DT)) ] \
    || fail "the cell gave out $DE FE over $DT ticks, expected exactly $((250 * DT)) (tier1MaxRFPerTick)"
# Stop the push before reading the receiver: two stores that are still moving are read a few
# ticks apart, so a conservation check across them needs both at rest.
side_set "$SX" 101 68 east none
cell_state "$SX" 101 68
STILL=$LOCAL
R1=$(energy_of "$((SX + 1))" 101 68)
[ "$R1" -gt 0 ] || fail "the OUTPUT face never reached the receiver: it still holds $R1 FE"
[ $((STILL + R1)) = 100000 ] \
    || fail "at rest the cell ($STILL) and the receiver ($R1) hold $((STILL + R1)) FE between them, not the 100,000 that was seeded"
echo "  the cell pushed 250 FE a tick out of its OUTPUT face; at rest the two stores still add to 100,000"

echo "== AA: a cell keeps its store and its face modes across save + relaunch =="
give_cell "$CELL" 7000
place_held "$SX" 101 74 "$CELL"
side_set "$SX" 101 74 west input
cell_state "$SX" 101 74
SAVED=$LOCAL
ctl save >/dev/null
ctl wait 10 >/dev/null
ctl quit >/dev/null 2>&1 || true
sleep 2
launch
ctl command "execute in minecraft:the_end run tp @s $((SX - 2)).5 101 74.5" >/dev/null
ctl wait 40 >/dev/null
[ "$(block_name "$SX" 101 74)" = "$CELL" ] || fail "the cell did not survive the relaunch"
cell_state "$SX" 101 74
[ "$LOCAL" -ge "$SAVED" ] || fail "after the relaunch the cell holds $LOCAL FE, was $SAVED before the save"
expect_sides "none,none,none,none,input,none"
echo "  after save + relaunch: $LOCAL/$LCAP FE, west face still input"

echo "== AB: a broken cell carries its own store =="
ctl command "gamemode survival" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 6 >/dev/null
give_cell "$CELL" 3000
place_held "$SX" 101 78 "$CELL"
cell_state "$SX" 101 78
expect_local 3000
break_block "$SX" 101 78 minecraft:iron_pickaxe
pick_up_item "$SX" 101 78 "$CELL"
DROP_LINE=$(held_item_line_for "$CELL")
[ -n "$DROP_LINE" ] || fail "no /data get reply for the picked-up cell: $(ctl messages 8 | jq -c '.chat')"
echo "  $DROP_LINE" >&2
DROP=$(python3 "$PORT/tools/parse_drop.py" "$DROP_LINE" 3000 rftoolspower:cell1_block_entity) || true
eval "$DROP"
[ "${ok:-0}" = 1 ] || fail "the dropped cell does not carry 3,000 FE: $DROP_LINE"
echo "  the item carries $carried FE"
place_held "$SX" 101 78 "$CELL"
cell_state "$SX" 101 78
[ "$LOCAL" -ge 3000 ] || fail "the placed-back cell holds $LOCAL FE, expected at least 3,000"
echo "  placed back at $LOCAL FE"

echo "== AC: the power core crafts, and the cell's recipe needs the parent's machine frame =="
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
for item in minecraft:diamond minecraft:redstone minecraft:redstone_block; do
    ctl command "give @s $item 16" >/dev/null
done
ctl wait 8 >/dev/null
TX=$((SX + 4)); TY=101; TZ=78
open_crafting_table "$TX" "$TY" "$TZ"
D0=$(held_count minecraft:diamond); R0=$(held_count minecraft:redstone); B0=$(held_count minecraft:redstone_block)
# " d " / "rRr" / " r ": a diamond over a redstone block, redstone around it.
place_one minecraft:diamond 101
place_one minecraft:redstone 103
place_one minecraft:redstone_block 104
place_one minecraft:redstone 105
place_one minecraft:redstone 107
RESULT=$(ctl screen | jq -r '[.slots[]? | select(.slot == 200) | .item] | first // "empty"')
echo "  the power core's recipe: '$RESULT'" >&2
[ "$RESULT" = "$CORE" ] || fail "the power core's recipe made '$RESULT'"
# The output slot puts the craft on the cursor; a second click stores it in the hotbar.
ctl click-slot 200 >/dev/null
ctl wait 3 >/dev/null
ctl click-slot 8 >/dev/null
ctl wait 6 >/dev/null
[ "$(held_count "$CORE")" = 1 ] || fail "the crafted core is not in the inventory: $(ctl screen | jq -c '[.slots[]? | select(.item != null) | {slot, item, count}]')"
LEFT=$(ctl screen | jq '[.slots[]? | select(.slot >= 100 and .slot <= 108 and .item != null)] | length')
[ "$LEFT" = 0 ] || fail "the crafting grid still holds $LEFT ingredients after the craft"
D1=$(held_count minecraft:diamond); R1=$(held_count minecraft:redstone); B1=$(held_count minecraft:redstone_block)
[ $((D0 - D1)) = 1 ] || fail "the core's diamond was not consumed ($D0 -> $D1)"
[ $((R0 - R1)) = 3 ] || fail "the core's three redstones were not consumed ($R0 -> $R1)"
[ $((B0 - B1)) = 1 ] || fail "the core's redstone block was not consumed ($B0 -> $B1)"
echo "  the core crafted once and its diamond, redstone block and three redstones were consumed"
ctl close >/dev/null 2>&1 || true
ctl wait 4 >/dev/null
ctl command "clear @s" >/dev/null
for item in minecraft:redstone minecraft:stone "$CORE"; do
    ctl command "give @s $item 16" >/dev/null
done
ctl wait 8 >/dev/null
ctl interact "$TX" "$TY" "$TZ" >/dev/null || fail "the crafting table did not take the second click"
ctl wait 6 >/dev/null
# "rKr" / "KFK" / "rKr" with a stone where `rftoolsbase:machine_frame` belongs.
place_one minecraft:redstone 100
place_one "$CORE" 101
place_one minecraft:redstone 102
place_one "$CORE" 103
place_one minecraft:stone 104
place_one "$CORE" 105
place_one minecraft:redstone 106
place_one "$CORE" 107
place_one minecraft:redstone 108
RESULT=$(ctl screen | jq -r '[.slots[]? | select(.slot == 200) | .item] | first // "empty"')
echo "  cell1's recipe with a stone where rftoolsbase:machine_frame belongs: '$RESULT'" >&2
[ "$RESULT" = "empty" ] || fail "a stone in the machine frame's cell crafted $RESULT"
ctl close >/dev/null 2>&1 || true
ctl wait 4 >/dev/null
echo "  the machine frame is what cell1's recipe needs and RFToolsBase is not in this build"

echo "== AD: the side command's refusals are parsed replies, not the exit status =="
side_refused "$SX" 101 48 nowhere input face nowhere
side_refused "$SX" 101 48 west inputt mode inputt
say "rftoolspower side $SX 101 30 west input"
LINE=$(await_line "power cell there")
[ -n "$LINE" ] || fail "no refusal for a position with no cell: $(ctl messages 8 | jq -c '.chat')"
eval "$(python3 "$PORT/tools/parse_side.py" "$LINE")"
[ "${ok:-0}" = 1 ] || fail "the no-cell refusal did not parse: $LINE"
[ "$REFUSAL" = target ] || fail "a stone position answered '$REFUSAL', expected a no-cell refusal: $LINE"
echo "  $LINE"
echo "  a bad face, a bad mode and a position with no cell are three parsed refusals"

# --- the endergenic generator and the pearl injector ---------------------
# Upstream's `EndergenicTileEntity` (1.21-7.0.6): a generator charges through modes 1..15 on a
# redstone pulse, and a pearl fired at it from another generator pays `RF_PER_HIT[mode] *
# powergenFactor` when it lands inside that window — and nothing when it lands at idle, where the
# pearl is lost. A pearl that lands starts a hold that costs 500 FE a tick. The pearl injector
# fires one pearl into the generator it is mounted on, on its own redstone pulse.
#
# The rows below z=92 are this slice's; the earlier slices' arena ends at z=90. Two generators are
# the minimum upstream's own tooltip names ("you need at least two generators for this to work"),
# and the link is the wrench's, set here by `/rftoolspower enderlink` — the harness's stand-in for
# the smart wrench the parent port does not carry.
ENDER=rftoolspower:endergenic
INJECTOR=rftoolspower:pearl_injector
ENDERGENIC_ENTITY=rftoolspower:endergenic_block_entity
# `EndergenicTileEntity.rfPerHit` and `powergenFactor`: the gain the leg checks against the mode it
# reads from the reply.
RF_PER_HIT=(0 100 150 200 400 800 1600 3200 6400 8000 12800 8000 6400 2500 1000 100)
POWERGEN_FACTOR=2

ender_arena() {
    ctl command "execute in minecraft:the_end run tp @s $((SX)).5 101 106.5" >/dev/null
    ctl wait 40 >/dev/null
    local attempt
    for attempt in 1 2 3; do
        ctl command "execute in minecraft:the_end run fill $((SX - 6)) 100 92 $((SX + 8)) 100 124 minecraft:stone" >/dev/null
        ctl wait 6 >/dev/null
        [ "$(block_name "$SX" 100 106)" = "minecraft:stone" ] && break
        echo "  the endergenic arena floor fill did not land (attempt $attempt); waiting" >&2
        ctl wait 40 >/dev/null
    done
    [ "$(block_name "$SX" 100 106)" = "minecraft:stone" ] || fail "the endergenic arena floor is not stone"
    ctl command "execute in minecraft:the_end run fill $((SX - 6)) 101 92 $((SX + 8)) 108 124 minecraft:air" >/dev/null
    ctl wait 8 >/dev/null
    [ "$(block_name "$SX" 101 106)" = "minecraft:air" ] || fail "the endergenic arena air fill did not land"
    ctl command "gamemode creative" >/dev/null
    ctl command "clear @s" >/dev/null
    ctl wait 4 >/dev/null
}

ender_state() { # ender_state X Y Z — the `/rftoolspower endergenic` line, parsed
    NONCE=$(( ${NONCE:-0} + 1 ))
    local line
    say "rftoolspower endergenic $1 $2 $3 $NONCE"
    line=$(await_line "nonce=$NONCE")
    [ -n "$line" ] || fail "no fresh /rftoolspower endergenic reply for nonce $NONCE: $(ctl messages 8 | jq -c '.chat')"
    eval "$(python3 "$PORT/tools/parse_ender.py" "$line" --nonce "$NONCE")"
    [ "${ok:-0}" = 1 ] || fail "the endergenic line did not parse: $line"
    echo "  $line" >&2
    echo "  parsed: energy=$ENERGY/$ECAP charging=$CHARGING gained=$GAINED spent=$SPENT arrived=$ARRIVED reason=$REASON dest=$DEST" >&2
}

injector_state() { # injector_state X Y Z — the `/rftoolspower injector` line, parsed
    NONCE=$(( ${NONCE:-0} + 1 ))
    local line
    say "rftoolspower injector $1 $2 $3 $NONCE"
    line=$(await_line "nonce=$NONCE")
    [ -n "$line" ] || fail "no fresh /rftoolspower injector reply for nonce $NONCE: $(ctl messages 8 | jq -c '.chat')"
    eval "$(python3 "$PORT/tools/parse_injector.py" "$line" --nonce "$NONCE")"
    [ "${ok:-0}" = 1 ] || fail "the injector line did not parse: $line"
    echo "  $line" >&2
    echo "  parsed: pearls=$PEARLS generator=$GENERATOR" >&2
}

give_ender() { # give_ender [ENERGY] — a generator item, optionally carrying a store
    ctl command "clear @s" >/dev/null
    if [ -n "${1:-}" ]; then
        ctl command "give @s $ENDER[minecraft:block_entity_data={id:\"$ENDERGENIC_ENTITY\",energy:$1}]" >/dev/null
    else
        ctl command "give @s $ENDER" >/dev/null
    fi
    ctl wait 8 >/dev/null
}

give_injector() {
    ctl command "clear @s" >/dev/null
    ctl command "give @s $INJECTOR" >/dev/null
    ctl wait 8 >/dev/null
}

# The injector sits on top of its generator; its front is pinned up so the generator behind it is
# the block below. `ctl place` exercises `state_for_placement` first (the block is placed from its
# item), then the state is set explicitly — the `aim_monitor` precedent: the placement context's
# face is the game's, not the harness's, and the direction is what the phase needs.
# The injector stands on the floor beside its generator, its front away from it (upstream's
# `getFacingFromEntity`: the front faces the placer, so the generator is behind it). It is placed
# from its item — `state_for_placement` runs — and then the front is pinned: `ctl place`'s
# placement yaw is the game's, not the player's (the monitor phases found this on 2026-11-21).
place_injector() { # place_injector X Y Z FACE
    local x=$1 y=$2 z=$3 face=${4:-east}
    ctl command "execute in minecraft:the_end run setblock $x $y $z minecraft:air" >/dev/null
    ctl wait 4 >/dev/null
    # Approach from the generator's far side: the block being aimed at must not be shadowed.
    ctl command "execute in minecraft:the_end run tp @s $((x + 2)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    ctl select "$INJECTOR" >/dev/null
    ctl wait 2 >/dev/null
    ctl look-at-block "$x" $((y - 1)) "$z" up >/dev/null \
        || fail "cannot aim at the floor under $x,$y,$z: $(ctl block "$x" $((y - 1)) "$z" | jq -c '.')"
    place_block "$x" "$y" "$z" "$INJECTOR" \
        || fail "ctl place $INJECTOR at $x,$y,$z failed: $PLACE_REPLY"
    ctl wait 4 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$INJECTOR" ] || fail "the injector is not at $x,$y,$z"
    echo "  injector: $(ctl block "$x" "$y" "$z" | jq -r '.state')" >&2
    local state
    state=$(ctl block "$x" "$y" "$z" | jq -r '.state')
    case "$state" in
        *facing="$face"*) ;;
        *)
            ctl command "execute in minecraft:the_end run setblock $x $y $z $INJECTOR[facing=$face]" >/dev/null
            ctl wait 4 >/dev/null
            state=$(ctl block "$x" "$y" "$z" | jq -r '.state')
            echo "  (the placement's front was '$state'; pinned to facing=$face)" >&2
            ;;
    esac
    case "$state" in
        *facing="$face"*) ;;
        *) fail "the injector's front is '$state', expected facing=$face" ;;
    esac
}

# One atomic redstone pulse: a fill places every cell in the same tick, so two blocks see the same
# rising edge (one command per block would let them fire on different ticks).
pulse_fill() { # pulse_fill X1 Y1 Z1 X2 Y2 Z2
    ctl command "execute in minecraft:the_end run fill $1 $2 $3 $4 $5 $6 minecraft:redstone_block" >/dev/null
    ctl wait 3 >/dev/null
    ctl command "execute in minecraft:the_end run fill $1 $2 $3 $4 $5 $6 minecraft:air" >/dev/null
    ctl wait 3 >/dev/null
}

link() { # link X Y Z DX DY DZ
    local line
    say "rftoolspower enderlink $1 $2 $3 $4 $5 $6"
    line=$(await_line "Endergenic link at $1,$2,$3")
    [ -n "$line" ] || fail "no link reply for $1,$2,$3 -> $4,$5,$6: $(ctl messages 8 | jq -c '.chat')"
    echo "  $line" >&2
}

# One ender pearl into the injector from a survival click, so it leaves the hand.
pearl_into_injector() { # pearl_into_injector X Y Z
    local x=$1 y=$2 z=$3
    ctl command "gamemode survival" >/dev/null
    ctl command "clear @s" >/dev/null
    ctl command "give @s minecraft:ender_pearl 1" >/dev/null
    ctl wait 8 >/dev/null
    ctl command "execute in minecraft:the_end run tp @s $((x + 2)).5 $y $z.5" >/dev/null
    ctl wait 6 >/dev/null
    ctl select 1 >/dev/null
    ctl wait 2 >/dev/null
    ctl interact "$x" "$y" "$z" >/dev/null
    ctl wait 8 >/dev/null
    injector_state "$x" "$y" "$z"
    [ "$PEARLS" = 1 ] || fail "the pearl click left $PEARLS pearls in the injector at $x,$y,$z"
    [ "$(held_count minecraft:ender_pearl)" = 0 ] || fail "the pearl stayed in the hand after the click"
    ctl command "gamemode creative" >/dev/null
    ctl wait 4 >/dev/null
}

expect_ender_energy() { [ "$ENERGY" = "$1" ] || fail "the endergenic holds $ENERGY FE, expected $1"; }
expect_charging() { [ "$CHARGING" = "$1" ] || fail "the endergenic's charging mode is $CHARGING, expected $1"; }

echo "== AE: a generator, its destination and the injector that feeds the link =="
ender_arena
for z in 94 97; do
    ctl command "execute in minecraft:the_end run setblock $SX 101 $z minecraft:air" >/dev/null
    ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 $z minecraft:air" >/dev/null
done
ctl wait 4 >/dev/null
# The injector first (placed with nothing to its east), then the source west of it, then the
# destination three blocks south: A -> B is a 2-tick flight, ((int)(3/3)+1).
give_injector
place_injector "$((SX + 1))" 101 94 east
give_ender
place_held "$SX" 101 94 "$ENDER"
give_ender
place_held "$SX" 101 97 "$ENDER"
injector_state "$((SX + 1))" 101 94
[ "$GENERATOR" = "$SX,101,94" ] || fail "the injector points at generator '$GENERATOR', expected $SX,101,94"
[ "$PEARLS" = 0 ] || fail "a fresh injector holds $PEARLS pearls"
link "$SX" 101 94 "$SX" 101 97
ender_state "$SX" 101 94
[ "$DEST" = "$SX,101,97" ] || fail "the source's link is $DEST, expected $SX,101,97"
[ "$DISTANCE" = 2 ] || fail "a three-block link is $DISTANCE ticks, expected 2 ((int)(3/3)+1)"
expect_ender_energy 0
ender_state "$SX" 101 97
expect_ender_energy 0
expect_charging 0
echo "  A links to B three blocks away (a 2-tick flight); both are empty and idle"

echo "== AF: a pearl that lands inside the window pays the hit table's amount =="
pearl_into_injector "$((SX + 1))" 101 94
# One fill pulses the injector and B on the same tick, through their top faces. It also covers the
# air above A, so A sees an edge too: A is idle, and it starts a charge the injector's fire resets.
pulse_fill $SX 102 94 $((SX + 1)) 102 97
ctl wait 20 >/dev/null
injector_state "$((SX + 1))" 101 94
[ "$PEARLS" = 0 ] || fail "the injector still holds $PEARLS pearls after its pulse"
ender_state "$SX" 101 94
[ "$FIRED" = 1 ] || fail "the source fired $FIRED pearls, expected 1"
ender_state "$SX" 101 97
[ "$ARRIVED" -ge 1 ] && [ "$ARRIVED" -le 15 ] \
    || fail "the pearl arrived at charging=$ARRIVED, outside the 1..15 window"
EXPECT=$(( RF_PER_HIT[ARRIVED] * POWERGEN_FACTOR ))
[ "$GAINED" = "$EXPECT" ] \
    || fail "the pearl paid $GAINED FE at mode $ARRIVED, expected $EXPECT (rfPerHit ${RF_PER_HIT[ARRIVED]} x $POWERGEN_FACTOR)"
[ "$ENERGY" = $(( GAINED - SPENT )) ] \
    || fail "the store is $ENERGY but the generator gained $GAINED and spent $SPENT holding"
[ $(( SPENT % 500 )) = 0 ] || fail "the hold cost $SPENT is not a multiple of the 500 a tick"
if [ "${SELFTEST_ENDER:-0}" = 1 ]; then
    echo "(selftest: asserting the pearl paid nothing)"
    [ "$GAINED" = 0 ] || fail "selftest: the pearl paid $GAINED FE at mode $ARRIVED, so the assertion is alive"
fi
echo "  the pearl landed at mode $ARRIVED and paid $GAINED FE (rfPerHit ${RF_PER_HIT[ARRIVED]} x $POWERGEN_FACTOR); holding spent $SPENT"
# Let the hold end (a big gain pays 500 a tick until the store cannot) so the monitor below reads a
# store at rest: two reads a few ticks apart of a moving store are not comparable.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    [ "$CHARGING" = -1 ] || break
    ctl wait 10 >/dev/null
    ender_state "$SX" 101 97
done
[ "$CHARGING" != -1 ] || fail "the generator is still holding a pearl after 120 ticks"
# The endergenic's buffer is a real energy capability: a monitor facing B reads the same store.
place_monitor "$((SX + 1))" 101 97
aim_monitor "$((SX + 1))" 101 97 east
ctl wait 30 >/dev/null
ender_state "$SX" 101 97
monitor "$((SX + 1))" 101 97
expect_target "$ENDER"
[ "$STORED" = "$ENERGY" ] || fail "the monitor reads $STORED FE but the generator holds $ENERGY"
[ "$MAXE" = "$ECAP" ] || fail "the monitor reads capacity $MAXE, expected $ECAP"
[ "$IS_ENERGY" = 1 ] || fail "the endergenic did not answer the energy capability"
echo "  the monitor facing the generator reads its $ENERGY/$ECAP FE through the capability"

echo "== AG: a pearl that lands while the destination is idle is lost and pays nothing =="
for z in 108 111; do
    ctl command "execute in minecraft:the_end run setblock $SX 101 $z minecraft:air" >/dev/null
    ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 $z minecraft:air" >/dev/null
done
ctl wait 4 >/dev/null
give_injector
place_injector "$((SX + 1))" 101 108 east
give_ender
place_held "$SX" 101 108 "$ENDER"
give_ender
place_held "$SX" 101 111 "$ENDER"
link "$SX" 101 108 "$SX" 101 111
pearl_into_injector "$((SX + 1))" 101 108
# Only the injector is pulsed: the destination never leaves idle, so the pearl has nowhere to land.
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 102 108 minecraft:redstone_block" >/dev/null
ctl wait 3 >/dev/null
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 102 108 minecraft:air" >/dev/null
ctl wait 24 >/dev/null
ender_state "$SX" 101 111
expect_ender_energy 0
[ "$GAINED" = 0 ] || fail "an idle destination paid $GAINED FE for a pearl it should have lost"
[ "$DROPPED" = 1 ] || fail "the destination dropped $DROPPED pearls, expected the one it lost"
[ "$REASON" = "Pearl arrived while idle" ] || fail "the drop reason is '$REASON', expected 'Pearl arrived while idle'"
[ "$ARRIVED" = -2 ] || fail "the destination records an arrival at mode $ARRIVED but paid nothing"
injector_state "$((SX + 1))" 101 108
[ "$PEARLS" = 0 ] || fail "the injector kept its pearl after the pulse"
ender_state "$SX" 101 108
[ "$FIRED" = 1 ] || fail "the source fired $FIRED pearls, expected 1"
echo "  the same shot outside the window: the pearl is lost, the destination gains 0 FE"

echo "== AH: a generator with no injector stays empty even while it charges =="
ctl command "execute in minecraft:the_end run setblock $SX 101 114 minecraft:air" >/dev/null
ctl wait 4 >/dev/null
give_ender
place_held "$SX" 101 114 "$ENDER"
ender_state "$SX" 101 114
expect_ender_energy 0
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 114 minecraft:redstone_block" >/dev/null
ctl wait 3 >/dev/null
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 114 minecraft:air" >/dev/null
ctl wait 2 >/dev/null
ender_state "$SX" 101 114
[ "$CHARGING" -ge 1 ] && [ "$CHARGING" -le 15 ] \
    || fail "the pulse left the generator at charging=$CHARGING, expected a mode inside 1..15"
ctl wait 30 >/dev/null
ender_state "$SX" 101 114
expect_charging 0
expect_ender_energy 0
[ "$GAINED" = 0 ] || fail "a generator with no injector gained $GAINED FE"
[ "$FIRED" = 0 ] || fail "a generator with no injector fired $FIRED pearls"
echo "  a charge runs 1..15 and expires with no pearl: 0 FE, nothing fired"

echo "== AI: the endergenic pushes out and keeps its 2,000 FE reserve =="
ctl command "execute in minecraft:the_end run setblock $SX 101 117 minecraft:air" >/dev/null
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 117 minecraft:air" >/dev/null
ctl wait 4 >/dev/null
give_ender 100000
place_held "$SX" 101 117 "$ENDER"
ender_state "$SX" 101 117
expect_ender_energy 100000
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 117 $RECEIVER" >/dev/null
ctl wait 6 >/dev/null
[ "$(block_name "$((SX + 1))" 101 117)" = "$RECEIVER" ] || fail "the harness receiver did not place beside the generator"
ctl wait 40 >/dev/null
ender_state "$SX" 101 117
expect_ender_energy 2000
R_ENDER=$(energy_of "$((SX + 1))" 101 117)
[ "$R_ENDER" = 98000 ] \
    || fail "the receiver holds $R_ENDER FE, expected 98,000: the generator pushes all but its 2,000 FE reserve"
echo "  the 100,000 FE store moved into the receiver and the generator kept exactly $ENERGY FE"

echo "== AJ: a broken endergenic carries its store on its item =="
ctl command "execute in minecraft:the_end run setblock $SX 101 120 minecraft:air" >/dev/null
ctl wait 4 >/dev/null
give_ender 3000
place_held "$SX" 101 120 "$ENDER"
ender_state "$SX" 101 120
expect_ender_energy 3000
ctl command "gamemode survival" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 6 >/dev/null
break_block "$SX" 101 120 minecraft:iron_pickaxe
pick_up_item "$SX" 101 120 "$ENDER"
DROP_LINE=$(held_item_line_for "$ENDER")
[ -n "$DROP_LINE" ] || fail "no /data get reply for the picked-up endergenic: $(ctl messages 8 | jq -c '.chat')"
echo "  $DROP_LINE" >&2
DROP=$(python3 "$PORT/tools/parse_drop.py" "$DROP_LINE" 3000 "$ENDERGENIC_ENTITY") || true
eval "$DROP"
[ "${ok:-0}" = 1 ] || fail "the dropped endergenic does not carry 3,000 FE: $DROP_LINE"
echo "  the item carries $carried FE"
place_held "$SX" 101 120 "$ENDER"
ender_state "$SX" 101 120
[ "$ENERGY" -ge 3000 ] || fail "the placed-back generator holds $ENERGY FE, expected at least 3,000"
[ "$DEST" = none ] || fail "the store's item carried the link ($DEST) as well; upstream copies the store only"
echo "  placed back at $ENERGY FE, with no link carried over"

echo "== AK: both endergenic recipes need the parent's machine frame, so neither crafts here =="
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
for item in minecraft:diamond minecraft:ender_pearl minecraft:stone; do
    ctl command "give @s $item 16" >/dev/null
done
ctl wait 8 >/dev/null
TX=$((SX + 4)); TY=101; TZ=94
open_crafting_table "$TX" "$TY" "$TZ"
# "dod" / "ZFZ" / "dod": diamonds and ender pearls in the outer cells, stones where
# `rftoolsbase:infused_enderpearl` (Z) and `rftoolsbase:machine_frame` (F) belong.
for cell in 100 102 106 108; do place_one minecraft:diamond "$cell"; done
for cell in 101 107; do place_one minecraft:ender_pearl "$cell"; done
place_one "$STONE" 103
place_one "$STONE" 104
place_one "$STONE" 105
RESULT=$(ctl screen | jq -r '[.slots[]? | select(.slot == 200) | .item] | first // "empty"')
echo "  the endergenic recipe with stones where the parent's items belong: '$RESULT'" >&2
[ "$RESULT" = "empty" ] || fail "the endergenic recipe crafted $RESULT without the parent"
ctl close >/dev/null 2>&1 || true
ctl wait 4 >/dev/null
# " C " / "rFr" / " H " with a chest for C, a stone for the machine frame, and a hopper for H.
ctl command "clear @s" >/dev/null
for item in minecraft:chest minecraft:redstone minecraft:hopper minecraft:stone; do
    ctl command "give @s $item 4" >/dev/null
done
ctl wait 8 >/dev/null
ctl interact "$TX" "$TY" "$TZ" >/dev/null || fail "the crafting table did not take the second click"
ctl wait 6 >/dev/null
place_one minecraft:chest 101
place_one minecraft:redstone 103
place_one "$STONE" 104
place_one minecraft:redstone 105
place_one minecraft:hopper 107
RESULT=$(ctl screen | jq -r '[.slots[]? | select(.slot == 200) | .item] | first // "empty"')
echo "  the pearl injector's recipe with a stone where rftoolsbase:machine_frame belongs: '$RESULT'" >&2
[ "$RESULT" = "empty" ] || fail "the injector's recipe crafted $RESULT without the parent"
ctl close >/dev/null 2>&1 || true
ctl wait 4 >/dev/null
echo "  the machine frame is what both recipes need and RFToolsBase is not in this build"

echo "== AL: the enderlink command's refusals are parsed replies =="
ctl command "execute in minecraft:the_end run setblock $SX 101 105 minecraft:stone" >/dev/null
ctl wait 4 >/dev/null
say "rftoolspower enderlink $SX 101 94 $SX 101 105"
LINE=$(await_line "is not an endergenic generator")
[ -n "$LINE" ] || fail "no refusal for a stone destination: $(ctl messages 8 | jq -c '.chat')"
echo "  $LINE"
ctl command "execute in minecraft:the_end run setblock $SX 101 106 minecraft:air" >/dev/null
ctl wait 4 >/dev/null
give_ender
place_held "$SX" 101 106 "$ENDER"
say "rftoolspower enderlink $SX 101 94 $SX 101 106"
LINE=$(await_line "is too far")
[ -n "$LINE" ] || fail "no 'too far' refusal for a twelve-block link: $(ctl messages 8 | jq -c '.chat')"
echo "  $LINE"
say "rftoolspower enderlink $SX 101 105 $SX 101 94"
LINE=$(await_line "endergenic generator there")
[ -n "$LINE" ] || fail "no refusal for a source that is not a generator: $(ctl messages 8 | jq -c '.chat')"
echo "  $LINE"
echo "  12 blocks is a 5-tick flight, upstream's maximum is 4; a stone is not a generator either way"

# --- the ender monitor ---------------------------------------------------
# Upstream's `EnderMonitorTileEntity` (1.21-7.0.6): one of three modes decides which generator
# event it reports (`MODE_LOSTPEARL`, `MODE_PEARLFIRED`, `MODE_PEARLARRIVED`), and
# `fireFromEndergenic(mode)` arms `needPulse` only when the event is the mode it watches. The
# next tick puts 15 on its redstone output and clears it — one tick, no more. The generator's
# side is `fireMonitors`: the neighbour in `dir` answers when its `logic_facing` input side is
# `dir`, which in this port (whose `facing` is the display) means a monitor at generator+`dir`
# with `facing=dir`.
#
# The rig: source A at z=130 with its injector, destination B at z=133 (a 2-tick link), four
# monitors — `arrived` on B's east side with a lamp on its display face, `lost` on B's west,
# `arrived` on B's south but facing **north** (the wrong side: the display points at the
# generator), and `fired` on A's west.
ENDERMON=rftoolspower:ender_monitor
ENDER_MON_ENTITY=rftoolspower:ender_monitor_block_entity
LAMP=minecraft:redstone_lamp
ENDERMON_IN=$SCRATCH/endermonitor-samples.in
ENDERMON_SAMPLES=$SCRATCH/endermonitor-samples.txt
MONX=$((SX + 1)); MONY=101; MONZ=133      # the `arrived` monitor
LOSTX=$((SX - 1)); LOSTZ=133               # the `lost` monitor
WRONGZ=134                                 # the mis-facing `arrived` monitor
FIREDX=$((SX - 1)); FIREDZ=130             # the `fired` monitor
LAMPX=$((SX + 2)); LAMPZ=133

monitor_arena() {
    ctl command "execute in minecraft:the_end run tp @s $SX.5 101 130.5" >/dev/null
    ctl wait 40 >/dev/null
    local attempt
    for attempt in 1 2 3; do
        ctl command "execute in minecraft:the_end run fill $((SX - 6)) 100 126 $((SX + 8)) 100 140 minecraft:stone" >/dev/null
        ctl wait 6 >/dev/null
        [ "$(block_name "$SX" 100 136)" = "minecraft:stone" ] && break
        echo "  the monitor arena floor fill did not land (attempt $attempt); waiting" >&2
        ctl wait 40 >/dev/null
    done
    [ "$(block_name "$SX" 100 136)" = "minecraft:stone" ] || fail "the monitor arena floor is not stone"
    ctl command "execute in minecraft:the_end run fill $((SX - 6)) 101 126 $((SX + 8)) 108 140 minecraft:air" >/dev/null
    ctl wait 8 >/dev/null
    [ "$(block_name "$SX" 101 133)" = "minecraft:air" ] || fail "the monitor arena air fill did not land"
    ctl command "gamemode creative" >/dev/null
    ctl command "clear @s" >/dev/null
    ctl wait 4 >/dev/null
}

give_endermonitor() { # give_endermonitor [MODE] — an item, optionally carrying its mode
    ctl command "clear @s" >/dev/null
    if [ -n "${1:-}" ]; then
        ctl command "give @s $ENDERMON[minecraft:block_entity_data={id:\"$ENDER_MON_ENTITY\",mode:\"$1\"}]" >/dev/null
    else
        ctl command "give @s $ENDERMON" >/dev/null
    fi
    ctl wait 8 >/dev/null
}

# A monitor placed from its item (so `state_for_placement` runs), then its display face pinned:
# `ctl place`'s yaw is the game's, not the player's (the monitor phases found this).
place_endermonitor() { # X Y Z FACE
    local x=$1 y=$2 z=$3 face=$4 state dx=2
    # Approach from the side the display faces, so the block behind the target (the generator)
    # never shadows the floor the item is placed on.
    [ "$face" = west ] && dx=-2
    ctl command "execute in minecraft:the_end run setblock $x $y $z minecraft:air" >/dev/null
    ctl wait 4 >/dev/null
    ctl command "execute in minecraft:the_end run tp @s $((x + dx)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    ctl select "$ENDERMON" >/dev/null
    ctl wait 2 >/dev/null
    ctl look-at-block "$x" $((y - 1)) "$z" up >/dev/null \
        || fail "cannot aim at the floor under $x,$y,$z"
    place_block "$x" "$y" "$z" "$ENDERMON" \
        || fail "ctl place $ENDERMON at $x,$y,$z failed: $PLACE_REPLY"
    ctl wait 4 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$ENDERMON" ] || fail "the ender monitor is not at $x,$y,$z"
    state=$(ctl block "$x" "$y" "$z" | jq -r '.state')
    echo "  placed: $state" >&2
    case "$state" in
        *facing="$face"*) ;;
        *)
            ctl command "execute in minecraft:the_end run setblock $x $y $z $ENDERMON[facing=$face,lit=false]" >/dev/null
            ctl wait 4 >/dev/null
            state=$(ctl block "$x" "$y" "$z" | jq -r '.state')
            echo "  (the placement's facing was not $face; pinned to $state)" >&2
            ;;
    esac
    case "$state" in
        *facing="$face"*) ;;
        *) fail "the ender monitor's state is '$state', expected facing=$face" ;;
    esac
}

# The fresh `/rftoolspower endermonitor <pos> status <nonce>` line: the nonce is what proves it is
# this call's reply (a reply that arrives a few ticks late is still the *previous* call's line).
endermonitor_state() { # X Y Z
    local x=$1 y=$2 z=$3 line="" attempt want
    want=$(( ${NONCE:-0} + 1 ))
    NONCE=$want
    say "rftoolspower endermonitor $x $y $z status $want"
    for attempt in $(seq 1 12); do
        line=$(ctl messages 20 | jq -r '.chat[]' | grep -m1 "nonce=$want" || true)
        [ -n "$line" ] && break
        ctl wait 5 >/dev/null
    done
    [ -n "$line" ] || fail "no fresh /rftoolspower endermonitor reply for $x,$y,$z (nonce $want): $(ctl messages 12 | jq -c '.chat')"
    eval "$(python3 "$PORT/tools/parse_endermonitor.py" "$line")"
    [ "${ok:-0}" = 1 ] || fail "the ender monitor line did not parse: $line"
    [ "${NONCE:-}" = "$want" ] || fail "the reply's nonce is '${NONCE:-none}', sent $want: $line"
    echo "  $line" >&2
    echo "  parsed: mode=$MODE facing=$FACING pulses=$PULSES last=$LAST needpulse=$NEEDPULSE out=$OUT" >&2
}

set_monitor_mode() { # X Y Z lost|fired|arrived
    local line="" attempt
    NONCE=$(( ${NONCE:-0} + 1 ))
    say "rftoolspower endermonitor $1 $2 $3 $4 $NONCE"
    for attempt in $(seq 1 12); do
        line=$(ctl messages 20 | jq -r '.chat[]' | grep -m1 "nonce=$NONCE" || true)
        [ -n "$line" ] && break
        ctl wait 5 >/dev/null
    done
    [ -n "$line" ] || fail "no fresh mode reply for $1,$2,$3 $4 (nonce $NONCE): $(ctl messages 12 | jq -c '.chat')"
    echo "  $line" >&2
}

expect_monitor_mode() { [ "$MODE" = "$1" ] || fail "the monitor's mode is $MODE, expected $1"; }
expect_monitor_pulses() {
    [ "$PULSES" = "$1" ] || fail "the monitor has pulsed $PULSES times, expected $1"
}

# One pulse of the rig with the game frozen, so one sample is exactly one server tick.
#
# With the game running, a `ctl block` round trip costs about half a tick and `wait 1` adds a whole
# one, so a one-tick window falls between two samples: the first attempt sampled the monitor every
# other tick and read `lit=false` 24 times, while the lamp beside it (vanilla's lamp keeps its light
# for 4 ticks after the power goes) still showed the pulse. Here every `tick step 1` is awaited
# (`Stepping 1 tick(s)`), and the `block` read between two steps sees that tick's state, so the 16
# samples are 16 consecutive server ticks and a one-tick pulse is exactly one `lit=true`. The
# `state` reply's `ticks` field is the client's clock (it keeps running while the server is frozen:
# the samples' labels are ~2 apart and are not the server tick), so it is only a cross-check.
sample_pulse() { # X Y Z BLOCK
    ctl command "tick freeze" >/dev/null
    {
        echo "command execute in minecraft:the_end run fill $SX 102 130 $((SX + 1)) 102 133 minecraft:redstone_block"
        for _ in $(seq 1 16); do
            echo "command tick step 1"
            echo "state"
            echo "block $1 $2 $3"
        done
        echo "command execute in minecraft:the_end run fill $SX 102 130 $((SX + 1)) 102 133 minecraft:air"
        echo "command tick unfreeze"
    } > "$ENDERMON_IN"
    ctl script "$ENDERMON_IN" > "$ENDERMON_SAMPLES" 2>&1 || true
    ctl command "tick unfreeze" >/dev/null 2>&1 || true
    eval "$(python3 "$PORT/tools/parse_pulse_samples.py" "$ENDERMON_SAMPLES" "$4")"
    echo "  samples of $4 at $1,$2,$3: '$PULSE_SEQUENCE' ($PULSE_LIT read lit of $PULSE_SAMPLES, over ticks $PULSE_TICKS)" >&2
    [ "$PULSE_SAMPLES" -ge 12 ] || fail "only $PULSE_SAMPLES samples of $4 came back; the frozen sampling did not run"
}

echo "== AN: the ender monitors stand on the generators' sides and read their modes =="
monitor_arena
give_injector
place_injector "$((SX + 1))" 101 130 east
give_ender
place_held "$SX" 101 130 "$ENDER"
# A seeded destination: a pearl's hold costs 500 FE a tick, and a destination that cannot pay drops
# it — which is itself a `lost` event. The differential below needs an arrival with *no* loss, so
# every shot starts from a destination refilled with 100,000 FE.
reset_destination() { # [ENERGY]
    ctl command "execute in minecraft:the_end run setblock $SX 101 133 minecraft:air" >/dev/null
    ctl wait 4 >/dev/null
    give_ender "${1:-}"
    place_held "$SX" 101 133 "$ENDER"
}
reset_destination 100000
link "$SX" 101 130 "$SX" 101 133
give_endermonitor
place_endermonitor "$MONX" "$MONY" "$MONZ" east
give_endermonitor
place_endermonitor "$SX" 101 "$WRONGZ" north
# The source's monitor is placed from an item that carries its mode (upstream's mode rides on the
# block's item), so no command is needed to configure it.
give_endermonitor MODE_PEARLFIRED
place_endermonitor "$FIREDX" 101 "$FIREDZ" west
ctl command "execute in minecraft:the_end run setblock $LAMPX 101 $LAMPZ $LAMP" >/dev/null
ctl wait 6 >/dev/null
[ "$(block_name "$LAMPX" 101 "$LAMPZ")" = "$LAMP" ] || fail "the lamp did not place beside the monitor"
endermonitor_state "$MONX" "$MONY" "$MONZ"
expect_monitor_mode lost
[ "$LAST" = none ] || fail "a fresh monitor's last mode is $LAST, expected none"
expect_monitor_pulses 0
[ "$OUT" = 0 ] || fail "a fresh monitor answers out=$OUT, expected 0"
[ "$NEEDPULSE" = false ] || fail "a fresh monitor owes a pulse"
case "$(ctl block "$MONX" "$MONY" "$MONZ" | jq -r '.state')" in
    *lit=false*) ;;
    *) fail "a fresh monitor's state is not lit=false" ;;
esac
set_monitor_mode "$MONX" "$MONY" "$MONZ" arrived
endermonitor_state "$MONX" "$MONY" "$MONZ"
expect_monitor_mode arrived
[ "$FACING" = east ] || fail "the monitor faces '$FACING', expected its display east"
set_monitor_mode "$SX" 101 "$WRONGZ" arrived
endermonitor_state "$SX" 101 "$WRONGZ"
expect_monitor_mode arrived
[ "$FACING" = north ] || fail "the mis-facing monitor reads facing=$FACING, expected north"
endermonitor_state "$FIREDX" 101 "$FIREDZ"
expect_monitor_mode fired
echo "  three monitors: arrived on B's east (with a lamp on its display face), arrived on B's south facing the generator, fired on A's west (from its item's mode, no command)"
# The other direction: a broken configured monitor keeps its mode on the item, and placing it
# restores it. The counters are the readout's and stay on the block, so the placed one starts at 0.
ctl command "gamemode survival" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 6 >/dev/null
break_block "$FIREDX" 101 "$FIREDZ" minecraft:iron_pickaxe
pick_up_item "$FIREDX" 101 "$FIREDZ" "$ENDERMON"
DROP_LINE=$(held_item_line_for "$ENDERMON")
[ -n "$DROP_LINE" ] || fail "no /data get reply for the picked-up ender monitor: $(ctl messages 8 | jq -c '.chat')"
echo "  $DROP_LINE" >&2
case "$DROP_LINE" in
    *"id: \"$ENDER_MON_ENTITY\""*) ;;
    *) fail "the dropped ender monitor does not name its block entity type: $DROP_LINE" ;;
esac
case "$DROP_LINE" in
    *"mode: \"MODE_PEARLFIRED\""*) ;;
    *) fail "the dropped ender monitor does not carry its mode: $DROP_LINE" ;;
esac
# `place_endermonitor` re-places the item this player picked up and pins the display face (the
# placement context's yaw is the game's, not the harness's — the same trap as the first placement).
place_endermonitor "$FIREDX" 101 "$FIREDZ" west
endermonitor_state "$FIREDX" 101 "$FIREDZ"
expect_monitor_mode fired
expect_monitor_pulses 0
[ "$LAST" = none ] || fail "the placed monitor's last mode is $LAST, expected none (the counters stay on the block)"
echo "  the broken monitor's item carries id=$ENDER_MON_ENTITY mode=MODE_PEARLFIRED; placed back it watches 'fired' with 0 pulses"
ctl command "gamemode creative" >/dev/null
ctl wait 4 >/dev/null

echo "== AO: an arrival pulses the arrived monitor for exactly one tick =="
pearl_into_injector "$((SX + 1))" 101 130
sample_pulse "$MONX" "$MONY" "$MONZ" "$ENDERMON"
if [ "${SELFTEST_ENDERMON:-0}" = 1 ]; then
    echo "(selftest: asserting the monitor never lit)"
    [ "$PULSE_LIT" = 0 ] || fail "selftest: the monitor lit for $PULSE_LIT sample(s), so the one-tick assertion is alive"
fi
[ "$PULSE_TICK_LIT" = 1 ] \
    || fail "the monitor's lit state was true in $PULSE_TICK_LIT game ticks of the pulse's window, expected exactly 1 ('$PULSE_SEQUENCE' over ticks $PULSE_TICKS)"
case "$PULSE_SEQUENCE" in
    *0) ;;
    *) fail "the monitor was still lit at the end of the window: '$PULSE_SEQUENCE'" ;;
esac
endermonitor_state "$MONX" "$MONY" "$MONZ"
expect_monitor_mode arrived
expect_monitor_pulses 1
[ "$LAST" = arrived ] || fail "the monitor's last mode is $LAST, expected arrived"
[ "$NEEDPULSE" = false ] || fail "the monitor still owes a pulse after it fired"
[ "$OUT" = 0 ] || fail "the monitor still answers out=$OUT after the pulse"
case "$(ctl block "$MONX" "$MONY" "$MONZ" | jq -r '.state')" in
    *lit=false*) ;;
    *) fail "the monitor's state is still lit after the pulse" ;;
esac
endermonitor_state "$FIREDX" 101 "$FIREDZ"
expect_monitor_mode fired
expect_monitor_pulses 1
[ "$LAST" = fired ] || fail "the source monitor's last mode is $LAST, expected fired"
endermonitor_state "$SX" 101 "$WRONGZ"
expect_monitor_pulses 0
ender_state "$SX" 101 133
[ "$GAINED" -gt 0 ] || fail "the destination paid nothing, so the shot did not land"
[ "$ARRIVED" -ge 1 ] || fail "the destination did not record the arrival (arrived=$ARRIVED)"
# A landed pearl is held and can be lost to upstream's 0.6 %-a-tick chance before this read; that is
# a later event, not a failed landing, so the loss counter is allowed to be 1 with that reason.
case "$REASON" in
    none | "Random pearl discard") ;;
    *) fail "the destination records a loss it should not have ('$REASON')" ;;
esac
echo "  the arrival lit the monitor for exactly one sampled tick, the source's fired monitor pulsed with it, the mis-facing one never did, and the destination gained $GAINED FE (dropped=$DROPPED, reason=$REASON)"
# The same shot again, this time sampling the lamp on the display face: the monitor's 15 is a real
# redstone output, not only a block state.
reset_destination 100000
pearl_into_injector "$((SX + 1))" 101 130
sample_pulse "$LAMPX" 101 "$LAMPZ" "$LAMP"
[ "$PULSE_LIT" -ge 1 ] \
    || fail "the lamp on the monitor's display face never lit ('$PULSE_SEQUENCE')"
case "$PULSE_SEQUENCE" in
    *0) ;;
    *) fail "the lamp was still lit at the end of the window: '$PULSE_SEQUENCE'" ;;
esac
[ "$(block_lit "$LAMPX" 101 "$LAMPZ")" = false ] || fail "the lamp is still lit after the pulse"
endermonitor_state "$MONX" "$MONY" "$MONZ"
expect_monitor_pulses 2
endermonitor_state "$FIREDX" 101 "$FIREDZ"
expect_monitor_pulses 2
echo "  the second shot lit the lamp on the display face and went dark again"

echo "== AP: the same shot does not pulse a monitor watching another mode =="
set_monitor_mode "$MONX" "$MONY" "$MONZ" lost
endermonitor_state "$MONX" "$MONY" "$MONZ"
MON_BEFORE=$PULSES
endermonitor_state "$FIREDX" 101 "$FIREDZ"
FIRED_BEFORE=$PULSES
# A lit sample on a `lost` monitor is legal only when one event can fire it: upstream's random
# pearl discard (0.6 % a tick while a landed pearl is held). That event is named by the drop
# reason, so an attempt where it fired is inconclusive, not a failure — retried. An arrival that
# lit it is the defect under test and fails at once.
ATTEMPT=0
INCONCLUSIVE=0
while :; do
    ATTEMPT=$((ATTEMPT + 1))
    reset_destination 100000
    pearl_into_injector "$((SX + 1))" 101 130
    sample_pulse "$MONX" "$MONY" "$MONZ" "$ENDERMON"
    if [ "$PULSE_LIT" = 0 ]; then
        break
    fi
    ender_state "$SX" 101 133
    if [ "$DROPPED" -ge 1 ] && [ "$REASON" = "Random pearl discard" ]; then
        INCONCLUSIVE=$((INCONCLUSIVE + 1))
        echo "  attempt $ATTEMPT: upstream's random discard fired the lost monitor ('$PULSE_SEQUENCE'); retrying ($INCONCLUSIVE inconclusive)" >&2
        [ "$INCONCLUSIVE" -lt 3 ] || fail "three attempts all lost the landed pearl to the random discard; the mode gate was never sampled"
        continue
    fi
    fail "a monitor set to 'lost' lit for $PULSE_LIT sample(s) on an arrival ('$PULSE_SEQUENCE', reason=$REASON)"
done
[ "$(block_lit "$LAMPX" 101 "$LAMPZ")" = false ] \
    || fail "the lamp lit on a monitor watching another mode"
ender_state "$SX" 101 133
[ "$GAINED" -gt 0 ] || fail "the differential's shot did not land"
[ "$ARRIVED" -ge 1 ] || fail "the differential's arrival was not recorded (arrived=$ARRIVED)"
case "$REASON" in
    none | "Random pearl discard") ;;
    *) fail "the differential's shot records a loss it should not have ('$REASON')" ;;
esac
# One shot per attempt; the source's fired monitor proves each attempt really fired a pearl.
endermonitor_state "$FIREDX" 101 "$FIREDZ"
expect_monitor_pulses "$((FIRED_BEFORE + ATTEMPT))"
endermonitor_state "$MONX" "$MONY" "$MONZ"
expect_monitor_mode lost
# The landing pays into the destination and the pearl is then held, so a discard can add a `lost`
# pulse after a window too. Which event the counter names is what matters: `arrived` means nothing
# was noticed (so the count did not move), `lost` means a discard was (at most one per attempt).
PULSES_AFTER_AP=$PULSES
if [ "$LAST" = arrived ]; then
    [ "$PULSES_AFTER_AP" = "$MON_BEFORE" ] \
        || fail "the lost-mode monitor moved from $MON_BEFORE to $PULSES_AFTER_AP pulses but names 'arrived'"
else
    [ "$LAST" = lost ] || fail "the lost-mode monitor's last mode is $LAST"
    [ "$PULSES_AFTER_AP" -gt "$MON_BEFORE" ] && [ "$PULSES_AFTER_AP" -le "$((MON_BEFORE + ATTEMPT))" ] \
        || fail "after $ATTEMPT landing(s) the lost-mode monitor reads $PULSES_AFTER_AP pulses, expected $MON_BEFORE..$((MON_BEFORE + ATTEMPT)) with last=lost"
fi
echo "  mode=lost: $ATTEMPT shot(s) left the monitor silent (lit never set over $PULSE_SAMPLES samples; pulses $MON_BEFORE -> $PULSES_AFTER_AP, last=$LAST), while every shot still landed and the source's fired monitor recorded $ATTEMPT more"

echo "== AQ: a pearl lost at an idle destination pulses both arrived and lost =="
# Reset the destination first: the previous shot left a pearl in its hold, and a random discard of
# that pearl would pulse the `lost` monitor below before this phase's shot does.
reset_destination
endermonitor_state "$MONX" "$MONY" "$MONZ"
BASE_PULSES=$PULSES
[ "$BASE_PULSES" -ge 2 ] \
    || fail "the arrived monitor reads $BASE_PULSES pulses before the miss, expected at least the two arrivals"
give_endermonitor
place_endermonitor "$LOSTX" 101 "$LOSTZ" west
set_monitor_mode "$LOSTX" 101 "$LOSTZ" lost
set_monitor_mode "$MONX" "$MONY" "$MONZ" arrived
endermonitor_state "$MONX" "$MONY" "$MONZ"
expect_monitor_pulses "$BASE_PULSES"
pearl_into_injector "$((SX + 1))" 101 130
# Only the injector is pulsed: the destination stays idle, so the pearl has nowhere to land.
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 102 130 minecraft:redstone_block" >/dev/null
ctl wait 3 >/dev/null
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 102 130 minecraft:air" >/dev/null
ctl wait 24 >/dev/null
ender_state "$SX" 101 133
[ "$DROPPED" = 1 ] || fail "the destination dropped $DROPPED pearls, expected the one it lost"
[ "$REASON" = "Pearl arrived while idle" ] || fail "the drop reason is '$REASON', expected 'Pearl arrived while idle'"
endermonitor_state "$MONX" "$MONY" "$MONZ"
expect_monitor_pulses "$((BASE_PULSES + 1))"
MISS_PULSES=$PULSES
[ "$LAST" = arrived ] || fail "the arrived monitor's last mode is $LAST after the miss"
endermonitor_state "$LOSTX" 101 "$LOSTZ"
expect_monitor_pulses 1
[ "$LAST" = lost ] || fail "the lost monitor's last mode is $LAST, expected lost"
endermonitor_state "$FIREDX" 101 "$FIREDZ"
expect_monitor_pulses "$((FIRED_BEFORE + ATTEMPT + 1))"
endermonitor_state "$SX" 101 "$WRONGZ"
expect_monitor_pulses 0
echo "  the miss pulsed the arrived monitor ($BASE_PULSES -> $MISS_PULSES) and the lost monitor (1); the mis-facing one stayed at 0"

echo "== AR: the endermonitor command's refusals are parsed replies =="
ctl command "execute in minecraft:the_end run setblock $SX 101 138 minecraft:stone" >/dev/null
ctl wait 4 >/dev/null
say "rftoolspower endermonitor $SX 101 138 lost"
LINE=$(await_line "ender monitor there")
[ -n "$LINE" ] || fail "no refusal for a position with no monitor: $(ctl messages 8 | jq -c '.chat')"
echo "  $LINE"
say "rftoolspower endermonitor $MONX $MONY $MONZ wrong"
LINE=$(await_line "unknown mode 'wrong'")
[ -n "$LINE" ] || fail "no refusal for an unknown mode: $(ctl messages 8 | jq -c '.chat')"
echo "  $LINE"
endermonitor_state "$MONX" "$MONY" "$MONZ"
expect_monitor_mode arrived
expect_monitor_pulses "$((BASE_PULSES + 1))"
echo "  a stone position and an unknown mode are refused, and the monitor's mode did not change"

echo "== AS: the ender monitor's recipe needs the parent's machine base, so it crafts nothing =="
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
for item in minecraft:ender_pearl minecraft:redstone minecraft:redstone_torch minecraft:stone; do
    ctl command "give @s $item 16" >/dev/null
done
ctl wait 8 >/dev/null
TX2=$((SX + 4)); TY2=101; TZ2=130
open_crafting_table "$TX2" "$TY2" "$TZ2"
# " o " / "rAr" / "TrT": an ender pearl up, redstone beside the centre, redstone torches below,
# and a stone where `rftoolsbase:machine_base` belongs.
place_one minecraft:ender_pearl 101
place_one minecraft:redstone 103
place_one "$STONE" 104
place_one minecraft:redstone 105
place_one minecraft:redstone_torch 106
place_one minecraft:redstone 107
place_one minecraft:redstone_torch 108
RESULT=$(ctl screen | jq -r '[.slots[]? | select(.slot == 200) | .item] | first // "empty"')
echo "  the ender monitor's recipe with a stone where rftoolsbase:machine_base belongs: '$RESULT'" >&2
[ "$RESULT" = "empty" ] || fail "the ender monitor's recipe crafted $RESULT without the parent"
ctl close >/dev/null 2>&1 || true
ctl wait 4 >/dev/null
echo "  the machine base is what the monitor's recipe needs and RFToolsBase is not in this build"

echo "== AM: the store and the link survive save + relaunch =="
ctl save >/dev/null
ctl wait 10 >/dev/null
ender_state "$SX" 101 97
SAVED_ENERGY=$ENERGY
SAVED_ARRIVED=$ARRIVED
ctl quit >/dev/null 2>&1 || true
sleep 2
launch
ctl command "execute in minecraft:the_end run tp @s $((SX - 2)).5 101 97.5" >/dev/null
ctl wait 40 >/dev/null
[ "$(block_name "$SX" 101 97)" = "$ENDER" ] || fail "the endergenic did not survive the relaunch"
ender_state "$SX" 101 97
[ "$ENERGY" = "$SAVED_ENERGY" ] || fail "after the relaunch the store is $ENERGY, was $SAVED_ENERGY"
[ "$ARRIVED" = "$SAVED_ARRIVED" ] || fail "after the relaunch the arrival mode is $ARRIVED, was $SAVED_ARRIVED"
KEPT_ENERGY=$ENERGY
KEPT_ARRIVED=$ARRIVED
ender_state "$SX" 101 94
[ "$DEST" = "$SX,101,97" ] || fail "after the relaunch the source's link is $DEST, expected $SX,101,97"
echo "  after save + relaunch: B holds $KEPT_ENERGY FE (its mode-$KEPT_ARRIVED arrival) and A still links to B"
# The ender monitors keep the mode they were set to and the pulses they gave.
[ "$(block_name "$MONX" "$MONY" "$MONZ")" = "$ENDERMON" ] || fail "the ender monitor did not survive the relaunch"
endermonitor_state "$MONX" "$MONY" "$MONZ"
expect_monitor_mode arrived
expect_monitor_pulses "$((BASE_PULSES + 1))"
[ "$LAST" = arrived ] || fail "after the relaunch the monitor's last mode is $LAST, expected arrived"
endermonitor_state "$LOSTX" 101 "$LOSTZ"
expect_monitor_mode lost
expect_monitor_pulses 1
echo "  after save + relaunch: the arrived monitor still watches 'arrived' with $((BASE_PULSES + 1)) pulses, the lost one 'lost' with 1"

echo "== AT: a power level on a 250,000 FE generator gives 5 on its display face =="
# A clear band in the monitor arena (its floor spans z 126..140); the earlier phases left blocks
# at z 130..138, so clear the strip this rig uses first.
ctl command "execute in minecraft:the_end run tp @s $((SX + 1)).5 101 136.5" >/dev/null
ctl wait 20 >/dev/null
ctl command "execute in minecraft:the_end run fill $((SX - 2)) 101 135 $((SX + 4)) 108 139 minecraft:air" >/dev/null
ctl wait 6 >/dev/null
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 4 >/dev/null
ctl command "give @s $BLOCK[minecraft:block_entity_data={id:\"rftoolspower:coalgenerator_block_entity\",burn:0,burn_max:0,energy:250000}]" >/dev/null
ctl wait 8 >/dev/null
place_kept "$SX" 101 136
info "$SX" 101 136
expect_energy 250000
place_powerlevel "$((SX + 1))" 101 136 east
aim_powerlevel "$((SX + 1))" 101 136 east
ctl command "execute in minecraft:the_end run setblock $((SX + 2)) 101 136 $DUST" >/dev/null
# The wrong face: a wire on the block's north side, which is not the display.
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 135 $DUST" >/dev/null
ctl wait 40 >/dev/null
powerlevel "$((SX + 1))" 101 136
expect_power 5
[ "$FACING" = east ] || fail "the power level faces '$FACING', expected its display east"
[ "$TARGET" = "$BLOCK" ] || fail "the power level reads target=$TARGET, expected $BLOCK"
expect_stored 250000
[ "$MAXE" = "$CAPACITY" ] || fail "the power level reads capacity $MAXE, expected $CAPACITY"
PSTATE=$(ctl block "$((SX + 1))" 101 136 | jq -r '.state')
case "$PSTATE" in
    *power=5*) ;;
    *) fail "the power level's state does not mirror power=5: $PSTATE" ;;
esac
DISPLAY_POWER=$(dust_power "$((SX + 2))" 101 136)
WRONG_POWER=$(dust_power "$((SX + 1))" 101 135)
echo "  display wire: $(ctl block "$((SX + 2))" 101 136 | jq -c '{block,state}')" >&2
echo "  north wire:   $(ctl block "$((SX + 1))" 101 135 | jq -c '{block,state}')" >&2
if [ "$SELFTEST_POWERLEVEL" = 1 ]; then
    echo "(selftest: asserting the brief's mistaken 4, so the assertion is alive)"
    [ "$DISPLAY_POWER" = 4 ] \
        || fail "selftest: the power level reads $DISPLAY_POWER at 250,000/500,000, not the 4 the inversion expects, so the assertion is alive"
fi
[ "$DISPLAY_POWER" = 5 ] \
    || fail "the redstone wire on the display face reads power=$DISPLAY_POWER, expected 5 (state $(ctl block "$((SX + 2))" 101 136 | jq -r '.state'))"
[ "$WRONG_POWER" = 0 ] \
    || fail "the wire on the power level's north face reads power=$WRONG_POWER, expected 0 (state $(ctl block "$((SX + 1))" 101 135 | jq -r '.state'))"
echo "  250,000/500,000 FE: the display face's wire reads power=5, the mirror says power=5, and the wire on another face reads 0"

echo "== AU: an empty generator reads 0 (the differential for AT) =="
ctl command "clear @s" >/dev/null
ctl wait 4 >/dev/null
place_generator "$SX" 101 138
info "$SX" 101 138
expect_energy 0
place_powerlevel "$((SX + 1))" 101 138 east
aim_powerlevel "$((SX + 1))" 101 138 east
ctl command "execute in minecraft:the_end run setblock $((SX + 2)) 101 138 $DUST" >/dev/null
ctl wait 40 >/dev/null
powerlevel "$((SX + 1))" 101 138
expect_power 0
expect_stored 0
EMPTY_POWER=$(dust_power "$((SX + 2))" 101 138)
echo "  empty display wire: $(ctl block "$((SX + 2))" 101 138 | jq -c '{block,state}')" >&2
[ "$EMPTY_POWER" = 0 ] || fail "the display wire on an empty generator reads power=$EMPTY_POWER, expected 0"
echo "  0/500,000 FE: power=0 on the readout and on the display face's wire — the signal follows the store"

echo "== AV: a full generator reads 9, not 10 =="
ctl command "clear @s" >/dev/null
ctl command "give @s $BLOCK[minecraft:block_entity_data={id:\"rftoolspower:coalgenerator_block_entity\",burn:0,burn_max:0,energy:500000}]" >/dev/null
ctl wait 8 >/dev/null
place_kept "$SX" 101 139
info "$SX" 101 139
expect_energy 500000
place_powerlevel "$((SX + 1))" 101 139 east
aim_powerlevel "$((SX + 1))" 101 139 east
ctl command "execute in minecraft:the_end run setblock $((SX + 2)) 101 139 $DUST" >/dev/null
ctl wait 40 >/dev/null
powerlevel "$((SX + 1))" 101 139
expect_power 9
FULL_POWER=$(dust_power "$((SX + 2))" 101 139)
echo "  full display wire: $(ctl block "$((SX + 2))" 101 139 | jq -c '{block,state}')" >&2
[ "$FULL_POWER" = 9 ] || fail "the display wire on a full generator reads power=$FULL_POWER, expected 9 (the ratio clamps to 9)"
echo "  500,000/500,000 FE: the ratio 10 clamps to 9 on the readout and on the display face's wire"

echo "== AW: the powerlevel refusal and the recipe's parent are parsed =="
ctl command "execute in minecraft:the_end run setblock $SX 101 141 minecraft:stone" >/dev/null
ctl wait 4 >/dev/null
say "rftoolspower powerlevel $SX 101 141"
LINE=$(await_line "power level there")
[ -n "$LINE" ] || fail "no refusal for a position with no power level: $(ctl messages 8 | jq -c '.chat')"
echo "  $LINE"
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
for item in minecraft:glass_pane minecraft:redstone minecraft:redstone_block minecraft:stone; do
    ctl command "give @s $item 16" >/dev/null
done
ctl wait 8 >/dev/null
TX2=$((SX + 4)); TY2=101; TZ2=136
open_crafting_table "$TX2" "$TY2" "$TZ2"
# " P " / "rAr" / " R ": a glass pane up, redstone beside the centre, a stone where
# `rftoolsbase:machine_base` belongs, and a redstone block below.
place_one minecraft:glass_pane 101
place_one minecraft:redstone 103
place_one "$STONE" 104
place_one minecraft:redstone 105
place_one minecraft:redstone_block 107
RESULT=$(ctl screen | jq -r '[.slots[]? | select(.slot == 200) | .item] | first // "empty"')
echo "  the power level's recipe with a stone where rftoolsbase:machine_base belongs: '$RESULT'" >&2
[ "$RESULT" = "empty" ] || fail "the power level's recipe crafted $RESULT without the parent"
ctl close >/dev/null 2>&1 || true
ctl wait 4 >/dev/null
echo "  a stone position and the missing parent are the recipe's limit here (RFToolsBase is not in this build)"

echo "PASS: a power level is a 0..9 redstone reading of the block it faces — at 250,000 of 500,000 FE its display face's wire read power=5 (stored * 10 / capacity, not the brief's 4), at 0 FE it read 0, at a full store it clamped to 9, the mirror state and the readout agreed, and a wire on another face stayed 0; the powerlevel refusal and the recipe's missing parent are parsed. Earlier: an ender monitor is a one-tick redstone pulse for the one generator event its mode names — the pearl's arrival lit its display face's output and a lamp beside it for exactly one sampled tick and cleared, the same shot left it silent once its mode was set to 'lost', a pearl lost at an idle destination pulsed both the 'arrived' and the 'lost' monitors, a monitor whose display points at the generator never pulsed, the modes and counters survive a relaunch, the endermonitor refusals parse, and its recipe needs the parent's machine base. Earlier: the endergenic pair fires a pearl across a 2-tick link and the destination pays rfPerHit[mode] x 2 when it lands inside the 15-tick charging window and nothing when it lands at idle; a charge with no injector makes no FE; the generator pushes all but its 2,000 FE reserve; a broken endergenic carries its store; both endergenic recipes need the parent machine frame; the enderlink refusals parse; the store and the link survive a relaunch. Earlier: a fresh cell1 is empty with six NONE faces; against a 100,000 FE generator it refuses the push until its west face is set INPUT, then takes exactly 250 FE a tick (tier1MaxRFPerTick) until the generator is empty, with the two stores adding up to the 100,000 seeded; a second cell1 beside it shares one network (3,000/1,000,000 in both), and a cell with a gap does not; a cell2 beside a cell1 joins the same network (5,000/4,500,000) while one with a gap stays alone (4,000,000) — the network is adjacency, not tier; an OUTPUT face pushes 250 FE a tick into a neighbour with nothing created or lost; the store and the face modes survive save and relaunch; a broken cell carries its own store and placing it gives it back; the power core's recipe crafts once and consumes its diamond, redstone block and three redstones, while cell1's recipe crafts nothing without the parent's machine frame; and the side command's bad face, bad mode and no-cell refusals parse as replies"
