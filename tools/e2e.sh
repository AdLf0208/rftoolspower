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
#
# SELFTEST=1 inverts phase V (the cell's NONE face must have taken the generator's FE) and exits
# non-zero, proving the face-mode assertion can fail; SELFTEST_MONITOR=1 keeps slice 2's inversion
# of O; SELFTEST_GENERATOR=1 keeps slice 1's inversion of C.
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
ctl setblock "$TX" "$TY" "$TZ" minecraft:air >/dev/null
ctl setblock "$TX" "$TY" "$TZ" minecraft:crafting_table >/dev/null
ctl wait 2 >/dev/null
ctl command "execute in minecraft:the_end run tp @s $((TX - 1)).5 $TY $((TZ)).5" >/dev/null
ctl wait 4 >/dev/null
ctl interact "$TX" "$TY" "$TZ" >/dev/null || fail "the crafting table did not take the click"
ctl wait 6 >/dev/null
GRID=$(ctl screen | jq '[.slots[]? | select(.slot >= 100)] | length')
[ "$GRID" = 10 ] || fail "the crafting table did not open its grid ($GRID grid slots)"
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
ctl setblock "$TX" "$TY" "$TZ" minecraft:air >/dev/null
ctl setblock "$TX" "$TY" "$TZ" minecraft:crafting_table >/dev/null
ctl wait 2 >/dev/null
ctl command "execute in minecraft:the_end run tp @s $((TX - 1)).5 $TY $((TZ)).5" >/dev/null
ctl wait 4 >/dev/null
ctl interact "$TX" "$TY" "$TZ" >/dev/null || fail "the crafting table did not take the click"
ctl wait 6 >/dev/null
GRID=$(ctl screen | jq '[.slots[]? | select(.slot >= 100)] | length')
[ "$GRID" = 10 ] || fail "the crafting table did not open its grid ($GRID grid slots)"
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
ctl setblock "$TX" "$TY" "$TZ" minecraft:air >/dev/null
ctl setblock "$TX" "$TY" "$TZ" minecraft:crafting_table >/dev/null
ctl wait 2 >/dev/null
ctl command "execute in minecraft:the_end run tp @s $((TX - 1)).5 $TY $((TZ)).5" >/dev/null
ctl wait 4 >/dev/null
ctl interact "$TX" "$TY" "$TZ" >/dev/null || fail "the crafting table did not take the click"
ctl wait 6 >/dev/null
GRID=$(ctl screen | jq '[.slots[]? | select(.slot >= 100)] | length')
[ "$GRID" = 10 ] || fail "the crafting table did not open its grid ($GRID grid slots)"
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

echo "PASS: a fresh cell1 is empty with six NONE faces; against a 100,000 FE generator it refuses the push until its west face is set INPUT, then takes exactly 250 FE a tick (tier1MaxRFPerTick) until the generator is empty, with the two stores adding up to the 100,000 seeded; a second cell1 beside it shares one network (3,000/1,000,000 in both), and a cell with a gap does not; a cell2 beside a cell1 joins the same network (5,000/4,500,000) while one with a gap stays alone (4,000,000) — the network is adjacency, not tier; an OUTPUT face pushes 250 FE a tick into a neighbour with nothing created or lost; the store and the face modes survive save and relaunch; a broken cell carries its own store and placing it gives it back; the power core's recipe crafts once and consumes its diamond, redstone block and three redstones, while cell1's recipe crafts nothing without the parent's machine frame; and the side command's bad face, bad mode and no-cell refusals parse as replies"
