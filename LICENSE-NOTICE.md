# Licence notice — RFTools Power for Horizon

The code and content of this package are a clean-room rewrite of **RFTools Power 1.21-7.0.6**,
whose `neoforge.mods.toml` declares:

    license="MIT License https://github.com/McJtyMods/RFToolsPower/blob/1.21_neo/LICENCE"

The text at that path (`Copyright (c) 2019 McJtyMods`) is in [`LICENSE`](LICENSE), together with
the Horizon port authors' line. That is the licence this package is offered under.

## Art carried from a second MIT jar

`assets/rftoolspower/textures/block/base/{machineside,machinebottom,machinetop}.png` are the three
machine base textures the generator's own block model names. Upstream keeps them in
**RFToolsBase** (`rftoolsbase-1.21-6.0.11.jar`, SHA-256 `5195ba53…4b00`), which declares
`license="MIT License …/LICENCE"` in the same form — the same license family and copyright holder
(McJtyMods). They are copied into this package's namespace because a Horizon package must stand
alone (one `.hmod`, no second content package); the model is re-pointed to match. No other file in
this package comes from that jar.

Every other carried file — the blockstate, the two block models, the item model, the front texture,
the recipe, the loot table, the advancement and the lang lines — comes from the RFTools Power jar
itself.

## Provenance of the code

`src/` was written from the mod's observed behaviour and its public repository (branch `1.21_neo`,
commit `e44463ca…`), as recorded in `FINDINGS.md`. No Java source was copied or translated, and no
jar was decompiled.
