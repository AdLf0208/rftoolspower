# RFTools Power for Horizon — the Coal Generator, the Power Monitor, the Power Level, the
# Powercell, the Endergenic, the Ender Monitor, the Blazing Generator, Agitator and Infuser, and
# the Dimensional Cell

A Horizon port of [RFTools Power](https://github.com/McJtyMods/RFToolsPower) 1.21-7.0.6
(Minecraft Java 1.21.1 NeoForge), rewritten for Horizon 26.3 at the campaign pin
`0a875da91dbb0fdcb7ba8c42c11341aa229af51a` / horizon-mixins `e59da909…`. Package **0.1.13**.

Ten families so far (slice 14 adds the dimensional cell):

**The Coal Generator** (slice 1)

- burns `minecraft:coal` or `minecraft:charcoal` for **600 ticks** each — a **coal block** for
  5,400 — at **60 FE a tick** (36,000 FE a coal) into a **500,000 FE** buffer;
- lights its own front (`lit`) while it burns and goes dark the moment the fuel runs out;
- takes fuel from its input slot (a hopper feeds it, or a right click puts the held fuel in);
- charges an **energy item in its second slot at 1,000 FE a tick** out of its own store (upstream's
  `handleChargingItem`); a powercell item is such an energy item, carrying its FE in the same
  `minecraft:block_entity_data` store the block reads;
- takes an **infusion carrier in its third slot**: an int 0–256 component (`rftoolspower:infusable_data`,
  this port's stand-in for McJtyLib's `ITEM_INFUSABLE`) raises the rate to `60 + (long)(60 × factor)`
  FE a tick and the burn to `600 + (int)(600 × factor / 2)` ticks, exactly upstream's float rules;
- gives up to **2,000 FE an extract** through the energy capability on every face, and **pushes
  2,000 FE a tick into each adjacent energy block** (upstream's `handleSendingEnergy`);
- keeps its store on its own item when broken, and clamps a doctored item back to the capacity;
- reads out through `/rftoolspower info <pos>` for the harness.

**The Power Monitor** (slice 2)

- reads the block **behind its display front** every **20 ticks** through the energy capability;
- shows the charge as the `level` state 0–5 (upstream's `1 + stored*5/capacity`, 0 when the block
  is not an energy block);
- gives a **redstone alarm** (15) on its display face while the charge is inside a percentage
  band, and mirrors it into `lit`;
- keeps its band on its own item when broken;
- reads and sets the band through `/rftoolspower monitor <pos>` and
  `/rftoolspower band <pos> <min> <max>` — the harness's stand-in for upstream's GUI sliders.

**The Powercell** (slice 3 `cell1`/`cell2`, slice 10 `cell3`)

- stores **500,000 FE** (tier 1) / **4,000,000 FE** (tier 2) / **20,000,000 FE** (tier 3) per cell;
- has six face modes — `NONE` (a fresh cell, all six), `INPUT`, `OUTPUT` — and moves at most
  **250 / 1,000 / 4,000 FE a tick a side**, plus 25 % of that per extra cell in its network
  (a pair of tier-3 cells moves 5,000 a side);
- shares one store and one capacity with **every adjacent powercell, of any tier** (upstream's
  `PowerCellNetwork` has no tier test): the capability answers the network's total, an insert fills
  the cell asked first, and a cell with an `OUTPUT` face pushes the network's FE out;
- keeps its own store on its item when broken;
- reads out through `/rftoolspower cell <pos>` and sets a face with
  `/rftoolspower side <pos> <face> NONE|INPUT|OUTPUT` — the harness's stand-in for the smart wrench
  the parent port does not carry.

**The Endergenic Generator and the Pearl Injector** (slice 4)

- two linked generators: a **rising redstone edge** starts a 15-mode charge on one, and the pearl
  injector fires a pearl from the other into it;
- a pearl that lands **inside the charging window** pays `rfPerHit[mode] × 2` — **200 FE** at mode 1
  up to **25,600 FE** at mode 10 — plus up to a **doubling** for its age; one that lands while the
  generator is idle is **lost** and pays nothing;
- a landed pearl is held for **500 FE a tick** and fired again on the next pulse (slice 13 adds an
  **infusion carrier** in the generator's own slot: a factor 0…1 scales the gain by `(factor+2)/2`
  — **300 FE** at mode 1 at full infusion — and the hold by `(3−factor)/3` — **333 FE a tick**);
- the buffer is **5,000,000 FE** and pushes out up to **20,000 FE a tick**, keeping a **2,000 FE**
  reserve to hold pearls with;
- a link is a **2-tick flight** for a three-block gap, the injector holds **18 pearls**, and the
  smart wrench's link is `/rftoolspower enderlink <pos> <dest>`.

**The Ender Monitor** (slice 5)

- watches **one** of the generator's three events — a lost pearl, a launch, an arrival — chosen by
  its mode (the item carries it; the command sets it);
- answers the event it watches with **15 on its display face for exactly one tick**, and its `lit`
  state mirrors that tick;
- keeps its mode on its own item when broken;
- reads and sets the mode through
  `/rftoolspower endermonitor <pos> status|MODE [nonce]` — the harness's stand-in for upstream's
  GUI picker.

**The Power Level** (slice 6)

- reads the block **behind its display front** 20 ticks after placement and then every **10
  ticks** through the energy capability;
- shows the charge as its **redstone output**, `stored * 10 / capacity` clamped to **0–9** (so
  250,000 of 500,000 FE is **5** and a full store clamps to 9), on its display face only;
- mirrors the ratio into its `power` state (the output's carrier at this pin) and reads out through
  `/rftoolspower powerlevel <pos> [nonce]` — the harness's stand-in for upstream's renderer.

**The Blazing Generator and the Blazing Rod** (slice 7)

- four rod slots; each rod **climbs** to its own ceiling — a 60,000-quality rod is **60 FE a tick**
  — by **a 150th of the gap plus 0.01 a tick**, and its burn counts down from the rod's `duration`;
- the buffer is **1,000,000 FE** and the generator **pushes 20,000 FE a tick into each neighbour**
  with no reserve;
- the rod's whole state — `quality`, `duration`, the agitator's `time` and the infuser's `steps` —
  is the mod's own **`rftoolspower:blazing_rod_data` item component**, written back as the rod
  burns and read by the generator;
- `working` mirrors the tick's own total into the block state, and the block's front faces its
  placer;
- a click puts a rod in the first free slot, anything else is refused, and the held item never
  acts on the machine (upstream opens its GUI there);
- reads out through `/rftoolspower blazing <pos> [nonce]`.

**The Blazing Agitator** (slice 8)

- a **3×3 box** of rods plus **nine output slots**; a click puts a rod in the first empty input slot
  and a plain blaze rod is converted to a blazing rod on the next tick;
- each rod's **quality and duration climb by the square of a factor built from its neighbours** —
  `quality += adjacency² × 10`, `duration += adjacency²`, `time -= adjacency/5` — with `−0.03` for
  every neighbour that is empty or outside the box, so a lone rod's factor is **0.22** and a full
  box's centre is **0.25** (never 1);
- a finished rod moves to the first free output slot unless its slot is **locked**
  (`/rftoolspower agitatelock <pos> <slot> on|off`);
- the buffer is **50,000 FE**, takes **100 FE a tick** through the energy capability and spends
  **10 a tick** while it runs;
- reads out through `/rftoolspower agitator <pos> [nonce]`.

**The Blazing Infuser** (slice 9)

- three slots — the rod in, the rod out, one catalyst — and a **50,000 FE** buffer that takes
  **100 FE a tick**;
- a run happens on the **11th tick and then every 11** (the `counter` field is 10, but the tick
  decrements it first and compares with zero) and costs **10 FE** plus **one catalyst item**;
- the catalyst raises the rod's **quality and duration** by its percentage of a whole **64-step
  stack**: nether star **+120 %** (`quality = 60,000 → 61,125`), redstone **+40 % quality only**,
  glowstone dust 10/30, quartz 0/40, dimensional shard 60/60, ghast tear 80/80;
- each run spends one **`steps`** and the last one moves the rod to the output slot (a busy output
  keeps it until there is room);
- a click puts a rod in the input slot or a catalyst in its slot, anything else is refused, and the
  held item never acts on the machine;
- reads out through `/rftoolspower infuser <pos> [nonce]`.

**The Dimensional Cell** (slice 14)

- four tiers: **250,000 / 1,000,000 / 4,000,000 FE** (simple / normal / advanced, creative shares
  the advanced numbers) and **1,250 / 5,000 / 20,000 FE a side a tick** — the artefact's
  `rfPerNormalCell`, `simpleFactor` and `advancedFactor`, not the powercell's numbers;
- six faces default to `NONE`, take FE only through an `INPUT` face and push through an `OUTPUT`
  face (`/rftoolspower dimside <pos> <face> NONE|INPUT|OUTPUT`);
- a **powercell card** carries the channel as this package's typed
  `rftoolspower:powercard_data={id:N}` component; clicking a linked card into a cell joins it to
  every other cell with the same id, near or far, so they read **one store and one summed capacity**;
- reads out through `/rftoolspower dimcell <pos> [nonce]`; the card's own id is read with
  `/rftoolspower card [nonce]`. The three cell recipes need the parent's machine frame or infused
  diamond and craft nothing in this build; the card's purely vanilla recipe does craft.

## Build

```sh
horizon-launcher native-build ports/rftoolspower --instance <instance> --trust-native-code
```

The package is one flat `.hmod` (mod API `0.2`): `horizon-mod.toml`, `Cargo.toml`, `src/`,
`assets/`, `data/`. `horizon-mod-api` comes from the pinned SDK in `.horizon/sdk/` and is never
packed.

## Layout

| Path | What |
|---|---|
| `src/runtime.rs` | the pure rules (fuel, burn, FE, clamps, restore, the monitor's ratio/band/counter, the power level's 0–9 ratio/cadence, the cell's tiers/faces/network/budgets, the endergenic's window/table/flight/hold, the ender monitor's mode gate and one-tick pulse, the blazing generator's rod/ramp/burn and its 1,000,000 FE clamp, the agitator's adjacency algorithm and locks, the infuser's 11-tick counter/catalyst table/steps) with their unit tests |
| `src/support.rs` | the glue: every block entity Part, the container and buffer declarations, the ticks, the clicks, the drops, the redstone, the `fireMonitors` notice, the blazing rod's item component and the commands |
| `src/lib.rs` | the one `impl mod_api::Hooks` |
| `assets/`, `data/` | the carried content, built by `tools/assemble_content.py` |
| `tools/e2e.sh` | the in-game leg (phases A–BS, BT–BW and DA–DE) |
| `tools/build-e2e-game.sh`, `tools/harness-receiver/` | the e2e-only energy receiver the push is proven against (never in the `.hmod`) |
| `notes.md` | the slices, the evidence, the gaps |
| `FINDINGS.md` | the upstream behaviour extracted (analysis only) |
| `CONTENT.md` | what is carried, and what 26.3 forces to change |
| `VALIDATION.md` | the ladder and in-game record |

## Licence

MIT, from the mod's own `neoforge.mods.toml`; the full text is in `LICENSE`. The three machine base
textures carried in this package come from the RFToolsBase jar (also MIT) — see
`LICENSE-NOTICE.md`. This is a clean-room rewrite from observed behaviour: no Java was copied or
translated and no jar was decompiled.
