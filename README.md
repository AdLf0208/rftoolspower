# RFTools Power for Horizon — slice 1: the Coal Generator

A Horizon port of [RFTools Power](https://github.com/McJtyMods/RFToolsPower) 1.21-7.0.6
(Minecraft Java 1.21.1 NeoForge), rewritten for Horizon 26.3 at the campaign pin
`0a875da91dbb0fdcb7ba8c42c11341aa229af51a` / horizon-mixins `e59da909…`.

This slice is the mod's **Coal Generator**:

- burns `minecraft:coal` or `minecraft:charcoal` for **600 ticks** each — a **coal block** for
  5,400 — at **60 FE a tick** (36,000 FE a coal) into a **500,000 FE** buffer;
- lights its own front (`lit`) while it burns and goes dark the moment the fuel runs out;
- takes fuel from its input slot (a hopper feeds it, or a right click puts the held fuel in);
- stores its FE in the block entity and gives up to **2,000 FE an extract** through the energy
  capability on every face;
- keeps its store on its own item when broken, so a moved generator is not a loss — and clamps a
  doctored item back to the capacity when it is placed;
- reads out through `/rftoolspower info <pos>` for the harness.

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
| `src/runtime.rs` | the pure rules (fuel, burn, FE, clamps, restore) with their unit tests |
| `src/support.rs` | the glue: the block entity Part, the container and buffer declarations, the tick, the click, the drop, the command |
| `src/lib.rs` | the one `impl mod_api::Hooks` |
| `assets/`, `data/` | the carried content, built by `tools/assemble_content.py` |
| `tools/e2e.sh` | the in-game leg (phases A–M) |
| `notes.md` | the slice, the evidence, the gaps |
| `FINDINGS.md` | the upstream behaviour extracted (analysis only) |
| `CONTENT.md` | what is carried, and what 26.3 forces to change |
| `VALIDATION.md` | the ladder and in-game record |

## Licence

MIT, from the mod's own `neoforge.mods.toml`; the full text is in `LICENSE`. The three machine base
textures carried in this package come from the RFToolsBase jar (also MIT) — see
`LICENSE-NOTICE.md`. This is a clean-room rewrite from observed behaviour: no Java was copied or
translated and no jar was decompiled.
