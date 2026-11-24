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
#  AX a blazing generator placed from its item is empty (no rod, no rate, working false), and a rod
#     given with the mod's own `rftoolspower:blazing_rod_data` component keeps it: the game reads it
#     back and the click puts the rod in slot 0 with a 60 FE a tick ceiling and 400 ticks to burn
#  AY the slot's rate climbs the artefact's curve: one 1/150th of the gap to the ceiling plus 0.01 a
#     tick, folded in single precision over the window the two replies name
#  AZ at the ceiling the store rises by exactly 60 FE per game tick, and it takes the ramp ~556
#     ticks to get there (the 400-tick rod never does — asserted, not assumed)
#  BA the rod is spent at its 400th tick: the slot empties, the rate decays a 30th of the gap a
#     tick, `working` falls and the store stops (the differential for AZ)
#  BB a doctored 999,995 FE generator clamps at 1,000,000 while its rod burns
#  BC the generator pushes its store into a neighbour with no reserve: 100,000 FE in, 100,000 out
#  BD the store, the rates and the rods survive save + relaunch
#  BE a stone is refused as a rod, the `blazing` refusal parses, and the carried recipe needs the
#     parent's machine frame and the absent `#c:rods/blaze` tag, so it crafts nothing here
#
#  BF an agitator placed with a store reads empty (nine slots, nine locks off) and three clicks fill
#     slots 0..2 with the rod's own `blazing_rod_data` (time 600)
#  BG three rods in a row agitate exactly as the adjacency algorithm folds them: quality and duration
#     climb by adjacency^2 (0.5176/0.5523/0.5176 a tick at the artefact's 0.2275/0.235 factors, not
#     a factor of 1), the clocks run down, and the 50,000 buffer spends exactly 10 FE a tick
#  BH a rod alone rises 0.484 a tick (its factor is 0.22); SELFTEST_AGITATOR=1 asserts the brief's
#     10 a tick and fails
#  BI a finished rod moves to the first free output slot, and a locked slot keeps its rod
#  BJ a vanilla blaze rod becomes a blazing rod; a rod already infused (steps 10) is refused and
#     stays in the server's inventory
#  BK the buffer takes exactly 100 FE a tick from a neighbour (the insert cap) and spends 10
#  BL a finished rod's component reaches the output box and a hopper under it pulls the rod out
#  BM the store, the locks and the rods survive save + relaunch
#  BN the agitator's refusals parse, a stone is refused as a rod, and the carried recipe needs the
#     parent's machine frame and the absent `#c:rods/blaze` tag
#
#  BO a rod in an energised infuser with no catalyst does not move: over a window the counter wraps
#     but steps, quality, duration and the store are unchanged (the differential for BP)
#  BP one nether star infuses exactly once — steps 64 -> 63, quality 60,000 -> 61,125, duration
#     20 -> 20.375, the store -10 and the catalyst consumed — and the two replies' counters and
#     ticks close an 11-tick period (the field is 10, the period 11)
#  BQ redstone raises quality by 375 (+40 %) and leaves duration alone: the per-catalyst differential
#  BR a hopper feeding nether stars runs the machine over a window where a 10-tick period would
#     predict a different count: the runs equal floor((dt + 10 - counter0)/11), each costs one star
#     and 10 FE, and the quality/duration fold is the single-precision per-run percentage
#  BS the infuser's refusals parse, a stone is refused as neither rod nor catalyst, and the carried
#     recipe needs the parent's dimensional shard and machine frame
#
#  BT a cell3 placed from its item with 5,000 FE reads tier=3, 5,000/20,000,000 locally and in its
#     own one-cell network (the capacity from the jar's PowerCellConfig.class)
#  BU a cell1 beside it sums the capacities to 20,500,000 over two cells; a cell3 with one air block
#     of gap reads only its own 20,000,000 (the tier-sum differential)
#  BV a lone cell3's east OUTPUT face pushes exactly 4,000 FE a tick (tier3MaxRFPerTick) into the
#     harness receiver; both replies' own t= close the rate and at rest the two stores still add up
#  BW with one extra cell in the network the same face moves 5,000 a tick: the 25 % per extra cell
#  BX the carried core3 recipe crafts nothing without the parent's dimensional shard, the core3 item
#     is carried, and a fourth-tier id is refused
#
#  BY a powercell item in the generator's charge slot gains exactly 1,000 FE a tick (upstream's
#     CHARGEITEMPERTICK), read from the item's own energy component through the two info replies'
#     t= values; the generator's store falls by exactly the same amount (it is never fed by the slot)
#  BZ a stone in the charge slot is refused: the slot stays empty, the stone stays in the inventory
#     server-side, and nothing is placed against the generator
#
#  CA an infusion carrier (an existing carried item with this port's own int component) in the third
#     slot raises the burn to 600 + (int)(600 * factor / 2) = 750 and the rate to 60 + 30 = 90 FE a
#     tick, proved from two info replies' own t=/energy=/burn= values (ΔE == 90 × Δburn)
#  CB the un-infused generator gives 60 × Δburn and a 600-tick burn (the differential), and a stone
#     in the infusion slot is refused and stays in the server's inventory
#  CC the endergenic accepts the typed infusion component in its own slot: the readout names the
#     carrier and reads infused=256 / factor=1.000 (the carrier gate — no chat-command shortcut)
#  CD a mode-1 pearl pays rfPerHit[mode] × 2 × (factor+2)/2 = 300 at full infusion (not the prose's
#     600), and a held pearl spends (long)(500 × (3-factor)/3) = 333 a tick, both from two replies'
#     own t=/spent= values; the un-infused 200/500 are the counterfactual
#  CE a stone in the endergenic's infusion slot is refused, kept server-side and not placed
#
#  DA the carrier gate: a powercell_card's typed rftoolspower:powercard_data={id:7} round-trips in
#     the hand and binds a fresh simple cell to channel 7 (never set by chat command)
#  DB two simple cells four blocks apart, linked by the same card id, read one 0/500,000 pool
#     (n=2) at both ends; an unlinked same-tier cell stays 0/250,000 (the differential)
#  DC a generator's 2,000 FE-a-tick push into cell A's INPUT face raises cell B by exactly the
#     artefact's 1,250 FE a side a tick over two replies' own t= values
#  DD an OUTPUT face pushes the shared pool into a harness receiver at the same 1,250 a tick
#  DE the card's plain vanilla recipe crafts and consumes; the three cell recipes need the
#     parent's machine frame / infused diamond and craft nothing here
#
# SELFTEST=dimensionalcell inverts DB/DC (it asserts the normal tier's 1,000,000 capacity and
# 5,000 FE a tick on the simple pair) and exits 1;
# SELFTEST=factor inverts CA (it asserts the un-infused 60 FE a tick on the infused machine) and
# exits non-zero;
# SELFTEST=charge inverts BY (it asserts 2,000 FE a tick) and exits non-zero;
# SELFTEST=cell3 inverts BT (it asserts the tier-2 capacity) and exits non-zero;
# SELFTEST=1 inverts phase V (the cell's NONE face must have taken the generator's FE) and exits
# non-zero, proving the face-mode assertion can fail; SELFTEST_MONITOR=1 keeps slice 2's inversion
# of O; SELFTEST_GENERATOR=1 keeps slice 1's inversion of C; SELFTEST_ENDER=1 inverts AF;
# SELFTEST_ENDERMON=1 inverts AO (the monitor must not have lit);
# SELFTEST_POWERLEVEL=1 inverts the power level's 5 (it asserts the brief's mistaken 4);
# SELFTEST_BLAZING=1 asserts a rod at its ceiling makes no FE (AZ inverted) and exits non-zero;
# SELFTEST_AGITATOR=1 asserts a rod alone rises the brief's 10 a tick (BH inverted) and exits 1;
# SELFTEST_INFUSER=1 asserts the brief's old 10-tick infuser period (BR inverted) and exits 1;
# SELFTEST=enderfactor inverts CC/CD (the un-infused 200 gain / 500 hold on an infused generator)
# and exits 1. CC checks the carrier gate first: a typed component in the endergenic's own slot.
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
# `SELFTEST=charge` is the charge-rate inversion: it asserts 2,000 FE a tick in phase BY and exits 1.
# `SELFTEST=cell3` is the tier-3 inversion: it asserts the tier-2 capacity in phase BT and exits 1.
# Keep the older numeric SELFTEST=1 (phase V) working alongside them.
SELFTEST_CHARGE=0
if [ "$SELFTEST" = charge ]; then
    SELFTEST_CHARGE=1
    SELFTEST=0
fi
# `SELFTEST=factor` is the infusion inversion: it asserts the un-infused 60 FE a tick in CA and
# exits 1. It runs only CA/CB, so an older phase cannot flake before the inversion is reached.
SELFTEST_FACTOR=0
if [ "$SELFTEST" = factor ]; then
    SELFTEST_FACTOR=1
    SELFTEST=0
fi
SELFTEST_CELL3=0
if [ "$SELFTEST" = cell3 ]; then
    SELFTEST_CELL3=1
    SELFTEST=0
fi
SELFTEST_MONITOR=${SELFTEST_MONITOR:-0}
SELFTEST_ENDERMON=${SELFTEST_ENDERMON:-0}
SELFTEST_POWERLEVEL=${SELFTEST_POWERLEVEL:-0}
SELFTEST_BLAZING=${SELFTEST_BLAZING:-0}
SELFTEST_AGITATOR=${SELFTEST_AGITATOR:-0}
SELFTEST_INFUSER=${SELFTEST_INFUSER:-0}
# `SELFTEST=enderfactor` inverts CC/CD: it asserts the un-infused 200 gain / 500 hold on the
# infused generator and exits 1, so both artefact assertions can fail.
SELFTEST_ENDERFACTOR=0
if [ "$SELFTEST" = enderfactor ]; then
    SELFTEST_ENDERFACTOR=1
    SELFTEST=0
fi
# `SELFTEST=dimensionalcell` inverts BU/BV/BW: it asserts the normal tier's 1,000,000 capacity
# and 5,000 per-side rate on a pair of linked *simple* cells (250,000 and 1,250) and exits 1.
SELFTEST_DIM=0
if [ "$SELFTEST" = dimensionalcell ]; then
    SELFTEST_DIM=1
    SELFTEST=0
fi
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
CELL3=rftoolspower:cell3
CORE=rftoolspower:power_core1
CORE3=rftoolspower:power_core3
RECEIVER=rfpowerharness:receiver
BIG_RECEIVER=rfpowerharness:big_receiver
BLAZING=rftoolspower:blazing_generator
ROD_ITEM=rftoolspower:blazing_rod
COAL=minecraft:coal
CHARCOAL=minecraft:charcoal
COAL_BLOCK=minecraft:coal_block
STONE=minecraft:stone
AGITATOR=rftoolspower:blazing_agitator
INFUSER=rftoolspower:blazing_infuser

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
                --wait --game-dir "$SCRATCH/game" --resources "$RES")
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
    echo "  parsed: energy=$ENERGY/$CAPACITY burn=$BURN/$BURN_MAX lit=$LIT fuel=$FUEL_ITEM x$FUEL_COUNT charge=$CHARGE_ITEM x$CHARGE_COUNT ($CHARGE_FE FE)" >&2
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

# --- the blazing generator (slice 7) -------------------------------------
# The rod's whole mechanic is the mod's own item component, so the rig gives rods with an explicit
# `rftoolspower:blazing_rod_data={steps,time,quality,duration}` and reads the same stack back.
blazing_arena() {
    # This band has no floor yet, and a tp into the void followed by the fill leaves the player
    # below it: the first run of this leg died there ("the dead screen is open" at the next
    # place). The player is put down on the floor only after it is filled.
    ctl command "gamemode creative" >/dev/null
    ctl command "execute in minecraft:the_end run tp @s $((SX + 1)).5 101 158.5" >/dev/null
    ctl wait 2 >/dev/null
    local attempt
    for attempt in 1 2 3; do
        ctl command "execute in minecraft:the_end run fill $((SX - 6)) 100 144 $((SX + 8)) 100 176 minecraft:stone" >/dev/null
        ctl wait 6 >/dev/null
        [ "$(block_name "$SX" 100 158)" = "minecraft:stone" ] && break
        echo "  the blazing arena floor fill did not land (attempt $attempt); waiting" >&2
        ctl wait 40 >/dev/null
    done
    [ "$(block_name "$SX" 100 158)" = "minecraft:stone" ] || fail "the blazing arena floor is not stone"
    ctl command "execute in minecraft:the_end run fill $((SX - 6)) 101 144 $((SX + 8)) 108 176 minecraft:air" >/dev/null
    ctl wait 6 >/dev/null
    [ "$(block_name "$SX" 101 158)" = "minecraft:air" ] || fail "the blazing arena air fill did not land"
    ctl command "execute in minecraft:the_end run tp @s $((SX + 1)).5 101 158.5" >/dev/null
    ctl wait 20 >/dev/null
    # The clicks the rods need are survival clicks (a creative hand keeps the stack, the cell
    # slice's trap), and the rod phase starts from an empty inventory.
    ctl command "gamemode survival" >/dev/null
    ctl command "clear @s" >/dev/null
    ctl wait 6 >/dev/null
}

aim_blazing() { # aim_blazing X Y Z
    # The placement's yaw is the game's, not the player's (the monitor/ender-monitor trap), so the
    # front is pinned after the placement; a `setblock` of the same block keeps its block entity.
    ctl command "execute in minecraft:the_end run setblock $1 $2 $3 $BLAZING[facing=north,working=false]" >/dev/null \
        || fail "cannot pin the blazing generator's facing at $1,$2,$3"
    ctl wait 4 >/dev/null
    [ "$(block_name "$1" "$2" "$3")" = "$BLAZING" ] || fail "the blazing generator vanished from $1,$2,$3"
}

place_blazing() { # place_blazing X Y Z — a fresh generator from the hotbar
    local x=$1 y=$2 z=$3 aim
    ctl command "execute in minecraft:the_end run setblock $x $y $z minecraft:air" >/dev/null
    ctl wait 4 >/dev/null
    ctl command "execute in minecraft:the_end run tp @s $((x - 2)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    hold "$BLAZING"
    aim=$(ctl look-at-block "$x" $((y - 1)) "$z" up 2>&1) \
        || fail "cannot aim at the floor under $x,$y,$z: $aim"
    place_block "$x" "$y" "$z" "$BLAZING" \
        || fail "ctl place at $x,$y,$z failed: $PLACE_REPLY"
    ctl wait 6 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$BLAZING" ] || fail "the blazing generator did not place at $x,$y,$z"
    aim_blazing "$x" "$y" "$z"
    echo "  placed: $(ctl block "$x" "$y" "$z" | jq -r '.state')" >&2
}

place_blazing_kept() { # place_blazing_kept X Y Z — the generator item the player already carries
    local x=$1 y=$2 z=$3
    ctl command "execute in minecraft:the_end run setblock $x $y $z minecraft:air" >/dev/null
    ctl wait 4 >/dev/null
    ctl command "execute in minecraft:the_end run tp @s $((x - 2)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    ctl select "$BLAZING" >/dev/null
    ctl wait 2 >/dev/null
    ctl look-at-block "$x" $((y - 1)) "$z" up >/dev/null || fail "cannot aim at the floor under $x,$y,$z"
    place_block "$x" "$y" "$z" "$BLAZING" \
        || fail "ctl place at $x,$y,$z failed: $PLACE_REPLY"
    ctl wait 6 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$BLAZING" ] || fail "the carried blazing generator did not place at $x,$y,$z"
    aim_blazing "$x" "$y" "$z"
}

hold_rod() { # hold_rod DURATION [QUALITY]
    ctl command "item replace entity @s hotbar.0 with $ROD_ITEM[rftoolspower:blazing_rod_data={steps:64,time:600,quality:${2:-60000},duration:$1}] 1" >/dev/null \
        || fail "the game refused the rod with its component"
    ctl wait 4 >/dev/null
    ctl select 1 >/dev/null
    ctl wait 2 >/dev/null
}

hold_rod_time() { # hold_rod_time TIME [DURATION] — a rod whose agitation clock is nearly out
    ctl command "item replace entity @s hotbar.0 with $ROD_ITEM[rftoolspower:blazing_rod_data={steps:64,time:$1,quality:60000,duration:${2:-20}}] 1" >/dev/null \
        || fail "the game refused the rod with its component"
    ctl wait 4 >/dev/null
    ctl select 1 >/dev/null
    ctl wait 2 >/dev/null
}

click_held() { # click_held X Y Z — right-click with whatever hotbar slot 1 holds
    local x=$1 y=$2 z=$3
    ctl command "execute in minecraft:the_end run tp @s $((x - 2)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    ctl select 1 >/dev/null
    ctl wait 2 >/dev/null
    ctl interact "$x" "$y" "$z" >/dev/null
    ctl wait 10 >/dev/null
}

# The *server's* inventory of the local player, as the `/data get entity @s Inventory` line. A
# refused click leaves the stack there; the client's own view can lose it to a prediction.
server_inventory() {
    ctl command "data get entity @s Inventory" >/dev/null
    ctl wait 4 >/dev/null
    await_line 'has the following entity data'
}

# `/rftoolspower blazing X Y Z <nonce>`: the line, then the parsed fields (BZ_*).
blazing() { # blazing X Y Z
    NONCE=$(( ${NONCE:-0} + 1 ))
    local line
    say "rftoolspower blazing $1 $2 $3 $NONCE"
    line=$(await_line "nonce=$NONCE")
    [ -n "$line" ] || fail "no fresh /rftoolspower blazing reply for nonce $NONCE: $(ctl messages 8 | jq -c '.chat')"
    eval "$(python3 "$PORT/tools/parse_blazing.py" "$line")"
    [ "${ok:-0}" = 1 ] || fail "the blazing line did not parse: $line"
    echo "  $line" >&2
}

expect_bz_energy() { [ "$BZ_ENERGY" = "$1" ] || fail "the blazing generator holds $BZ_ENERGY FE, expected $1"; }
expect_bz_working() { [ "$BZ_WORKING" = "$1" ] || fail "the blazing generator reports working=$BZ_WORKING, expected $1"; }
expect_bz_rod() { # expect_bz_rod SLOT ITEM|empty
    local rod
    eval "rod=\$BZ_ROD$1"
    [ "$rod" = "$2" ] || fail "blazing slot $1 holds '$rod', expected '$2'"
}

# --- the blazing agitator (slice 8) --------------------------------------
# A slab, `RotationType.NONE`: no state to pin, and the click is the only way a rod goes in (the
# GUI is not carried). The readout names every slot's own rod data, which is what the fold needs.
place_agitator() { # place_agitator X Y Z — a fresh agitator from the hotbar
    local x=$1 y=$2 z=$3 aim
    ctl command "execute in minecraft:the_end run setblock $x $y $z minecraft:air" >/dev/null
    ctl wait 4 >/dev/null
    ctl command "execute in minecraft:the_end run tp @s $((x - 2)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    hold "$AGITATOR"
    aim=$(ctl look-at-block "$x" $((y - 1)) "$z" up 2>&1) \
        || fail "cannot aim at the floor under $x,$y,$z: $aim"
    place_block "$x" "$y" "$z" "$AGITATOR" \
        || fail "ctl place at $x,$y,$z failed: $PLACE_REPLY"
    ctl wait 6 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$AGITATOR" ] || fail "the agitator did not place at $x,$y,$z"
    echo "  placed: $(ctl block "$x" "$y" "$z" | jq -r '.state')" >&2
}

place_agitator_kept() { # place_agitator_kept X Y Z — the agitator item the player already carries
    local x=$1 y=$2 z=$3
    ctl command "execute in minecraft:the_end run setblock $x $y $z minecraft:air" >/dev/null
    ctl wait 4 >/dev/null
    ctl command "execute in minecraft:the_end run tp @s $((x - 2)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    ctl select "$AGITATOR" >/dev/null
    ctl wait 2 >/dev/null
    ctl look-at-block "$x" $((y - 1)) "$z" up >/dev/null || fail "cannot aim at the floor under $x,$y,$z"
    place_block "$x" "$y" "$z" "$AGITATOR" \
        || fail "ctl place at $x,$y,$z failed: $PLACE_REPLY"
    ctl wait 6 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$AGITATOR" ] || fail "the carried agitator did not place at $x,$y,$z"
}

# An agitator with `FE` in its own store: the machine's item carries `block_entity_data`, which
# the block entity reads back on placement (the buffer clamps it to 50,000).
energised_agitator() { # energised_agitator X Y Z FE
    ctl command "give @s $AGITATOR[minecraft:block_entity_data={id:\"rftoolspower:blazing_agitator_block_entity\",energy:$4}]" >/dev/null
    ctl wait 6 >/dev/null
    place_agitator_kept "$1" "$2" "$3"
}

# A right click on the agitator's top face: the slab's upper surface is below the eye at y=101.
click_agitator() { # click_agitator X Y Z
    ctl command "execute in minecraft:the_end run tp @s $(($1 - 2)).5 101 $3.5" >/dev/null
    ctl wait 6 >/dev/null
    ctl select 1 >/dev/null
    ctl wait 2 >/dev/null
    ctl look-at "$1.5" "$2.25" "$3.5" >/dev/null || fail "cannot aim at the agitator at $1,$2,$3"
    ctl interact "$1" "$2" "$3" up >/dev/null
    ctl wait 10 >/dev/null
}

# `/rftoolspower agitator X Y Z <nonce>`: the line, then the parsed fields (AG_*).
agitator() { # agitator X Y Z
    NONCE=$(( ${NONCE:-0} + 1 ))
    local line
    say "rftoolspower agitator $1 $2 $3 $NONCE"
    line=$(await_line "nonce=$NONCE")
    [ -n "$line" ] || fail "no fresh /rftoolspower agitator reply for nonce $NONCE: $(ctl messages 8 | jq -c '.chat')"
    eval "$(python3 "$PORT/tools/parse_agitator.py" "$line")"
    [ "${ok:-0}" = 1 ] || fail "the agitator line did not parse: $line"
    echo "  $line" >&2
}

expect_ag_energy() { [ "$AG_ENERGY" = "$1" ] || fail "the agitator holds $AG_ENERGY FE, expected $1"; }
expect_ag_rod() { # expect_ag_rod SLOT ITEM|empty
    local held
    eval "held=\$AG_ROD$1"
    [ "$held" = "$2" ] || fail "agitator slot $1 holds '$held', expected '$2'"
}
expect_ag_out() { # expect_ag_out SLOT ITEM|empty
    local held
    eval "held=\$AG_OUT$1"
    [ "$held" = "$2" ] || fail "agitator output $1 holds '$held', expected '$2'"
}
expect_ag_lock() { # expect_ag_lock SLOT 0|1
    local locked
    eval "locked=\$AG_LOCK$1"
    [ "$locked" = "$2" ] || fail "agitator slot $1's lock is $locked, expected $2"
}

# The 3×3 box folded from the two replies' own values over the ticks their `t=` names.
ag_fold() { # ag_fold T0 T1 TIME0 QUALITY0 DURATION0 TIME1 QUALITY1 DURATION1
    eval "$(python3 "$PORT/tools/parse_agitator.py" --fold "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8")"
}

# --- the blazing infuser (slice 9) ---------------------------------------
# A full cube with a six-way `facing`. The GUI is not carried, so a click is the only way a rod or a
# catalyst goes in; the readout names the counter, which is what makes the 11-tick period solvable
# from two replies (`parse_infuser.py --period`).
place_infuser() { # place_infuser X Y Z — a fresh infuser from the hotbar
    local x=$1 y=$2 z=$3 aim
    ctl command "execute in minecraft:the_end run setblock $x $y $z minecraft:air" >/dev/null
    ctl wait 4 >/dev/null
    ctl command "execute in minecraft:the_end run tp @s $((x - 2)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    hold "$INFUSER"
    aim=$(ctl look-at-block "$x" $((y - 1)) "$z" up 2>&1) \
        || fail "cannot aim at the floor under $x,$y,$z: $aim"
    place_block "$x" "$y" "$z" "$INFUSER" \
        || fail "ctl place at $x,$y,$z failed: $PLACE_REPLY"
    ctl wait 6 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$INFUSER" ] || fail "the infuser did not place at $x,$y,$z"
    # The placement's yaw is the game's, not the player's (the monitor/injector trap): pin the front
    # so a change in the placement context cannot silently repoint the machine.
    ctl command "execute in minecraft:the_end run setblock $x $y $z $INFUSER[facing=north]" >/dev/null
    ctl wait 4 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$INFUSER" ] || fail "the infuser vanished from $x,$y,$z"
    echo "  placed: $(ctl block "$x" "$y" "$z" | jq -r '.state')" >&2
}

place_infuser_kept() { # place_infuser_kept X Y Z — the infuser item the player already carries
    local x=$1 y=$2 z=$3
    ctl command "execute in minecraft:the_end run setblock $x $y $z minecraft:air" >/dev/null
    ctl wait 4 >/dev/null
    ctl command "execute in minecraft:the_end run tp @s $((x - 2)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    ctl select "$INFUSER" >/dev/null
    ctl wait 2 >/dev/null
    ctl look-at-block "$x" $((y - 1)) "$z" up >/dev/null || fail "cannot aim at the floor under $x,$y,$z"
    place_block "$x" "$y" "$z" "$INFUSER" \
        || fail "ctl place at $x,$y,$z failed: $PLACE_REPLY"
    ctl wait 6 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$INFUSER" ] || fail "the carried infuser did not place at $x,$y,$z"
    ctl command "execute in minecraft:the_end run setblock $x $y $z $INFUSER[facing=north]" >/dev/null
    ctl wait 4 >/dev/null
    [ "$(block_name "$x" "$y" "$z")" = "$INFUSER" ] || fail "the infuser vanished from $x,$y,$z"
}

# An infuser with `FE` in its own store: the machine's item carries `block_entity_data`, which the
# block entity reads back on placement (the buffer clamps it to 50,000).
energised_infuser() { # energised_infuser X Y Z FE
    ctl command "give @s $INFUSER[minecraft:block_entity_data={id:\"rftoolspower:blazing_infuser_block_entity\",energy:$4}]" >/dev/null
    ctl wait 6 >/dev/null
    place_infuser_kept "$1" "$2" "$3"
}

# A right click with whatever hotbar slot 1 holds: a rod into the input slot, a catalyst into its
# own slot. Survival, because a creative hand keeps the clicked stack (the cell slice's trap).
click_infuser() { # click_infuser X Y Z
    ctl command "execute in minecraft:the_end run tp @s $(($1 - 2)).5 101 $3.5" >/dev/null
    ctl wait 6 >/dev/null
    ctl select 1 >/dev/null
    ctl wait 2 >/dev/null
    ctl look-at "$1.5" "$2.5" "$3.5" >/dev/null || fail "cannot aim at the infuser at $1,$2,$3"
    ctl interact "$1" "$2" "$3" >/dev/null
    ctl wait 10 >/dev/null
}

# `/rftoolspower infuser X Y Z <nonce>`: the line, then the parsed fields (IN_*).
infuser() { # infuser X Y Z
    NONCE=$(( ${NONCE:-0} + 1 ))
    local line
    say "rftoolspower infuser $1 $2 $3 $NONCE"
    line=$(await_line "nonce=$NONCE")
    [ -n "$line" ] || fail "no fresh /rftoolspower infuser reply for nonce $NONCE: $(ctl messages 8 | jq -c '.chat')"
    eval "$(python3 "$PORT/tools/parse_infuser.py" "$line")"
    [ "${ok:-0}" = 1 ] || fail "the infuser line did not parse: $line"
    echo "  $line" >&2
}

expect_in_steps() { [ "$IN_STEPS" = "$1" ] || fail "the input rod has $IN_STEPS steps, expected $1"; }
expect_in_catalyst() { [ "$IN_CATALYST" = "$1" ] || fail "the catalyst slot holds '$IN_CATALYST', expected '$1'"; }
expect_in_quality() { [ "$IN_QUALITY" = "$1" ] || fail "the input rod's quality is $IN_QUALITY, expected $1"; }
expect_in_duration() { [ "$IN_DURATION" = "$1" ] || fail "the input rod's duration is $IN_DURATION, expected $1"; }

# The counter solved over the window two replies name: PERIOD_RUNS is how many times it wrapped,
# PERIOD_REMAINDER must be 0 for an 11-tick period, PERIOD_FIELD is what 11 ticks predicts for this
# phase and PERIOD_TEN what the brief's old 10 ticks would.
inf_period() { # inf_period COUNTER0 COUNTER1 T0 T1
    eval "$(python3 "$PORT/tools/parse_infuser.py" --period "$1" "$2" "$3" "$4")"
}

echo "== launch (The End arena, the package's own content and code) =="
launch
arena
# Survival from here: vanilla's creative rule keeps a container stack in the hand
# (`ItemPlace`), so the fuel a click moves would never leave it. The mod's mechanic is the
# survival one, and a survival break is also what fires `block_drops`.
ctl command "gamemode survival" >/dev/null
ctl wait 4 >/dev/null

# The infusable factor is a function so `SELFTEST=factor` can run just CA/CB and exit 1 without
# replaying the older (and occasionally flaky) phases before reaching the inversion.
infusable_phases() {
# --- the infusable upgrade factor (slice 12) ---------------------------------
# Upstream `handlePowerGeneration`/`getRfPerTick` (1.21-7.0.6):
#   burning += (int)(burning * factor / 2.0f)   (after the coal block's x9)
#   rf = 60 + (long)(60 * factor)
# with `factor = infused / 256.0f` (McJtyLib IInfusable, maxInfuse 256). This port carries the int
# on an existing carried item with its own `rftoolspower:infusable_data` component, in slot 2.
UPGRADE_ITEM="$CORE[rftoolspower:infusable_data={infused:128}]"   # factor 0.5

echo "== CA: an infusion carrier raises the burn to 750 and the rate to 90 FE a tick =="
ctl close >/dev/null 2>&1 || true
ctl command "gamemode survival" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 4 >/dev/null
AX=$SX; AY=101; AZ=44
ctl command "execute in minecraft:the_end run tp @s $((AX - 2)).5 103 $AZ.5" >/dev/null
ctl wait 20 >/dev/null
ctl setblock "$AX" 100 "$AZ" minecraft:stone >/dev/null
ctl setblock "$AX" "$AY" "$AZ" minecraft:air >/dev/null
ctl wait 6 >/dev/null
[ "$(block_name "$AX" 100 "$AZ")" = minecraft:stone ] || fail "no floor under the infusion generator at $AX,100,$AZ"
place_generator "$AX" "$AY" "$AZ"
info "$AX" "$AY" "$AZ"
expect_energy 0
[ "$INFUSED" = 0 ] || fail "a fresh generator already carries an infusion: '$INFUSED'"
[ "$RF" = 60 ] || fail "a fresh generator's rate is $RF, expected 60"
# The carrier goes in slot 2: the click checks the component before the energy capability.
ctl command "item replace entity @s hotbar.0 with $UPGRADE_ITEM 1" >/dev/null
ctl wait 4 >/dev/null
ctl select 1 >/dev/null
ctl wait 2 >/dev/null
ctl look-at "$AX.5" 101.5 "$AZ.5" >/dev/null || fail "cannot aim at the infusion generator at $AX,$AY,$AZ"
ctl interact "$AX" "$AY" "$AZ" >/dev/null
ctl wait 12 >/dev/null
info "$AX" "$AY" "$AZ"
[ "$CARRIER" = "$CORE" ] || fail "the infusion slot holds '$CARRIER', expected $CORE"
[ "$INFUSED" = 128 ] || fail "the carrier's component was not read: infused=$INFUSED, expected 128"
[ "$FACTOR" = 0.500 ] || fail "the factor is $FACTOR, expected 0.500 (128/256)"
[ "$RF" = 90 ] || fail "the rate is $RF, expected 60 + (long)(60*0.5) = 90"
# One coal starts a 750-tick burn; the store then rises 90 a tick, with no adjacent energy block.
ctl command "item replace entity @s hotbar.0 with $COAL 1" >/dev/null
ctl wait 4 >/dev/null
ctl select 1 >/dev/null
ctl wait 2 >/dev/null
ctl look-at "$AX.5" 101.5 "$AZ.5" >/dev/null || fail "cannot aim at the infusion generator"
ctl interact "$AX" "$AY" "$AZ" >/dev/null
ctl wait 4 >/dev/null
info "$AX" "$AY" "$AZ"
[ "$BURN_MAX" = 750 ] || fail "the burn started at $BURN_MAX ticks, expected 600 + (int)(600*0.5/2) = 750"
[ "$BURN" -gt 0 ] || fail "the coal did not start a burn: burn=$BURN"
F0=$ENERGY; B0=$BURN; T0=$T
ctl wait 30 >/dev/null
info "$AX" "$AY" "$AZ"
F_DT=$((T - T0)); F_DB=$((B0 - BURN)); F_DE=$((ENERGY - F0))
[ "$F_DT" -ge 20 ] || fail "the two replies name only $F_DT ticks; the window is too small"
[ "$F_DB" -gt 0 ] || fail "the burn did not advance over the window: $B0 -> $BURN"
if [ "$SELFTEST_FACTOR" = 1 ]; then
    echo "(selftest: asserting the un-infused 60 FE a tick on the infused machine)"
    [ "$F_DE" = $((60 * F_DB)) ] \
        || fail "selftest: the infused generator made $F_DE FE over $F_DB ticks (90 a tick), so asserting the un-infused 60 a tick fails — the assertion is alive"
fi
[ "$F_DE" = $((90 * F_DB)) ] \
    || fail "the generator made $F_DE FE over $F_DB ticks ($((F_DE / F_DB)) a tick), expected 90 x $F_DB = $((90 * F_DB)) (60 x (1 + 0.5) x burn)"
echo "  the carrier's factor 0.5 gave a 750-tick burn and 90 FE a tick (dE == 90 x dBurn over the two replies' own ticks)"

echo "== CB: the un-infused differential and a stone refused in the infusion slot =="
IX=$SX; IY=101; IZ=46
ctl command "execute in minecraft:the_end run tp @s $((IX - 2)).5 103 $IZ.5" >/dev/null
ctl wait 20 >/dev/null
ctl setblock "$IX" 100 "$IZ" minecraft:stone >/dev/null
ctl setblock "$IX" "$IY" "$IZ" minecraft:air >/dev/null
ctl wait 6 >/dev/null
[ "$(block_name "$IX" 100 "$IZ")" = minecraft:stone ] || fail "no floor under the un-infused generator at $IX,100,$IZ"
place_generator "$IX" "$IY" "$IZ"
ctl command "item replace entity @s hotbar.0 with $COAL 1" >/dev/null
ctl select 1 >/dev/null
ctl wait 2 >/dev/null
ctl look-at "$IX.5" 101.5 "$IZ.5" >/dev/null || fail "cannot aim at the un-infused generator"
ctl interact "$IX" "$IY" "$IZ" >/dev/null
ctl wait 4 >/dev/null
info "$IX" "$IY" "$IZ"
[ "$INFUSED" = 0 ] || fail "a generator with no carrier reports infused=$INFUSED"
[ "$BURN_MAX" = 600 ] || fail "the un-infused burn is $BURN_MAX, expected 600"
U0=$ENERGY; UB0=$BURN; UT0=$T
ctl wait 30 >/dev/null
info "$IX" "$IY" "$IZ"
U_DT=$((T - UT0)); U_DB=$((UB0 - BURN)); U_DE=$((ENERGY - U0))
[ "$U_DT" -ge 20 ] || fail "the un-infused window is only $U_DT ticks"
[ "$U_DE" = $((60 * U_DB)) ] \
    || fail "the un-infused generator made $U_DE FE over $U_DB ticks, expected 60 x $U_DB"
echo "  with no carrier: a 600-tick burn and exactly 60 FE a tick (the differential for CA)"
# A stone answers neither fuel, nor the infusion component, nor the energy capability.
ctl command "item replace entity @s hotbar.0 with $STONE 1" >/dev/null
ctl wait 4 >/dev/null
ctl select 1 >/dev/null
ctl wait 2 >/dev/null
ctl look-at "$AX.5" 101.5 "$AZ.5" >/dev/null || fail "cannot aim at the infusion generator for the stone"
ctl interact "$AX" "$AY" "$AZ" >/dev/null
ctl wait 10 >/dev/null
info "$AX" "$AY" "$AZ"
[ "$INFUSED" = 128 ] || fail "the stone changed the infusion level: $INFUSED"
SERVER=$(server_inventory)
case "$SERVER" in
    *'"minecraft:stone"'*) ;;
    *) fail "the server lost the stone: a refused infusion click must change nothing ($SERVER)" ;;
esac
for cell in "$((AX - 1)) 101 $AZ" "$AX 102 $AZ" "$AX 101 $((AZ + 1))"; do
    [ "$(block_name $cell)" = minecraft:air ] \
        || fail "the refused stone was placed against the generator at $cell ($(block_name $cell))"
done
echo "  a stone is refused in the infusion slot, kept on the server and nothing is placed against the machine"
}

if [ "$SELFTEST_FACTOR" = 1 ]; then
    infusable_phases
    fail "selftest: the infusion inversion did not fail"
fi

# The endergenic's infusable factors are a function so `SELFTEST=enderfactor` can run just CC/CD.
enderfactor_phases() {
# --- the endergenic generator's infusable factors (slice 13) ---------------------------------
# `EndergenicTileEntity.java` @ e44463ca, read first:
#   :353   rf = rfToHoldPearl (500); rf = (long)(rf * (3.0f - factor) / 3.0f);
#   :578   rf = (long)(rfPerHit[mode] * powergenFactor (2.0));
#   :579   rf = (long)(rf * (factor + 2.0f) / 2.0f);   then the age bonus
# Factor 1: the gain is 3x the table (mode 1 = 100*3 = 300), the hold 333 FE a tick. The dispatch
# prose's 600 double-counts powergenFactor; the artefact and its own quoted formula both give 300.
CARRIER_ITEM="$CORE[rftoolspower:infusable_data={infused:256}]"

echo "== CC: the carrier gate — a typed component is accepted by the endergenic's slot =="
ctl close >/dev/null 2>&1 || true
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 4 >/dev/null
EFX=$SX; EFY=101; EFZ=190
ctl command "execute in minecraft:the_end run tp @s $EFX.5 101 $((EFZ + 4)).5" >/dev/null
ctl wait 40 >/dev/null
for attempt in 1 2 3; do
    ctl command "execute in minecraft:the_end run fill $((EFX - 3)) 100 186 $((EFX + 5)) 100 198 minecraft:stone" >/dev/null
    ctl wait 6 >/dev/null
    [ "$(block_name "$EFX" 100 "$EFZ")" = minecraft:stone ] && break
    ctl wait 40 >/dev/null
done
[ "$(block_name "$EFX" 100 "$EFZ")" = minecraft:stone ] || fail "no floor under the endergenic infusion arena"
ctl command "execute in minecraft:the_end run fill $((EFX - 3)) 101 186 $((EFX + 5)) 108 198 minecraft:air" >/dev/null
ctl wait 8 >/dev/null

# Place a fresh, seeded destination and click the carrier into its one slot. A survival click is
# needed so the stack actually leaves the hand, as in the coal generator's infusion phases.
place_infused_dest() {
    ctl command "gamemode creative" >/dev/null
    ctl command "clear @s" >/dev/null
    ctl command "execute in minecraft:the_end run setblock $EFX $EFY $((EFZ + 3)) minecraft:air" >/dev/null
    ctl wait 4 >/dev/null
    ctl command "give @s $ENDER[minecraft:block_entity_data={id:\"$ENDERGENIC_ENTITY\",energy:20000}]" >/dev/null
    ctl wait 8 >/dev/null
    place_held "$EFX" "$EFY" $((EFZ + 3)) "$ENDER"
    ctl command "gamemode survival" >/dev/null
    ctl command "clear @s" >/dev/null
    ctl command "item replace entity @s hotbar.0 with $CARRIER_ITEM 1" >/dev/null
    ctl wait 8 >/dev/null
    ctl select 1 >/dev/null
    ctl wait 2 >/dev/null
    ctl command "execute in minecraft:the_end run tp @s $((EFX - 2)).5 101 $((EFZ + 3)).5" >/dev/null
    ctl wait 6 >/dev/null
    ctl look-at "$EFX.5" 101.5 "$((EFZ + 3)).5" >/dev/null \
        || fail "cannot aim at the infusion destination $EFX,$EFY,$((EFZ + 3))"
    ctl interact "$EFX" "$EFY" $((EFZ + 3)) >/dev/null
    ctl wait 10 >/dev/null
    ender_state "$EFX" "$EFY" $((EFZ + 3))
    [ "$CARRIER" = "$CORE" ] \
        || fail "blocked(infusable-carrier): the endergenic slot holds '$CARRIER', expected $CORE"
    [ "$INFUSED" = 256 ] \
        || fail "blocked(infusable-carrier): the component was not read: infused=$INFUSED, expected 256"
    [ "$FACTOR" = 1.000 ] \
        || fail "blocked(infusable-carrier): the factor is $FACTOR, expected 1.000"
    ctl command "gamemode creative" >/dev/null
    ctl wait 4 >/dev/null
}
place_infused_dest
echo "  GATE: the endergenic's slot holds $CARRIER with infused=$INFUSED factor=$FACTOR"

# The destination exists now, so the source can be linked to it.
give_injector
place_injector "$((EFX + 1))" "$EFY" "$EFZ" east
give_ender
place_held "$EFX" "$EFY" "$EFZ" "$ENDER"
link "$EFX" "$EFY" "$EFZ" "$EFX" "$EFY" $((EFZ + 3))
ender_state "$EFX" "$EFY" "$EFZ"
[ "$DEST" = "$EFX,101,$((EFZ + 3))" ] || fail "the source did not link to the destination: '$DEST'"

echo "== CD: a mode-1 pearl pays the artefact's 300 and a held pearl spends 333 a tick =="
# Upstream's 0.6%-a-tick discard can end a hold inside a sampling window. A window whose `dropped`
# counter moved is inconclusive; the shot is repeated on a fresh destination (up to three times).
CD_ATTEMPT=0
while :; do
    CD_ATTEMPT=$((CD_ATTEMPT + 1))
    [ "$CD_ATTEMPT" = 1 ] || place_infused_dest
    ender_state "$EFX" "$EFY" $((EFZ + 3))
    D0=$DROPPED; S0=$SPENT; T0=$T
    pearl_into_injector "$((EFX + 1))" "$EFY" "$EFZ"
    pulse_fill "$EFX" 102 "$EFZ" "$((EFX + 1))" 102 $((EFZ + 3))
    ctl wait 14 >/dev/null
    ender_state "$EFX" "$EFY" "$EFZ"
    [ "$FIRED" -ge "$CD_ATTEMPT" ] || fail "the source fired $FIRED pearls after $CD_ATTEMPT attempts"
    ender_state "$EFX" "$EFY" $((EFZ + 3))
    [ "$ARRIVED" -ge 1 ] && [ "$ARRIVED" -le 15 ] \
        || fail "the pearl arrived at mode $ARRIVED, outside the 1..15 window"
    EXPECT=$(( RF_PER_HIT[ARRIVED] * 3 ))
    UNINFUSED=$(( RF_PER_HIT[ARRIVED] * 2 ))
    if [ "$SELFTEST_ENDERFACTOR" = 1 ] && [ "$GAINED" != "$UNINFUSED" ]; then
        SELFTEST_GAIN_FAIL=1
        SELFTEST_GAIN_NOTE="the pearl paid $GAINED FE at mode $ARRIVED (artefact: 3 x ${RF_PER_HIT[ARRIVED]} = $EXPECT), so asserting the un-infused $UNINFUSED fails"
        echo "(selftest gain: $SELFTEST_GAIN_NOTE)" >&2
    fi
    [ "$GAINED" = "$EXPECT" ] \
        || fail "the pearl paid $GAINED FE at mode $ARRIVED, expected $EXPECT (rfPerHit ${RF_PER_HIT[ARRIVED]} x 2 x (1+2)/2; the artefact's :578-579, not the prose's 600)"
    [ "$INFUSED" = 256 ] || fail "the carrier changed during the shot: infused=$INFUSED"
    A_DROPPED=$DROPPED; A_SPENT=$SPENT; A_T=$T
    [ "$A_DROPPED" = "$D0" ] || { echo "  attempt $CD_ATTEMPT: a pearl was discarded before the first read; repeating" >&2; continue; }
    ctl wait 14 >/dev/null
    ender_state "$EFX" "$EFY" $((EFZ + 3))
    [ "$DROPPED" = "$A_DROPPED" ] || { echo "  attempt $CD_ATTEMPT: a pearl was discarded inside the hold window; repeating" >&2; continue; }
    H_DT=$((T - A_T)); H_DS=$((SPENT - A_SPENT))
    [ "$H_DT" -ge 8 ] || fail "the hold window is only $H_DT ticks"
    if [ "$SELFTEST_ENDERFACTOR" = 1 ] && [ "$H_DS" != $((500 * H_DT)) ]; then
        SELFTEST_HOLD_FAIL=1
        SELFTEST_HOLD_NOTE="a held pearl spent $H_DS FE in $H_DT ticks (333 a tick), so asserting the un-infused 500 a tick fails"
        echo "(selftest hold: $SELFTEST_HOLD_NOTE)" >&2
    fi
    [ "$H_DS" = $((333 * H_DT)) ] \
        || fail "a held pearl spent $H_DS FE over $H_DT ticks ($((H_DS / H_DT)) a tick), expected 333 x $H_DT = $((333 * H_DT)) (the artefact's (long)(500*(3-1)/3))"
    break
done
[ "$CD_ATTEMPT" -le 6 ] || fail "six hold windows were all cut by the upstream discard"
if [ "${SELFTEST_GAIN_FAIL:-0}" = 1 ] || [ "${SELFTEST_HOLD_FAIL:-0}" = 1 ]; then
    fail "selftest: the enderfactor assertions are alive — gain: ${SELFTEST_GAIN_NOTE:-passed as un-infused}; hold: ${SELFTEST_HOLD_NOTE:-passed as un-infused}"
fi

echo "== CE: a stone in the infusion slot is refused, kept server-side and not placed =="
ctl command "gamemode survival" >/dev/null
ctl command "clear @s" >/dev/null
ctl command "item replace entity @s hotbar.0 with $STONE 1" >/dev/null
ctl wait 6 >/dev/null
ctl select 1 >/dev/null
ctl wait 2 >/dev/null
ctl command "execute in minecraft:the_end run tp @s $((EFX - 2)).5 101 $((EFZ + 3)).5" >/dev/null
ctl wait 6 >/dev/null
ctl look-at "$EFX.5" 101.5 "$((EFZ + 3)).5" >/dev/null || fail "cannot aim at the destination for the stone"
ctl interact "$EFX" "$EFY" $((EFZ + 3)) >/dev/null
ctl wait 10 >/dev/null
ender_state "$EFX" "$EFY" $((EFZ + 3))
[ "$INFUSED" = 256 ] || fail "the stone changed the infusion level: $INFUSED"
SERVER=$(server_inventory)
case "$SERVER" in
    *'"minecraft:stone"'*) ;;
    *) fail "the server lost the stone: a refused infusion click must change nothing ($SERVER)" ;;
esac
for cell in "$((EFX - 1)) 101 $((EFZ + 3))" "$EFX 102 $((EFZ + 3))" "$EFX 101 $((EFZ + 4))"; do
    [ "$(block_name $cell)" = minecraft:air ] \
        || fail "the refused stone was placed against the endergenic at $cell ($(block_name $cell))"
done
echo "  a stone is refused in the endergenic's infusion slot, kept on the server and nothing is placed"
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 4 >/dev/null
}

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
        [ "$item" = "$CELL3" ] && type=rftoolspower:cell3_block_entity
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

# cell3 is a function so `SELFTEST=cell3` can run just its capacity inversion and exit 1
# instead of replaying (and flaking in) the 26 older phases before reaching it.
cell3_phases() {
# --- cell3 (slice 10) -------------------------------------------------------
# The numbers are read from the jar's own PowerCellConfig.class (javap: `ldc2_w long 20000000l`
# for tier3MaxRF and `sipush 4000` for tier3MaxRFPerTick), not inferred from cell1/cell2. The cell's
# runtime was already tier-generic; what is new here is the carried block/item/drop payload and the
# game reading those tier-3 numbers back.
# The cells get the still-free rows z=80..88 of the cell arena (floor z=44..90, filled above).

echo "== BT: a cell3 placed from its item with 5,000 FE reads its tier-3 capacity =="
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 4 >/dev/null
give_cell "$CELL3" 5000
place_held "$SX" 101 80 "$CELL3"
cell_state "$SX" 101 80
expect_tier 3
expect_cells 1
expect_local 5000
expect_network 5000 20000000
expect_sides "none,none,none,none,none,none"
if [ "$SELFTEST_CELL3" = 1 ]; then
    echo "(selftest: asserting the tier-3 cell has the tier-2 capacity)"
    [ "$NCAP" = 4000000 ] \
        || fail "selftest: the cell3 capacity is $NCAP (20,000,000), so asserting 4,000,000 fails — the assertion is alive"
fi
echo "  tier=3 local=5000/20000000 network=5000/20000000 cells=1, six NONE faces"

echo "== BU: an adjacent cell1 sums the capacities; one block of air does not =="
give_cell "$CELL" 0
place_held "$SX" 101 81 "$CELL"
cell_state "$SX" 101 80
expect_tier 3
expect_cells 2
expect_network 5000 20500000
cell_state "$SX" 101 81
expect_tier 1
expect_cells 2
expect_network 5000 20500000
give_cell "$CELL3" 0
place_held "$SX" 101 83 "$CELL3"
cell_state "$SX" 101 83
expect_cells 1
expect_local 0
expect_network 0 20000000
echo "  adjacent cell3+cell1 share 5,000/20,500,000; a cell3 behind one air block reads 0/20,000,000"

echo "== BV: a lone cell3's OUTPUT face pushes exactly 4,000 FE a side a tick =="
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 85 minecraft:air" >/dev/null
ctl wait 4 >/dev/null
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 85 $BIG_RECEIVER" >/dev/null
ctl wait 4 >/dev/null
[ "$(block_name "$((SX + 1))" 101 85)" = "$BIG_RECEIVER" ] \
    || fail "the harness receiver did not place at $((SX + 1)),101,85"
give_cell "$CELL3" 500000
place_held "$SX" 101 85 "$CELL3"
cell_state "$SX" 101 85
side_set "$SX" 101 85 east output
expect_sides "none,none,none,none,none,output"
# Let the mode write land before T0. The big receiver cannot fill inside the window, so neither
# the cell's 500,000 store nor the neighbour's room clips the 4,000-a-tick rate.
ctl wait 2 >/dev/null
cell_state "$SX" 101 85
T0=$T; E0=$LOCAL; R0=$(energy_of "$((SX + 1))" 101 85)
ctl wait 4 >/dev/null
cell_state "$SX" 101 85
DT=$((T - T0)); DE=$((E0 - LOCAL))
echo "  over $DT ticks: cell $E0 -> $LOCAL FE (-$DE)"
[ "$DT" -ge 6 ] || fail "only $DT ticks passed; the window is too small to assert"
[ "$DE" = $((4000 * DT)) ] \
    || fail "the cell gave out $DE FE over $DT ticks, expected $((4000 * DT)): tier3MaxRFPerTick is 4,000 (a pair is 5,000)"
# The receiver took the FE the rate assertion measured. Conservation across two sequential reads
# is not assertable while the store moves (phase Z proves it at rest); here the rate is the point.
side_set "$SX" 101 85 east none
R1=$(energy_of "$((SX + 1))" 101 85)
[ "$R1" -gt 0 ] || fail "the receiver never took any FE: it still holds $R1"
echo "  the lone tier-3 cell pushed 4,000 a tick into the receiver ($R1 FE and rising)"

echo "== BW: a pair moves 5,000 a side — the 25 % per extra cell, in game =="
give_cell "$CELL" 0
place_held "$SX" 101 87 "$CELL"
give_cell "$CELL3" 500000
place_held "$SX" 101 88 "$CELL3"
cell_state "$SX" 101 88
expect_tier 3
expect_cells 2
expect_network 500000 20500000
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 88 minecraft:air" >/dev/null
ctl wait 4 >/dev/null
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 88 $BIG_RECEIVER" >/dev/null
ctl wait 4 >/dev/null
cell_state "$SX" 101 88
side_set "$SX" 101 88 east output
# Let the mode write land, as in BV; the big receiver has room for the whole window.
ctl wait 2 >/dev/null
cell_state "$SX" 101 88
T0=$T; E0=$LOCAL; R0=$(energy_of "$((SX + 1))" 101 88)
ctl wait 1 >/dev/null
cell_state "$SX" 101 88
DT=$((T - T0)); DE=$((E0 - LOCAL))
echo "  over $DT ticks: pair $E0 -> $LOCAL FE (-$DE)"
[ "$DT" -ge 5 ] || fail "only $DT ticks passed; the window is too small to assert"
[ "$DE" = $((5000 * DT)) ] \
    || fail "the pair gave out $DE FE over $DT ticks, expected $((5000 * DT)): 4,000 + 25 %"
side_set "$SX" 101 88 east none
R1=$(energy_of "$((SX + 1))" 101 88)
[ "$R1" -gt 0 ] || fail "the receiver never took any FE: it still holds $R1"
echo "  a cell3 with one extra cell moves 5,000 a side into the receiver ($R1 FE and rising)"

echo "== BX: the carried core3 recipe crafts nothing here, and an unknown id is refused =="
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
for item in minecraft:diamond minecraft:emerald minecraft:redstone_block minecraft:redstone "$STONE"; do
    ctl command "give @s $item 16" >/dev/null
done
ctl wait 8 >/dev/null
TX10=$((SX + 4)); TY10=101; TZ10=88
open_crafting_table "$TX10" "$TY10" "$TZ10"
# "sds"/"rRr"/"ses": stones stand where the parent's rftoolsbase:dimensionalshard belongs.
place_one "$STONE" 100
place_one minecraft:diamond 101
place_one "$STONE" 102
place_one minecraft:redstone 103
place_one minecraft:redstone_block 104
place_one minecraft:redstone 105
place_one "$STONE" 106
place_one minecraft:emerald 107
place_one "$STONE" 108
RESULT=$(ctl screen | jq -r '[.slots[]? | select(.slot == 200) | .item] | first // "empty"')
echo "  power_core3's recipe with stones where the parent's dimensional shard belongs: '$RESULT'" >&2
[ "$RESULT" = "empty" ] || fail "the core3 recipe crafted $RESULT without the parent's dimensional shard"
ctl close >/dev/null 2>&1 || true
ctl wait 4 >/dev/null
ctl command "clear @s" >/dev/null
ctl command "give @s $CORE3" >/dev/null
ctl wait 6 >/dev/null
[ "$(held_count "$CORE3")" = 1 ] \
    || fail "the carried power_core3 item is not registered: $(ctl inventory | jq -c '{hotbar,main}')"
ctl command "item replace entity @s hotbar.0 with rftoolspower:cell4" >/dev/null || true
ctl wait 6 >/dev/null
UNKNOWN=$(ctl inventory | jq -r '[.hotbar[], .main[] | select(.item == "rftoolspower:cell4")] | length')
[ "$UNKNOWN" = 0 ] || fail "an unknown fourth tier found its way into the inventory"
ctl messages 8 | jq -r '.chat[]' | grep -qi "unknown item\|No such item\|Unknown item" \
    || fail "the game did not refuse rftoolspower:cell4: $(ctl messages 8 | jq -c '.chat')"
echo "  the core3 item is carried, a cell4 id is refused, and the core3 recipe needs the parent"
}

# The charge-item slot is a function so `SELFTEST=charge` can run just its rate inversion and exit 1
# without replaying the 29 older phases before reaching it.
chargeitem_phases() {
# --- the charge-item slot (slice 11) -----------------------------------------
# Upstream `handleChargingItem`: `min(CHARGEITEMPERTICK, stored)` — 1,000 FE a tick from
# CoalGeneratorConfig — inserted into the charge-slot item's `Capabilities.Energy.ITEM` handler and
# consumed from the generator's own store. A powercell item answers that capability with the energy
# int in its `minecraft:block_entity_data` component, the same store a placed cell reads.

echo "== BY: a powercell item in the charge slot takes exactly 1,000 FE a tick out of the store =="
ctl close >/dev/null 2>&1 || true
ctl command "gamemode survival" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 4 >/dev/null
CX=$SX; CY=101; CZ=40   # the main arena floor reaches z=48; this row is clear
# Stand in the row first: a setblock in an unloaded chunk lands nothing, and the player would fall
# through the missing floor before the placement (the cell arena's trap).
ctl command "execute in minecraft:the_end run tp @s $((CX - 2)).5 103 $CZ.5" >/dev/null
ctl wait 20 >/dev/null
ctl setblock "$CX" 100 "$CZ" minecraft:stone >/dev/null
ctl setblock "$CX" "$CY" "$CZ" minecraft:air >/dev/null
ctl wait 6 >/dev/null
[ "$(block_name "$CX" 100 "$CZ")" = minecraft:stone ] || fail "no floor under the charge generator at $CX,100,$CZ"
# A seeded store, no fuel and no adjacent energy block: nothing generates and nothing is pushed,
# so every FE the item gains must have left this store through the charge slot.
ctl command "give @s $BLOCK[minecraft:block_entity_data={id:\"rftoolspower:coalgenerator_block_entity\",burn:0,burn_max:0,energy:100000}]" >/dev/null
ctl wait 4 >/dev/null
place_held "$CX" "$CY" "$CZ" "$BLOCK" || fail "the seeded generator did not place at $CX,$CY,$CZ"
info "$CX" "$CY" "$CZ"
[ "$ENERGY" = 100000 ] || fail "the seeded generator holds $ENERGY FE, expected 100000"
[ "$CHARGE_ITEM" = empty ] || fail "a fresh generator already has a charge item: '$CHARGE_ITEM'"
click_with "$CX" "$CY" "$CZ" "$CELL"
info "$CX" "$CY" "$CZ"
[ "$CHARGE_ITEM" = "$CELL" ] || fail "the right click did not put the cell in the charge slot: '$CHARGE_ITEM'"
# The item's own energy component, as the SDK's ITEM_ENERGY handler reads it. The level tick
# charges it during the click and this reply's latency, so it need not be zero yet: the rate below
# is measured between the two replies' own t= values, not from insertion.
Y_T0=$T; Y_FE0=$CHARGE_FE; Y_E0=$ENERGY
ctl wait 30 >/dev/null
info "$CX" "$CY" "$CZ"
Y_DT=$((T - Y_T0)); Y_DFE=$((CHARGE_FE - Y_FE0)); Y_DE=$((ENERGY - Y_E0))
[ "$Y_DT" -ge 20 ] || fail "the two replies name only $Y_DT ticks; the window is too small to assert"
if [ "$SELFTEST_CHARGE" = 1 ]; then
    echo "(selftest: asserting the charge rate is 2,000 FE a tick, not the artefact's 1,000)"
    [ "$Y_DFE" = $((2000 * Y_DT)) ] \
        || fail "selftest: the item gained $Y_DFE FE over $Y_DT ticks ($((Y_DFE / Y_DT)) a tick), so asserting 2,000 a tick fails — the assertion is alive"
fi
[ "$Y_DFE" = $((1000 * Y_DT)) ] \
    || fail "the charge item gained $Y_DFE FE over $Y_DT ticks ($((Y_DFE / Y_DT)) a tick), expected 1,000 x $Y_DT = $((1000 * Y_DT))"
[ "$Y_DE" = $((0 - Y_DFE)) ] \
    || fail "the generator's store changed by $Y_DE FE while the item gained $Y_DFE; the slot must pay exactly what the item took, never feed the generator"
echo "  the item's component rose $Y_DFE FE over $Y_DT ticks (1,000 x dt) and the store fell by exactly the same"

echo "== BZ: a stone is refused in the charge slot and stays in the inventory =="
BX=$SX; BY=101; BZZ=42
ctl close >/dev/null 2>&1 || true
ctl command "execute in minecraft:the_end run tp @s $((BX - 2)).5 103 $BZZ.5" >/dev/null
ctl wait 20 >/dev/null
ctl setblock "$BX" 100 "$BZZ" minecraft:stone >/dev/null
ctl setblock "$BX" "$BY" "$BZZ" minecraft:air >/dev/null
ctl wait 6 >/dev/null
[ "$(block_name "$BX" 100 "$BZZ")" = minecraft:stone ] || fail "no floor under the refusal generator at $BX,100,$BZZ"
hold "$BLOCK"
ctl look-at-block "$BX" 100 "$BZZ" up >/dev/null \
    || fail "cannot aim at the floor under $BX,$BY,$BZZ"
place_block "$BX" "$BY" "$BZZ" "$BLOCK" \
    || fail "ctl place at $BX,$BY,$BZZ failed: $PLACE_REPLY"
info "$BX" "$BY" "$BZZ"
[ "$CHARGE_ITEM" = empty ] || fail "a fresh generator already has a charge item: '$CHARGE_ITEM'"
ctl command "item replace entity @s hotbar.0 with $STONE 1" >/dev/null
ctl wait 4 >/dev/null
ctl select 1 >/dev/null
ctl wait 2 >/dev/null
ctl command "execute in minecraft:the_end run tp @s $((BX - 2)).5 101 $BZZ.5" >/dev/null
ctl wait 6 >/dev/null
ctl look-at "$BX.5" 101.5 "$BZZ.5" >/dev/null || fail "cannot aim at the generator at $BX,$BY,$BZZ"
ctl interact "$BX" "$BY" "$BZZ" >/dev/null
ctl wait 10 >/dev/null
info "$BX" "$BY" "$BZZ"
[ "$CHARGE_ITEM" = empty ] || fail "the stone was accepted into the charge slot: '$CHARGE_ITEM'"
[ "$CHARGE_FE" = 0 ] || fail "a refused stone somehow holds $CHARGE_FE FE"
SERVER=$(server_inventory)
case "$SERVER" in
    *'"minecraft:stone"'*) ;;
    *) fail "the server lost the stone: a refused click must change nothing ($SERVER)" ;;
esac
for cell in "$((BX - 1)) 101 $BZZ" "$BX 102 $BZZ" "$BX 101 $((BZZ + 1))"; do
    [ "$(block_name $cell)" = minecraft:air ] \
        || fail "the refused stone was placed against the generator at $cell ($(block_name $cell))"
done
echo "  a stone is refused, kept on the server and nothing is placed against the machine"
}

if [ "$SELFTEST_CELL3" = 1 ]; then
    cell3_phases
    fail "selftest: the tier-3 capacity inversion did not fail"
fi

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
# The window is sixteen consecutive *stepped* server ticks. A window that saw no pulse while the
# shot really fired is inconclusive, not a failure — the freeze/step hand-off is the harness's, and
# one run missed it entirely ('0000000000000000') while the destination recorded the arrival; such
# an attempt is retried, and the monitors' counters count every attempt. A real regression (no
# pulse ever) fails on the third window.
AO_ATTEMPTS=0
while :; do
    AO_ATTEMPTS=$((AO_ATTEMPTS + 1))
    pearl_into_injector "$((SX + 1))" 101 130
    sample_pulse "$MONX" "$MONY" "$MONZ" "$ENDERMON"
    [ "$PULSE_TICK_LIT" = 1 ] && break
    injector_state "$((SX + 1))" 101 130
    [ "$PEARLS" = 0 ] \
        || fail "the pulse left $PEARLS pearl(s) in the injector, so the shot never fired ('$PULSE_SEQUENCE')"
    echo "  attempt $AO_ATTEMPTS: the shot fired but the window saw no pulse ('$PULSE_SEQUENCE'); sampling again" >&2
    [ "$AO_ATTEMPTS" -lt 3 ] \
        || fail "three windows saw no pulse although the injector fired each shot ('$PULSE_SEQUENCE'); the monitor never lit"
done
if [ "${SELFTEST_ENDERMON:-0}" = 1 ]; then
    echo "(selftest: asserting the monitor never lit)"
    [ "$PULSE_LIT" = 0 ] || fail "selftest: the monitor lit for $PULSE_LIT sample(s), so the one-tick assertion is alive"
fi
case "$PULSE_SEQUENCE" in
    *0) ;;
    *) fail "the monitor was still lit at the end of the window: '$PULSE_SEQUENCE'" ;;
esac
endermonitor_state "$MONX" "$MONY" "$MONZ"
expect_monitor_mode arrived
expect_monitor_pulses "$AO_ATTEMPTS"
[ "$LAST" = arrived ] || fail "the monitor's last mode is $LAST, expected arrived"
[ "$NEEDPULSE" = false ] || fail "the monitor still owes a pulse after it fired"
[ "$OUT" = 0 ] || fail "the monitor still answers out=$OUT after the pulse"
case "$(ctl block "$MONX" "$MONY" "$MONZ" | jq -r '.state')" in
    *lit=false*) ;;
    *) fail "the monitor's state is still lit after the pulse" ;;
esac
endermonitor_state "$FIREDX" 101 "$FIREDZ"
expect_monitor_mode fired
expect_monitor_pulses "$AO_ATTEMPTS"
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
expect_monitor_pulses "$((AO_ATTEMPTS + 1))"
endermonitor_state "$FIREDX" 101 "$FIREDZ"
expect_monitor_pulses "$((AO_ATTEMPTS + 1))"
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
    if [ "$PULSES_AFTER_AP" = "$MON_BEFORE" ] && [ "$NEEDPULSE" = true ]; then
        # Upstream's 0.6 % discard can arm this monitor between two replies: `last` is already
        # 'lost' but the one-tick pulse has not been spent, so `pulses` has not moved yet. That is
        # an in-flight notice, not an arrival lighting a lost-mode monitor.
        echo "  the lost notice is armed (needpulse=true) but not yet spent: pulses still $MON_BEFORE"
    else
        [ "$PULSES_AFTER_AP" -gt "$MON_BEFORE" ] && [ "$PULSES_AFTER_AP" -le "$((MON_BEFORE + ATTEMPT))" ] \
            || fail "after $ATTEMPT landing(s) the lost-mode monitor reads $PULSES_AFTER_AP pulses, expected $MON_BEFORE..$((MON_BEFORE + ATTEMPT)) with last=lost"
    fi
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

# --- the blazing generator (slice 7) -------------------------------------
echo "== AX: a blazing generator places empty, and a given rod carries its component =="
blazing_arena
place_blazing "$SX" 101 150
blazing "$SX" 101 150
expect_bz_energy 0
expect_bz_working 0
for slot in 0 1 2 3; do
    expect_bz_rod "$slot" empty
done
[ "$BZ_RFTMAX0" = 0 ] && [ "$BZ_TICKS0" = 0 ] || fail "a fresh generator's slot 0 reads rftmax=$BZ_RFTMAX0 ticks=$BZ_TICKS0"
hold_rod 400
ROD_COMPONENTS=$(ctl inventory | jq -r '.held.components // ""')
echo "  the given rod's stack: $ROD_COMPONENTS" >&2
case "$ROD_COMPONENTS" in
    *rftoolspower:blazing_rod_data*) ;;
    *) fail "the given rod carries no rftoolspower:blazing_rod_data component: $ROD_COMPONENTS" ;;
esac
case "$ROD_COMPONENTS" in
    *quality*60000*) ;;
    *) fail "the rod's component does not carry quality 60000: $ROD_COMPONENTS" ;;
esac
click_held "$SX" 101 150
blazing "$SX" 101 150
expect_bz_rod 0 "$ROD_ITEM"
[ "$BZ_RFTMAX0" = 60 ] || fail "the rod's ceiling is $BZ_RFTMAX0, expected 60 (60,000 quality / 1,000)"
[ "$BZ_TICKS0" -gt 300 ] && [ "$BZ_TICKS0" -le 400 ] \
    || fail "the rod has $BZ_TICKS0 ticks left of its 400"
[ "$(held_count "$ROD_ITEM")" = 0 ] || fail "the hand still holds $(held_count "$ROD_ITEM") rod(s) after the click"
ctl wait 4 >/dev/null
blazing "$SX" 101 150
expect_bz_working 1
echo "  the rod went into slot 0 with a ceiling of 60 and $BZ_TICKS0 ticks left; the generator is working"

echo "== AY: the slot's rate climbs the artefact's 1/150th-of-the-gap curve =="
blazing "$SX" 101 150
R0=$BZ_RFT0; T0=$BZ_T; CEIL=$BZ_RFTMAX0
ctl wait 25 >/dev/null
blazing "$SX" 101 150
R1=$BZ_RFT0; T1=$BZ_T
eval "$(python3 "$PORT/tools/parse_blazing.py" --ramp "$R0" "$T0" "$R1" "$T1" "$CEIL")"
echo "  rft $R0 at t=$T0 -> $R1 at t=$T1: the fold says $RAMP_EXPECTED (delta $RAMP_DELTA)" >&2
[ "$RAMP_RISING" = 1 ] || fail "the rate did not climb: $R0 -> $R1"
python3 - "$RAMP_DELTA" <<'RAMPCHECK' || fail "the rate at $R1 is not the 150-tick fold of $R0 ($RAMP_EXPECTED, delta $RAMP_DELTA)"
import sys
sys.exit(0 if float(sys.argv[1]) < 0.0001 else 1)
RAMPCHECK
echo "  the climb is one 1/150th of the gap plus 0.01 a tick, to six decimals"

echo "== AZ: at its ceiling the store rises by exactly 60 FE a game tick =="
place_blazing "$SX" 101 158
hold_rod 5000
click_held "$SX" 101 158
REACHED=0
for _ in $(seq 1 45); do
    blazing "$SX" 101 158
    [ "$BZ_RFT0" = "60.000000" ] && { REACHED=1; break; }
    ctl wait 20 >/dev/null
done
[ "$REACHED" = 1 ] || fail "the rate settled at $BZ_RFT0 after its rod's whole ramp, expected the ceiling 60"
E0=$BZ_ENERGY; T0=$BZ_T
ctl wait 40 >/dev/null
blazing "$SX" 101 158
E1=$BZ_ENERGY; T1=$BZ_T
DE=$((E1 - E0)); DT=$((T1 - T0))
echo "  over $DT ticks: $E0 -> $E1 FE (+$DE)" >&2
[ "$DT" -ge 20 ] || fail "only $DT ticks passed; the window is too small to assert"
if [ "$SELFTEST_BLAZING" = 1 ]; then
    echo "(selftest: asserting a rod at its ceiling makes no FE)"
    [ "$DE" = 0 ] || fail "selftest: the blazing generator made $DE FE in $DT ticks, so the assertion is alive"
fi
[ "$DE" = $((60 * DT)) ] || fail "FE rose $DE over $DT ticks, expected $((60 * DT)) (one rod at its 60 ceiling)"

echo "== BA: the 400-tick rod is spent, the slot empties and the rate decays away =="
SPENT=0
for _ in $(seq 1 40); do
    blazing "$SX" 101 150
    [ "$BZ_ROD0" = empty ] && { SPENT=1; break; }
    ctl wait 20 >/dev/null
done
[ "$SPENT" = 1 ] || fail "the 400-tick rod was never spent: slot 0 still holds '$BZ_ROD0'"
[ "$BZ_TICKS0" = 0 ] || fail "the spent slot still reads $BZ_TICKS0 ticks"
[ "$BZ_RFTMAX0" = 0 ] || fail "the spent slot's ceiling is $BZ_RFTMAX0, expected 0"
DECAY0=$BZ_RFT0
ctl wait 20 >/dev/null
blazing "$SX" 101 150
DECAY1=$BZ_RFT0
echo "  the spent slot's rate: $DECAY0 -> $DECAY1" >&2
python3 - "$DECAY0" "$DECAY1" <<'DECAYCHECK' || fail "the spent slot's rate did not fall: $DECAY0 -> $DECAY1"
import sys
sys.exit(0 if float(sys.argv[2]) < float(sys.argv[1]) else 1)
DECAYCHECK
CALM=0
for _ in $(seq 1 25); do
    blazing "$SX" 101 150
    [ "$BZ_WORKING" = 0 ] && { CALM=1; break; }
    ctl wait 20 >/dev/null
done
[ "$CALM" = 1 ] || fail "the generator still reports working after its rod was spent and its rate decayed"
E0=$BZ_ENERGY; T0=$BZ_T
ctl wait 20 >/dev/null
blazing "$SX" 101 150
[ "$BZ_ENERGY" = "$E0" ] || fail "with no rod the store still moved: $E0 -> $BZ_ENERGY"
echo "  no rod, no FE: the store held $BZ_ENERGY for $((BZ_T - T0)) ticks and working is false"

echo "== BB: a doctored 999,995 FE generator clamps at the million =="
ctl command "give @s $BLAZING[minecraft:block_entity_data={id:\"rftoolspower:blazing_generator_block_entity\",energy:999995}]" >/dev/null
ctl wait 6 >/dev/null
place_blazing_kept "$SX" 101 166
blazing "$SX" 101 166
expect_bz_energy 999995
hold_rod 600
click_held "$SX" 101 166
ctl wait 40 >/dev/null
blazing "$SX" 101 166
expect_bz_energy 1000000
expect_bz_working 1
ctl wait 20 >/dev/null
blazing "$SX" 101 166
expect_bz_energy 1000000
echo "  999,995 FE plus a 60 FE ceiling stops at exactly 1,000,000 and keeps burning"

echo "== BC: the generator pushes its store into a neighbour, with no reserve =="
ctl command "execute in minecraft:the_end run setblock $SX 101 172 minecraft:air" >/dev/null
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 172 minecraft:air" >/dev/null
ctl wait 4 >/dev/null
ctl command "give @s $BLAZING[minecraft:block_entity_data={id:\"rftoolspower:blazing_generator_block_entity\",energy:100000}]" >/dev/null
ctl wait 6 >/dev/null
place_blazing_kept "$SX" 101 172
blazing "$SX" 101 172
expect_bz_energy 100000
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 172 $RECEIVER" >/dev/null
ctl wait 6 >/dev/null
[ "$(block_name "$((SX + 1))" 101 172)" = "$RECEIVER" ] || fail "the harness receiver did not place beside the blazing generator"
ctl wait 40 >/dev/null
blazing "$SX" 101 172
expect_bz_energy 0
PUSHED=$(energy_of "$((SX + 1))" 101 172)
[ "$PUSHED" = 100000 ] || fail "the receiver holds $PUSHED FE, expected the generator's whole 100,000 (no reserve)"
echo "  the 100,000 FE store moved into the receiver and the generator ends empty"

echo "== BD: the store, the rates and the rods survive save + relaunch =="
blazing "$SX" 101 158
SAVED_ENERGY=$BZ_ENERGY
SAVED_RFT=$BZ_RFT0
ctl save >/dev/null
ctl wait 10 >/dev/null
ctl quit >/dev/null 2>&1 || true
sleep 2
launch
ctl command "execute in minecraft:the_end run tp @s $((SX + 1)).5 101 158.5" >/dev/null
ctl wait 30 >/dev/null
[ "$(block_name "$SX" 101 158)" = "$BLAZING" ] || fail "the blazing generator did not survive the relaunch"
blazing "$SX" 101 158
[ "$BZ_ENERGY" -ge "$SAVED_ENERGY" ] || fail "after the relaunch the store is $BZ_ENERGY, was $SAVED_ENERGY before save"
expect_bz_rod 0 "$ROD_ITEM"
[ "$BZ_RFTMAX0" = 60 ] || fail "after the relaunch the ceiling is $BZ_RFTMAX0, expected 60"
[ "$BZ_RFT0" = "60.000000" ] || fail "after the relaunch the rate is $BZ_RFT0, was $SAVED_RFT at its ceiling"
echo "  after save + relaunch: $BZ_ENERGY FE, slot 0 still the rod with a ceiling of 60 and rft $BZ_RFT0"

echo "== BE: a stone is refused as a rod, and the carried recipe needs the parent =="
place_blazing "$SX" 101 176
ctl command "execute in minecraft:the_end run tp @s $((SX - 2)).5 101 176.5" >/dev/null
ctl wait 6 >/dev/null
ctl command "item replace entity @s hotbar.0 with $STONE 1" >/dev/null
ctl wait 4 >/dev/null
ctl select 1 >/dev/null
ctl wait 2 >/dev/null
INTERACT=$(ctl interact "$SX" 101 176 2>&1) || true
echo "  ctl interact on a blazing generator with a stone: $INTERACT" >&2
ctl wait 10 >/dev/null
blazing "$SX" 101 176
expect_bz_rod 0 empty
# The server is the authority. The *client's* own view loses the stack, because it predicts the
# placement and this pin's prediction does not consult a mod's hooks — measured: the client shows an
# empty hand while the entity's own Inventory still holds the stone (a refused click changed
# nothing). So the assertion reads the server's inventory through a command, and the cells around
# the machine (which the client predicted a stone into) are read back from the server too.
SERVER_INV=$(server_inventory)
echo "  the server's inventory after the click: $SERVER_INV" >&2
case "$SERVER_INV" in
    *'"minecraft:stone"'*) ;;
    *) fail "the server lost the stone: a non-rod click must change nothing ($SERVER_INV)" ;;
esac
for cell in "$((SX - 1)) 101 176" "$SX 102 176" "$SX 101 177"; do
    [ "$(block_name $cell)" = "minecraft:air" ] \
        || fail "the refused stone was placed against the machine at $cell ($(block_name $cell))"
done
echo "  the server kept the stone and no block was placed against the machine; every rod slot stayed empty"
ctl command "execute in minecraft:the_end run setblock $SX 101 178 minecraft:stone" >/dev/null
ctl wait 4 >/dev/null
say "rftoolspower blazing $SX 101 178"
LINE=$(await_line "blazing generator there")
[ -n "$LINE" ] || fail "no refusal for a position with no blazing generator: $(ctl messages 8 | jq -c '.chat')"
echo "  $LINE" >&2
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 4 >/dev/null
TX3=$((SX + 4)); TY3=101; TZ3=170
open_crafting_table "$TX3" "$TY3" "$TZ3"
# The grid's ingredients are given with the table already open: a give issued before it was read
# back by the screen one run (the client's inventory view had not caught up after the refused click).
for item in minecraft:blaze_rod minecraft:redstone_block "$STONE"; do
    ctl command "give @s $item 16" >/dev/null
done
ctl wait 10 >/dev/null
echo "  the table's inventory: $(ctl screen | jq -c '[.slots[]? | select(.slot < 36 and .item != null) | {slot, item, count}]')" >&2
# "XYX" / "RFR" / "XYX": blaze rods where `#c:rods/blaze` belongs, redstone blocks at R, a stone
# where `rftoolsbase:machine_frame` (and where its `infused_diamond` Y) belongs.
place_one minecraft:blaze_rod 100
place_one "$STONE" 101
place_one minecraft:blaze_rod 102
place_one minecraft:redstone_block 103
place_one "$STONE" 104
place_one minecraft:redstone_block 105
place_one minecraft:blaze_rod 106
place_one "$STONE" 107
place_one minecraft:blaze_rod 108
RESULT=$(ctl screen | jq -r '[.slots[]? | select(.slot == 200) | .item] | first // "empty"')
echo "  the blazing generator's recipe with a stone where rftoolsbase:machine_frame belongs: '$RESULT'" >&2
[ "$RESULT" = "empty" ] || fail "the blazing generator's recipe crafted $RESULT without the parent"
ctl close >/dev/null 2>&1 || true
ctl wait 4 >/dev/null
echo "  the machine frame and the absent #c:rods/blaze tag are the recipe's limit here"

# --- the blazing agitator (slice 8) --------------------------------------
echo "== BF: an agitator with a store fills its 3x3 box from clicks =="
# BE left the player in creative for its crafting table, and vanilla's creative rule keeps the
# clicked stack in the hand (`ItemPlace`), so the rod phases run in survival.
ctl command "gamemode survival" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 6 >/dev/null
energised_agitator "$SX" 101 146 40000
agitator "$SX" 101 146
# The store has already spent a few ticks' worth between the placement and this read (it runs as
# soon as it has 10 FE), so the seed is an upper bound, not an equality.
python3 - "$AG_ENERGY" <<'SEEDED' || fail "the agitator holds $AG_ENERGY FE, expected just under the 40,000 seeded"
import sys
sys.exit(0 if 39000 <= int(sys.argv[1]) <= 40000 else 1)
SEEDED
[ "$AG_READY" = 1 ] || fail "a 40,000 FE agitator is not ready ($AG_READY)"
for slot in 0 1 2 3 4 5 6 7 8; do
    expect_ag_rod "$slot" empty
    expect_ag_lock "$slot" 0
done
for _ in 1 2 3; do
    hold_rod 600
    click_agitator "$SX" 101 146
done
agitator "$SX" 101 146
for slot in 0 1 2; do
    expect_ag_rod "$slot" "$ROD_ITEM"
    expect_ag_out "$slot" empty
done
SERVER_INV=$(server_inventory)
if printf '%s' "$SERVER_INV" | grep -q "rftoolspower:blazing_rod"; then
    fail "the server still holds a rod after the three clicks: $SERVER_INV"
fi
# A rod whose clock started at 600 and is still running: it has been agitated since it landed.
python3 - "$AG_TIME0" <<'TIME600' || fail "slot 0's clock reads $AG_TIME0, expected just under 600"
import sys
sys.exit(0 if 0.0 < 600.0 - float(sys.argv[1]) < 60.0 else 1)
TIME600
echo "  three clicks filled slots 0..2: time $AG_TIME0/$AG_TIME1/$AG_TIME2, quality $AG_QUALITY0 (the store is being spent)"

echo "== BG: three rods in a row agitate at the adjacency square, and a tick costs 10 FE =="
agitator "$SX" 101 146
E0=$AG_ENERGY; T0=$AG_T
A_TIME0=$AG_TIME0,$AG_TIME1,$AG_TIME2,-,-,-,-,-,-
A_QUALITY0=$AG_QUALITY0,$AG_QUALITY1,$AG_QUALITY2,-,-,-,-,-,-
A_DURATION0=$AG_DURATION0,$AG_DURATION1,$AG_DURATION2,-,-,-,-,-,-
Q_LEFT0=$AG_QUALITY0; Q_MIDDLE0=$AG_QUALITY1
ctl wait 40 >/dev/null
agitator "$SX" 101 146
E1=$AG_ENERGY; T1=$AG_T
DT=$((T1 - T0)); DE=$((E0 - E1))
A_TIME1=$AG_TIME0,$AG_TIME1,$AG_TIME2,-,-,-,-,-,-
A_QUALITY1=$AG_QUALITY0,$AG_QUALITY1,$AG_QUALITY2,-,-,-,-,-,-
A_DURATION1=$AG_DURATION0,$AG_DURATION1,$AG_DURATION2,-,-,-,-,-,-
echo "  over $DT ticks: $E0 -> $E1 FE (-$DE), quality $Q_LEFT0/$Q_MIDDLE0 -> $AG_QUALITY0/$AG_QUALITY1" >&2
[ "$DT" -ge 20 ] || fail "only $DT ticks passed; the window is too small to assert"
[ "$DE" = $((10 * DT)) ] || fail "the store fell $DE over $DT ticks, expected $((10 * DT)) (10 FE a tick)"
ag_fold "$T0" "$T1" "$A_TIME0" "$A_QUALITY0" "$A_DURATION0" "$A_TIME1" "$A_QUALITY1" "$A_DURATION1"
echo "  the fold: $FOLD_QUALITY (error $FOLD_ERROR against the reply's own values)" >&2
python3 - "$FOLD_ERROR" <<'FOLDOK' || fail "the rods are not the adjacency algorithm's fold (largest delta $FOLD_ERROR over $FOLD_TICKS ticks)"
import sys
sys.exit(0 if float(sys.argv[1]) < 0.0001 else 1)
FOLDOK
python3 - "$Q_LEFT0" "$AG_QUALITY0" "$FOLD_TICKS" <<'ADJACENCY' \
    || fail "slot 0's quality rose $((0)) — it is not adjacency² × 10 a tick"
import sys
first, now, ticks = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3])
rise = now - first
# The brief's claim (a factor of 1) would be 10 a tick; the artefact's edge rod is 0.2275² × 10.
sys.exit(0 if 0.0 < rise < 10.0 * ticks * 0.1 else 1)
ADJACENCY
echo "  the three rods' quality/duration rose and their clocks fell exactly as the adjacency algorithm folds"

echo "== BH: a rod alone is agitated by its own factor (the brief's 1 is wrong) =="
energised_agitator "$SX" 101 152 5000
hold_rod 600
click_agitator "$SX" 101 152
agitator "$SX" 101 152
L_T0=$AG_T; L_TIME0=$AG_TIME0,-,-,-,-,-,-,-,-; L_QUALITY0=$AG_QUALITY0,-,-,-,-,-,-,-,-
L_DURATION0=$AG_DURATION0,-,-,-,-,-,-,-,-
L_Q0=$AG_QUALITY0
ctl wait 30 >/dev/null
agitator "$SX" 101 152
L_T1=$AG_T
L_TIME1=$AG_TIME0,-,-,-,-,-,-,-,-; L_QUALITY1=$AG_QUALITY0,-,-,-,-,-,-,-,-
L_DURATION1=$AG_DURATION0,-,-,-,-,-,-,-,-
ag_fold "$L_T0" "$L_T1" "$L_TIME0" "$L_QUALITY0" "$L_DURATION0" "$L_TIME1" "$L_QUALITY1" "$L_DURATION1"
echo "  the lone rod: quality $L_Q0 -> $AG_QUALITY0 in $FOLD_TICKS ticks (fold $FOLD_QUALITY, error $FOLD_ERROR)" >&2
python3 - "$FOLD_ERROR" <<'FOLDOK1' || fail "the lone rod is not the adjacency algorithm's fold (delta $FOLD_ERROR)"
import sys
sys.exit(0 if float(sys.argv[1]) < 0.0001 else 1)
FOLDOK1
if [ "$SELFTEST_AGITATOR" = 1 ]; then
    echo "(selftest: asserting a rod alone rises 10 a tick, the brief's factor of 1)"
    python3 - "$L_Q0" "$AG_QUALITY0" "$FOLD_TICKS" <<'BRIEFRISE' \
        || fail "selftest: the lone rod's quality rose $(python3 -c "print(round($AG_QUALITY0 - $L_Q0, 3))") in $FOLD_TICKS ticks (0.22² × 10 = 0.484 a tick), not the brief's 10 a tick ($((10 * FOLD_TICKS))) — the assertion is alive"
import sys
first, now, ticks = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3])
rise = now - first
sys.exit(0 if abs(rise - 10.0 * ticks) < 0.5 else 1)
BRIEFRISE
fi
python3 - "$L_Q0" "$AG_QUALITY0" "$FOLD_TICKS" <<'LONE' || fail "the lone rod's rise is not a quarter of a lone rod's factor"
import sys
first, now, ticks = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3])
rise = now - first
expected = 0.22 * 0.22 * 10.0 * ticks
sys.exit(0 if abs(rise - expected) < 0.05 * max(1.0, expected) else 1)
LONE
[ "$AG_READY" = 1 ] || fail "the lone-rod agitator ran out of FE"
echo "  a rod alone rises 0.484 a tick (0.22² × 10), not the brief's 10: its factor is 0.22, not 1"

echo "== BI: a finished rod moves to the output box unless its slot is locked =="
energised_agitator "$SX" 101 154 5000
say "rftoolspower agitatelock $SX 101 154 2 on $((NONCE + 1))"
NONCE=$((NONCE + 1))
LINE=$(await_line "nonce=$NONCE")
[ -n "$LINE" ] || fail "no fresh agitatelock reply: $(ctl messages 8 | jq -c '.chat')"
echo "  $LINE" >&2
eval "$(python3 "$PORT/tools/parse_agitator.py" "$LINE")"
[ "${ok:-0}" = 1 ] || fail "the agitatelock echo did not parse: $LINE"
expect_ag_lock 2 1
hold_rod_time 0.05
click_agitator "$SX" 101 154
hold_rod_time 0.05
click_agitator "$SX" 101 154
# Slots 0 and 1 hold the two short rods; slot 2 is empty and locked (its lock is the differential).
MOVED=0
for _ in $(seq 1 30); do
    agitator "$SX" 101 154
    [ "$AG_ROD0" = empty ] && [ "$AG_OUT0" = "$ROD_ITEM" ] && { MOVED=1; break; }
    ctl wait 5 >/dev/null
done
[ "$MOVED" = 1 ] || fail "neither short rod left its slot (slot0 '$AG_ROD0', out0 '$AG_OUT0')"
[ "$AG_OUT1" = "$ROD_ITEM" ] || fail "the second short rod did not reach output slot 1 ('$AG_OUT1')"
expect_ag_lock 2 1
echo "  both finished rods moved to the output box in order and the locked slot 2 kept its lock"

# The locked slot keeps a *rod*: put a spent rod into it and watch it stay.
say "rftoolspower agitatelock $SX 101 154 0 on $((NONCE + 1))"
NONCE=$((NONCE + 1))
LINE=$(await_line "nonce=$NONCE")
[ -n "$LINE" ] || fail "no fresh agitatelock reply for slot 0: $(ctl messages 8 | jq -c '.chat')"
eval "$(python3 "$PORT/tools/parse_agitator.py" "$LINE")"
expect_ag_lock 0 1
hold_rod_time 0.01
click_agitator "$SX" 101 154
KEPT=0
for _ in $(seq 1 30); do
    agitator "$SX" 101 154
    [ "$AG_ROD0" = "$ROD_ITEM" ] && { KEPT=1; break; }
    ctl wait 5 >/dev/null
done
[ "$KEPT" = 1 ] || fail "the rod clicked into the locked slot 0 never arrived ('$AG_ROD0')"
ctl wait 20 >/dev/null
agitator "$SX" 101 154
expect_ag_rod 0 "$ROD_ITEM"
python3 - "$AG_TIME0" <<'SPENT' || fail "the locked slot's rod is not spent (time $AG_TIME0)"
import sys
sys.exit(0 if float(sys.argv[1]) <= 0.0 else 1)
SPENT
echo "  a spent rod stays in its locked slot ($AG_ROD0, time $AG_TIME0) while an unlocked one moves out"

echo "== BJ: a blaze rod becomes a blazing rod, and an infused rod is refused =="
energised_agitator "$SX" 101 156 5000
hold minecraft:blaze_rod
click_agitator "$SX" 101 156
CONVERTED=0
for _ in $(seq 1 20); do
    agitator "$SX" 101 156
    [ "$AG_ROD0" = "$ROD_ITEM" ] && { CONVERTED=1; break; }
    ctl wait 5 >/dev/null
done
[ "$CONVERTED" = 1 ] || fail "the clicked blaze rod never became a blazing rod ('$AG_ROD0')"
echo "  a vanilla blaze rod became a blazing rod in slot 0"
# A blazing rod that has already been infused (steps < 64) is not valid on the left side.
ctl command "item replace entity @s hotbar.0 with $ROD_ITEM[rftoolspower:blazing_rod_data={steps:10,time:600,quality:60000,duration:20}] 1" >/dev/null
ctl wait 4 >/dev/null
ctl select 1 >/dev/null
ctl wait 2 >/dev/null
ctl command "execute in minecraft:the_end run tp @s $(($SX - 2)).5 101 156.5" >/dev/null
ctl wait 6 >/dev/null
ctl look-at "$SX.5" 101.25 156.5 >/dev/null || fail "cannot aim at the agitator at $SX,101,156"
ctl interact "$SX" 101 156 up >/dev/null
ctl wait 10 >/dev/null
agitator "$SX" 101 156
expect_ag_rod 1 empty
SERVER_INV=$(server_inventory)
printf '%s' "$SERVER_INV" | grep -Eq 'steps: *10' \
    || fail "the refused infused rod is not in the server's inventory: $SERVER_INV"
echo "  an already-infused rod (steps 10) was refused and stayed in the server's inventory"

echo "== BK: the agitator takes 100 FE a tick from a neighbour and spends 10 =="
ctl command "give @s $BLOCK[minecraft:block_entity_data={id:\"rftoolspower:coalgenerator_block_entity\",energy:100000}]" >/dev/null
ctl wait 6 >/dev/null
place_kept "$((SX + 1))" 101 160
energised_agitator "$SX" 101 160 0
# Each store's rate is measured against its own reply's tick (a store still moving is not
# conserved across two reads several ticks apart — the cell slice's trap 3).
agitator "$SX" 101 160
A_E0=$AG_ENERGY
A_T0=$AG_T
info "$((SX + 1))" 101 160
G_E0=$ENERGY
G_T0=$T
ctl wait 40 >/dev/null
agitator "$SX" 101 160
A_DT=$((AG_T - A_T0))
A_E1=$AG_ENERGY
info "$((SX + 1))" 101 160
G_DT=$((T - G_T0))
G_E1=$ENERGY
G_DE=$((G_E0 - G_E1))
A_DE=$((A_E1 - A_E0))
echo "  over $A_DT agitator / $G_DT generator ticks: generator $G_E0 -> $G_E1 (-$G_DE), agitator $A_E0 -> $A_E1 (+$A_DE)" >&2
[ "$A_DT" -ge 20 ] || fail "only $A_DT ticks passed; the window is too small to assert"
[ "$G_DE" = $((100 * G_DT)) ] || fail "the generator lost $G_DE FE over $G_DT ticks, expected $((100 * G_DT)) (the 100-a-tick insert cap)"
[ "$A_DE" = $((90 * A_DT)) ] || fail "the agitator gained $A_DE FE over $A_DT ticks, expected $((90 * A_DT)) (100 in, 10 spent)"
echo "  the buffer takes exactly 100 FE a tick and spends 10, so an idle box still nets 90"

echo "== BL: a finished rod's component reaches the output box and leaves with it =="
energised_agitator "$SX" 101 162 5000
hold_rod_time 5
click_agitator "$SX" 101 162
agitator "$SX" 101 162
[ "$AG_ROD0" = "$ROD_ITEM" ] || fail "the short rod did not land in slot 0 ('$AG_ROD0')"
Q_BEFORE=$AG_QUALITY0
python3 - "$Q_BEFORE" <<'ROSE' || fail "the short rod's quality did not rise in its slot ($Q_BEFORE)"
import sys
sys.exit(0 if float(sys.argv[1]) > 60000.0 else 1)
ROSE
OUT=0
for _ in $(seq 1 40); do
    agitator "$SX" 101 162
    [ "$AG_ROD0" = empty ] && [ "$AG_OUT0" = "$ROD_ITEM" ] && { OUT=1; break; }
    ctl wait 10 >/dev/null
done
[ "$OUT" = 1 ] || fail "the finished rod never reached output slot 0 ('$AG_OUT0')"
# A hopper under the agitator pulls the output slot out; its own inventory proves the item, and its
# `rftoolspower:blazing_rod_data` proves the component the agitator wrote.
ctl command "execute in minecraft:the_end run setblock $SX 100 162 minecraft:hopper[facing=down]" >/dev/null
ctl wait 6 >/dev/null
[ "$(block_name "$SX" 100 162)" = "minecraft:hopper" ] || fail "the hopper did not place under the agitator"
PULLED=0
for _ in $(seq 1 30); do
    ctl command "data get block $SX 100 162 Items" >/dev/null
    ctl wait 4 >/dev/null
    LINE=$(await_line 'has the following block data')
    case "$LINE" in
        *rftoolspower:blazing_rod_data*) PULLED=1; break ;;
    esac
    ctl wait 10 >/dev/null
done
[ "$PULLED" = 1 ] || fail "the hopper holds no blazing rod with its data: $LINE"
echo "  the hopper's Items: $(printf '%s' "$LINE" | cut -c1-220)" >&2
agitator "$SX" 101 162
expect_ag_out 0 empty
echo "  the agitated rod with its component left the agitator for the hopper"

echo "== BM: the store, the locks and the rods survive save + relaunch =="
say "rftoolspower agitatelock $SX 101 146 4 on $((NONCE + 1))"
NONCE=$((NONCE + 1))
LINE=$(await_line "nonce=$NONCE")
[ -n "$LINE" ] || fail "no fresh agitatelock reply before the save: $(ctl messages 8 | jq -c '.chat')"
eval "$(python3 "$PORT/tools/parse_agitator.py" "$LINE")"
expect_ag_lock 4 1
agitator "$SX" 101 146
SAVED_ENERGY=$AG_ENERGY; SAVED_QUALITY=$AG_QUALITY0
ctl save >/dev/null
ctl wait 10 >/dev/null
ctl quit >/dev/null 2>&1 || true
sleep 2
launch
ctl command "execute in minecraft:the_end run tp @s $((SX + 1)).5 101 146.5" >/dev/null
ctl wait 30 >/dev/null
[ "$(block_name "$SX" 101 146)" = "$AGITATOR" ] || fail "the agitator did not survive the relaunch"
agitator "$SX" 101 146
expect_ag_rod 0 "$ROD_ITEM"
expect_ag_lock 4 1
[ "$AG_ENERGY" -gt 0 ] || fail "the store is empty after the relaunch (was $SAVED_ENERGY)"
python3 - "$SAVED_QUALITY" "$AG_QUALITY0" <<'KEPTQUAL' || fail "after the relaunch slot 0's quality is $AG_QUALITY0, was $SAVED_QUALITY before the save"
import sys
sys.exit(0 if float(sys.argv[2]) >= float(sys.argv[1]) else 1)
KEPTQUAL
echo "  after save + relaunch: $AG_ENERGY FE, slot 0 still a rod at quality $AG_QUALITY0, lock 4 set"

echo "== BN: the agitator's refusals are parsed replies, and its recipe needs the parent =="
ctl command "execute in minecraft:the_end run setblock $SX 101 168 minecraft:stone" >/dev/null
ctl wait 4 >/dev/null
say "rftoolspower agitator $SX 101 168"
LINE=$(await_line "blazing agitator there")
[ -n "$LINE" ] || fail "no refusal for a position with no agitator: $(ctl messages 8 | jq -c '.chat')"
echo "  $LINE" >&2
say "rftoolspower agitatelock $SX 101 146 9 on"
LINE=$(await_line "slot 9 is not one of 0..8")
[ -n "$LINE" ] || fail "no refusal for slot 9: $(ctl messages 8 | jq -c '.chat')"
echo "  $LINE" >&2
say "rftoolspower agitatelock $SX 101 146 3 maybe"
LINE=$(await_line "unknown lock 'maybe'")
[ -n "$LINE" ] || fail "no refusal for the lock word 'maybe': $(ctl messages 8 | jq -c '.chat')"
echo "  $LINE" >&2
# A stone is not a rod: the server keeps it and no slot takes it.
energised_agitator "$SX" 101 170 5000
ctl command "item replace entity @s hotbar.0 with $STONE 1" >/dev/null
ctl wait 4 >/dev/null
ctl select 1 >/dev/null
ctl wait 2 >/dev/null
ctl command "execute in minecraft:the_end run tp @s $(($SX - 2)).5 101 170.5" >/dev/null
ctl wait 6 >/dev/null
ctl look-at "$SX.5" 101.25 170.5 >/dev/null || fail "cannot aim at the agitator at $SX,101,170"
ctl interact "$SX" 101 170 up >/dev/null
ctl wait 10 >/dev/null
agitator "$SX" 101 170
for slot in 0 1 2 3 4 5 6 7 8; do
    expect_ag_rod "$slot" empty
done
SERVER_INV=$(server_inventory)
case "$SERVER_INV" in
    *'"minecraft:stone"'*) ;;
    *) fail "the server lost the stone: a non-rod click must change nothing ($SERVER_INV)" ;;
esac
for cell in "$((SX - 1)) 101 170" "$SX 102 170" "$SX 101 171"; do
    [ "$(block_name $cell)" = "minecraft:air" ] \
        || fail "the refused stone was placed against the agitator at $cell ($(block_name $cell))"
done
echo "  a stone is refused as a rod, kept on the server and nothing is placed against the machine"
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 4 >/dev/null
TX4=$((SX + 4)); TY4=101; TZ4=160
open_crafting_table "$TX4" "$TY4" "$TZ4"
for item in minecraft:blaze_rod minecraft:glass "minecraft:iron_ingot" "$STONE"; do
    ctl command "give @s $item 16" >/dev/null
done
ctl wait 10 >/dev/null
# "XXX" / "GFG" / "iii": blaze rods where `#c:rods/blaze` belongs, glass where `#c:glass_blocks`,
# iron ingots at `i`, and a stone where `rftoolsbase:machine_frame` belongs.
place_one minecraft:blaze_rod 100
place_one minecraft:blaze_rod 101
place_one minecraft:blaze_rod 102
place_one minecraft:glass 103
place_one "$STONE" 104
place_one minecraft:glass 105
place_one minecraft:iron_ingot 106
place_one minecraft:iron_ingot 107
place_one minecraft:iron_ingot 108
RESULT=$(ctl screen | jq -r '[.slots[]? | select(.slot == 200) | .item] | first // "empty"')
echo "  the agitator's recipe with a stone where rftoolsbase:machine_frame belongs: '$RESULT'" >&2
[ "$RESULT" = "empty" ] || fail "the agitator's recipe crafted $RESULT without the parent"
ctl close >/dev/null 2>&1 || true
ctl wait 4 >/dev/null
echo "  the machine frame and the absent #c:rods/blaze tag are the recipe's limit here"

echo "== BO: a rod with no catalyst does not move (the differential) =="
# BN left the player in creative for its crafting table; the clicks here are survival clicks (a
# creative hand keeps the clicked stack — the cell slice's trap).
ctl command "gamemode survival" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 6 >/dev/null
energised_infuser "$SX" 101 172 5000
infuser "$SX" 101 172
[ "$IN_ENERGY" = 5000 ] || fail "the seeded infuser reads $IN_ENERGY FE, expected exactly 5000 (it has no way to spend it)"
[ "$IN_STEPS" = "-" ] || fail "a fresh infuser's input slot reports steps '$IN_STEPS', expected '-'"
expect_in_catalyst empty
hold_rod 20
click_infuser "$SX" 101 172
infuser "$SX" 101 172
expect_in_steps 64
[ "$IN_INPUT" = "$ROD_ITEM" ] || fail "the rod did not land in the input slot ('$IN_INPUT')"
echo "  the rod is in the input slot (steps=$IN_STEPS), the catalyst slot '$IN_CATALYST'"
I_T0=$IN_T; I_C0=$IN_COUNTER
ctl wait 25 >/dev/null
infuser "$SX" 101 172
inf_period "$I_C0" "$IN_COUNTER" "$I_T0" "$IN_T"
expect_in_steps 64
expect_in_quality 60000.000000
expect_in_duration 20.000000
expect_in_catalyst empty
[ "$IN_ENERGY" = 5000 ] || fail "the store moved to $IN_ENERGY FE with no catalyst"
[ "$PERIOD_REMAINDER" = 0 ] || fail "the counter does not close an 11-tick period (remainder $PERIOD_REMAINDER over $PERIOD_TICKS ticks)"
[ "$PERIOD_RUNS" -ge 1 ] || fail "the counter did not wrap in $PERIOD_TICKS ticks"
echo "  over $PERIOD_TICKS ticks the counter wrapped $PERIOD_RUNS time(s) and nothing was infused or spent"

echo "== BP: one nether star infuses once: a run on the 11th tick, +1,125 quality =="
energised_infuser "$SX" 101 174 5000
hold_rod 20
click_infuser "$SX" 101 174
infuser "$SX" 101 174
expect_in_steps 64
I_T0=$IN_T; I_C0=$IN_COUNTER; I_E0=$IN_ENERGY
hold minecraft:nether_star 1
click_infuser "$SX" 101 174
infuser "$SX" 101 174
expect_in_catalyst empty
expect_in_steps 63
# 60,000 + 60,000 × 120 / (100 × 64) = 61,125 — the brief's +112.5 is a factor 10 out.
expect_in_quality 61125.000000
expect_in_duration 20.375000
[ "$IN_ENERGY" = $((I_E0 - 10)) ] || fail "the store is $IN_ENERGY FE, expected $((I_E0 - 10)) (a run spends 10)"
inf_period "$I_C0" "$IN_COUNTER" "$I_T0" "$IN_T"
[ "$PERIOD_REMAINDER" = 0 ] || fail "the counter does not close an 11-tick period (remainder $PERIOD_REMAINDER over $PERIOD_TICKS ticks)"
[ "$PERIOD_RUNS" -ge 1 ] || fail "no counter tick happened in $PERIOD_TICKS ticks"
echo "  one star, one run: steps 64 -> $IN_STEPS, quality 60,000 -> $IN_QUALITY, duration 20 -> $IN_DURATION, store -10"

echo "== BQ: redstone is quality-only (+40 %) — the per-catalyst differential =="
energised_infuser "$SX" 101 176 5000
hold_rod 20
click_infuser "$SX" 101 176
infuser "$SX" 101 176
expect_in_steps 64
hold minecraft:redstone 1
click_infuser "$SX" 101 176
infuser "$SX" 101 176
expect_in_catalyst empty
expect_in_steps 63
expect_in_quality 60375.000000
expect_in_duration 20.000000
echo "  redstone: quality 60,000 -> $IN_QUALITY (+375), duration unchanged at $IN_DURATION (the star moved both)"

echo "== BR: a hopper feeds catalysts, and the counter's period is 11, not 10 =="
ctl command "execute in minecraft:the_end run setblock $SX 102 172 minecraft:air" >/dev/null
ctl wait 4 >/dev/null
energised_infuser "$SX" 101 172 20000
hold_rod 20
click_infuser "$SX" 101 172
infuser "$SX" 101 172
expect_in_steps 64
[ "$IN_INPUT" = "$ROD_ITEM" ] || fail "the rod did not land in the input slot ('$IN_INPUT')"
# A hopper above the machine: one star at a time is pushed into the catalyst slot, so every run has
# one to eat (the input slot is occupied, and the output slot takes no insert).
ctl command "execute in minecraft:the_end run setblock $SX 102 172 minecraft:hopper[facing=down]" >/dev/null
ctl wait 4 >/dev/null
ctl command "item replace block $SX 102 172 container.0 with minecraft:nether_star 16" >/dev/null
ctl wait 6 >/dev/null
[ "$(block_name "$SX" 102 172)" = "minecraft:hopper" ] || fail "the hopper did not place above the infuser"
hopper_stars() { # hopper_stars X Y Z -> the first stack's count
    ctl command "data get block $1 $2 $3 Items[0].count" >/dev/null
    ctl wait 4 >/dev/null
    local line
    line=$(await_line 'has the following block data')
    printf '%s' "$line" | sed -n 's/.*has the following block data: *\([0-9-]*\).*/\1/p'
}
infuser "$SX" 101 172
I_T0=$IN_T; I_C0=$IN_COUNTER; I_E0=$IN_ENERGY; I_STEPS0=$IN_STEPS
I_Q0=$IN_QUALITY; I_D0=$IN_DURATION
# Wait until the 11- and 10-tick predictions for this phase differ, so the selftest's inversion is
# a real difference and not a coincidence of the window.
for attempt in $(seq 1 8); do
    ctl wait 11 >/dev/null
    infuser "$SX" 101 172
    inf_period "$I_C0" "$IN_COUNTER" "$I_T0" "$IN_T"
    [ "$PERIOD_FIELD" != "$PERIOD_TEN" ] && [ "$PERIOD_RUNS" -ge 3 ] && break
done
RUNS=$((I_STEPS0 - IN_STEPS))
STARS=$(hopper_stars "$SX" 102 172)
[ -n "$STARS" ] || fail "the hopper did not answer its own stack count"
# One catalyst a run, conserved exactly: 16 seeded = runs so far + what the hopper still holds + the
# one in the catalyst slot (a run consumes the slot's star before the hopper refills it). `steps`
# names the runs exactly, so this needs no timing assumption between the two reads.
CAT_N=${IN_CATALYST_COUNT:-0}
TOTAL=$(( (64 - IN_STEPS) + STARS + CAT_N ))
echo "  over $PERIOD_TICKS ticks: $RUNS run(s) (counter wrapped $PERIOD_RUNS), '$STARS' stars left in the hopper ($CAT_N in the slot), store $I_E0 -> $IN_ENERGY" >&2
# One catalyst a run, conserved: 16 seeded = runs + what the hopper holds + what the catalyst slot
# holds. The hopper and the infuser are two reads a few ticks apart (the campaign's trap 3), so a
# star that moved from the hopper into the slot between them is counted on neither side: 16 or 15.
[ "$TOTAL" -ge 15 ] && [ "$TOTAL" -le 16 ] \
    || fail "the 16 seeded nether stars are not one a run: $((64 - IN_STEPS)) runs + '$STARS' in the hopper + $CAT_N in the slot = $TOTAL"
[ "$PERIOD_REMAINDER" = 0 ] || fail "the counter does not close an 11-tick period (remainder $PERIOD_REMAINDER over $PERIOD_TICKS ticks)"
[ "$PERIOD_RUNS" -ge 3 ] || fail "only $PERIOD_RUNS counter tick(s) in $PERIOD_TICKS ticks; the window is too small to assert the period"
[ "$PERIOD_RUNS" = "$PERIOD_FIELD" ] || fail "the counter wrapped $PERIOD_RUNS times, not floor((Δt + 10 - counter0)/11) = $PERIOD_FIELD over $PERIOD_TICKS ticks (counter0 $I_C0): the period is 11"
[ "$RUNS" -le "$PERIOD_RUNS" ] || fail "$RUNS runs in $PERIOD_RUNS counter ticks: a run tick cannot be outrun"
[ "$RUNS" -ge 1 ] || fail "the machine never ran"
[ $((I_E0 - IN_ENERGY)) = $((10 * RUNS)) ] || fail "the store fell $((I_E0 - IN_ENERGY)) FE over $RUNS runs, expected $((10 * RUNS))"
python3 - "$RUNS" "$I_Q0" "$IN_QUALITY" "$I_D0" "$IN_DURATION" <<'INFOLD' \
    || fail "the rod is not the catalyst's per-run percentage fold (quality $I_Q0 -> $IN_QUALITY, duration $I_D0 -> $IN_DURATION over $RUNS runs)"
import struct
import sys
runs, q0, q1, d0, d1 = int(sys.argv[1]), *map(float, sys.argv[2:6])
f32 = lambda x: struct.unpack("<f", struct.pack("<f", x))[0]
quality, duration = f32(q0), f32(d0)
for _ in range(runs):
    quality = f32(quality + f32(f32(quality * f32(120.0)) / f32(100.0 * 64.0)))
    duration = f32(duration + f32(f32(duration * f32(120.0)) / f32(100.0 * 64.0)))
sys.exit(0 if abs(quality - q1) < 0.5 and abs(duration - d1) < 0.01 else 1)
INFOLD
if [ "$SELFTEST_INFUSER" = 1 ]; then
    echo "(selftest: asserting the brief's 10-tick period: $PERIOD_TEN counter ticks, not the artefact's 11)"
    [ "$PERIOD_RUNS" = "$PERIOD_TEN" ] || fail "selftest: the counter wrapped $PERIOD_RUNS times in $PERIOD_TICKS ticks — one run every 11 (floor((Δt + 10 − counter0)/11) = $PERIOD_FIELD), not the brief's 10-tick period ($PERIOD_TEN) — the assertion is alive"
fi
echo "  one catalyst a run, 10 FE a run, and $RUNS runs in $PERIOD_TICKS ticks (the artefact's 11, not the field's 10)"

echo "== BS: the infuser's refusals parse, a stone is refused, and its recipe needs the parent =="
ctl command "execute in minecraft:the_end run setblock $SX 101 168 minecraft:stone" >/dev/null
ctl wait 4 >/dev/null
say "rftoolspower infuser $SX 101 168"
LINE=$(await_line "blazing infuser there")
[ -n "$LINE" ] || fail "no refusal for a position with no infuser: $(ctl messages 8 | jq -c '.chat')"
echo "  $LINE" >&2
# A stone is neither a rod nor a catalyst: the server keeps it and no slot takes it.
energised_infuser "$SX" 101 174 5000
ctl command "item replace entity @s hotbar.0 with $STONE 1" >/dev/null
ctl wait 4 >/dev/null
ctl select 1 >/dev/null
ctl wait 2 >/dev/null
ctl command "execute in minecraft:the_end run tp @s $(($SX - 2)).5 101 174.5" >/dev/null
ctl wait 6 >/dev/null
ctl look-at "$SX.5" 101.5 174.5 >/dev/null || fail "cannot aim at the infuser at $SX,101,174"
ctl interact "$SX" 101 174 >/dev/null
ctl wait 10 >/dev/null
infuser "$SX" 101 174
[ "$IN_INPUT" = empty ] || fail "the input slot took a stone ('$IN_INPUT')"
[ "$IN_CATALYST" = empty ] || fail "the catalyst slot took a stone ('$IN_CATALYST')"
SERVER_INV=$(server_inventory)
case "$SERVER_INV" in
    *'"minecraft:stone"'*) ;;
    *) fail "the server lost the stone: a refused click must change nothing ($SERVER_INV)" ;;
esac
for cell in "$((SX - 1)) 101 174" "$SX 102 174" "$SX 101 175"; do
    [ "$(block_name $cell)" = "minecraft:air" ] \
        || fail "the refused stone was placed against the infuser at $cell ($(block_name $cell))"
done
echo "  a stone is refused, kept on the server and nothing is placed against the machine"
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 4 >/dev/null
TX9=$((SX + 4)); TY9=101; TZ9=176
open_crafting_table "$TX9" "$TY9" "$TZ9"
for item in minecraft:blaze_rod minecraft:iron_ingot "$STONE"; do
    ctl command "give @s $item 16" >/dev/null
done
ctl wait 10 >/dev/null
# "iXi" / "sFs" / "iXi": iron ingots at `i`, blaze rods where `#c:rods/blaze` belongs, and stones
# where the parent's `rftoolsbase:dimensionalshard` (`s`) and `rftoolsbase:machine_frame` (`F`) go.
place_one minecraft:iron_ingot 100
place_one minecraft:blaze_rod 101
place_one minecraft:iron_ingot 102
place_one "$STONE" 103
place_one "$STONE" 104
place_one "$STONE" 105
place_one minecraft:iron_ingot 106
place_one minecraft:blaze_rod 107
place_one minecraft:iron_ingot 108
RESULT=$(ctl screen | jq -r '[.slots[]? | select(.slot == 200) | .item] | first // "empty"')
echo "  the infuser's recipe with stones where the parent's items belong: '$RESULT'" >&2
[ "$RESULT" = "empty" ] || fail "the infuser's recipe crafted $RESULT without the parent"
ctl close >/dev/null 2>&1 || true
ctl wait 4 >/dev/null
echo "  the parent's dimensional shard and machine frame are the recipe's limit here"

DIM_SIMPLE_ITEM=rftoolspower:dimensionalcell_simple
DIM_CARD_ITEM=rftoolspower:powercell_card

dim_cell_state() { # dim_cell_state X Y Z — the `/rftoolspower dimcell` line, parsed
    NONCE=$(( ${NONCE:-0} + 1 ))
    local line
    say "rftoolspower dimcell $1 $2 $3 $NONCE"
    line=$(await_line "nonce=$NONCE")
    [ -n "$line" ] || fail "no fresh /rftoolspower dimcell reply for nonce $NONCE: $(ctl messages 8 | jq -c '.chat')"
    eval "$(python3 "$PORT/tools/parse_dimcell.py" "$line" --nonce "$NONCE")"
    [ "${ok:-0}" = 1 ] || fail "the dimensional-cell line did not parse: $line"
    echo "  $line" >&2
}

dim_side_set() { # dim_side_set X Y Z FACE MODE
    local line
    say "rftoolspower dimside $1 $2 $3 $4 $5"
    line=$(await_line "Dimensional Cell side at $1,$2,$3: $4 $5")
    [ -n "$line" ] || fail "no 'Dimensional Cell side' reply for $4 $5: $(ctl messages 8 | jq -c '.chat')"
    echo "  $line" >&2
}

dim_give_cell() { # dim_give_cell X Y Z [ENERGY]
    local x=$1 y=$2 z=$3 energy=${4:-}
    ctl command "gamemode creative" >/dev/null
    ctl command "clear @s" >/dev/null
    if [ -n "$energy" ]; then
        ctl command "give @s $DIM_SIMPLE_ITEM[minecraft:block_entity_data={id:\"rftoolspower:dimensionalcell_block_entity\",energy:$energy}]" >/dev/null
    else
        ctl command "give @s $DIM_SIMPLE_ITEM" >/dev/null
    fi
    ctl wait 8 >/dev/null
    place_held "$x" "$y" "$z" "$DIM_SIMPLE_ITEM"
}

dim_click_card() { # dim_click_card X Y Z ID — click a card carrying {id:ID} into the cell
    local x=$1 y=$2 z=$3 id=$4 line
    ctl command "gamemode creative" >/dev/null
    ctl command "clear @s" >/dev/null
    ctl command "give @s $DIM_CARD_ITEM[rftoolspower:powercard_data={id:$id}] 1" >/dev/null
    ctl wait 10 >/dev/null
    # The gate: the typed component round-trips on the existing item, read from the live hand.
    NONCE=$(( ${NONCE:-0} + 1 ))
    say "rftoolspower card $NONCE"
    line=$(await_line "nonce=$NONCE")
    [ -n "$line" ] || fail "blocked(dimensional-cell-carrier): no /rftoolspower card reply: $(ctl messages 8 | jq -c '.chat')"
    local card_item card_net
    card_item=$(printf '%s\n' "$line" | sed -n 's/.*item=\([^ ]*\).*/\1/p')
    card_net=$(printf '%s\n' "$line" | sed -n 's/.*net=\(-[0-9]*\|[0-9]*\).*/\1/p')
    echo "  GATE: $line" >&2
    [ "$card_item" = "$DIM_CARD_ITEM" ] && [ "$card_net" = "$id" ] \
        || fail "blocked(dimensional-cell-carrier): the card component did not round-trip: item=$card_item net=$card_net, expected $DIM_CARD_ITEM/$id"
    # A survival click is needed so the stack really leaves the hand (slice 13's trap).
    ctl command "gamemode survival" >/dev/null
    ctl command "clear @s" >/dev/null
    ctl command "give @s $DIM_CARD_ITEM[rftoolspower:powercard_data={id:$id}] 1" >/dev/null
    ctl wait 8 >/dev/null
    ctl select 1 >/dev/null
    ctl wait 2 >/dev/null
    ctl command "execute in minecraft:the_end run tp @s $((x - 2)).5 101 $z.5" >/dev/null
    ctl wait 6 >/dev/null
    ctl look-at "$x.5" 101.5 "$z.5" >/dev/null \
        || fail "cannot aim at the dimensional cell at $x,101,$z"
    ctl interact "$x" 101 "$z" >/dev/null
    ctl wait 10 >/dev/null
    dim_cell_state "$x" 101 "$z"
    [ "$DNET" = "$id" ] \
        || fail "blocked(dimensional-cell-carrier): the cell did not bind to the card's channel: net=$DNET, expected $id"
    ctl command "gamemode creative" >/dev/null
    ctl wait 4 >/dev/null
}

dimensionalcell_phases() {
# --- the dimensional cell (slice 14) -----------------------------------------
# `DimensionalCellConfiguration` @ e44463ca: rfPerTick 5000, rfPerNormalCell 1,000,000,
# simpleFactor 4, advancedFactor 4. `getPowerFactor` 1/4/16 gives simple 250,000/1,250,
# normal 1,000,000/5,000, advanced 4,000,000/20,000. Two simple cells linked by a card at
# z=204 and z=208 are four blocks apart, so adjacency cannot explain the shared pool.

echo "== DA: the carrier gate — a typed component round-trips and binds a cell to a channel =="
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 4 >/dev/null
ctl command "execute in minecraft:the_end run tp @s $SX.5 101 208.5" >/dev/null
ctl wait 40 >/dev/null
for attempt in 1 2 3; do
    ctl command "execute in minecraft:the_end run fill $((SX - 4)) 100 200 $((SX + 8)) 100 216 minecraft:stone" >/dev/null
    ctl wait 6 >/dev/null
    [ "$(block_name "$SX" 100 204)" = minecraft:stone ] && break
    ctl wait 40 >/dev/null
done
[ "$(block_name "$SX" 100 204)" = minecraft:stone ] || fail "no floor under the dimensional-cell arena"
ctl command "execute in minecraft:the_end run fill $((SX - 4)) 101 200 $((SX + 8)) 108 216 minecraft:air" >/dev/null
ctl wait 8 >/dev/null

dim_give_cell "$SX" 101 204
dim_cell_state "$SX" 101 204
[ "$DTILE" = simple ] || fail "the cell is tier $DTILE, expected simple"
[ "$DN" = 1 ] || fail "a lone cell reports $DN members, expected 1"
[ "$DNET" = -1 ] || fail "a fresh cell is unlinked (net=$DNET), expected -1"
[ "$DNCAP" = 250000 ] || fail "the simple cell's capacity is $DNCAP, expected 250,000"
[ "$DLCAP" = 250000 ] || fail "the simple cell's own limit is $DLCAP, expected 250,000"
echo "  a fresh simple cell reads 0/250,000, one member, net=-1, six NONE faces"
dim_click_card "$SX" 101 204 7
echo "  the card's rftoolspower:powercard_data={id:7} round-tripped and bound cell A to channel 7"

echo "== DB: two card-linked cells four blocks apart share one store and one capacity =="
dim_give_cell "$SX" 101 208
dim_click_card "$SX" 101 208 7
dim_cell_state "$SX" 101 204
[ "$DN" = 2 ] || fail "the linked pair reads $DN members, expected 2 (the cells are 4 blocks apart)"
[ "$DNET" = 7 ] || fail "cell A's channel is $DNET, expected 7"
[ "$DNCAP" = 500000 ] || fail "the pair's capacity is $DNCAP, expected 2 x 250,000"
dim_cell_state "$SX" 101 208
[ "$DN" = 2 ] || fail "cell B reads $DN members, expected the same two"
[ "$DNCAP" = 500000 ] || fail "cell B's shared capacity is $DNCAP, expected 500,000"
# The differential: an unlinked cell of the same tier stays at its own capacity.
dim_give_cell "$SX" 101 212
dim_cell_state "$SX" 101 212
[ "$DN" = 1 ] && [ "$DNET" = -1 ] || fail "an unlinked cell joined the pool: n=$DN net=$DNET"
[ "$DNCAP" = 250000 ] || fail "the unlinked differential reads $DNCAP, expected 250,000"
if [ "$SELFTEST_DIM" = 1 ]; then
    echo "(selftest: asserting the normal tier's 1,000,000 capacity on the simple pair)"
    [ "$DNCAP" = 500000 ] \
        || fail "selftest: the simple pair's capacity is $DNCAP (500,000), so asserting 1,000,000 fails — the assertion is alive"
fi
echo "  the pair reads one 0/500,000 pool (n=2) at both ends; a same-tier cell with no card stays 0/250,000"

echo "== DC: an insert into cell A raises cell B by exactly 1,250 FE a tick =="
# The generator pushes 2,000 a tick; the simple cell's per-side cap is 1,250, so the *cell* sets
# the rate. Sample at both ends of a window using each reply's own t= and network= values.
dim_side_set "$SX" 101 204 west input
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
ctl command "give @s $BLOCK[minecraft:block_entity_data={id:\"rftoolspower:coalgenerator_block_entity\",burn:0,burn_max:0,energy:100000}]" >/dev/null
ctl wait 8 >/dev/null
place_held "$((SX - 1))" 101 204 "$BLOCK"
info "$((SX - 1))" 101 204
# The generator starts pushing the moment it is placed, so the first read sees whatever is left
# of the seeded 100,000 — the assertion below is the cell's per-side rate from two cell replies,
# not the generator's untouched initial store.
BW_G0=$ENERGY
[ "$BW_G0" -gt 0 ] && [ "$BW_G0" -le 100000 ] \
    || fail "the seeded generator reads $BW_G0 FE, expected 1..100,000"
ctl wait 2 >/dev/null
dim_cell_state "$SX" 101 208
BW_T0=$DT; BW_E0=$DNETWORK
ctl wait 24 >/dev/null
dim_cell_state "$SX" 101 208
BW_DT=$((DT - BW_T0)); BW_DE=$((DNETWORK - BW_E0))
echo "  read at cell B over $BW_DT ticks: shared store $BW_E0 -> $DNETWORK (+$BW_DE FE)"
[ "$BW_DT" -ge 12 ] || fail "only $BW_DT ticks passed; the rate window is too small"
[ "$BW_DE" -gt 0 ] || fail "an insert into cell A never reached cell B: +$BW_DE over $BW_DT ticks"
[ "$BW_DE" = $((1250 * BW_DT)) ] \
    || fail "cell B rose $BW_DE FE over $BW_DT ticks, expected 1250 x $BW_DT = $((1250 * BW_DT)): the artefact's simple per-side rate is 1,250, not the generator's 2,000"
if [ "$SELFTEST_DIM" = 1 ]; then
    echo "(selftest: asserting the normal tier's 5,000 per-side rate on the simple pair)"
    [ "$BW_DE" = $((5000 * BW_DT)) ] \
        || fail "selftest: the shared store rose $BW_DE over $BW_DT ticks (1,250 a tick), so asserting 5,000 a tick fails — the assertion is alive"
fi
dim_cell_state "$SX" 101 212
[ "$DNETWORK" = 0 ] || fail "the unlinked differential changed store: $DNETWORK (expected 0)"
echo "  the link crosses four blocks: 1,250 FE a tick from two replies' own t= values; the unlinked cell stays empty"

echo "== DD: an OUTPUT face pushes the pool into a neighbour at the same per-side rate =="
# The generator may refuse a setblock while its block entity is loaded; closing cell A's INPUT face
# is the reliable way to stop its 2,000-a-tick push, so only the OUTPUT face feeds the receiver.
dim_side_set "$SX" 101 204 west none
ctl command "execute in minecraft:the_end run setblock $((SX - 1)) 101 204 minecraft:air" >/dev/null
ctl wait 6 >/dev/null
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 208 minecraft:air" >/dev/null
ctl command "execute in minecraft:the_end run setblock $((SX + 1)) 101 208 $BIG_RECEIVER" >/dev/null
ctl wait 6 >/dev/null
[ "$(block_name "$((SX + 1))" 101 208)" = "$BIG_RECEIVER" ] \
    || fail "the harness receiver did not place east of cell B"
dim_side_set "$SX" 101 208 east output
ctl wait 2 >/dev/null
dim_cell_state "$SX" 101 204
BX_T0=$DT; BX_E0=$DNETWORK
# A fresh receiver has no `energy` NBT key yet, so its initial store is exactly 0; asking
# /data get for a missing key answers "Found no elements matching energy" instead of 0.
BX_R0=0
ctl wait 16 >/dev/null
dim_cell_state "$SX" 101 204
BX_DT=$((DT - BX_T0)); BX_DE=$((BX_E0 - DNETWORK))
BX_R1=$(energy_of "$((SX + 1))" 101 208)
echo "  over $BX_DT ticks: the pool fell $BX_DE FE and the receiver gained $((BX_R1 - BX_R0))"
[ "$BX_DT" -ge 8 ] || fail "the output window is only $BX_DT ticks"
[ "$BX_DE" = $((1250 * BX_DT)) ] \
    || fail "the OUTPUT face moved $BX_DE FE over $BX_DT ticks, expected 1250 x $BX_DT"
[ $((BX_R1 - BX_R0)) -gt 0 ] \
    || fail "the OUTPUT face never reached the receiver: it still holds $((BX_R1 - BX_R0)) FE"
echo "  OUTPUT moves the artefact's 1,250 FE a side a tick out of the shared pool"

echo "== DE: the card's plain recipe crafts and consumes; the cell recipes need the parent =="
ctl command "gamemode creative" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 4 >/dev/null
open_crafting_table "$SX" 101 214
for item in minecraft:gold_nugget minecraft:paper minecraft:redstone; do
    ctl command "give @s $item 16" >/dev/null
done
ctl wait 10 >/dev/null
# rgr / gpg / rgr
place_one minecraft:redstone 100
place_one minecraft:gold_nugget 101
place_one minecraft:redstone 102
place_one minecraft:gold_nugget 103
place_one minecraft:paper 104
place_one minecraft:gold_nugget 105
place_one minecraft:redstone 106
place_one minecraft:gold_nugget 107
place_one minecraft:redstone 108
RESULT=$(ctl screen | jq -r '[.slots[]? | select(.slot == 200) | .item] | first // "empty"')
[ "$RESULT" = "$DIM_CARD_ITEM" ] \
    || fail "the card's plain vanilla recipe crafted '$RESULT', expected $DIM_CARD_ITEM"
ctl click-slot 200 >/dev/null
ctl wait 3 >/dev/null
# Slot 200 lands the result on the cursor; slot 8 is where the other recipes park their output.
ctl click-slot 8 >/dev/null
ctl wait 6 >/dev/null
[ "$(held_count "$DIM_CARD_ITEM")" -ge 1 ] \
    || fail "the crafted card never reached the inventory: $(ctl screen | jq -c '[.slots[]? | select(.item != null) | {slot, item, count}]')"
[ "$(held_count minecraft:gold_nugget)" = 12 ] \
    || fail "the craft did not consume four gold nuggets: $(held_count minecraft:gold_nugget) left"
[ "$(held_count minecraft:paper)" = 15 ] \
    || fail "the craft did not consume one paper: $(held_count minecraft:paper) left"
[ "$(held_count minecraft:redstone)" = 12 ] \
    || fail "the craft did not consume four redstone: $(held_count minecraft:redstone) left"
echo "  the card crafts from 4 gold nuggets, 1 paper and 4 redstone, and the ingredients were consumed"
# The cell recipes centre on rftoolsbase:machine_frame / infused_diamond, which this build lacks.
ctl command "clear @s" >/dev/null
for item in "$STONE" minecraft:prismarine_shard minecraft:diamond minecraft:redstone_block minecraft:emerald; do
    ctl command "give @s $item 16" >/dev/null
done
ctl wait 10 >/dev/null
place_one "$STONE" 100
place_one minecraft:diamond 101
place_one minecraft:redstone_block 102
place_one minecraft:prismarine_shard 103
place_one "$STONE" 104
place_one minecraft:prismarine_shard 105
place_one minecraft:redstone_block 106
place_one minecraft:diamond 107
place_one minecraft:redstone_block 108
RESULT=$(ctl screen | jq -r '[.slots[]? | select(.slot == 200) | .item] | first // "empty"')
[ "$RESULT" = empty ] \
    || fail "a dimensional cell crafted as '$RESULT' without the parent's machine_frame"
ctl close >/dev/null 2>&1 || true
echo "  the three cell recipes are carried as blocked(parent-absent): no machine frame, no craft"
}

if [ "$SELFTEST_DIM" = 1 ]; then
    dimensionalcell_phases
    fail "selftest: the dimensionalcell inversion did not fail"
elif [ "$SELFTEST_ENDERFACTOR" = 1 ]; then
    enderfactor_phases
    fail "selftest: the enderfactor inversion did not fail"
else
    cell3_phases
    chargeitem_phases
    infusable_phases
    enderfactor_phases
    dimensionalcell_phases
fi

echo "PASS: the endergenic generator's infusion carrier was accepted in its own slot (infused=256 factor=1.000), a mode-1 pearl paid the artefact's 300 FE (rfPerHit[1] x 2 x (1+2)/2, not the prose's 600), a held pearl spent 333 FE a tick ((long)(500 x (3-1)/3)) from two replies' own game-time stamps, and a stone in the slot was refused and kept server-side. Earlier: the coal generator's infusion carrier raised its burn to 750 ticks (600 + (int)(600*0.5/2)) and its rate to 90 FE a tick (60 + (long)(60*0.5)), the two info replies' own t=/energy=/burn= closing ΔE == 90 × Δburn, while the un-infused generator gave 60 × Δburn and a 600-tick burn and a stone in the infusion slot was refused and stayed server-side. Earlier: the coal generator's charge slot inserted exactly 1,000 FE a tick into a powercell item's own energy component, the two info replies' t= closing the rate, and the store fell by exactly what the item gained; a stone in that slot was refused and kept on the server. Earlier: a blazing infuser spends one catalyst and 10 FE a run on the 11th tick after its counter resets (the field is 10, the period 11 — two replies' counters close it exactly), raising the rod's quality by the catalyst's percentage of a whole 64-step stack (a nether star +1,125 on a 60,000-quality rod, redstone +375 quality and no duration), moving it to the output slot on its last step, costing exactly one catalyst and 10 of its 50,000 FE a run (a hopper-fed window proved one run every 11 ticks over several runs), infusing nothing without a catalyst, and refusing a stone; its recipe needs the parent's dimensional shard and machine frame. Earlier: a blazing agitator is a 3x3 box of blazing rods whose quality and duration climb by the square of a factor built from the neighbouring rods and whose clocks run down — three rods in a row rose 0.5176/0.5523/0.5176 a tick (the artefact's 0.2275/0.235/0.2275 adjacency factors, not a factor of 1), matched the single-precision fold of the whole box to four decimals over the window the two replies named, spent exactly 10 FE a tick of the 50,000 buffer, took exactly 100 FE a tick from a neighbour, moved finished rods to one of nine output slots unless their slot was locked, converted a plain blaze rod, refused an already-infused one and a stone, carried an agitated rod's component out through a hopper, and kept its store, locks and rods across a relaunch; its recipe needs the parent's machine frame and the absent #c:rods/blaze tag. Earlier: a blazing generator is four rod slots whose rates each climb the artefact's 1/150th-of-the-gap curve onto a 60 FE a tick ceiling over a 1,000,000 FE store — the rate over the window two replies named matched the single-precision fold to six decimals, a rod at its ceiling raised the store by exactly 60 FE per game tick, the 400-tick rod emptied its slot at its 400th tick and the rate decayed a 30th of the gap a tick until working fell and the store stopped, a doctored 999,995 FE generator clamped at 1,000,000 while still burning, the store pushed its whole 100,000 FE into a neighbour with no reserve, the rod's rftoolspower:blazing_rod_data component survived the give and the game read it back, the store and the rods survived a relaunch, a stone was refused as a rod, and the carried recipe needs the parent's machine frame. Earlier: a power level is a 0..9 redstone reading of the block it faces — at 250,000 of 500,000 FE its display face's wire read power=5 (stored * 10 / capacity, not the brief's 4), at 0 FE it read 0, at a full store it clamped to 9, the mirror state and the readout agreed, and a wire on another face stayed 0; the powerlevel refusal and the recipe's missing parent are parsed. Earlier: an ender monitor is a one-tick redstone pulse for the one generator event its mode names — the pearl's arrival lit its display face's output and a lamp beside it for exactly one sampled tick and cleared, the same shot left it silent once its mode was set to 'lost', a pearl lost at an idle destination pulsed both the 'arrived' and the 'lost' monitors, a monitor whose display points at the generator never pulsed, the modes and counters survive a relaunch, the endermonitor refusals parse, and its recipe needs the parent's machine base. Earlier: the endergenic pair fires a pearl across a 2-tick link and the destination pays rfPerHit[mode] x 2 when it lands inside the 15-tick charging window and nothing when it lands at idle; a charge with no injector makes no FE; the generator pushes all but its 2,000 FE reserve; a broken endergenic carries its store; both endergenic recipes need the parent machine frame; the enderlink refusals parse; the store and the link survive a relaunch. Earlier: a fresh cell1 is empty with six NONE faces; against a 100,000 FE generator it refuses the push until its west face is set INPUT, then takes exactly 250 FE a tick (tier1MaxRFPerTick) until the generator is empty, with the two stores adding up to the 100,000 seeded; a second cell1 beside it shares one network (3,000/1,000,000 in both), and a cell with a gap does not; a cell2 beside a cell1 joins the same network (5,000/4,500,000) while one with a gap stays alone (4,000,000) — the network is adjacency, not tier; an OUTPUT face pushes 250 FE a tick into a neighbour with nothing created or lost; the store and the face modes survive save and relaunch; a broken cell carries its own store and placing it gives it back; the power core's recipe crafts once and consumes its diamond, redstone block and three redstones, while cell1's recipe crafts nothing without the parent's machine frame; and the side command's bad face, bad mode and no-cell refusals parse as replies"
