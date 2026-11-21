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
#
# SELFTEST=1 flips C (the generator must make no FE while burning) and exits non-zero, proving
# the assertion can fail.
# CONTROL=1 runs phase A on the Nightly WITHOUT this package (CONTROL_GAME, exported by
# launcher-game.sh): the generator item does not exist, so A fails and the log says why.
set -Eeuo pipefail
export LC_ALL=C

CLONE=/home/adlf/Desktop/all_the_mods_10_rust_rewrite
PORT=$CLONE/ports/rftoolspower
CTL=${CTL:-}
GAME=${GAME:-}
RES=${RES:-${HORIZON_RES:-/home/adlf/Desktop/horizon/.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/rftoolspower-e2e.sock}
SELFTEST=${SELFTEST:-0}
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

SCRATCH=$(mktemp -d /tmp/opencode/rftoolspower-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")" "$XDG_CONFIG_HOME"
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
    ctl command "execute in minecraft:the_end run fill $((X0 - 4)) 100 -24 $((X0 + 6)) 100 24 minecraft:stone" >/dev/null
    ctl wait 6 >/dev/null
    ctl command "execute in minecraft:the_end run fill $((X0 - 4)) 101 -24 $((X0 + 6)) 108 24 minecraft:air" >/dev/null
    ctl wait 6 >/dev/null
    ctl command "execute in minecraft:the_end run kill @e[type=!player]" >/dev/null
    ctl command "execute in minecraft:the_end run tp @s $X0.5 101 0.5" >/dev/null
    ctl wait 20
    [ "$(block_name "$X0" 100 0)" = "minecraft:stone" ] || fail "the arena floor is not stone"
    [ "$(block_name "$X0" 101 0)" = "minecraft:air" ] || fail "the arena air above the floor is not air"
}

# `/rftoolspower info X Y Z`: the line, then the parsed fields.
NONCE_TAG=""
info() { # info X Y Z
    NONCE=$(( ${NONCE:-0} + 1 ))
    NONCE_TAG=$NONCE
    local line
    say "rftoolspower info $1 $2 $3 $NONCE"
    ctl wait 12 >/dev/null
    line=$(ctl messages 20 | jq -r '.chat[]' | grep -m1 "nonce=$NONCE)" || true)
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

place_generator() { # place_generator X Y Z
    local x=$1 y=$2 z=$3
    ctl command "execute in minecraft:the_end run tp @s $((x - 2)).5 $y $z.5" >/dev/null
    ctl wait 6 >/dev/null
    hold "$BLOCK"
    local aim reply
    aim=$(ctl look-at-block "$x" $((y - 1)) "$z" up 2>&1) \
        || fail "cannot aim at the floor under $x,$y,$z: $aim"
    reply=$(ctl place "$x" "$y" "$z" --item "$BLOCK" 2>&1) \
        || fail "ctl place at $x,$y,$z failed: $(tr -d '\n' <<<"$reply" | cut -c1-300)"
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
    ctl place "$x" "$y" "$z" --item "$BLOCK" >/dev/null \
        || fail "ctl place at $x,$y,$z failed: $(ctl inventory | jq -c '{hotbar,main}')"
    ctl wait 6 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$BLOCK" ] || fail "the carried generator did not place at $x,$y,$z"
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
if [ "$SELFTEST" = 1 ]; then
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

echo "PASS: a placed generator is empty and dark; one coal in its slot starts a 600-tick burn, spends it from the hand and lights the block; FE rises by exactly 60 a tick while it burns; the burn ends, the block goes dark and FE stops (no fuel, no FE); a stone is refused; charcoal is fuel and a coal block burns 5,400 ticks; the buffer clamps at 500,000 FE while the generator keeps burning; a hopper over it feeds the slot; the store survives save and relaunch; a broken generator's item carries its store and placing it restores it, while an item doctored to 999,999 FE is clamped to 500,000; an unknown id is refused; and the carried recipe's machine-frame cell crafts nothing without RFToolsBase"
