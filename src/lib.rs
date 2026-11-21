//! RFTools Power — the coal generator, as one `impl Hooks` at the crate root.
//!
//! The carried content is this package's own `assets/` and `data/` (`rftoolspower:coalgenerator`,
//! its item, models and recipe); the behaviour is [`support`]: a [`BlockEntityPart`] on the
//! generator ticks it on the server, mirrors the burn into the block's `lit` state, takes fuel from
//! its one slot, and declares the 500,000 FE buffer through the energy capability; a click puts one
//! fuel item in the slot; `block_drops` keeps the store on the block's item; and
//! `/rftoolspower info` serves the harness.
//!
//! The numbers — the 60 FE a tick, the 600 ticks a coal, the capacity and the clamps — are in
//! [`runtime`], a plain module with no `mod_api` types, so `cargo test` alone proves them.
use mod_api::{
    self, Flow, Hooks, RegisterCommandsEvent, Registrar, RegistrationContext, ServerHost,
};

pub mod runtime;
pub mod support;

#[derive(Default)]
struct Mod;

#[mod_api::horizon_mod]
impl Hooks for Mod {
    /// Declare the generator's block entity type, its Part, its one fuel slot and its buffer.
    fn register(&self, r: &mut dyn Registrar, context: &RegistrationContext) {
        support::declare(r, context);
    }

    /// `/rftoolspower info <pos> [nonce]`.
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

    /// A broken generator's own item carries its store.
    fn block_drops(
        &self,
        level: &dyn mod_api::LevelHost,
        event: &mut mod_api::BlockDropsEvent<'_>,
    ) -> Flow {
        support::on_block_drops(level, event)
    }
}
