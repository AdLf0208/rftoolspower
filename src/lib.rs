//! RFTools Power — six machines, as one `impl Hooks` at the crate root.
//!
//! The carried content is this package's own `assets/` and `data/` (`rftoolspower:coalgenerator`,
//! `power_monitor`, `cell1`/`cell2`, `endergenic`, `pearl_injector`, `ender_monitor`,
//! `blazing_generator`, `blazing_agitator`, `blazing_infuser` and their items, models and
//! recipes); the behaviour is [`support`]:
//!
//! - a [`BlockEntityPart`] on the coal generator ticks it on the server, mirrors the burn into the
//!   block's `lit` state, takes fuel from its one slot, declares the 500,000 FE buffer through the
//!   energy capability and pushes 2,000 FE a tick into its neighbours;
//! - the power monitor reads the block it is mounted on every 20 ticks, writes a 0..5 `level` and
//!   an alarm into its `lit` state, and gives 15 on its display face inside the configured band;
//! - the power level display reads the block it is mounted on 20 ticks after placement and then
//!   every 10, and gives its 0..9 ratio (`stored * 10 / capacity`) straight on its display face;
//! - the powercells answer the energy capability with their whole adjacency network and push out
//!   of their `OUTPUT` faces;
//! - the endergenic generator runs the 15-mode charge, the pearl flight and the hit table, holds a
//!   landed pearl for 500 FE a tick, and notifies the ender monitors around it; the pearl injector
//!   fires one pearl a rising edge at the generator it points at;
//! - the ender monitor arms on the one event its mode names and answers 15 for exactly one tick.
//! - the blazing generator ramps each rod slot's rate a 150th of the gap to its own quality
//!   ceiling; the blazing agitator's 3×3 box mutates rods it holds — their quality and duration
//!   climb by the square of a factor built from the neighbouring rods, their clock runs down, and
//!   a finished rod moves to one of nine output slots unless its slot is locked; the blazing
//!   infuser spends one catalyst and 10 FE per run (on the 11th tick and then every 11) to raise a
//!   rod's quality and duration by the catalyst's percentage of a whole 64-step stack, and moves
//!   the rod to its output slot when its last step is used.
//!
//! `/rftoolspower info|monitor|powerlevel|band|cell|side|endergenic|injector|enderlink|endermonitor|blazing|agitator|agitatelock|infuser`
//! serves the harness and is the stand-in for the GUIs and the smart wrench this tier does not
//! carry.
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
    /// monitor's; the power level's; the two powercells' Part and network energy capability; the
    /// endergenic's Part and buffer; the injector's Part and eighteen pearl slots; the ender
    /// monitor's Part; and the blazing generator's, agitator's and infuser's Parts, slots and
    /// buffers.
    fn register(&self, r: &mut dyn Registrar, context: &RegistrationContext) {
        support::declare(r, context);
    }

    /// `/rftoolspower info|monitor|powerlevel|band|cell|side|endergenic|injector|enderlink|endermonitor|blazing|agitator|agitatelock|infuser …`.
    fn register_commands(&self, _host: &mut dyn ServerHost, event: &mut RegisterCommandsEvent<'_>) {
        support::declare_commands(event.commands);
    }

    /// The mod's own item component: a blazing rod's `{steps, time, quality, duration}`
    /// (upstream's `BlazingModule.ITEM_BLAZING_ROD_DATA`). Registered before content loads; the
    /// game installs the name, so a `/give` carrying it lands in the stack's patch.
    fn component_types(
        &self,
        _cx: &RegistrationContext,
        event: &mut mod_api::ComponentTypesEvent<'_>,
    ) {
        support::declare_component(event.types);
    }

    /// Run the `/rftoolspower` commands a player types.
    fn run_mod_command(
        &self,
        host: &mut dyn ServerHost,
        event: &mut mod_api::RunModCommandEvent<'_>,
    ) -> Flow {
        support::run_command(host, event)
    }

    /// A click on the blazing generator, the blazing agitator or the blazing infuser never uses
    /// the held item (upstream opens a GUI): the click takes a rod (or, in the infuser, a
    /// catalyst) or refuses the item, and a block in the hand is not placed against the machine.
    fn right_click_block(
        &self,
        host: mod_api::HostSide<'_>,
        event: &mut mod_api::RightClickBlockEvent<'_>,
    ) -> Flow {
        support::on_right_click_block(host, event)
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
