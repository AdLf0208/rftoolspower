//! RFTools Power — five machines, as one `impl Hooks` at the crate root.
//!
//! The carried content is this package's own `assets/` and `data/` (`rftoolspower:coalgenerator`,
//! `power_monitor`, `cell1`/`cell2`, `endergenic`, `pearl_injector`, `ender_monitor` and their
//! items, models and recipes); the behaviour is [`support`]:
//!
//! - a [`BlockEntityPart`] on the coal generator ticks it on the server, mirrors the burn into the
//!   block's `lit` state, takes fuel from its one slot, declares the 500,000 FE buffer through the
//!   energy capability and pushes 2,000 FE a tick into its neighbours;
//! - the power monitor reads the block it is mounted on every 20 ticks, writes a 0..5 `level` and
//!   an alarm into its `lit` state, and gives 15 on its display face inside the configured band;
//! - the powercells answer the energy capability with their whole adjacency network and push out
//!   of their `OUTPUT` faces;
//! - the endergenic generator runs the 15-mode charge, the pearl flight and the hit table, holds a
//!   landed pearl for 500 FE a tick, and notifies the ender monitors around it; the pearl injector
//!   fires one pearl a rising edge at the generator it points at;
//! - the ender monitor arms on the one event its mode names and answers 15 for exactly one tick.
//!
//! `/rftoolspower info|monitor|band|cell|side|endergenic|injector|enderlink|endermonitor` serves
//! the harness and is the stand-in for the GUIs and the smart wrench this tier does not carry.
//!
//! The numbers — 60 FE a tick, 600 ticks a coal, every capacity and clamp, the `rfPerHit` table —
//! are in [`runtime`], a plain module with no `mod_api` types, so `cargo test` alone proves them.
use mod_api::{
    self, Flow, Hooks, RegisterCommandsEvent, Registrar, RegistrationContext, ServerHost,
};

pub mod runtime;
pub mod support;

#[derive(Default)]
struct Mod;

#[mod_api::horizon_mod]
impl Hooks for Mod {
    /// Declare the generator's block entity type, its Part, its one fuel slot and its buffer; the
    /// monitor's; the two powercells' Part and network energy capability; the endergenic's Part
    /// and buffer; the injector's Part and eighteen pearl slots; and the ender monitor's Part.
    fn register(&self, r: &mut dyn Registrar, context: &RegistrationContext) {
        support::declare(r, context);
    }

    /// `/rftoolspower info|monitor|band|cell|side|endergenic|injector|enderlink|endermonitor …`.
    fn register_commands(&self, _host: &mut dyn ServerHost, event: &mut RegisterCommandsEvent<'_>) {
        support::declare_commands(event.commands);
    }

    /// Run the `/rftoolspower` commands a player types.
    fn run_mod_command(
        &self,
        host: &mut dyn ServerHost,
        event: &mut mod_api::RunModCommandEvent<'_>,
    ) -> Flow {
        support::run_command(host, event)
    }

    /// A broken machine's own item carries what upstream's loot copies: the generator's store and
    /// fuel bookkeeping, a monitor's band, an endergenic's store, and an ender monitor's mode.
    fn block_drops(
        &self,
        level: &dyn mod_api::LevelHost,
        event: &mut mod_api::BlockDropsEvent<'_>,
    ) -> Flow {
        support::on_block_drops(level, event)
    }
}
