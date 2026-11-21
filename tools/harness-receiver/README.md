# The e2e's energy receiver (not part of the package)

Upstream's `CoalGeneratorTileEntity.handleSendingEnergy` pushes 2,000 FE a tick into adjacent
energy handlers. The mod's own receiver — the powercell — is blocked on `rftoolsbase:smartwrench`,
and a power monitor is a display with no buffer. To prove the push in game, this folder holds a
**harness-only** native mod: one block, `rfpowerharness:receiver`, with a 100,000 FE buffer that
accepts 10,000 FE a face and gives nothing out. Its store lives in the block entity's saved
compound as the int `energy` (the game's `ModEnergyBuffer`), so the leg reads it back with
`/data get block`.

It is **never packed into `rftoolspower.hmod`**. The source is stored as `.in` files because the
launcher refuses nested package paths (`horizon-mod.toml`, `Cargo.toml`, `src/lib.rs`) inside a
mod folder; [`tools/build-e2e-game.sh`](../build-e2e-game.sh) materialises it, beside a copy of
this port, into the launcher's scratch folder and builds both mods into one game.

`python3 tools/verify-sdk-package.py rftoolspower` checks the delivered package only; nothing in
this folder is in it.
