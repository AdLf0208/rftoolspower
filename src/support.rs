//! The coal generator's glue: its Part, the block's container and buffer declarations, the saved
//! state, the tick, the `lit` mirror, the click, the drop and the `/rftoolspower info` command.
//!
//! Every rule lives in [`crate::runtime`]; this file reads the game, calls it and writes the result
//! back. Its tests pin what it *declares* (one insert-only fuel slot, a store that gives out 2,000
//! FE a tick and takes nothing in), that the state written to the saved compound reads back, and the
//! exact line `/rftoolspower info` prints.
use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::{LazyLock, Mutex};

use mod_api::{
    self, BlockClick, BlockDropsEvent, BlockEntityEvent, BlockEntityPart, BlockEntityTickEvent,
    BlockEntityTickReply, BlockEntityTicksEvent, BlockPart, BlockSide, BlockSignalEvent,
    BlockState, Command, CommandArgumentValue, Component, Compound, Direction, ENERGY,
    EnergyHandler, Flow, Host, HostSide, HostTransaction, Identifier, InteractionResult,
    IsSignalSourceEvent, ItemPart, ItemPlace, ItemResource, ItemStack, LevelHost, LevelRef,
    LevelSide, ModContainer, ModEnergyBuffer, NeighbourUpdate, OnBlockPlacedByEvent, Registrar,
    RegistrationContext, RightClickBlockEvent, RunModCommandEvent, ServerHost,
    StateForPlacementEvent, Tag, Text, Transaction, UseItemOnEvent, UseWithoutItemEvent,
};

use crate::runtime::{
    AGITATOR_CAPACITY, AGITATOR_INSERT_PER_TICK, AGITATOR_OUTPUTS, AGITATOR_SLOTS,
    AGITATOR_USE_PER_TICK, Agitator, BLAZING_CAPACITY, BLAZING_SLOTS, Blazing, BlazingSlot,
    CAPACITY, Cell, ENDERGENIC_CAPACITY, EXTRACT_PER_TICK, EnderMonitor, Endergenic,
    FIRST_POWER_OBSERVE_TICKS, Fuel, Generator, HOLDING, IDLE, INJECTOR_SLOTS, Loss, MAX_DISTANCE,
    MONITOR_SIGNAL, Monitor, MonitorMode, NETWORK_MAX, OBSERVE_TICKS, PEARL, PowerLevel, Pulse,
    ROD_START_STEPS, Rod, RodSlot, SideMode, Sides, Tier, as_capability,
    capacity as network_capacity, clamp_agitator, clamp_blazing, clamp_endergenic, clamped_energy,
    network_valid, pearl_lost, receive as network_receive, restored, rf_per_tick, rising_edge,
    send_amount, stored as network_stored, take as network_take,
};

/// The generator block; the block entity type carries its own path.
pub(crate) const GENERATOR: &str = "rftoolspower:coalgenerator";
/// The block entity type's path: a type whose id equals its block's id makes the host skip the
/// block entity it should create, so the type is named apart from the block (`actuallyadditions`
/// measured this at the pin).
const GENERATOR_TYPE: &str = "coalgenerator_block_entity";
/// That type's registry id, which `minecraft:block_entity_data` tags its payload with
/// (`TypedEntityData.loadInto` only loads data whose `id` names the block entity it is placed as).
const GENERATOR_TYPE_ID: &str = "rftoolspower:coalgenerator_block_entity";
/// The one slot: fuel (`CoalGeneratorTileEntity.SLOT_COALINPUT`).
const FUEL_SLOT: usize = 0;
/// How many slots the container has. Upstream's second slot charges an energy item; that family
/// (and the item capability it needs) is not in this slice.
const SLOTS: usize = 1;
/// The block's `lit` property, which the `minecraft:furnace` template already declares.
const KEY_LIT: &str = "lit";
/// The saved store, under the key the energy capability reads (`ModEnergyBuffer`'s amount).
const KEY_ENERGY: &str = "energy";
/// Ticks of burn left (upstream's `CoalGeneratorData.burning`).
const KEY_BURN: &str = "burn";
/// The burn bar's denominator; not upstream's saved state, but the readout needs it.
const KEY_BURN_MAX: &str = "burn_max";
/// The vanilla component that carries a block entity's saved data on its item
/// (`BlockEntity.applyComponentsFromItemStack`).
const BLOCK_ENTITY_DATA: &str = "minecraft:block_entity_data";
/// The level `/rftoolspower info` is registered at: 2, the game master level, because it names
/// another player's machine and its contents from anywhere in the level.
const OPERATOR_LEVEL: u8 = 2;
/// What a read where no generator stands answers.
const NO_GENERATOR: &str = "No RFTools Power coal generator there.";
/// Vanilla's stack limit, for an item this world does not know.
const DEFAULT_STACK: u32 = 64;

/// The power monitor (`MonitorModule.POWER_MONITOR`).
pub(crate) const MONITOR: &str = "rftoolspower:power_monitor";
/// The monitor's block entity type, named apart from its block for the reason
/// [`GENERATOR_TYPE`] is (`actuallyadditions` measured the host skipping a same-id entity).
const MONITOR_TYPE: &str = "power_monitor_block_entity";
/// That type's registry id, which the monitor item's `block_entity_data` names.
const MONITOR_TYPE_ID: &str = "rftoolspower:power_monitor_block_entity";
/// The monitor's `level` state: upstream's `IntegerProperty.create("level", 0, 5)`.
const KEY_LEVEL: &str = "level";
/// The monitor's alarm band and flag (upstream's `PowerMonitorData` plus its `inAlarm` field).
const KEY_MINIMUM: &str = "minimum";
const KEY_MAXIMUM: &str = "maximum";
const KEY_ALARM: &str = "alarm";
/// The 20-tick observation counter (upstream's `counter` field, kept saved here because the tick
/// reply discards payload edits that are not reported as changed).
const KEY_COUNTER: &str = "counter";
/// The monitor's read side (upstream's `LogicSupport.getFacing(state).getInputSide()`).
const KEY_FACING: &str = "facing";
/// What a read where no monitor stands answers.
const NO_MONITOR: &str = "No RFTools Power power monitor there.";
/// The strongest signal a monitor's alarm gives.
const ALARM_SIGNAL: i32 = 15;

/// The power level display (`MonitorModule.POWER_LEVEL`). Its block entity type is named apart
/// from its block for the reason [`GENERATOR_TYPE`] is.
pub(crate) const POWER_LEVEL: &str = "rftoolspower:power_level";
const POWER_LEVEL_TYPE: &str = "power_level_block_entity";
/// The ratio the display mirrors into its `power` state (upstream's tile-entity field).
const KEY_POWER: &str = "power";
/// What a read where no power level stands answers.
const NO_POWER_LEVEL: &str = "No RFTools Power power level there.";

// The powercell (`PowerCellModule.CELL1`/`CELL2`). Its block entity type is named apart from its
// block for the reason [`GENERATOR_TYPE`] is; the type id is what a broken cell's payload names.
/// `rftoolspower:cell1`, the tier-1 cell (500,000 FE, 250 a side a tick).
pub(crate) const CELL1: &str = "rftoolspower:cell1";
const CELL1_TYPE: &str = "cell1_block_entity";
const CELL1_TYPE_ID: &str = "rftoolspower:cell1_block_entity";
/// `rftoolspower:cell2`, the tier-2 cell (4,000,000 FE, 1,000 a side a tick).
pub(crate) const CELL2: &str = "rftoolspower:cell2";
const CELL2_TYPE: &str = "cell2_block_entity";
const CELL2_TYPE_ID: &str = "rftoolspower:cell2_block_entity";
/// The six face modes, saved as upstream's own six-digit string (`saveClientDataToNBT`).
const KEY_MODE: &str = "mode";
/// What a read where no cell stands answers.
const NO_CELL: &str = "No RFTools Power power cell there.";

// ---------------------------------------------------------------------------
// What the mod declares for its block
// ---------------------------------------------------------------------------

/// Declare the generator: its block entity type and Part, its one fuel slot and its store
/// (upstream's `EntityBlock.newBlockEntity`, the items capability and the energy capability).
pub(crate) fn declare(r: &mut dyn Registrar, context: &RegistrationContext) {
    // The type is declared first, then every per-block capability, then the Part: that is the
    // order the pin's registrar expects (the block's declaration is what a container or a buffer
    // hangs off).
    let kind = r
        .block_entity_type(GENERATOR_TYPE)
        .blocks(&["coalgenerator"])
        .build();
    let block = r.block_key(GENERATOR);
    r.block_container(&block, generator_container());
    r.block_energy(&block, generator_battery());
    // A broken generator's item carries its store (`block_drops`) and clamps it back when placed
    // again (this Part on the block item).
    let item = r.item_key(GENERATOR);
    r.item_part(item, GeneratorItemPart);
    // `block_entity_part` attaches the Part to the type's blocks as well, so registering it with
    // `block_part` first would attach it twice and the game refuses a duplicate.
    if let Err(error) = r.block_entity_part(&kind, GeneratorPart) {
        context.refuse(&format!(
            "rftoolspower: the coal generator part was refused: {error}"
        ));
    }

    // The monitor: a block entity type, a Part and its item's Part. It has no container and no
    // energy buffer — it reads the block it faces, it is not a battery.
    let kind = r
        .block_entity_type(MONITOR_TYPE)
        .blocks(&["power_monitor"])
        .build();
    let item = r.item_key(MONITOR);
    r.item_part(item, MonitorItemPart);
    if let Err(error) = r.block_entity_part(&kind, MonitorPart) {
        context.refuse(&format!(
            "rftoolspower: the power monitor part was refused: {error}"
        ));
    }

    // The power level: a type and a Part. Like the monitor it has no container and no buffer —
    // it reads the block it faces and mirrors the ratio into its redstone output. It carries no
    // item data (upstream keeps no component on the block's item).
    let kind = r
        .block_entity_type(POWER_LEVEL_TYPE)
        .blocks(&["power_level"])
        .build();
    if let Err(error) = r.block_entity_part(&kind, PowerLevelPart) {
        context.refuse(&format!(
            "rftoolspower: the power level part was refused: {error}"
        ));
    }

    // The powercells: tier 1 and tier 2 (`cell1`/`cell2`). Each has its own block entity type and
    // its own energy capability — the faces' modes and the shared network are not the game's
    // plain buffer, so the handler is this port's.
    declare_cell(r, context, CELL1_TYPE, "cell1", CELL1, Tier::One);
    declare_cell(r, context, CELL2_TYPE, "cell2", CELL2, Tier::Two);

    // The endergenic generator: a type, the buffer the monitor reads (5,000,000 FE, nothing in or
    // out through the capability — it pushes on its own tick), its Part and its item's Part.
    let kind = r
        .block_entity_type(ENDERGENIC_TYPE)
        .blocks(&["endergenic"])
        .build();
    let block = r.block_key(ENDERGENIC);
    r.block_energy(&block, endergenic_battery());
    let item = r.item_key(ENDERGENIC);
    r.item_part(item, EndergenicItemPart);
    if let Err(error) = r.block_entity_part(&kind, EndergenicPart) {
        context.refuse(&format!(
            "rftoolspower: the endergenic generator part was refused: {error}"
        ));
    }

    // The pearl injector: a type, its eighteen pearl slots, its Part and its item's Part (the
    // placed item's saved pearls are not carried — recorded in notes.md).
    let kind = r
        .block_entity_type(INJECTOR_TYPE)
        .blocks(&["pearl_injector"])
        .build();
    let block = r.block_key(INJECTOR);
    r.block_container(&block, injector_container());
    if let Err(error) = r.block_entity_part(&kind, InjectorPart) {
        context.refuse(&format!(
            "rftoolspower: the pearl injector part was refused: {error}"
        ));
    }

    // The ender monitor: a type and a Part. It has no container and no buffer — it watches one
    // event mode of the generator it is mounted on and gives 15 for the one tick it fires.
    let kind = r
        .block_entity_type(ENDER_MONITOR_TYPE)
        .blocks(&["ender_monitor"])
        .build();
    if let Err(error) = r.block_entity_part(&kind, EnderMonitorPart) {
        context.refuse(&format!(
            "rftoolspower: the ender monitor part was refused: {error}"
        ));
    }

    // The blazing generator: a type, its four rod slots, its 1,000,000 FE buffer and its Part.
    // Its item carries nothing (upstream's loot copies only the infusable factor, which this port
    // does not carry), so there is no ItemPart. The rod is a pure item of its own.
    let kind = r
        .block_entity_type(BLAZING_TYPE)
        .blocks(&["blazing_generator"])
        .build();
    let block = r.block_key(BLAZING);
    r.block_container(&block, blazing_container());
    r.block_energy(&block, blazing_battery());
    let item = r.item_key(BLAZING);
    r.item_part(item, BlazingItemPart);
    if let Err(error) = r.block_entity_part(&kind, BlazingPart) {
        context.refuse(&format!(
            "rftoolspower: the blazing generator part was refused: {error}"
        ));
    }

    // The blazing agitator: a type, its eighteen slots (nine in, nine out), its 50,000 FE buffer
    // and its Part. Its item carries the store and the locks through `block_entity_data`.
    let kind = r
        .block_entity_type(AGITATOR_TYPE)
        .blocks(&["blazing_agitator"])
        .build();
    let block = r.block_key(AGITATOR);
    r.block_container(&block, agitator_container());
    r.block_energy(&block, agitator_battery());
    let item = r.item_key(AGITATOR);
    r.item_part(item, AgitatorItemPart);
    if let Err(error) = r.block_entity_part(&kind, AgitatorPart) {
        context.refuse(&format!(
            "rftoolspower: the blazing agitator part was refused: {error}"
        ));
    }
}

/// Declare one powercell: its block entity type, its energy capability and its Part.
fn declare_cell(
    r: &mut dyn Registrar,
    context: &RegistrationContext,
    type_name: &str,
    block_path: &str,
    block_id: &str,
    tier: Tier,
) {
    let kind = r.block_entity_type(type_name).blocks(&[block_path]).build();
    let block = r.block_key(block_id);
    // `PowerCellTileEntity.SidedHandler`: the amount and capacity are the *network's*, and only a
    // face whose mode is INPUT takes anything in. Asked with no side (upstream's NullHandler) it
    // still reads, and takes nothing.
    r.block_capability(&ENERGY, &block, |_host, at, _state, entity| {
        entity.map(|_| Box::new(CellEnergy { at }) as Box<dyn EnergyHandler>)
    });
    let item = r.item_key(block_id);
    r.item_part(item, CellItemPart);
    if let Err(error) = r.block_entity_part(&kind, CellPart { tier }) {
        context.refuse(&format!(
            "rftoolspower: the {block_path} part was refused: {error}"
        ));
    }
}

/// The generator's container: one fuel slot every face reaches, insert-only for automation.
pub(crate) fn generator_container() -> ModContainer {
    ModContainer {
        slots: SLOTS,
        faces: std::array::from_fn(|_| vec![FUEL_SLOT]),
        inputs: vec![FUEL_SLOT],
        outputs: vec![],
        menu: None,
    }
}

/// The generator's buffer: upstream's `GenericEnergyStorage(this, false, 500000, 0)` — it stores,
/// takes no FE in (it is the producer), and gives [`EXTRACT_PER_TICK`] an extract.
pub(crate) fn generator_battery() -> ModEnergyBuffer {
    ModEnergyBuffer {
        capacity: CAPACITY,
        max_insert: 0,
        max_extract: EXTRACT_PER_TICK,
        insert_faces: [false; 6],
        extract_faces: [true; 6],
    }
}

// ---------------------------------------------------------------------------
// The saved state
// ---------------------------------------------------------------------------

/// A saved int, 0 when absent or of another type.
fn int(saved: &Tag, key: &str) -> i32 {
    match saved.get(key) {
        Some(Tag::Int(value)) => *value,
        _ => 0,
    }
}

/// A saved int, `default` when absent or of another type.
fn int_or(saved: &Tag, key: &str, default: i32) -> i32 {
    match saved.get(key) {
        Some(Tag::Int(value)) => *value,
        _ => default,
    }
}

/// Write one int into a saved compound, as the energy capability and the tick read it.
fn set_int(saved: &mut Tag, key: &str, value: i32) {
    if let Tag::Compound(nbt) = saved {
        nbt.insert(key.into(), Tag::Int(value));
    }
}

/// The generator a saved compound holds, clamped (`read` of `energy`/`burn`/`burn_max`).
pub(crate) fn read_generator(saved: &Tag) -> Generator {
    restored(
        int(saved, KEY_ENERGY),
        int(saved, KEY_BURN),
        int(saved, KEY_BURN_MAX),
    )
}

/// Write the generator back into a saved compound.
pub(crate) fn write_generator(saved: &mut Tag, state: &Generator) {
    set_int(saved, KEY_ENERGY, state.energy);
    set_int(saved, KEY_BURN, state.burn as i32);
    set_int(saved, KEY_BURN_MAX, state.burn_max as i32);
}

/// A saved flag, false when absent or of another type (vanilla's NBT boolean is a byte).
fn flag(saved: &Tag, key: &str) -> bool {
    match saved.get(key) {
        Some(Tag::Byte(value)) => *value != 0,
        _ => false,
    }
}

/// Write one boolean into a saved compound as vanilla's byte.
fn set_flag(saved: &mut Tag, key: &str, value: bool) {
    if let Tag::Compound(nbt) = saved {
        nbt.insert(key.into(), Tag::Byte(i8::from(value)));
    }
}

/// The monitor a saved compound holds, with every value clamped (`Monitor::restored`).
pub(crate) fn read_monitor(saved: &Tag) -> Monitor {
    let counter = match saved.get(KEY_COUNTER) {
        Some(Tag::Int(value)) => u32::try_from(*value).unwrap_or(0),
        // A fresh block entity observes 20 ticks after placement, as upstream's field does.
        _ => OBSERVE_TICKS,
    };
    Monitor::restored(
        int(saved, KEY_LEVEL),
        int(saved, KEY_MINIMUM),
        int(saved, KEY_MAXIMUM),
        flag(saved, KEY_ALARM),
        counter,
    )
}

/// Write the monitor back into a saved compound.
pub(crate) fn write_monitor(saved: &mut Tag, state: &Monitor) {
    set_int(saved, KEY_LEVEL, state.level);
    set_int(saved, KEY_MINIMUM, state.minimum);
    set_int(saved, KEY_MAXIMUM, state.maximum);
    set_flag(saved, KEY_ALARM, state.alarm);
    set_int(saved, KEY_COUNTER, state.counter as i32);
}

/// The power level a saved compound holds, with every value clamped (`PowerLevel::restored`).
pub(crate) fn read_power_level(saved: &Tag) -> PowerLevel {
    let counter = match saved.get(KEY_COUNTER) {
        Some(Tag::Int(value)) => u32::try_from(*value).unwrap_or(0),
        // A fresh block entity observes 20 ticks after placement, as upstream's field does.
        _ => FIRST_POWER_OBSERVE_TICKS,
    };
    PowerLevel::restored(int(saved, KEY_POWER), counter)
}

/// Write the power level back into a saved compound.
pub(crate) fn write_power_level(saved: &mut Tag, state: &PowerLevel) {
    set_int(saved, KEY_POWER, state.power);
    set_int(saved, KEY_COUNTER, state.counter as i32);
}

// ---------------------------------------------------------------------------
// The readout `/rftoolspower info` prints
// ---------------------------------------------------------------------------

/// The generator's report line as `/rftoolspower info` prints it, `t` being the world time (the
/// in-game check uses it, and the nonce, to prove a reply is fresh).
pub(crate) fn generator_line(
    pos: [i32; 3],
    state: &Generator,
    fuel: Option<(&str, u32)>,
    t: i64,
    nonce: Option<&str>,
) -> String {
    let fuel = match fuel {
        Some((item, count)) => format!("{item} x{count}"),
        None => "empty".to_owned(),
    };
    let suffix = nonce.map_or(String::new(), |nonce| format!(" nonce={nonce}"));
    format!(
        "Coal Generator at {},{},{}: {}/{} FE (burning {}/{} ticks, lit {}, fuel {fuel}, \
         t={t}{suffix})",
        pos[0],
        pos[1],
        pos[2],
        state.energy,
        CAPACITY,
        state.burn,
        state.burn_max,
        state.lit(),
    )
}

// ---------------------------------------------------------------------------
// Reading the world
// ---------------------------------------------------------------------------

/// The level a block-entity tick is in: a tick is not told its level, so the one in place answers.
pub(crate) fn in_place_level(host: &dyn ServerHost) -> Option<LevelRef> {
    host.levels()
        .list_levels()
        .into_iter()
        .find(|level| level.in_place(host))
}

/// The block id at a position, `None` for an unknown block.
fn block_id(host: &dyn Host, level: LevelRef, pos: [i32; 3]) -> Option<String> {
    level.block(host, pos).map(|key| key.id(host))
}

/// The item id a stack holds.
fn item_id(host: &dyn Host, stack: &ItemStack) -> String {
    stack.item().id(host)
}

/// The block's `lit` state follows the burn. `set_block_property` writes only when it differs, so
/// the tick does not dirty a chunk that did not change.
pub(crate) fn mirror_lit(host: &mut dyn ServerHost, pos: [i32; 3], lit: bool) {
    let _ = host.set_block_property(pos, KEY_LIT, if lit { "true" } else { "false" });
}

// ---------------------------------------------------------------------------
// The tick
// ---------------------------------------------------------------------------

/// One server tick (`CoalGeneratorTileEntity.handlePowerGeneration`): take one fuel item when
/// nothing is burning, spend a tick of burn and make 60 FE, then mirror `lit`.
///
/// True when the saved state or the fuel slot changed (the tick's `BlockEntityTickReply` decides
/// whether this Part's payload edits are applied at all, so a change must say so).
pub(crate) fn tick_generator(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    pos: [i32; 3],
    saved: &mut Tag,
    items: &mut [Option<ItemStack>],
) -> bool {
    let before = read_generator(saved);
    let mut state = before.clone();
    let mut changed = false;
    // Upstream's order: push to the neighbours first, from the store the tick started with,
    // then burn and generate.
    push_energy(host, level, pos, &mut state);
    if state.wants_fuel()
        && let Some(stack) = items.get(FUEL_SLOT).and_then(Option::clone)
        && let Some(fuel) = Fuel::of(&item_id(&*host, &stack))
        && state.load(fuel)
    {
        // One item is spent; `shrink` answers `None` when that empties the stack.
        items[FUEL_SLOT] = stack.shrink(1);
        changed = true;
    }
    state.tick();
    changed |= state != before;
    write_generator(saved, &state);
    if level.is_some() {
        mirror_lit(host, pos, state.lit());
    }
    changed
}

/// `CoalGeneratorTileEntity.handleSendingEnergy`: offer up to [`EXTRACT_PER_TICK`] to each of the
/// six neighbours that answers the energy capability, and take what it accepted out of the store.
///
/// Upstream offers `SENDPERTICK` to *each* neighbour (the budget is per face, not shared) and
/// runs this before generation, from the store the tick started with; [`tick_generator`] does the
/// same. A target's own insert limit and room decide what actually moves.
pub(crate) fn push_energy(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    pos: [i32; 3],
    state: &mut Generator,
) {
    let Some(level) = level else {
        return;
    };
    for direction in Direction::ALL {
        let offer = send_amount(state.energy, EXTRACT_PER_TICK);
        if offer == 0 {
            break;
        }
        let normal = direction.normal();
        let target = [pos[0] + normal[0], pos[1] + normal[1], pos[2] + normal[2]];
        // The neighbour's face toward this generator (`facing.getOpposite()` upstream).
        let Some(handler) = level.capability(host, &ENERGY, target, Some(direction.opposite()))
        else {
            continue;
        };
        let moved = host
            .transaction(|host, tx| -> Result<u32, ()> { Ok(handler.insert(host, tx, offer)) })
            .unwrap_or(0);
        state.energy -= i32::try_from(moved).unwrap_or(0);
    }
}

// ---------------------------------------------------------------------------
// The power monitor
// ---------------------------------------------------------------------------

/// A direction's vanilla name (`facing=north`).
fn dir_name(direction: Direction) -> &'static str {
    match direction {
        Direction::Down => "down",
        Direction::Up => "up",
        Direction::North => "north",
        Direction::South => "south",
        Direction::West => "west",
        Direction::East => "east",
    }
}

/// The direction a vanilla name spells.
fn dir_from_name(name: &str) -> Option<Direction> {
    Direction::ALL
        .into_iter()
        .find(|direction| dir_name(*direction) == name)
}

/// The horizontal direction a placer's yaw faces: 0° south, 90° west, 180° north, −90° east.
///
/// The monitor's `facing` is its **display front**, set facing the placer as a furnace's is; the
/// block it monitors is the one behind it, which is upstream's logic-slab input side (a monitor
/// mounts on the machine and its screen points away from it).
pub(crate) fn facing_from_yaw(yaw: f32) -> Direction {
    match (yaw / 90.0).round().rem_euclid(4.0) as i32 {
        0 => Direction::South,
        1 => Direction::West,
        2 => Direction::North,
        _ => Direction::East,
    }
}

/// The face a monitor gives its alarm on: the display side, opposite the read side.
pub(crate) fn output_face(read: Direction) -> Direction {
    read.opposite()
}

/// The block a monitor reads (behind its display front) and the read direction.
pub(crate) fn read_target(
    host: &dyn Host,
    level: LevelRef,
    pos: [i32; 3],
) -> Option<([i32; 3], Direction)> {
    let name = level.block_property(host, pos, KEY_FACING)?;
    let read = dir_from_name(name.as_str())?.opposite();
    let normal = read.normal();
    Some((
        [pos[0] + normal[0], pos[1] + normal[1], pos[2] + normal[2]],
        read,
    ))
}

/// The store and capacity of the block at `target`, if it answers the energy capability.
pub(crate) fn energy_at(
    host: &mut dyn ServerHost,
    level: LevelRef,
    target: [i32; 3],
) -> Option<(u32, u32)> {
    let handler = level.capability(host, &ENERGY, target, None)?;
    Some((handler.amount(&mut *host), handler.capacity(&mut *host)))
}

/// Mirror the monitor's level and alarm into its block state, and let the neighbours re-read the
/// redstone output when it changed (a lamp on the display side must light at once).
pub(crate) fn mirror_monitor(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    state: &Monitor,
) {
    let _ = host.set_block_property(pos, KEY_LEVEL, &state.level.to_string());
    let _ = host.set_block_property(pos, KEY_LIT, if state.alarm { "true" } else { "false" });
    if let Some(source) = level.block_state(&*host, pos) {
        let _ = level.update_neighbors(host, pos, source, NeighbourUpdate::Neighbours);
    }
}

/// One monitor tick (`PowerMonitorTileEntity.tickServer`): count the 20 ticks down, then read the
/// block it faces and set its level and alarm. True when the saved state moved.
pub(crate) fn tick_monitor(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    pos: [i32; 3],
    saved: &mut Tag,
) -> bool {
    let before = read_monitor(saved);
    let mut state = before.clone();
    let due = state.tick();
    if due {
        // A tick is only asked in the level in place; if none answers (shutdown), keep the last
        // reading rather than treating the monitor as facing nothing.
        if let Some(level) = level {
            let observed = read_target(&*host, level, pos)
                .and_then(|(target, _read)| energy_at(host, level, target));
            state.observe(observed);
        }
    }
    let changed = state != before;
    if changed {
        write_monitor(saved, &state);
        if let Some(level) = level {
            mirror_monitor(host, level, pos, &state);
        }
    }
    changed
}

/// A state decoded for `block_signal`, cached by ordinal: a state's properties never change.
#[derive(Clone, Copy)]
struct MonitorFace {
    read: Direction,
    alarm: bool,
}

static MONITOR_FACES: LazyLock<Mutex<HashMap<BlockState, MonitorFace>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Decode a serialized monitor state into its display face and alarm
/// (`rftoolspower:power_monitor[facing=east,level=3,lit=true]`).
pub(crate) fn parse_monitor_state(text: &str) -> Option<(Direction, bool)> {
    let (block, rest) = text.split_once('[')?;
    if block != MONITOR {
        return None;
    }
    let mut read = None;
    let mut alarm = false;
    for property in rest.strip_suffix(']')?.split(',') {
        let (key, value) = property.split_once('=')?;
        match key {
            KEY_FACING => read = Some(dir_from_name(value)?),
            KEY_LIT => alarm = value == "true",
            _ => {}
        }
    }
    Some((read?, alarm))
}

/// The decoded state, through the cache `block_signal` (asked very often) reads.
fn monitor_face(level: &dyn LevelHost, state: BlockState) -> Option<MonitorFace> {
    if let Some(hit) = MONITOR_FACES
        .lock()
        .expect("the monitor state cache is never held across a panic")
        .get(&state)
    {
        return Some(*hit);
    }
    // The state's `facing` is the display front; the block read is behind it, and the alarm
    // leaves through the display, so the read side is its opposite.
    let (display, alarm) = parse_monitor_state(&level.state_string(state)?)?;
    let face = MonitorFace {
        read: display.opposite(),
        alarm,
    };
    MONITOR_FACES
        .lock()
        .expect("the monitor state cache is never held across a panic")
        .insert(state, face);
    Some(face)
}

/// `block_signal`: the alarm's 15 on the display side while it holds, nothing anywhere else.
///
/// Upstream answers only `getSignal` (weak) and leaves `getDirectSignal` at 0; so does this.
pub(crate) fn monitor_signal(level: &dyn LevelHost, event: &mut BlockSignalEvent) {
    if event.direct {
        return;
    }
    let Some(face) = monitor_face(level, event.state) else {
        return;
    };
    if face.alarm && event.face == output_face(face.read) {
        event.signal = ALARM_SIGNAL;
    }
}

/// `is_signal_source`: a monitor answers the signal query, so redstone wire connects to it.
pub(crate) fn monitor_signal_source(level: &dyn LevelHost, event: &mut IsSignalSourceEvent) {
    if level.state_block(event.state) == Some(MONITOR) {
        event.source = true;
    }
}

/// `LogicSlabBlock.getStateForPlacement`: the placer's look is the monitor's read side.
pub(crate) fn monitor_placement(
    level: &dyn LevelHost,
    event: &StateForPlacementEvent<'_>,
) -> Option<Option<BlockState>> {
    if level.state_block(event.state) != Some(MONITOR) {
        return None;
    }
    let read = facing_from_yaw(event.context.yaw);
    Some(level.state_with_property(event.state, KEY_FACING, dir_name(read)))
}

/// The monitor's report line, as `/rftoolspower monitor` and a click print it.
pub(crate) fn monitor_line(
    pos: [i32; 3],
    state: &Monitor,
    target: Option<(&str, Option<(u32, u32)>)>,
    t: i64,
    nonce: Option<&str>,
) -> String {
    let band = if Monitor::band_set(state.minimum, state.maximum) {
        format!("{}..{}", state.minimum, state.maximum)
    } else {
        format!("{}..{} (unset)", state.minimum, state.maximum)
    };
    let target = match target {
        Some((id, Some((stored, max)))) => format!("target={id} stored={stored} max={max}"),
        Some((id, None)) => format!("target={id} (not an energy block) stored=- max=-"),
        None => "target=none stored=- max=-".to_owned(),
    };
    let suffix = nonce.map_or(String::new(), |nonce| format!(" nonce={nonce}"));
    format!(
        "Power Monitor at {},{},{}: level={} band={band} {target} alarm={} t={t}{suffix}",
        pos[0], pos[1], pos[2], state.level, state.alarm,
    )
}

/// The monitor's line for the block at `pos`, or [`NO_MONITOR`].
pub(crate) fn monitor_status_line(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    nonce: Option<&str>,
) -> String {
    if block_id(&*host, level, pos).as_deref() != Some(MONITOR) {
        return NO_MONITOR.to_owned();
    }
    let Some(entity) = host.block_entity(level, pos) else {
        return NO_MONITOR.to_owned();
    };
    let Some(saved) = entity.data(&*host) else {
        return NO_MONITOR.to_owned();
    };
    let state = read_monitor(&Tag::Compound(saved));
    let target = read_target(&*host, level, pos).map(|(target, _read)| target);
    let report = target.map(|target| {
        let id = block_id(&*host, level, target);
        let energy = energy_at(host, level, target);
        (id.unwrap_or_else(|| "none".to_owned()), energy)
    });
    let t = level.game_time(&*host).unwrap_or(0);
    let report = report.as_ref().map(|(id, energy)| (id.as_str(), *energy));
    monitor_line(pos, &state, report, t, nonce)
}

/// Set a monitor's alarm band (`PowerMonitorData.withMinimum`/`withMaximum`); the next
/// observation applies it. Answers the line a player reads.
pub(crate) fn set_band(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    minimum: i32,
    maximum: i32,
) -> String {
    if block_id(&*host, level, pos).as_deref() != Some(MONITOR) {
        return NO_MONITOR.to_owned();
    }
    let Some(entity) = host.block_entity(level, pos) else {
        return NO_MONITOR.to_owned();
    };
    let Some(saved) = entity.data(&*host) else {
        return NO_MONITOR.to_owned();
    };
    let mut saved = Tag::Compound(saved);
    let current = read_monitor(&saved);
    let banded = Monitor::restored(
        current.level,
        minimum,
        maximum,
        current.alarm,
        current.counter,
    );
    write_monitor(&mut saved, &banded);
    if let Tag::Compound(data) = saved {
        let _ = entity.replace_data(host, data);
    }
    let _ = entity.set_changed(&mut *host);
    format!(
        "Power Monitor band at {},{},{}: {}..{} (alarm at the next observation)",
        pos[0], pos[1], pos[2], banded.minimum, banded.maximum
    )
}

// ---------------------------------------------------------------------------
// The power level
// ---------------------------------------------------------------------------

/// Mirror the power level's ratio into its `power` block state, and let the neighbours re-read the
/// redstone output when it changed (a wire on the display face must see the new signal at once).
///
/// Upstream keeps the ratio in the tile entity, but the pin's `block_signal` gets only a state and
/// must answer from it (`BlockPart::block_signal`: "don't read or change the world here"), so the
/// state is this port's carrier for the output — the same mirror the monitor's `lit` gives its
/// alarm.
pub(crate) fn mirror_power_level(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    power: i32,
) {
    let _ = host.set_block_property(pos, KEY_POWER, &power.to_string());
    if let Some(source) = level.block_state(&*host, pos) {
        let _ = level.update_neighbors(host, pos, source, NeighbourUpdate::Neighbours);
    }
}

/// One power level tick (`PowerLevelTileEntity.tickServer`): count the ticks down, then read the
/// block it faces and set its ratio. True when the saved state moved.
pub(crate) fn tick_power_level(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    pos: [i32; 3],
    saved: &mut Tag,
) -> bool {
    let before = read_power_level(saved);
    let mut state = before.clone();
    let due = state.tick();
    if due {
        // A tick is only asked in the level in place; if none answers (shutdown), keep the last
        // reading rather than treating the target as absent.
        if let Some(level) = level {
            let observed = read_target(&*host, level, pos)
                .and_then(|(target, _read)| energy_at(host, level, target));
            state.observe(observed);
        }
    }
    let changed = state != before;
    if changed {
        write_power_level(saved, &state);
        if let Some(level) = level {
            mirror_power_level(host, level, pos, state.power);
        }
    }
    changed
}

/// A state decoded for `block_signal`, cached by ordinal: a state's properties never change.
#[derive(Clone, Copy)]
struct PowerLevelFace {
    display: Direction,
    power: i32,
}

static POWER_LEVEL_FACES: LazyLock<Mutex<HashMap<BlockState, PowerLevelFace>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Decode a serialized power level state into its display face and ratio
/// (`rftoolspower:power_level[facing=east,power=5]`).
pub(crate) fn parse_power_level_state(text: &str) -> Option<(Direction, i32)> {
    let (block, rest) = text.split_once('[')?;
    if block != POWER_LEVEL {
        return None;
    }
    let mut facing = None;
    let mut power = 0;
    for property in rest.strip_suffix(']')?.split(',') {
        let (key, value) = property.split_once('=')?;
        match key {
            KEY_FACING => facing = Some(dir_from_name(value)?),
            KEY_POWER => power = value.parse().ok()?,
            _ => {}
        }
    }
    Some((facing?, power))
}

/// The decoded state, through the cache `block_signal` (asked very often) reads.
fn power_level_face(level: &dyn LevelHost, state: BlockState) -> Option<PowerLevelFace> {
    if let Some(hit) = POWER_LEVEL_FACES
        .lock()
        .expect("the power level state cache is never held across a panic")
        .get(&state)
    {
        return Some(*hit);
    }
    // The state's `facing` is the display front; the block read is behind it, and the output
    // leaves through the display (upstream's notify side, the same fix slice 2 recorded).
    let (display, power) = parse_power_level_state(&level.state_string(state)?)?;
    let face = PowerLevelFace { display, power };
    POWER_LEVEL_FACES
        .lock()
        .expect("the power level state cache is never held across a panic")
        .insert(state, face);
    Some(face)
}

/// `block_signal`: the ratio on the display side, nothing anywhere else.
///
/// Upstream answers only `getSignal` (weak) and leaves `getDirectSignal` at 0; so does this.
pub(crate) fn power_level_signal(level: &dyn LevelHost, event: &mut BlockSignalEvent) {
    if event.direct {
        return;
    }
    let Some(face) = power_level_face(level, event.state) else {
        return;
    };
    if event.face == face.display {
        event.signal = face.power;
    }
}

/// `is_signal_source`: a power level answers the signal query, so redstone wire connects to it.
pub(crate) fn power_level_signal_source(level: &dyn LevelHost, event: &mut IsSignalSourceEvent) {
    if level.state_block(event.state) == Some(POWER_LEVEL) {
        event.source = true;
    }
}

/// `LogicSlabBlock.getStateForPlacement`: the placer's look sets the display face.
pub(crate) fn power_level_placement(
    level: &dyn LevelHost,
    event: &StateForPlacementEvent<'_>,
) -> Option<Option<BlockState>> {
    if level.state_block(event.state) != Some(POWER_LEVEL) {
        return None;
    }
    let display = facing_from_yaw(event.context.yaw);
    Some(level.state_with_property(event.state, KEY_FACING, dir_name(display)))
}

/// The power level's report line, as `/rftoolspower powerlevel` prints it.
pub(crate) fn power_level_line(
    pos: [i32; 3],
    state: &PowerLevel,
    display: Option<Direction>,
    target: Option<(&str, Option<(u32, u32)>)>,
    t: i64,
    nonce: Option<&str>,
) -> String {
    let facing = display.map_or_else(|| "none".to_owned(), |face| dir_name(face).to_owned());
    let target = match target {
        Some((id, Some((stored, max)))) => format!("target={id} stored={stored} max={max}"),
        Some((id, None)) => format!("target={id} (not an energy block) stored=- max=-"),
        None => "target=none stored=- max=-".to_owned(),
    };
    let suffix = nonce.map_or(String::new(), |nonce| format!(" nonce={nonce}"));
    format!(
        "Power Level at {},{},{}: power={} facing={facing} {target} t={t}{suffix}",
        pos[0], pos[1], pos[2], state.power,
    )
}

/// The power level's line for the block at `pos`, or [`NO_POWER_LEVEL`].
pub(crate) fn power_level_status_line(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    nonce: Option<&str>,
) -> String {
    if block_id(&*host, level, pos).as_deref() != Some(POWER_LEVEL) {
        return NO_POWER_LEVEL.to_owned();
    }
    let Some(entity) = host.block_entity(level, pos) else {
        return NO_POWER_LEVEL.to_owned();
    };
    let Some(saved) = entity.data(&*host) else {
        return NO_POWER_LEVEL.to_owned();
    };
    let state = read_power_level(&Tag::Compound(saved));
    let display = level
        .block_property(&*host, pos, KEY_FACING)
        .and_then(|name| dir_from_name(name.as_str()));
    let target = read_target(&*host, level, pos).map(|(target, _read)| target);
    let report = target.map(|target| {
        let id = block_id(&*host, level, target);
        let energy = energy_at(host, level, target);
        (id.unwrap_or_else(|| "none".to_owned()), energy)
    });
    let t = level.game_time(&*host).unwrap_or(0);
    let report = report.as_ref().map(|(id, energy)| (id.as_str(), *energy));
    power_level_line(pos, &state, display, report, t, nonce)
}

// ---------------------------------------------------------------------------
// The powercell
// ---------------------------------------------------------------------------

/// A direction's face number: vanilla's `Direction.ordinal()`, which upstream indexes its saved
/// `modes` with.
fn face_index(direction: Direction) -> usize {
    match direction {
        Direction::Down => 0,
        Direction::Up => 1,
        Direction::North => 2,
        Direction::South => 3,
        Direction::West => 4,
        Direction::East => 5,
    }
}

/// A saved string, `None` when absent or of another type.
fn text(saved: &Tag, key: &str) -> Option<String> {
    match saved.get(key) {
        Some(Tag::String(value)) => Some(value.to_string_lossy()),
        _ => None,
    }
}

/// Write one string into a saved compound.
fn set_text(saved: &mut Tag, key: &str, value: &str) {
    if let Tag::Compound(nbt) = saved {
        nbt.insert(key.into(), Tag::String(value.into()));
    }
}

/// The cell a saved compound holds for `tier`, clamped to that tier's capacity.
fn read_cell(saved: &Tag, tier: Tier) -> Cell {
    Cell {
        tier,
        energy: clamped_energy(tier, int(saved, KEY_ENERGY)),
    }
}

/// Write a cell's own store back into a saved compound.
fn write_cell(saved: &mut Tag, cell: &Cell) {
    set_int(saved, KEY_ENERGY, cell.energy);
}

/// The six face modes a saved compound holds (`PowerCellTileEntity.loadClientDataFromNBT`); a
/// fresh or unreadable compound is six `NONE`s.
fn read_sides_from(saved: &Tag) -> Sides {
    text(saved, KEY_MODE).map_or_else(Sides::fresh, |saved| Sides::from_saved(&saved))
}

/// Write the six face modes in upstream's own six-digit form.
fn write_sides(saved: &mut Tag, sides: Sides) {
    set_text(saved, KEY_MODE, &sides.to_saved());
}

/// One cell of a network and where it stands.
struct Network {
    positions: Vec<[i32; 3]>,
    cells: Vec<Cell>,
}

impl Network {
    /// What the network holds.
    fn stored(&self) -> u64 {
        network_stored(&self.cells)
    }

    /// What the network can hold.
    fn capacity(&self) -> u64 {
        network_capacity(&self.cells)
    }

    /// How many cells are in it.
    fn len(&self) -> usize {
        self.cells.len()
    }

    /// How many cells are in it.
    fn is_empty(&self) -> bool {
        self.cells.is_empty()
    }

    /// Take up to `request` in, the cell asked first (see [`crate::runtime::receive`]).
    fn receive(&mut self, request: u32) -> u32 {
        network_receive(&mut self.cells, request)
    }

    /// Drain up to `amount`, the cell asked first (see [`crate::runtime::take`]).
    fn take(&mut self, amount: u32) -> u32 {
        network_take(&mut self.cells, amount)
    }

    /// The stores the cells held before a move, to write back only what changed.
    fn energies(&self) -> Vec<i32> {
        self.cells.iter().map(|cell| cell.energy).collect()
    }

    /// Write every cell whose store moved back to its saved compound, except the one at `skip`
    /// (a cell out for its own tick writes its own payload instead). True when anything was
    /// written.
    fn write(
        &self,
        host: &mut dyn ServerHost,
        level: LevelRef,
        skip: [i32; 3],
        before: &[i32],
    ) -> bool {
        let mut changed = false;
        for (index, cell) in self.cells.iter().enumerate() {
            if before.get(index).copied() == Some(cell.energy) || self.positions[index] == skip {
                continue;
            }
            let Some(entity) = host.block_entity(level, self.positions[index]) else {
                continue;
            };
            let Some(saved) = entity.data(&*host) else {
                continue;
            };
            let mut saved = Tag::Compound(saved);
            write_cell(&mut saved, cell);
            if let Tag::Compound(data) = saved {
                let _ = entity.replace_data(host, data);
            }
            changed = true;
        }
        changed
    }
}

/// The cell at `pos`, if the block there is a powercell and its block entity reads.
fn cell_at(host: &mut dyn ServerHost, level: LevelRef, pos: [i32; 3]) -> Option<Cell> {
    let tier = Tier::of_block(block_id(&*host, level, pos)?.as_str())?;
    let entity = host.block_entity(level, pos)?;
    let saved = entity.data(&*host)?;
    Some(read_cell(&Tag::Compound(saved), tier))
}

/// The network the cell at `pos` belongs to (`PowerCellTileEntity.buildNetwork`): every powercell
/// reachable through a shared face, of **any** tier — upstream walks from one
/// `PowerCellTileEntity` to the next and only the per-tier redistribution and the capacities
/// differ by tier. The cell asked comes first, then its neighbours breadth-first.
///
/// `self_state` answers for a cell that is out for its own tick: its handle cannot be read then,
/// so the caller hands in what it already knows and that becomes the first entry.
fn network_of(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    pos: [i32; 3],
    self_state: Option<(Tier, i32)>,
) -> Option<Network> {
    let level = level?;
    let mut positions = Vec::new();
    let mut cells = Vec::new();
    let mut seen = HashSet::new();
    let mut queue = VecDeque::new();
    match self_state {
        Some((tier, energy)) => cells.push(Cell {
            tier,
            energy: clamped_energy(tier, energy),
        }),
        None => cells.push(cell_at(host, level, pos)?),
    }
    positions.push(pos);
    seen.insert(pos);
    queue.push_back(pos);
    while let Some(at) = queue.pop_front() {
        for direction in Direction::ALL {
            let normal = direction.normal();
            let next = [at[0] + normal[0], at[1] + normal[1], at[2] + normal[2]];
            if !seen.insert(next) {
                continue;
            }
            let Some(cell) = cell_at(host, level, next) else {
                continue;
            };
            cells.push(cell);
            positions.push(next);
            queue.push_back(next);
            if cells.len() > NETWORK_MAX {
                // Upstream's `networkMax`: a bigger network is `!isValid()` and moves nothing.
                // Stop the walk so a doctored world cannot make this unbounded.
                return Some(Network { positions, cells });
            }
        }
    }
    Some(Network { positions, cells })
}

/// The six modes of the cell at `pos`, or a fresh cell's when there is none.
fn read_sides(host: &mut dyn ServerHost, level: LevelRef, pos: [i32; 3]) -> Sides {
    let Some(entity) = host.block_entity(level, pos) else {
        return Sides::fresh();
    };
    let Some(saved) = entity.data(&*host) else {
        return Sides::fresh();
    };
    read_sides_from(&Tag::Compound(saved))
}

/// `PowerCellTileEntity.SidedHandler`: the network's store behind the cell's energy capability,
/// taking FE in only through a face whose mode is `INPUT`, and never giving any out (the cell
/// pushes on its own tick, exactly as upstream's `extractEnergy` answers 0).
struct CellEnergy {
    at: BlockSide,
}

impl CellEnergy {
    /// The network this face belongs to, or `None` when the block is no longer a cell.
    fn network(&self, host: &mut dyn ServerHost) -> Option<Network> {
        network_of(host, Some(self.at.level), self.at.pos, None)
    }
}

impl EnergyHandler for CellEnergy {
    fn amount(&self, host: &mut dyn ServerHost) -> u32 {
        self.network(host)
            .map_or(0, |network| as_capability(network.stored()))
    }

    fn capacity(&self, host: &mut dyn ServerHost) -> u32 {
        self.network(host)
            .map_or(0, |network| as_capability(network.capacity()))
    }

    fn insert(&self, host: &mut dyn ServerHost, _tx: &Transaction, amount: u32) -> u32 {
        if amount == 0 {
            return 0;
        }
        // Upstream's `getEnergyStorage(null)` is the NullHandler: no side, nothing taken.
        let Some(face) = self.at.side else {
            return 0;
        };
        // `receiveEnergyFacing` checks the mode of the face the FE arrives through.
        if read_sides(host, self.at.level, self.at.pos).get(face_index(face)) != SideMode::Input {
            return 0;
        }
        let Some(mut network) = self.network(host) else {
            return 0;
        };
        if network.is_empty() || !network_valid(network.len()) {
            return 0;
        }
        let before = network.energies();
        let received = network.receive(amount);
        if received > 0 {
            network.write(host, self.at.level, [i32::MIN; 3], &before);
        }
        received
    }

    fn extract(&self, _host: &mut dyn ServerHost, _tx: &Transaction, _amount: u32) -> u32 {
        0
    }
}

/// One powercell tick (`PowerCellTileEntity.tickServer` → `sendOutEnergy`): for every face whose
/// mode is `OUTPUT`, offer up to the network's per-side budget to the block there, skipping
/// another powercell (cells share through the network, never by pushing into each other), and
/// drain what the neighbours accepted from the network, this cell first.
///
/// Returns whether the saved payload moved (the engine discards a tick's payload edits unless
/// the tick answers `Changed`).
pub(crate) fn tick_cell(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    pos: [i32; 3],
    tier: Tier,
    saved: &mut Tag,
) -> bool {
    let sides = read_sides_from(saved);
    if !sides.any_output() {
        return false;
    }
    let Some(level) = level else {
        return false;
    };
    let own = read_cell(saved, tier);
    let Some(mut network) = network_of(host, Some(level), pos, Some((tier, own.energy))) else {
        return false;
    };
    if !network_valid(network.len()) {
        return false;
    }
    let before = network.energies();
    let mut budget = network.stored();
    let per_face = u64::from(rf_per_tick(tier, network.len()));
    let mut moved = 0;
    for (face, direction) in Direction::ALL.into_iter().enumerate() {
        if sides.get(face) != SideMode::Output {
            continue;
        }
        if budget == 0 {
            break;
        }
        let normal = direction.normal();
        let target = [pos[0] + normal[0], pos[1] + normal[1], pos[2] + normal[2]];
        // Upstream: `if (!(te instanceof PowerCellTileEntity))` — a cell is never a push target.
        if cell_at(host, level, target).is_some() {
            continue;
        }
        let offer = u32::try_from(budget.min(per_face)).unwrap_or(0);
        if offer == 0 {
            continue;
        }
        let Some(handler) = level.capability(host, &ENERGY, target, Some(direction.opposite()))
        else {
            continue;
        };
        let received = host
            .transaction(|host, tx| -> Result<u32, ()> { Ok(handler.insert(host, tx, offer)) })
            .unwrap_or(0);
        let received = received.min(offer);
        budget -= u64::from(received);
        moved += received;
    }
    if moved == 0 {
        return false;
    }
    network.take(moved);
    let self_energy = network.cells[0].energy;
    let written = network.write(host, level, pos, &before);
    let self_changed = self_energy != own.energy;
    if self_changed {
        write_cell(saved, &network.cells[0]);
    }
    self_changed || written
}

/// A powercell's report line, as `/rftoolspower cell` and a click print it.
#[allow(clippy::too_many_arguments)]
pub(crate) fn cell_line(
    pos: [i32; 3],
    tier: Tier,
    cell: &Cell,
    stored: u64,
    capacity: u64,
    cells: usize,
    sides: Sides,
    t: i64,
    nonce: Option<&str>,
) -> String {
    let suffix = nonce.map_or(String::new(), |nonce| format!(" nonce={nonce}"));
    format!(
        "Power Cell at {},{},{}: tier={} local={}/{} network={}/{} cells={} sides={} t={t}{suffix}",
        pos[0],
        pos[1],
        pos[2],
        tier.suffix(),
        cell.energy,
        tier.capacity(),
        as_capability(stored),
        as_capability(capacity),
        cells,
        sides.names(),
    )
}

/// The powercell at `pos`, or [`NO_CELL`].
pub(crate) fn cell_status_line(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    nonce: Option<&str>,
) -> String {
    let Some(tier) = block_id(&*host, level, pos).and_then(|id| Tier::of_block(&id)) else {
        return NO_CELL.to_owned();
    };
    let Some(entity) = host.block_entity(level, pos) else {
        return NO_CELL.to_owned();
    };
    let Some(saved) = entity.data(&*host) else {
        return NO_CELL.to_owned();
    };
    let saved = Tag::Compound(saved);
    let cell = read_cell(&saved, tier);
    let sides = read_sides_from(&saved);
    let (stored, capacity, cells) = network_of(host, Some(level), pos, None).map_or(
        (
            u64::try_from(cell.energy.max(0)).unwrap_or(0),
            u64::try_from(tier.capacity()).unwrap_or(0),
            1,
        ),
        |network| (network.stored(), network.capacity(), network.len()),
    );
    let t = level.game_time(&*host).unwrap_or(0);
    cell_line(pos, tier, &cell, stored, capacity, cells, sides, t, nonce)
}

/// Set one face of a cell (`PowerCellTileEntity.toggleMode`'s absolute form — the harness's
/// stand-in for the smart wrench the parent port does not carry). Answers the line a player
/// reads, including the refusal when the face or the mode is not one.
pub(crate) fn set_side(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    face_name: &str,
    mode_name: &str,
) -> String {
    if block_id(&*host, level, pos)
        .and_then(|id| Tier::of_block(&id))
        .is_none()
    {
        return NO_CELL.to_owned();
    }
    let Some(face) = dir_from_name(&face_name.to_ascii_lowercase()) else {
        return format!(
            "Power Cell at {},{},{}: unknown face '{face_name}' (down|up|north|south|west|east)",
            pos[0], pos[1], pos[2]
        );
    };
    let Some(mode) = SideMode::parse(mode_name) else {
        return format!(
            "Power Cell at {},{},{}: unknown mode '{mode_name}' (none|input|output)",
            pos[0], pos[1], pos[2]
        );
    };
    let Some(entity) = host.block_entity(level, pos) else {
        return NO_CELL.to_owned();
    };
    let Some(saved) = entity.data(&*host) else {
        return NO_CELL.to_owned();
    };
    let mut saved = Tag::Compound(saved);
    let mut sides = read_sides_from(&saved);
    if !sides.set(face_index(face), mode) {
        return format!(
            "Power Cell at {},{},{}: unknown face '{face_name}' (down|up|north|south|west|east)",
            pos[0], pos[1], pos[2]
        );
    }
    write_sides(&mut saved, sides);
    if let Tag::Compound(data) = saved {
        let _ = entity.replace_data(host, data);
    }
    let _ = entity.set_changed(&mut *host);
    format!(
        "Power Cell side at {},{},{}: {} {} (sides={})",
        pos[0],
        pos[1],
        pos[2],
        dir_name(face),
        mode.name(),
        sides.names()
    )
}

/// A click on a cell reads its status in the action bar (there is no GUI in this slice), so the
/// block's own menu never opens.
pub(crate) fn cell_click(
    host: &mut dyn ServerHost,
    click: &BlockClick<'_>,
) -> Option<InteractionResult> {
    let level = host.level(click.dimension.key().id())?;
    Tier::of_block(&block_id(&*host, level, click.pos)?)?;
    let line = cell_status_line(host, level, click.pos, None);
    if let Some(player) = host.player(click.player) {
        let _ = player.action_bar(host, Text::literal(line));
    }
    Some(InteractionResult::Success)
}

/// A powercell: it ticks to push out of its OUTPUT faces, and a click reads it.
pub(crate) struct CellPart {
    tier: Tier,
}

#[mod_api::horizon_part]
impl BlockPart for CellPart {
    fn use_item_on(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseItemOnEvent<'_>,
    ) -> Option<InteractionResult> {
        cell_click(host, event.click)
    }

    fn use_without_item(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseWithoutItemEvent<'_>,
    ) -> Option<InteractionResult> {
        cell_click(host, event.click)
    }
}

#[mod_api::horizon_part]
impl BlockEntityPart for CellPart {
    /// `EntityBlock.newBlockEntity`: an empty saved compound — no FE, every face `NONE`
    /// (`PowerCellTileEntity.modes`), which is why a fresh cell takes nothing in.
    fn block_entity(
        &self,
        _level: LevelSide,
        _event: &mut BlockEntityEvent<'_>,
    ) -> Option<Compound> {
        Some(Compound::new())
    }

    /// `EntityBlock.getTicker`: the cell ticks its OUTPUT faces. Never clear a value an earlier
    /// mod set.
    fn block_entity_ticks(&self, _host: &dyn Host, event: &mut BlockEntityTicksEvent<'_>) {
        event.ticks = true;
    }

    /// One server tick: push out of every OUTPUT face, the network paying for it.
    fn block_entity_tick(&self, host: &mut dyn ServerHost, event: &mut BlockEntityTickEvent<'_>) {
        let pos = event.pos;
        let level = in_place_level(host);
        let mut saved = Tag::Compound(std::mem::take(&mut event.entity.nbt));
        let changed = tick_cell(host, level, pos, self.tier, &mut saved);
        if let Tag::Compound(nbt) = saved {
            event.entity.nbt = nbt;
        }
        if !changed {
            *event.reply = BlockEntityTickReply::Unchanged;
        }
    }
}

/// A powercell item's Part: clamp what a placed item's `block_entity_data` restored to the
/// block's own tier (`PowerCellBlock.setPlacedBy` reads the item's energy; a doctored one is
/// clamped here).
pub(crate) struct CellItemPart;

#[mod_api::horizon_part]
impl ItemPart for CellItemPart {
    fn on_block_placed_by(&self, host: &mut dyn ServerHost, event: &mut OnBlockPlacedByEvent<'_>) {
        let Some(level) = event
            .placer
            .and_then(|player| player.level(&*host))
            .or_else(|| in_place_level(host))
        else {
            return;
        };
        let Some(tier) = block_id(&*host, level, event.pos).and_then(|id| Tier::of_block(&id))
        else {
            return;
        };
        let Some(entity) = host.block_entity(level, event.pos) else {
            return;
        };
        let Some(saved) = entity.data(&*host) else {
            return;
        };
        let mut saved = Tag::Compound(saved);
        let cell = read_cell(&saved, tier);
        if cell.energy == int(&saved, KEY_ENERGY) {
            return;
        }
        write_cell(&mut saved, &cell);
        if let Tag::Compound(data) = saved {
            let _ = entity.replace_data(host, data);
        }
    }
}

// ---------------------------------------------------------------------------
// The click
// ---------------------------------------------------------------------------

/// A right click on the generator: there is no GUI in this slice, so the click inserts one fuel
/// item (upstream's fuel slot) and an empty hand reads the status. The click is always claimed, so
/// the furnace template never opens its own menu and a refused item is never placed.
pub(crate) fn generator_click(
    host: &mut dyn ServerHost,
    click: &BlockClick<'_>,
    held: Option<&ItemStack>,
) -> Option<InteractionResult> {
    let level = host.level(click.dimension.key().id())?;
    if block_id(&*host, level, click.pos).as_deref() != Some(GENERATOR) {
        return None;
    }
    let Some(held) = held.filter(|stack| stack.count() > 0) else {
        let line = status_line(host, level, click.pos, None);
        if let Some(player) = host.player(click.player) {
            let _ = player.action_bar(host, Text::literal(line));
        }
        return Some(InteractionResult::Success);
    };
    let refused = item_id(&*host, held);
    if Fuel::of(&refused).is_none() {
        if let Some(player) = host.player(click.player) {
            let _ = player.action_bar(host, Text::literal(format!("{refused} is not a fuel")));
        }
        return Some(InteractionResult::Success);
    }
    let hand = ItemPlace::PlayerHand {
        player: click.player,
        hand: click.hand,
    };
    insert_from_hand(host, level, click.pos, held, &hand);
    Some(InteractionResult::Success)
}

/// Insert as much of the held fuel as the slot takes, and take exactly that from the hand, in one
/// transaction (a creative player's hand gives without losing any).
pub(crate) fn insert_from_hand(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    held: &ItemStack,
    hand: &ItemPlace,
) -> u32 {
    host.transaction(|host, tx| -> Result<u32, ()> {
        let entity = host.block_entity(level, pos).ok_or(())?;
        let key = held.item();
        let limit = host.max_stack_size(key).unwrap_or(DEFAULT_STACK);
        let existing = entity.item_slot(&*host, FUEL_SLOT as u32).ok().flatten();
        // The slot keeps the stack it already holds; an inserted stack is the caller's own stack
        // (components and damage included), never rebuilt from an id and a count.
        let (inserted, after) = match existing {
            None => {
                let count = held.count().min(limit);
                let mut after = held.clone();
                after.set_count(count).map_err(|_| ())?;
                (count, after)
            }
            Some(existing) if existing.is_stackable_with(held) => {
                let room = limit.saturating_sub(existing.count());
                let count = held.count().min(room);
                let mut after = existing;
                let merged = after.count().saturating_add(count);
                after.set_count(merged).map_err(|_| ())?;
                (count, after)
            }
            // A different item, or the same item with a different component patch, is not a
            // compatible merge: a plain coal must not swallow a component-bearing one.
            Some(_) => (0, held.clone()),
        };
        if inserted == 0 {
            return Ok(0);
        }
        // Take from the hand first and require the full amount: a hand that cannot supply what
        // the slot would take aborts the transaction, so the slot never gains items the player
        // did not pay for.
        let taken = hand.extract(&mut *host, tx, &ItemResource::of(held), inserted);
        if taken != inserted {
            return Err(());
        }
        entity
            .set_item_slot(&mut *host, tx, FUEL_SLOT as u32, Some(after))
            .map_err(|_| ())?;
        let _ = entity.set_changed(&mut *host);
        Ok(inserted)
    })
    .unwrap_or(0)
}

// ---------------------------------------------------------------------------
// A broken generator keeps its store
// ---------------------------------------------------------------------------

/// `saved` tagged as the block entity type's data, under the vanilla component's name: the patch
/// a broken block's drop carries (upstream's loot table copies its components; this is the
/// vanilla carrier, and `TypedEntityData.loadInto` only loads a payload whose `id` names the type).
pub(crate) fn entity_data_patch(saved: &Compound, type_id: &str) -> Compound {
    let mut payload = saved.clone();
    payload.insert("id".into(), Tag::String(type_id.into()));
    let mut patch = Compound::new();
    patch.insert(BLOCK_ENTITY_DATA.into(), Tag::Compound(payload));
    patch
}

/// `Hooks::block_drops`: a broken generator keeps its store on its own item, so a player who breaks
/// a burning or charged generator and places it again does not lose the FE or the burn; a monitor
/// keeps its configured alarm band the same way (upstream's `ITEM_POWER_MONITOR_DATA`), and a
/// powercell keeps its own local store (upstream's `copy_components` of `item_energy` — the face
/// modes are client data and do not travel).
pub(crate) fn on_block_drops(level: &dyn LevelHost, event: &mut BlockDropsEvent<'_>) -> Flow {
    let Some(block) = level.state_block(event.state) else {
        return Flow::Continue;
    };
    let Some(entity) = event.block_entity else {
        return Flow::Continue;
    };
    let Some(saved) = level.block_entity_data(entity) else {
        return Flow::Continue;
    };
    let patch = if let Some(tier) = Tier::of_block(block) {
        let cell = read_cell(&Tag::Compound(saved), tier);
        if cell.energy == 0 {
            return Flow::Continue;
        }
        let mut payload = Compound::new();
        payload.insert(KEY_ENERGY.into(), Tag::Int(cell.energy));
        let type_id = if tier == Tier::One {
            CELL1_TYPE_ID
        } else {
            CELL2_TYPE_ID
        };
        entity_data_patch(&payload, type_id)
    } else if block == GENERATOR {
        if !crate::runtime::carried(&read_generator(&Tag::Compound(saved.clone()))) {
            return Flow::Continue;
        }
        entity_data_patch(&saved, GENERATOR_TYPE_ID)
    } else if block == MONITOR {
        // An unconfigured monitor has nothing worth carrying; a configured band does.
        let state = read_monitor(&Tag::Compound(saved.clone()));
        if !Monitor::band_set(state.minimum, state.maximum) {
            return Flow::Continue;
        }
        entity_data_patch(&saved, MONITOR_TYPE_ID)
    } else if block == ENDERGENIC {
        // Upstream's loot copies `mcjtylib:item_energy` only: the store travels, the charging
        // state and the link do not.
        let energy = int(&Tag::Compound(saved.clone()), KEY_ENERGY);
        if energy == 0 {
            return Flow::Continue;
        }
        let mut payload = Compound::new();
        payload.insert(KEY_ENERGY.into(), Tag::Int(energy));
        entity_data_patch(&payload, ENDERGENIC_TYPE_ID)
    } else if block == BLAZING {
        // Upstream's loot copies `mcjtylib:item_energy` (and the inventory, which the engine keeps
        // apart from this payload): the store travels, the slots and their rates do not.
        let energy = int(&Tag::Compound(saved.clone()), KEY_ENERGY);
        if energy == 0 {
            return Flow::Continue;
        }
        let mut payload = Compound::new();
        payload.insert(KEY_ENERGY.into(), Tag::Int(energy));
        entity_data_patch(&payload, BLAZING_TYPE_ID)
    } else if block == AGITATOR {
        // Upstream's loot copies `mcjtylib:item_energy` and `rftoolspower:agitator_data`: the
        // store and the nine locks travel, the rods in the box do not (the engine keeps container
        // items apart from this payload).
        let state = read_agitator(&Tag::Compound(saved.clone()));
        if state.energy == 0 && !state.locks.iter().any(|locked| *locked) {
            return Flow::Continue;
        }
        entity_data_patch(&saved, AGITATOR_TYPE_ID)
    } else if block == ENDER_MONITOR {
        // Upstream's mode rides on the block's item (`EnderMonitorData` on the dropped stack):
        // the configured mode travels, the default one has nothing worth carrying, and the
        // readout's counters are this port's own so they stay on the block.
        let mode = read_ender_monitor(&Tag::Compound(saved)).mode;
        if mode == MonitorMode::LostPearl {
            return Flow::Continue;
        }
        let mut payload = Compound::new();
        payload.insert(KEY_MONITOR_MODE.into(), Tag::String(mode.saved().into()));
        entity_data_patch(&payload, ENDER_MONITOR_TYPE_ID)
    } else {
        return Flow::Continue;
    };
    // The block's loot is the block itself, so its data goes on every drop the table made.
    for drop in event.drops.iter_mut() {
        let _ = drop.stack.apply_components(&patch);
    }
    Flow::Continue
}

/// The generator item's Part: clamp what a placed item's `block_entity_data` restored. The engine
/// applies the whole saved compound, including values a stale or edited item could carry.
pub(crate) struct GeneratorItemPart;

#[mod_api::horizon_part]
impl ItemPart for GeneratorItemPart {
    fn on_block_placed_by(&self, host: &mut dyn ServerHost, event: &mut OnBlockPlacedByEvent<'_>) {
        let Some(level) = event
            .placer
            .and_then(|player| player.level(&*host))
            .or_else(|| in_place_level(host))
        else {
            return;
        };
        if block_id(&*host, level, event.pos).as_deref() != Some(GENERATOR) {
            return;
        }
        let Some(entity) = host.block_entity(level, event.pos) else {
            return;
        };
        let Some(saved) = entity.data(&*host) else {
            return;
        };
        let mut saved = Tag::Compound(saved);
        let current = read_generator(&saved);
        let clamped = restored(current.energy, current.burn as i32, current.burn_max as i32);
        if clamped == current {
            return;
        }
        write_generator(&mut saved, &clamped);
        if let Tag::Compound(data) = saved {
            let _ = entity.replace_data(host, data);
        }
        mirror_lit(host, event.pos, clamped.lit());
    }
}

/// The monitor item's Part: clamp what a placed item's `block_entity_data` restored.
pub(crate) struct MonitorItemPart;

#[mod_api::horizon_part]
impl ItemPart for MonitorItemPart {
    fn on_block_placed_by(&self, host: &mut dyn ServerHost, event: &mut OnBlockPlacedByEvent<'_>) {
        let Some(level) = event
            .placer
            .and_then(|player| player.level(&*host))
            .or_else(|| in_place_level(host))
        else {
            return;
        };
        if block_id(&*host, level, event.pos).as_deref() != Some(MONITOR) {
            return;
        }
        let Some(entity) = host.block_entity(level, event.pos) else {
            return;
        };
        let Some(saved) = entity.data(&*host) else {
            return;
        };
        let mut saved = Tag::Compound(saved);
        let current = read_monitor(&saved);
        let clamped = Monitor::restored(
            current.level,
            current.minimum,
            current.maximum,
            current.alarm,
            current.counter,
        );
        if clamped == current {
            return;
        }
        write_monitor(&mut saved, &clamped);
        if let Tag::Compound(data) = saved {
            let _ = entity.replace_data(host, data);
        }
        mirror_monitor(host, level, event.pos, &clamped);
    }
}

/// A click on a monitor reads its status in the action bar (there is no GUI in this slice), so
/// the furnace template's own menu never opens.
pub(crate) fn monitor_click(
    host: &mut dyn ServerHost,
    click: &BlockClick<'_>,
) -> Option<InteractionResult> {
    let level = host.level(click.dimension.key().id())?;
    if block_id(&*host, level, click.pos).as_deref() != Some(MONITOR) {
        return None;
    }
    let line = monitor_status_line(host, level, click.pos, None);
    if let Some(player) = host.player(click.player) {
        let _ = player.action_bar(host, Text::literal(line));
    }
    Some(InteractionResult::Success)
}

/// The Power Monitor: it ticks every 20 ticks against the block it faces and answers redstone on
/// its display side.
pub(crate) struct MonitorPart;

#[mod_api::horizon_part]
impl BlockPart for MonitorPart {
    fn use_item_on(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseItemOnEvent<'_>,
    ) -> Option<InteractionResult> {
        monitor_click(host, event.click)
    }

    fn use_without_item(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseWithoutItemEvent<'_>,
    ) -> Option<InteractionResult> {
        monitor_click(host, event.click)
    }

    /// The placer's look sets the read side; the display is opposite it.
    fn state_for_placement(
        &self,
        level: &dyn LevelHost,
        event: &mut StateForPlacementEvent<'_>,
    ) -> Option<Option<BlockState>> {
        monitor_placement(level, event)
    }

    /// The alarm's 15 on the display side.
    fn block_signal(&self, level: &dyn LevelHost, event: &mut BlockSignalEvent) {
        monitor_signal(level, event);
    }

    /// A monitor answers the signal query, so wire connects to it.
    fn is_signal_source(&self, level: &dyn LevelHost, event: &mut IsSignalSourceEvent) {
        monitor_signal_source(level, event);
    }
}

#[mod_api::horizon_part]
impl BlockEntityPart for MonitorPart {
    /// `EntityBlock.newBlockEntity`: an empty saved compound; the tick fills it.
    fn block_entity(
        &self,
        _level: LevelSide,
        _event: &mut BlockEntityEvent<'_>,
    ) -> Option<Compound> {
        Some(Compound::new())
    }

    /// `EntityBlock.getTicker`: it ticks. Never clear a value an earlier mod set.
    fn block_entity_ticks(&self, _host: &dyn Host, event: &mut BlockEntityTicksEvent<'_>) {
        event.ticks = true;
    }

    /// One server tick: count the observation window down, then read the block it faces.
    fn block_entity_tick(&self, host: &mut dyn ServerHost, event: &mut BlockEntityTickEvent<'_>) {
        let pos = event.pos;
        let level = in_place_level(host);
        let mut saved = Tag::Compound(std::mem::take(&mut event.entity.nbt));
        let changed = tick_monitor(host, level, pos, &mut saved);
        if let Tag::Compound(nbt) = saved {
            event.entity.nbt = nbt;
        }
        if !changed {
            *event.reply = BlockEntityTickReply::Unchanged;
        }
    }
}

/// The Power Level: it ticks, reads the block it faces and answers its ratio on the display face.
pub(crate) struct PowerLevelPart;

#[mod_api::horizon_part]
impl BlockPart for PowerLevelPart {
    /// The placer's look sets the display face.
    fn state_for_placement(
        &self,
        level: &dyn LevelHost,
        event: &mut StateForPlacementEvent<'_>,
    ) -> Option<Option<BlockState>> {
        power_level_placement(level, event)
    }

    /// The ratio on the display side.
    fn block_signal(&self, level: &dyn LevelHost, event: &mut BlockSignalEvent) {
        power_level_signal(level, event);
    }

    /// A power level answers the signal query, so wire connects to it.
    fn is_signal_source(&self, level: &dyn LevelHost, event: &mut IsSignalSourceEvent) {
        power_level_signal_source(level, event);
    }
}

#[mod_api::horizon_part]
impl BlockEntityPart for PowerLevelPart {
    /// `EntityBlock.newBlockEntity`: an empty saved compound; the tick fills it.
    fn block_entity(
        &self,
        _level: LevelSide,
        _event: &mut BlockEntityEvent<'_>,
    ) -> Option<Compound> {
        Some(Compound::new())
    }

    /// `EntityBlock.getTicker`: it ticks. Never clear a value an earlier mod set.
    fn block_entity_ticks(&self, _host: &dyn Host, event: &mut BlockEntityTicksEvent<'_>) {
        event.ticks = true;
    }

    /// One server tick: count the window down, then read the block it faces.
    fn block_entity_tick(&self, host: &mut dyn ServerHost, event: &mut BlockEntityTickEvent<'_>) {
        let pos = event.pos;
        let level = in_place_level(host);
        let mut saved = Tag::Compound(std::mem::take(&mut event.entity.nbt));
        let changed = tick_power_level(host, level, pos, &mut saved);
        if let Tag::Compound(nbt) = saved {
            event.entity.nbt = nbt;
        }
        if !changed {
            *event.reply = BlockEntityTickReply::Unchanged;
        }
    }
}

// ---------------------------------------------------------------------------
// The blazing generator (`BlazingGeneratorTileEntity`, `BlazingRod`, `BlazingRodData`)
// ---------------------------------------------------------------------------

/// `rftoolspower:blazing_generator` (`BlazingModule.BLAZING_GENERATOR`).
pub(crate) const BLAZING: &str = "rftoolspower:blazing_generator";
/// Its block entity type, named apart from its block for the reason [`GENERATOR_TYPE`] is.
const BLAZING_TYPE: &str = "blazing_generator_block_entity";
/// That type's registry id, which a broken generator's payload names.
const BLAZING_TYPE_ID: &str = "rftoolspower:blazing_generator_block_entity";
/// `rftoolspower:blazing_rod` (`BlazingModule.BLAZING_ROD`) — a pure item, carried as content.
pub(crate) const BLAZING_ROD: &str = "rftoolspower:blazing_rod";
/// The mod's own item component (`BlazingModule.ITEM_BLAZING_ROD_DATA`), the rod's whole data.
const ROD_DATA: &str = "rftoolspower:blazing_rod_data";
/// The block's `working` state (`BlazingGeneratorTileEntity.WORKING`), mirrored from the tick.
const KEY_WORKING: &str = "working";
/// The per-slot saved fields, under upstream's own keys (`rftMax{i}`, `rft{i}`, `ticks{i}`).
const KEY_RFT_MAX: &str = "rftMax";
const KEY_RFT: &str = "rft";
const KEY_ROD_TICKS: &str = "ticks";
/// What a read where no blazing generator stands answers.
const NO_BLAZING: &str = "No RFTools Power blazing generator there.";
/// The rod slot the readout and the click name first.
const ROD_SLOT_FIRST: usize = 0;

/// `rftoolspower:blazing_rod_data`: the rod's `{steps, time, quality, duration}`, the component
/// `BlazingRodData`'s own codec writes.
struct RodData;

impl Component for RodData {
    type Value = Rod;

    fn id(&self) -> &str {
        ROD_DATA
    }

    /// A field that is absent or of another type keeps the default row's value, which is what
    /// upstream's `getOrDefault(…, BlazingRodData.DEFAULT)` answers for a stack without data.
    fn decode(&self, value: &Tag) -> Option<Rod> {
        if !matches!(value, Tag::Compound(_)) {
            return None;
        }
        let default = Rod::default();
        Some(Rod {
            steps: number(value, "steps").map_or(default.steps, |steps| steps as i32),
            time: number(value, "time").unwrap_or(default.time),
            quality: number(value, "quality").unwrap_or(default.quality),
            duration: number(value, "duration").unwrap_or(default.duration),
        })
    }

    /// Upstream's codec: an int `steps` and three floats.
    fn encode(&self, rod: Rod) -> Tag {
        Tag::compound([
            ("steps", Tag::Int(rod.steps)),
            ("time", Tag::Float(rod.time.to_bits())),
            ("quality", Tag::Float(rod.quality.to_bits())),
            ("duration", Tag::Float(rod.duration.to_bits())),
        ])
    }
}

/// A numeric component field, whatever numeric NBT type the item carries (`60000` is an int in
/// SNBT, `60000.0f` a float; upstream's codec takes both).
#[expect(
    clippy::cast_precision_loss,
    reason = "upstream's BlazingRodData fields are floats; a rod's numbers are small"
)]
fn number(saved: &Tag, key: &str) -> Option<f32> {
    match saved.get(key)? {
        Tag::Float(bits) => Some(f32::from_bits(*bits)),
        // A `Double` carries f64 *bits*, not a value (the slice-8 leg read a 0.05 clock as
        // 4.58e18 ticks when this arm cast the raw bits).
        Tag::Double(bits) => Some(f64::from_bits(*bits) as f32),
        Tag::Int(value) => Some(*value as f32),
        Tag::Long(value) => Some(*value as f32),
        _ => None,
    }
}

/// The rod a stack carries, its default row when it carries none.
fn rod_of(stack: &ItemStack) -> Rod {
    stack.get(&RodData).unwrap_or_default()
}

/// Write the rod back onto its stack; false when the game refused the patch.
fn set_rod(stack: &mut ItemStack, rod: Rod) -> bool {
    stack.set(&RodData, rod).is_ok()
}

/// Register the mod's own item component with the game before content loads
/// (`BlazingModule.ITEM_BLAZING_ROD_DATA`): the game installs the name, so a rod's patch survives
/// a `/give`, a save and a reload instead of being dropped as an unknown component.
pub(crate) fn declare_component(types: &mut Vec<String>) {
    if !types.iter().any(|known| known == ROD_DATA) {
        types.push(ROD_DATA.to_owned());
    }
}

/// A saved float, 0 when absent or of another type.
fn float(saved: &Tag, key: &str) -> f32 {
    number(saved, key).unwrap_or(0.0)
}

/// Write one float into a saved compound.
fn set_float(saved: &mut Tag, key: &str, value: f32) {
    if let Tag::Compound(nbt) = saved {
        nbt.insert(key.into(), Tag::Float(value.to_bits()));
    }
}

/// The generator's saved state: its store and its four slots (upstream's `loadAdditional`).
pub(crate) fn read_blazing(saved: &Tag) -> Blazing {
    let mut blazing = Blazing {
        energy: clamp_blazing(int(saved, KEY_ENERGY)),
        ..Blazing::default()
    };
    for slot in 0..BLAZING_SLOTS {
        blazing.slots[slot] = BlazingSlot {
            max: int(saved, &format!("{KEY_RFT_MAX}{slot}")),
            rft: float(saved, &format!("{KEY_RFT}{slot}")),
            ticks: int(saved, &format!("{KEY_ROD_TICKS}{slot}")),
        };
    }
    blazing
}

/// Write the generator's state back (`saveAdditional`).
pub(crate) fn write_blazing(saved: &mut Tag, state: &Blazing) {
    set_int(saved, KEY_ENERGY, state.energy);
    for (slot, slot_state) in state.slots.iter().enumerate() {
        set_int(saved, &format!("{KEY_RFT_MAX}{slot}"), slot_state.max);
        set_float(saved, &format!("{KEY_RFT}{slot}"), slot_state.rft);
        set_int(saved, &format!("{KEY_ROD_TICKS}{slot}"), slot_state.ticks);
    }
}

/// The generator's container: four rod slots every face reaches, insert-only, one item each.
pub(crate) fn blazing_container() -> ModContainer {
    ModContainer {
        slots: BLAZING_SLOTS,
        faces: std::array::from_fn(|_| (0..BLAZING_SLOTS).collect()),
        inputs: (0..BLAZING_SLOTS).collect(),
        outputs: vec![],
        menu: None,
    }
}

/// The generator's buffer: upstream's `GenericEnergyStorage(this, false, 1000000, 0)` — it
/// stores, takes nothing in and gives nothing out through the capability (`extractEnergy` is 0
/// upstream too; the generator pushes on its own tick).
pub(crate) fn blazing_battery() -> ModEnergyBuffer {
    ModEnergyBuffer {
        capacity: BLAZING_CAPACITY,
        max_insert: 0,
        max_extract: 0,
        insert_faces: [false; 6],
        extract_faces: [false; 6],
    }
}

/// `BlazingGeneratorTileEntity.handleSendingEnergy`: up to 20,000 FE a tick to every neighbour
/// that answers the energy capability, with no reserve.
pub(crate) fn push_blazing_energy(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    pos: [i32; 3],
    state: &mut Blazing,
) {
    let Some(level) = level else {
        return;
    };
    for direction in Direction::ALL {
        let offer = state.send_amount();
        if offer == 0 {
            break;
        }
        let normal = direction.normal();
        let target = [pos[0] + normal[0], pos[1] + normal[1], pos[2] + normal[2]];
        let Some(handler) = level.capability(host, &ENERGY, target, Some(direction.opposite()))
        else {
            continue;
        };
        let moved = host
            .transaction(|host, tx| -> Result<u32, ()> { Ok(handler.insert(host, tx, offer)) })
            .unwrap_or(0);
        state.take(moved);
    }
}

/// One blazing-generator tick (`BlazingGeneratorTileEntity.tickServer`): the push, then the ramp,
/// the store and the rods' burn. True when the saved payload or a rod moved (the tick's reply
/// decides whether this Part's edits are applied at all).
pub(crate) fn tick_blazing(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    pos: [i32; 3],
    saved: &mut Tag,
    items: &mut [Option<ItemStack>],
) -> bool {
    let before = read_blazing(saved);
    let mut state = before.clone();
    let mut rods = [None; BLAZING_SLOTS];
    for (slot, rod) in rods.iter_mut().enumerate() {
        *rod = items.get(slot).and_then(Option::as_ref).map(rod_of);
    }
    // A rod a hopper (or a menu) put there never saw `updateSlot`; a slot emptied behind the
    // tick's back still carries its ceiling. Both are settled before the tick spends anything.
    let mut changed = state.reconcile(&rods);
    push_blazing_energy(host, level, pos, &mut state);
    let made = state.tick(true, &mut rods);
    for slot in 0..BLAZING_SLOTS {
        match rods[slot] {
            None => {
                if items.get(slot).is_some_and(Option::is_some) {
                    // The rod is spent: the slot is emptied (upstream's `setStackInSlot(EMPTY)`).
                    items[slot] = None;
                    changed = true;
                }
            }
            Some(rod) => {
                // The rod's own duration counts down with the burn (`setPowerDuration`).
                if let Some(stack) = items.get_mut(slot).and_then(Option::as_mut)
                    && rod_of(stack) != rod
                    && set_rod(stack, rod)
                {
                    changed = true;
                }
            }
        }
    }
    changed |= state != before;
    write_blazing(saved, &state);
    if level.is_some() {
        mirror_working(host, pos, made > 0);
    }
    changed
}

/// The block's `working` state follows the tick's own total (`BlockStateProperties`-style mirror;
/// upstream sets its `WORKING` property only when it moved).
pub(crate) fn mirror_working(host: &mut dyn ServerHost, pos: [i32; 3], working: bool) {
    let _ = host.set_block_property(pos, KEY_WORKING, if working { "true" } else { "false" });
}

/// The blazing generator's line, as `/rftoolspower blazing` and a click print it.
pub(crate) fn blazing_line(
    pos: [i32; 3],
    state: &Blazing,
    rods: &[Option<String>; BLAZING_SLOTS],
    working: bool,
    t: i64,
    nonce: Option<&str>,
) -> String {
    let rates: Vec<String> = state
        .slots
        .iter()
        .map(|slot| format!("{:.6}", slot.rft))
        .collect();
    let ceilings: Vec<String> = state
        .slots
        .iter()
        .map(|slot| slot.max.to_string())
        .collect();
    let ticks: Vec<String> = state
        .slots
        .iter()
        .map(|slot| slot.ticks.to_string())
        .collect();
    let names: Vec<&str> = rods
        .iter()
        .map(|rod| rod.as_deref().unwrap_or("empty"))
        .collect();
    let suffix = nonce.map_or(String::new(), |nonce| format!(" nonce={nonce}"));
    format!(
        "Blazing Generator at {},{},{}: {}/{} FE (working {}, rft={}, rftmax={}, ticks={}, \
         rods={}, t={t}{suffix})",
        pos[0],
        pos[1],
        pos[2],
        state.energy,
        BLAZING_CAPACITY,
        working,
        rates.join(","),
        ceilings.join(","),
        ticks.join(","),
        names.join(","),
    )
}

/// The line `/rftoolspower blazing <pos>` prints for the block at `pos`.
pub(crate) fn blazing_status_line(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    nonce: Option<&str>,
) -> String {
    if block_id(&*host, level, pos).as_deref() != Some(BLAZING) {
        return NO_BLAZING.to_owned();
    }
    let Some(entity) = host.block_entity(level, pos) else {
        return NO_BLAZING.to_owned();
    };
    let Some(saved) = entity.data(&*host) else {
        return NO_BLAZING.to_owned();
    };
    let rods: [Option<String>; BLAZING_SLOTS] = std::array::from_fn(|slot| {
        entity
            .item_slot(&*host, slot as u32)
            .ok()
            .flatten()
            .map(|stack| stack.item().id(&*host))
    });
    let working = level
        .block_property(&*host, pos, KEY_WORKING)
        .is_some_and(|value| value == "true");
    let t = level.game_time(&*host).unwrap_or(0);
    blazing_line(
        pos,
        &read_blazing(&Tag::Compound(saved)),
        &rods,
        working,
        t,
        nonce,
    )
}

/// `BaseBlock.getStateForPlacement` with `RotationType.ROTATION`: the front faces the placer.
/// The event carries the placer's view angles, not its height, so upstream's vertical branches
/// (placer above → UP, block above the eye → DOWN) are not expressible here and the front is
/// horizontal — recorded in `notes.md`, the same limit the pearl injector has.
pub(crate) fn blazing_placement(
    level: &dyn LevelHost,
    event: &StateForPlacementEvent<'_>,
) -> Option<Option<BlockState>> {
    if level.state_block(event.state) != Some(BLAZING) {
        return None;
    }
    let front = facing_from_yaw(event.context.yaw).opposite();
    Some(level.state_with_property(event.state, KEY_FACING, dir_name(front)))
}

/// `PlayerInteractEvent.RightClickBlock`: the blazing generator takes every click as its own —
/// a rod goes into the first empty slot, anything else is refused with a line, an empty hand reads
/// the machine out — and **nothing else acts**. Upstream opens its GUI here, so the held item never
/// runs either: without this a **block** held in the hand was placed against the machine, because
/// this pin dispatches `BlockPart::use_item_on` for a click with an item only where the block's own
/// template has a `useItemOn` to replace (measured: the furnace-template generator refused the
/// stone, the `iron_block`-template blazing generator had it placed on its top face).
///
/// One owner per click: the Part answers only `state_for_placement`, so a click is never handled
/// twice. The client is left to predict as it does; the server refuses before anything acts.
pub(crate) fn on_right_click_block(
    host: HostSide<'_>,
    event: &mut RightClickBlockEvent<'_>,
) -> Flow {
    if event.cancelled {
        return Flow::Continue;
    }
    let HostSide::Server(host) = host else {
        return Flow::Continue;
    };
    let click = event.click;
    let Some(level) = host.level(click.dimension.key().id()) else {
        return Flow::Continue;
    };
    let block = block_id(&*host, level, click.pos);
    let handled = match block.as_deref() {
        Some(BLAZING) => blazing_click(host, click, click.stack),
        Some(AGITATOR) => agitator_click(host, click, click.stack),
        _ => return Flow::Continue,
    };
    if handled.is_none() {
        return Flow::Continue;
    }
    *event.cancellation_result = InteractionResult::Success;
    event.cancelled = true;
    Flow::Cancel
}

/// A right click on the blazing generator: a rod goes into the first empty slot, anything else is
/// refused with a line; a click with an empty hand prints the readout (the GUI stand-in).
pub(crate) fn blazing_click(
    host: &mut dyn ServerHost,
    click: &BlockClick<'_>,
    held: Option<&ItemStack>,
) -> Option<InteractionResult> {
    let level = host.level(click.dimension.key().id())?;
    if block_id(&*host, level, click.pos).as_deref() != Some(BLAZING) {
        return None;
    }
    let Some(held) = held.filter(|stack| stack.count() > 0) else {
        let line = blazing_status_line(host, level, click.pos, None);
        if let Some(player) = host.player(click.player) {
            let _ = player.action_bar(host, Text::literal(line));
        }
        return Some(InteractionResult::Success);
    };
    let refused = item_id(&*host, held);
    if refused != BLAZING_ROD {
        if let Some(player) = host.player(click.player) {
            let _ = player.action_bar(
                host,
                Text::literal(format!("{refused} is not a blazing rod")),
            );
        }
        return Some(InteractionResult::Success);
    }
    let free = free_rod_slot(host, level, click.pos, BLAZING_SLOTS);
    let Some(slot) = free else {
        if let Some(player) = host.player(click.player) {
            let _ = player.action_bar(host, Text::literal("all four blazing rod slots are full"));
        }
        return Some(InteractionResult::Success);
    };
    let hand = ItemPlace::PlayerHand {
        player: click.player,
        hand: click.hand,
    };
    if insert_rod_from_hand(host, level, click.pos, held, &hand, slot) == 0
        && let Some(player) = host.player(click.player)
    {
        let _ = player.action_bar(host, Text::literal("the rod did not go in"));
    }
    Some(InteractionResult::Success)
}

/// The first rod slot with nothing in it, `slots` slots wide.
fn free_rod_slot(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    slots: usize,
) -> Option<usize> {
    let entity = host.block_entity(level, pos)?;
    (ROD_SLOT_FIRST..slots).find(|slot| {
        entity
            .item_slot(&*host, *slot as u32)
            .ok()
            .flatten()
            .is_none()
    })
}

/// Put one held rod in `slot` and take exactly that from the hand, in one transaction (a creative
/// player's hand gives without losing any, which is the game's rule and not this port's).
pub(crate) fn insert_rod_from_hand(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    held: &ItemStack,
    hand: &ItemPlace,
    slot: usize,
) -> u32 {
    host.transaction(|host, tx| -> Result<u32, ()> {
        let entity = host.block_entity(level, pos).ok_or(())?;
        if entity
            .item_slot(&*host, slot as u32)
            .ok()
            .flatten()
            .is_some()
        {
            return Ok(0);
        }
        // One item a slot (`slotLimit(1)`): the stack's own components travel with it.
        let mut after = held.clone();
        after.set_count(1).map_err(|_| ())?;
        let taken = hand.extract(&mut *host, tx, &ItemResource::of(held), 1);
        if taken != 1 {
            return Err(());
        }
        entity
            .set_item_slot(&mut *host, tx, slot as u32, Some(after))
            .map_err(|_| ())?;
        let _ = entity.set_changed(&mut *host);
        Ok(1)
    })
    .unwrap_or(0)
}

// ---------------------------------------------------------------------------
// The blazing agitator (`BlazingAgitatorTileEntity`, `BlazingAgitatorAlgorithm`, `AgitatorData`)
// ---------------------------------------------------------------------------

/// `rftoolspower:blazing_agitator` (`BlazingModule.BLAZING_AGITATOR`).
pub(crate) const AGITATOR: &str = "rftoolspower:blazing_agitator";
/// Its block entity type, named apart from its block for the reason [`GENERATOR_TYPE`] is.
const AGITATOR_TYPE: &str = "blazing_agitator_block_entity";
/// That type's registry id, which a broken agitator's payload names.
const AGITATOR_TYPE_ID: &str = "rftoolspower:blazing_agitator_block_entity";
/// A plain blaze rod: the box takes it and turns it into a blazing rod (`isValidBlazingRod`).
const BLAZE_ROD: &str = "minecraft:blaze_rod";
/// One saved lock per input slot (`AgitatorData.locked`).
const KEY_LOCK: &str = "lock";
/// What a read where no agitator stands answers.
const NO_AGITATOR: &str = "No RFTools Power blazing agitator there.";

/// The agitator's container: nine rod slots and nine output slots (upstream's two 3×3 boxes).
pub(crate) fn agitator_container() -> ModContainer {
    let all: Vec<usize> = (0..AGITATOR_SLOTS + AGITATOR_OUTPUTS).collect();
    ModContainer {
        slots: all.len(),
        faces: std::array::from_fn(|_| all.clone()),
        inputs: (0..AGITATOR_SLOTS).collect(),
        outputs: (AGITATOR_SLOTS..AGITATOR_SLOTS + AGITATOR_OUTPUTS).collect(),
        menu: None,
    }
}

/// The agitator's buffer: upstream's `GenericEnergyStorage(this, true, 50000, 100)` — it takes
/// [`AGITATOR_INSERT_PER_TICK`] an insert on any face and gives nothing out (it has no output).
pub(crate) fn agitator_battery() -> ModEnergyBuffer {
    ModEnergyBuffer {
        capacity: AGITATOR_CAPACITY,
        max_insert: AGITATOR_INSERT_PER_TICK,
        max_extract: 0,
        insert_faces: [true; 6],
        extract_faces: [false; 6],
    }
}

/// The agitator's saved state: its store and the nine locks (`saveAdditional` + `AgitatorData`).
pub(crate) fn read_agitator(saved: &Tag) -> Agitator {
    let mut agitator = Agitator {
        energy: clamp_agitator(int(saved, KEY_ENERGY)),
        ..Agitator::default()
    };
    for (slot, locked) in agitator.locks.iter_mut().enumerate() {
        *locked = flag(saved, &format!("{KEY_LOCK}{slot}"));
    }
    agitator
}

/// Write the agitator back into a saved compound.
pub(crate) fn write_agitator(saved: &mut Tag, state: &Agitator) {
    set_int(saved, KEY_ENERGY, state.energy);
    for (slot, locked) in state.locks.iter().enumerate() {
        set_flag(saved, &format!("{KEY_LOCK}{slot}"), *locked);
    }
}

/// A blazing-rod stack carrying `rod`, built from the item registry (`new ItemStack(BLAZING_ROD)`
/// then `setPowerQuality`-style writes). `None` when the item is not registered here.
fn rod_stack(host: &dyn Host, rod: Rod) -> Option<ItemStack> {
    let key = host.item_key(&Identifier::parse(BLAZING_ROD).ok()?)?;
    let mut stack = ItemStack::of(key);
    stack.set(&RodData, rod).ok()?;
    Some(stack)
}

/// What one slot of the agitator's box holds, read from its item.
fn rod_slot(host: &dyn Host, stack: Option<&ItemStack>) -> RodSlot {
    let Some(stack) = stack else {
        return RodSlot::Empty;
    };
    match item_id(host, stack).as_str() {
        BLAZING_ROD => RodSlot::Rod(rod_of(stack)),
        BLAZE_ROD => RodSlot::BlazeRod,
        _ => RodSlot::Foreign,
    }
}

/// What the tick wants the container to do with one slot.
#[derive(Clone, Copy, Debug, PartialEq)]
enum SlotWrite {
    /// Nothing: the item stays, the rod's data is already what the tick left it.
    Leave,
    /// The slot loses its rod (the tick moved it to an output slot).
    Clear,
    /// The slot's rod, with the data the tick wrote.
    Rod(Rod),
}

/// Compare a slot's model after the tick with what it held before.
///
/// A slot whose model is unchanged is left alone (no stack is rebuilt every tick), a rod that
/// went to the output box clears its slot, and an agitated rod's new data goes back onto a fresh
/// blazing-rod stack. An item that is no rod is never touched: the tick's model for such a slot
/// is always [`RodSlot::Foreign`], so the last arm cannot fire for it.
fn slot_write(current: RodSlot, model: RodSlot) -> SlotWrite {
    if current == model {
        return SlotWrite::Leave;
    }
    match model {
        RodSlot::Rod(rod) => SlotWrite::Rod(rod),
        RodSlot::Empty if current.is_rod() => SlotWrite::Clear,
        _ => SlotWrite::Leave,
    }
}

/// One agitator tick (`tickServer` → `tickRods`): pay the 10 FE, convert, agitate and move.
///
/// True when the saved payload or a slot moved (the tick's reply decides whether this Part's
/// edits are applied at all).
pub(crate) fn tick_agitator(
    host: &mut dyn ServerHost,
    saved: &mut Tag,
    items: &mut Vec<Option<ItemStack>>,
) -> bool {
    let before = read_agitator(saved);
    let mut state = before;
    let total = AGITATOR_SLOTS + AGITATOR_OUTPUTS;
    if items.len() != total {
        items.resize(total, None);
    }
    let mut box_rods: [RodSlot; AGITATOR_SLOTS] =
        std::array::from_fn(|slot| rod_slot(&*host, items[slot].as_ref()));
    let mut outputs: [RodSlot; AGITATOR_OUTPUTS] =
        std::array::from_fn(|slot| rod_slot(&*host, items[AGITATOR_SLOTS + slot].as_ref()));
    let agitation = state.tick(true, &mut box_rods, &mut outputs);
    let mut changed = agitation.changed || state != before;
    for (slot, model) in box_rods.iter().enumerate() {
        let current = rod_slot(&*host, items[slot].as_ref());
        match slot_write(current, *model) {
            SlotWrite::Leave => {}
            SlotWrite::Clear => {
                items[slot] = None;
                changed = true;
            }
            SlotWrite::Rod(rod) => {
                if let Some(stack) = rod_stack(&*host, rod) {
                    items[slot] = Some(stack);
                    changed = true;
                }
            }
        }
    }
    for (slot, model) in outputs.iter().enumerate() {
        let index = AGITATOR_SLOTS + slot;
        let current = rod_slot(&*host, items[index].as_ref());
        match slot_write(current, *model) {
            SlotWrite::Leave => {}
            SlotWrite::Clear => {
                items[index] = None;
                changed = true;
            }
            SlotWrite::Rod(rod) => {
                if let Some(stack) = rod_stack(&*host, rod) {
                    items[index] = Some(stack);
                    changed = true;
                }
            }
        }
    }
    write_agitator(saved, &state);
    changed
}

/// The agitator's line, as `/rftoolspower agitator` and a click print it.
pub(crate) fn agitator_line(
    pos: [i32; 3],
    state: &Agitator,
    slots: &[Option<Rod>; AGITATOR_SLOTS],
    rods: &[Option<String>; AGITATOR_SLOTS],
    outputs: &[Option<String>; AGITATOR_OUTPUTS],
    t: i64,
    nonce: Option<&str>,
) -> String {
    let list = |pick: fn(&Rod) -> f32| -> String {
        slots
            .iter()
            .map(|slot| slot.map_or("-".to_owned(), |rod| format!("{:.6}", pick(&rod))))
            .collect::<Vec<String>>()
            .join(",")
    };
    let locks: String = state
        .locks
        .iter()
        .map(|locked| if *locked { '1' } else { '0' })
        .collect();
    let names = |slots: &[Option<String>]| -> String {
        slots
            .iter()
            .map(|slot| slot.as_deref().unwrap_or("empty"))
            .collect::<Vec<&str>>()
            .join(",")
    };
    let suffix = nonce.map_or(String::new(), |nonce| format!(" nonce={nonce}"));
    format!(
        "Blazing Agitator at {},{},{}: {}/{} FE (ready {}, time={}, quality={}, duration={}, \
         locks={locks}, rods={}, out={}, t={t}{suffix})",
        pos[0],
        pos[1],
        pos[2],
        state.energy,
        AGITATOR_CAPACITY,
        state.energy >= AGITATOR_USE_PER_TICK,
        list(|rod| rod.time),
        list(|rod| rod.quality),
        list(|rod| rod.duration),
        names(rods),
        names(outputs),
    )
}

/// The slots an agitator block entity holds, as [`agitator_line`] wants them.
type AgitatorSlots = (
    [Option<Rod>; AGITATOR_SLOTS],
    [Option<String>; AGITATOR_SLOTS],
    [Option<String>; AGITATOR_OUTPUTS],
);

/// Read the nine input rods and the nine output items off a block entity.
fn agitator_slots(host: &mut dyn ServerHost, entity: mod_api::BlockEntityRef) -> AgitatorSlots {
    let stack = |host: &mut dyn ServerHost, slot: usize| -> Option<ItemStack> {
        entity.item_slot(&*host, slot as u32).ok().flatten()
    };
    let rods: [Option<String>; AGITATOR_SLOTS] =
        std::array::from_fn(|slot| stack(host, slot).map(|held| item_id(&*host, &held)));
    let outputs: [Option<String>; AGITATOR_OUTPUTS] = std::array::from_fn(|slot| {
        stack(host, AGITATOR_SLOTS + slot).map(|held| item_id(&*host, &held))
    });
    let slots: [Option<Rod>; AGITATOR_SLOTS] = std::array::from_fn(|slot| {
        stack(host, slot)
            .filter(|held| item_id(&*host, held) == BLAZING_ROD)
            .map(|held| rod_of(&held))
    });
    (slots, rods, outputs)
}

/// The line `/rftoolspower agitator <pos>` prints for the block at `pos`.
pub(crate) fn agitator_status_line(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    nonce: Option<&str>,
) -> String {
    if block_id(&*host, level, pos).as_deref() != Some(AGITATOR) {
        return NO_AGITATOR.to_owned();
    }
    let Some(entity) = host.block_entity(level, pos) else {
        return NO_AGITATOR.to_owned();
    };
    let Some(saved) = entity.data(&*host) else {
        return NO_AGITATOR.to_owned();
    };
    let (slots, rods, outputs) = agitator_slots(host, entity);
    let t = level.game_time(&*host).unwrap_or(0);
    agitator_line(
        pos,
        &read_agitator(&Tag::Compound(saved)),
        &slots,
        &rods,
        &outputs,
        t,
        nonce,
    )
}

/// `/rftoolspower agitatelock <pos> <slot> <on|off>`: the GUI's lock checkbox, and the echo.
pub(crate) fn set_agitator_lock(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    slot: i32,
    word: &str,
    nonce: Option<&str>,
) -> String {
    if block_id(&*host, level, pos).as_deref() != Some(AGITATOR) {
        return NO_AGITATOR.to_owned();
    }
    let Some(index) = usize::try_from(slot)
        .ok()
        .filter(|slot| *slot < AGITATOR_SLOTS)
    else {
        return format!(
            "Blazing Agitator at {},{},{}: slot {slot} is not one of 0..{}",
            pos[0],
            pos[1],
            pos[2],
            AGITATOR_SLOTS - 1
        );
    };
    let locked = match word {
        "on" => true,
        "off" => false,
        other => {
            return format!(
                "Blazing Agitator at {},{},{}: unknown lock '{other}' (on|off)",
                pos[0], pos[1], pos[2]
            );
        }
    };
    let Some(mut state) = agitator_at(host, level, pos) else {
        return NO_AGITATOR.to_owned();
    };
    state.locks[index] = locked;
    write_agitator_at(host, level, pos, &state);
    agitator_status_line(host, level, pos, nonce)
}

/// The agitator's saved state at `pos`, if that block is one.
fn agitator_at(host: &mut dyn ServerHost, level: LevelRef, pos: [i32; 3]) -> Option<Agitator> {
    if block_id(&*host, level, pos).as_deref() != Some(AGITATOR) {
        return None;
    }
    let entity = host.block_entity(level, pos)?;
    let saved = entity.data(&*host)?;
    Some(read_agitator(&Tag::Compound(saved)))
}

/// Write the agitator's state back; false when it did not change.
fn write_agitator_at(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    state: &Agitator,
) -> bool {
    let Some(entity) = host.block_entity(level, pos) else {
        return false;
    };
    let Some(saved) = entity.data(&*host) else {
        return false;
    };
    let mut saved = Tag::Compound(saved);
    if read_agitator(&saved) == *state {
        return false;
    }
    write_agitator(&mut saved, state);
    if let Tag::Compound(data) = saved {
        let _ = entity.replace_data(host, data);
    }
    let _ = entity.set_changed(&mut *host);
    true
}

/// `PlayerInteractEvent.RightClickBlock`: an agitator takes every click as its own — a valid rod
/// goes into the first empty slot of the 3×3 box, anything else is refused with a line, an empty
/// hand reads the machine out — and nothing else acts (upstream opens its GUI).
pub(crate) fn agitator_click(
    host: &mut dyn ServerHost,
    click: &BlockClick<'_>,
    held: Option<&ItemStack>,
) -> Option<InteractionResult> {
    let level = host.level(click.dimension.key().id())?;
    if block_id(&*host, level, click.pos).as_deref() != Some(AGITATOR) {
        return None;
    }
    let Some(held) = held.filter(|stack| stack.count() > 0) else {
        let line = agitator_status_line(host, level, click.pos, None);
        if let Some(player) = host.player(click.player) {
            let _ = player.action_bar(host, Text::literal(line));
        }
        return Some(InteractionResult::Success);
    };
    // `isValidBlazingRod`: a blaze rod, or a blazing rod that has not been infused yet.
    let valid = {
        let id = item_id(&*host, held);
        id == BLAZE_ROD || (id == BLAZING_ROD && rod_of(held).steps >= ROD_START_STEPS)
    };
    if !valid {
        let refused = item_id(&*host, held);
        if let Some(player) = host.player(click.player) {
            let _ = player.action_bar(
                host,
                Text::literal(format!(
                    "{refused} is not a blazing rod with infusion steps left"
                )),
            );
        }
        return Some(InteractionResult::Success);
    }
    let Some(slot) = free_rod_slot(host, level, click.pos, AGITATOR_SLOTS) else {
        if let Some(player) = host.player(click.player) {
            let _ = player.action_bar(host, Text::literal("all nine blazing rod slots are full"));
        }
        return Some(InteractionResult::Success);
    };
    let hand = ItemPlace::PlayerHand {
        player: click.player,
        hand: click.hand,
    };
    if insert_rod_from_hand(host, level, click.pos, held, &hand, slot) == 0
        && let Some(player) = host.player(click.player)
    {
        let _ = player.action_bar(host, Text::literal("the rod did not go in"));
    }
    Some(InteractionResult::Success)
}

// ---------------------------------------------------------------------------
// The command
// ---------------------------------------------------------------------------

/// The mod's commands. `info`, `monitor`, `cell`, `endergenic`, `injector` and `endermonitor` are
/// the harness's readouts (there is no GUI in this slice); `band` sets the monitor's alarm band,
/// `side` sets a powercell face's mode, `enderlink` is the smart wrench's link and `endermonitor`
/// (with a mode word) is the ender monitor's GUI picker — the stand-ins for what the port does
/// not carry.
pub(crate) fn declare_commands(commands: &mut Vec<Command>) {
    for usage in [
        "rftoolspower info <pos:block_pos> [nonce:word]",
        "rftoolspower monitor <pos:block_pos> [nonce:word]",
        "rftoolspower powerlevel <pos:block_pos> [nonce:word]",
        "rftoolspower band <pos:block_pos> <minimum:integer> <maximum:integer>",
        "rftoolspower cell <pos:block_pos> [nonce:word]",
        "rftoolspower side <pos:block_pos> <face:word> <mode:word>",
        "rftoolspower endergenic <pos:block_pos> [nonce:word]",
        "rftoolspower injector <pos:block_pos> [nonce:word]",
        "rftoolspower enderlink <pos:block_pos> <destination:block_pos>",
        "rftoolspower endermonitor <pos:block_pos> <action:word> [nonce:word]",
        "rftoolspower blazing <pos:block_pos> [nonce:word]",
        "rftoolspower agitator <pos:block_pos> [nonce:word]",
        "rftoolspower agitatelock <pos:block_pos> <slot:integer> <lock:word> [nonce:word]",
    ] {
        commands.push(Command::op(usage, OPERATOR_LEVEL));
    }
}

/// Whether a command source may read a generator: an operator, or the console (level 4).
fn may_read(permission: mod_api::PermissionLevel) -> bool {
    permission.level() >= OPERATOR_LEVEL
}

/// The one line the command prints for the block at `pos`.
pub(crate) fn status_line(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    nonce: Option<&str>,
) -> String {
    if block_id(&*host, level, pos).as_deref() != Some(GENERATOR) {
        return NO_GENERATOR.to_owned();
    }
    let Some(entity) = host.block_entity(level, pos) else {
        return NO_GENERATOR.to_owned();
    };
    let Some(saved) = entity.data(&*host) else {
        return NO_GENERATOR.to_owned();
    };
    let fuel = entity
        .item_slot(&*host, FUEL_SLOT as u32)
        .ok()
        .flatten()
        .map(|stack| (stack.item().id(&*host), stack.count()));
    let t = level.game_time(&*host).unwrap_or(0);
    generator_line(
        pos,
        &read_generator(&Tag::Compound(saved)),
        fuel.as_ref().map(|(item, count)| (item.as_str(), *count)),
        t,
        nonce,
    )
}

/// The running level the command was run in.
fn command_level(host: &mut dyn ServerHost, event: &RunModCommandEvent<'_>) -> Option<LevelRef> {
    host.levels()
        .list_levels()
        .into_iter()
        .find(|level| level.dimension() == event.command.dimension)
}

/// The harness's nonce, which proves a reply is fresh.
fn nonce_of<'a>(event: &'a RunModCommandEvent<'_>) -> Option<&'a str> {
    match event.command.argument("nonce") {
        Some(CommandArgumentValue::String(word)) => Some(word.as_str()),
        _ => None,
    }
}

/// A required integer argument, 0 when it is absent or another kind.
fn integer_of(event: &RunModCommandEvent<'_>, name: &str) -> i32 {
    match event.command.argument(name) {
        Some(CommandArgumentValue::Integer(value)) => *value,
        _ => 0,
    }
}

/// A plain `word` argument, as typed.
fn word_of<'a>(event: &'a RunModCommandEvent<'_>, name: &str) -> Option<&'a str> {
    match event.command.argument(name) {
        Some(CommandArgumentValue::String(word)) => Some(word.as_str()),
        _ => None,
    }
}

/// Run `/rftoolspower info|monitor|band|cell|side|endergenic|injector|enderlink …`;
/// `Flow::Cancel` when it was ours.
pub(crate) fn run_command(host: &mut dyn ServerHost, event: &mut RunModCommandEvent<'_>) -> Flow {
    let literals: Vec<&str> = event.command.literals.iter().map(String::as_str).collect();
    let subcommand = match literals.as_slice() {
        ["rftoolspower", name] => *name,
        _ => return Flow::Continue,
    };
    if !matches!(
        subcommand,
        "info"
            | "monitor"
            | "powerlevel"
            | "band"
            | "cell"
            | "side"
            | "endergenic"
            | "injector"
            | "enderlink"
            | "endermonitor"
            | "blazing"
            | "agitator"
            | "agitatelock"
    ) {
        return Flow::Continue;
    }
    if !may_read(event.source.permission()) {
        let _ = host.commands().feedback(Text::literal(format!(
            "rftoolspower {subcommand} needs an operator (permission level {OPERATOR_LEVEL})"
        )));
        return Flow::Cancel;
    }
    let Some(CommandArgumentValue::BlockPos(pos)) = event.command.argument("pos") else {
        return Flow::Continue;
    };
    let level = command_level(host, event);
    if level.is_none() {
        let _ = host.commands().feedback(Text::literal(match subcommand {
            "monitor" | "band" => NO_MONITOR,
            "powerlevel" => NO_POWER_LEVEL,
            "cell" | "side" => NO_CELL,
            "endergenic" | "enderlink" => NO_ENDERGENIC,
            "injector" => NO_INJECTOR,
            "endermonitor" => NO_ENDER_MONITOR,
            "blazing" => NO_BLAZING,
            "agitator" | "agitatelock" => NO_AGITATOR,
            _ => NO_GENERATOR,
        }));
        return Flow::Cancel;
    }
    let Some(level) = level else {
        return Flow::Cancel;
    };
    let line = match subcommand {
        "info" => status_line(host, level, *pos, nonce_of(event)),
        "monitor" => monitor_status_line(host, level, *pos, nonce_of(event)),
        "powerlevel" => power_level_status_line(host, level, *pos, nonce_of(event)),
        "cell" => cell_status_line(host, level, *pos, nonce_of(event)),
        "side" => set_side(
            host,
            level,
            *pos,
            word_of(event, "face").unwrap_or_default(),
            word_of(event, "mode").unwrap_or_default(),
        ),
        "endergenic" => endergenic_status_line(host, level, *pos, nonce_of(event)),
        "injector" => injector_status_line(host, level, *pos, nonce_of(event)),
        "blazing" => blazing_status_line(host, level, *pos, nonce_of(event)),
        "agitator" => agitator_status_line(host, level, *pos, nonce_of(event)),
        "agitatelock" => set_agitator_lock(
            host,
            level,
            *pos,
            integer_of(event, "slot"),
            word_of(event, "lock").unwrap_or_default(),
            nonce_of(event),
        ),
        "endermonitor" => match word_of(event, "action") {
            None | Some("status") => ender_monitor_status_line(host, level, *pos, nonce_of(event)),
            Some(word) => set_monitor_mode(host, level, *pos, word, nonce_of(event)),
        },
        "enderlink" => match event.command.argument("destination") {
            Some(CommandArgumentValue::BlockPos(destination)) => {
                set_link(host, level, *pos, *destination)
            }
            _ => format!(
                "Endergenic at {},{},{}: no destination given",
                pos[0], pos[1], pos[2]
            ),
        },
        _ => set_band(
            host,
            level,
            *pos,
            integer_of(event, "minimum"),
            integer_of(event, "maximum"),
        ),
    };
    let _ = host.commands().feedback(Text::literal(line));
    Flow::Cancel
}

// ---------------------------------------------------------------------------
// The Part
// ---------------------------------------------------------------------------

/// The Coal Generator: it ticks, and a click puts fuel in its slot.
pub(crate) struct GeneratorPart;

#[mod_api::horizon_part]
impl BlockPart for GeneratorPart {
    fn use_item_on(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseItemOnEvent<'_>,
    ) -> Option<InteractionResult> {
        generator_click(host, event.click, event.click.stack)
    }

    fn use_without_item(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseWithoutItemEvent<'_>,
    ) -> Option<InteractionResult> {
        generator_click(host, event.click, None)
    }
}

#[mod_api::horizon_part]
impl BlockEntityPart for GeneratorPart {
    /// `EntityBlock.newBlockEntity`: an empty saved compound; the tick fills it.
    fn block_entity(
        &self,
        _level: LevelSide,
        _event: &mut BlockEntityEvent<'_>,
    ) -> Option<Compound> {
        Some(Compound::new())
    }

    /// `EntityBlock.getTicker`: it ticks. Never clear a value an earlier mod set.
    fn block_entity_ticks(&self, _host: &dyn Host, event: &mut BlockEntityTicksEvent<'_>) {
        event.ticks = true;
    }

    /// One server tick: fuel, burn, FE and the `lit` mirror.
    fn block_entity_tick(&self, host: &mut dyn ServerHost, event: &mut BlockEntityTickEvent<'_>) {
        let pos = event.pos;
        let level = in_place_level(host);
        if event.entity.items.len() != SLOTS {
            event.entity.items.resize(SLOTS, None);
        }
        let mut saved = Tag::Compound(std::mem::take(&mut event.entity.nbt));
        let items = &mut event.entity.items;
        let changed = tick_generator(host, level, pos, &mut saved, items);
        if let Tag::Compound(nbt) = saved {
            event.entity.nbt = nbt;
        }
        if !changed {
            *event.reply = BlockEntityTickReply::Unchanged;
        }
    }
}

// ---------------------------------------------------------------------------
// The endergenic generator and the pearl injector
// ---------------------------------------------------------------------------

/// `rftoolspower:endergenic` (`EndergenicModule.ENDERGENIC`).
pub(crate) const ENDERGENIC: &str = "rftoolspower:endergenic";
/// Its block entity type, named apart from its block for the reason [`GENERATOR_TYPE`] is.
const ENDERGENIC_TYPE: &str = "endergenic_block_entity";
/// That type's registry id, which the endergenic item's `block_entity_data` names.
const ENDERGENIC_TYPE_ID: &str = "rftoolspower:endergenic_block_entity";
/// `rftoolspower:pearl_injector` (`EndergenicModule.PEARL_INJECTOR`).
pub(crate) const INJECTOR: &str = "rftoolspower:pearl_injector";
const INJECTOR_TYPE: &str = "pearl_injector_block_entity";
/// The generator's saved fields (upstream's `charging`, `age`, `dest`, `distance`, `prevIn`,
/// `pearls`, plus the counters the readout prints).
const KEY_CHARGING: &str = "charging";
const KEY_AGE: &str = "age";
const KEY_DEST: &str = "dest";
const KEY_DISTANCE: &str = "distance";
const KEY_PREV: &str = "prev";
const KEY_PEARLS: &str = "pearls";
const KEY_GAINED: &str = "gained";
const KEY_SPENT: &str = "spent";
const KEY_LAUNCHED: &str = "launched";
const KEY_DROPPED: &str = "dropped";
const KEY_ARRIVED: &str = "arrived";
/// Why the last pearl was dropped (upstream's `lastPearlsLostReason`, kept for the readout).
const KEY_LOSS: &str = "loss";
/// What a read where no generator / no injector stands answers.
const NO_ENDERGENIC: &str = "No RFTools Power endergenic generator there.";
const NO_INJECTOR: &str = "No RFTools Power pearl injector there.";

// The ender monitor (`EndergenicModule.ENDER_MONITOR`). Its type is named apart from its block
// for the reason [`GENERATOR_TYPE`] is; it carries no container and no buffer.
/// `rftoolspower:ender_monitor`.
pub(crate) const ENDER_MONITOR: &str = "rftoolspower:ender_monitor";
const ENDER_MONITOR_TYPE: &str = "ender_monitor_block_entity";
/// That type's registry id, which a broken monitor's `block_entity_data` payload names.
const ENDER_MONITOR_TYPE_ID: &str = "rftoolspower:ender_monitor_block_entity";
/// The mode it watches (upstream's `EnderMonitorData.mode`, in its codec's spelling). The
/// powercell's `mode` key is a different value on a different block, so this one is named apart.
const KEY_MONITOR_MODE: &str = "mode";
/// Upstream's saved `needPulse`, which the tick spends as its one-tick output.
const KEY_NEED_PULSE: &str = "needPulse";
/// The readout's pulse counter.
const KEY_PULSES: &str = "pulses";
/// The mode of the last event it armed for.
const KEY_LAST: &str = "last";
/// What a read where no ender monitor stands answers.
const NO_ENDER_MONITOR: &str = "No RFTools Power ender monitor there.";

/// A saved long, 0 when absent or of another type.
fn long(saved: &Tag, key: &str) -> i64 {
    match saved.get(key) {
        Some(Tag::Long(value)) => *value,
        Some(Tag::Int(value)) => i64::from(*value),
        _ => 0,
    }
}

/// Write one long into a saved compound.
fn set_long(saved: &mut Tag, key: &str, value: i64) {
    if let Tag::Compound(nbt) = saved {
        nbt.insert(key.into(), Tag::Long(value));
    }
}

/// A saved position (`BlockPosTools.write`), as three ints under one key.
fn position(saved: &Tag, key: &str) -> Option<[i32; 3]> {
    match saved.get(key) {
        Some(Tag::IntArray(values)) if values.len() == 3 => Some([values[0], values[1], values[2]]),
        _ => None,
    }
}

/// Write one position as three ints under one key.
fn set_position(saved: &mut Tag, key: &str, pos: [i32; 3]) {
    if let Tag::Compound(nbt) = saved {
        nbt.insert(key.into(), Tag::IntArray(pos.to_vec()));
    }
}

/// The pearls a saved compound holds (`loadAdditional`'s `pearls` list).
fn read_pearls(saved: &Tag) -> Vec<crate::runtime::Pearl> {
    let Some(Tag::List(list)) = saved.get(KEY_PEARLS) else {
        return Vec::new();
    };
    list.iter()
        .filter_map(|entry| {
            let ticks_left = int(entry, "t");
            let age = int(entry, "age");
            let destination = position(entry, KEY_DEST)?;
            Some(crate::runtime::Pearl {
                ticks_left,
                destination,
                age,
            })
        })
        .collect()
}

/// Write the pearls back in the same shape.
fn write_pearls(saved: &mut Tag, pearls: &[crate::runtime::Pearl]) {
    let list: Vec<Tag> = pearls
        .iter()
        .map(|pearl| {
            let mut entry = Compound::new();
            entry.insert("t".into(), Tag::Int(pearl.ticks_left));
            entry.insert("age".into(), Tag::Int(pearl.age));
            entry.insert(KEY_DEST.into(), Tag::IntArray(pearl.destination.to_vec()));
            Tag::Compound(entry)
        })
        .collect();
    if let Tag::Compound(nbt) = saved {
        nbt.insert(KEY_PEARLS.into(), Tag::List(list));
    }
}

/// The generator a saved compound holds, every value clamped.
pub(crate) fn read_endergenic(saved: &Tag) -> Endergenic {
    let mut state = Endergenic::restored(
        int(saved, KEY_ENERGY),
        int(saved, KEY_CHARGING),
        int(saved, KEY_AGE),
        position(saved, KEY_DEST),
        int(saved, KEY_DISTANCE),
        flag(saved, KEY_PREV),
        read_pearls(saved),
        long(saved, KEY_GAINED),
        long(saved, KEY_SPENT),
        int(saved, KEY_LAUNCHED),
        int(saved, KEY_DROPPED),
        int_or(saved, KEY_ARRIVED, -2),
    );
    state.last_loss = text(saved, KEY_LOSS).and_then(|reason| Loss::parse(&reason));
    state
}

/// Write the generator back into a saved compound.
pub(crate) fn write_endergenic(saved: &mut Tag, state: &Endergenic) {
    set_int(saved, KEY_ENERGY, state.energy);
    set_int(saved, KEY_CHARGING, state.charging);
    set_int(saved, KEY_AGE, state.age);
    match state.destination {
        Some(position) => {
            set_position(saved, KEY_DEST, position);
            set_int(saved, KEY_DISTANCE, state.distance);
        }
        None => {
            if let Tag::Compound(nbt) = &mut *saved {
                nbt.remove(&KEY_DEST.into());
            }
            set_int(saved, KEY_DISTANCE, 0);
        }
    }
    set_flag(saved, KEY_PREV, state.prev_in);
    write_pearls(saved, &state.pearls);
    set_long(saved, KEY_GAINED, state.gained);
    set_long(saved, KEY_SPENT, state.spent);
    set_int(
        saved,
        KEY_LAUNCHED,
        i32::try_from(state.launched).unwrap_or(i32::MAX),
    );
    set_int(
        saved,
        KEY_DROPPED,
        i32::try_from(state.dropped).unwrap_or(i32::MAX),
    );
    set_int(saved, KEY_ARRIVED, state.arrived_at);
    match state.last_loss {
        Some(loss) => set_text(saved, KEY_LOSS, loss.text()),
        None => {
            if let Tag::Compound(nbt) = &mut *saved {
                nbt.remove(&KEY_LOSS.into());
            }
        }
    }
}

/// The mode a saved string names, or the attachment's default when the key is absent or unknown.
fn saved_mode(saved: &Tag) -> MonitorMode {
    text(saved, KEY_MONITOR_MODE)
        .as_deref()
        .and_then(MonitorMode::parse_saved)
        .unwrap_or_default()
}

/// The ender monitor a saved compound holds (`EnderMonitorData.mode`, `needPulse`, the counters).
pub(crate) fn read_ender_monitor(saved: &Tag) -> EnderMonitor {
    let pulses = u32::try_from(int(saved, KEY_PULSES)).unwrap_or(0);
    let last = text(saved, KEY_LAST)
        .as_deref()
        .and_then(MonitorMode::parse_saved);
    EnderMonitor::restored(saved_mode(saved), flag(saved, KEY_NEED_PULSE), pulses, last)
}

/// Write an ender monitor back into a saved compound.
pub(crate) fn write_ender_monitor(saved: &mut Tag, state: &EnderMonitor) {
    set_text(saved, KEY_MONITOR_MODE, state.mode.saved());
    set_flag(saved, KEY_NEED_PULSE, state.need_pulse);
    set_int(
        saved,
        KEY_PULSES,
        i32::try_from(state.pulses).unwrap_or(i32::MAX),
    );
    match state.last {
        Some(mode) => set_text(saved, KEY_LAST, mode.saved()),
        None => {
            if let Tag::Compound(nbt) = &mut *saved {
                nbt.remove(&KEY_LAST.into());
            }
        }
    }
}

/// The ender monitor at `pos`, if the block there is one.
fn ender_monitor_at(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
) -> Option<EnderMonitor> {
    if block_id(&*host, level, pos).as_deref() != Some(ENDER_MONITOR) {
        return None;
    }
    let entity = host.block_entity(level, pos)?;
    let saved = entity.data(&*host)?;
    Some(read_ender_monitor(&Tag::Compound(saved)))
}

/// Write a monitor's state back to its block entity. True when it differs from what was there.
fn write_ender_monitor_at(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    state: &EnderMonitor,
) -> bool {
    let Some(entity) = host.block_entity(level, pos) else {
        return false;
    };
    let Some(saved) = entity.data(&*host) else {
        return false;
    };
    let mut saved = Tag::Compound(saved);
    if read_ender_monitor(&saved) == *state {
        return false;
    }
    write_ender_monitor(&mut saved, state);
    if let Tag::Compound(data) = saved {
        let _ = entity.replace_data(host, data);
    }
    let _ = entity.set_changed(&mut *host);
    true
}

/// Something happened at the generator at `pos`: tell every ender monitor that watches it
/// (upstream's `fireMonitors`).
///
/// A monitor watches the generator its **display** faces away from (upstream's
/// `inputSide == dir.getOpposite()`), so the monitor at `pos + direction` fires when its `facing`
/// names `direction`.
pub(crate) fn fire_monitors(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    mode: MonitorMode,
) {
    for direction in Direction::ALL {
        let normal = direction.normal();
        let at = [pos[0] + normal[0], pos[1] + normal[1], pos[2] + normal[2]];
        if block_id(&*host, level, at).as_deref() != Some(ENDER_MONITOR) {
            continue;
        }
        let display = level
            .block_property(&*host, at, KEY_FACING)
            .and_then(|name| dir_from_name(name.as_str()));
        if display != Some(direction) {
            // A monitor mounted on this generator but watching another mode or another block.
            continue;
        }
        let Some(mut state) = ender_monitor_at(host, level, at) else {
            continue;
        };
        if state.notice(mode) {
            write_ender_monitor_at(host, level, at, &state);
        }
    }
}

/// The generator at `pos`, if the block there is one.
fn endergenic_at(host: &mut dyn ServerHost, level: LevelRef, pos: [i32; 3]) -> Option<Endergenic> {
    if block_id(&*host, level, pos).as_deref() != Some(ENDERGENIC) {
        return None;
    }
    let entity = host.block_entity(level, pos)?;
    let saved = entity.data(&*host)?;
    Some(read_endergenic(&Tag::Compound(saved)))
}

/// Write a generator's state back to its block entity. True when it differs from what was there.
fn write_endergenic_at(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    state: &Endergenic,
) -> bool {
    let Some(entity) = host.block_entity(level, pos) else {
        return false;
    };
    let Some(saved) = entity.data(&*host) else {
        return false;
    };
    let mut saved = Tag::Compound(saved);
    if read_endergenic(&saved) == *state {
        return false;
    }
    write_endergenic(&mut saved, state);
    if let Tag::Compound(data) = saved {
        let _ = entity.replace_data(host, data);
    }
    let _ = entity.set_changed(&mut *host);
    true
}

/// Something happened at the generator at `pos`: fire the monitors around it when there is a
/// level to read them from.
fn notify_monitors(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    pos: [i32; 3],
    mode: MonitorMode,
) {
    if let Some(level) = level {
        fire_monitors(host, level, pos, mode);
    }
}

/// One pearl arrives at the generator at `dest` (`EndergenicPearl.handleTick` →
/// `receivePearl`). A destination that is gone or no longer a generator loses the pearl, as
/// upstream's "where did the destination go?" does.
pub(crate) fn deliver_pearl(host: &mut dyn ServerHost, level: LevelRef, dest: [i32; 3], age: i32) {
    let Some(mut state) = endergenic_at(host, level, dest) else {
        return;
    };
    let gained = state.receive(age);
    write_endergenic_at(host, level, dest, &state);
    // Upstream's `receivePearl` fires `arrived` before it branches, and a miss then also fires
    // `lost` through `discardPearl`: an arrival outside the window pulses both monitor modes.
    fire_monitors(host, level, dest, MonitorMode::PearlArrived);
    if gained.is_none() {
        fire_monitors(host, level, dest, MonitorMode::LostPearl);
    }
}

/// A deterministic draw for the pearl-loss chance: the world time mixed with the position.
fn loss_seed(host: &dyn Host, level: Option<LevelRef>, pos: [i32; 3]) -> u64 {
    let time = level
        .and_then(|level| level.game_time(host))
        .unwrap_or(0)
        .unsigned_abs();
    let place = (u64::from(pos[0].unsigned_abs()) << 32)
        ^ (u64::from(pos[1].unsigned_abs()) << 16)
        ^ u64::from(pos[2].unsigned_abs());
    time.wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ place.rotate_left(17)
}

/// The endergenic's energy push (`handleSendingEnergy`): up to 20,000 FE a tick to every
/// neighbour that answers the energy capability, from the store above the 2,000 FE reserve.
pub(crate) fn push_endergenic_energy(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    pos: [i32; 3],
    state: &mut Endergenic,
) {
    let Some(level) = level else {
        return;
    };
    for direction in Direction::ALL {
        let offer = state.send_amount();
        if offer == 0 {
            break;
        }
        let normal = direction.normal();
        let target = [pos[0] + normal[0], pos[1] + normal[1], pos[2] + normal[2]];
        let Some(handler) = level.capability(host, &ENERGY, target, Some(direction.opposite()))
        else {
            continue;
        };
        let moved = host
            .transaction(|host, tx| -> Result<u32, ()> { Ok(handler.insert(host, tx, offer)) })
            .unwrap_or(0);
        state.energy -= i32::try_from(moved).unwrap_or(0);
    }
}

/// One endergenic tick (`EndergenicTileEntity.tickOnServer`), in upstream's order: the pearls in
/// flight, then the push, then the loss chance, then the redstone edge and the state machine.
///
/// True when the saved payload changed (the engine discards a tick's edits unless it says so).
pub(crate) fn tick_endergenic(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    pos: [i32; 3],
    saved: &mut Tag,
) -> bool {
    let before = read_endergenic(saved);
    let mut state = before.clone();
    let arrivals = state.tick_pearls();
    if let Some(level) = level {
        for (destination, age) in arrivals {
            deliver_pearl(host, level, destination, age);
        }
    }
    push_endergenic_energy(host, level, pos, &mut state);
    if state.holding() && pearl_lost(loss_seed(&*host, level, pos)) {
        state.discard(Loss::Chance);
        notify_monitors(host, level, pos, MonitorMode::LostPearl);
    }
    match state.pulse(power_at(&*host, level, pos)) {
        Pulse::Start => state.start_charging(),
        Pulse::Fire => {
            // Upstream's `firePearl`: a real launch fires `fired`, a generator with no
            // destination drops the pearl and fires `lost`.
            let fired = state.fire(false);
            notify_monitors(
                host,
                level,
                pos,
                if fired {
                    MonitorMode::PearlFired
                } else {
                    MonitorMode::LostPearl
                },
            );
        }
        Pulse::None => match state.charging {
            IDLE => {}
            HOLDING => {
                if !state.hold() {
                    state.discard(Loss::NotEnoughEnergy);
                    notify_monitors(host, level, pos, MonitorMode::LostPearl);
                }
            }
            _ => state.charge_step(),
        },
    }
    let changed = state != before;
    write_endergenic(saved, &state);
    changed
}

/// The redstone input at `pos`: `Level.getBestNeighborSignal`, upstream's `checkRedstone`.
fn power_at(host: &dyn Host, level: Option<LevelRef>, pos: [i32; 3]) -> i32 {
    level
        .and_then(|level| level.best_neighbor_signal(host, pos))
        .unwrap_or(0)
}

/// The generator a pearl injector feeds: upstream's `findEndergenicTileEntity` looks behind the
/// injector's front and then above it.
pub(crate) fn find_generator(host: &dyn Host, level: LevelRef, pos: [i32; 3]) -> Option<[i32; 3]> {
    let facing = level
        .block_property(host, pos, KEY_FACING)
        .and_then(|name| dir_from_name(name.as_str()))
        .unwrap_or(Direction::North);
    [facing.opposite(), Direction::Up]
        .into_iter()
        .filter_map(|direction| {
            let normal = direction.normal();
            let at = [pos[0] + normal[0], pos[1] + normal[1], pos[2] + normal[2]];
            (block_id(host, level, at).as_deref() == Some(ENDERGENIC)).then_some(at)
        })
        .next()
}

/// Take one ender pearl from an injector's buffer (`PearlInjectorTileEntity.takePearl`). True
/// when one was taken.
pub(crate) fn take_pearl(host: &dyn Host, items: &mut [Option<ItemStack>]) -> bool {
    for slot in items.iter_mut() {
        let Some(stack) = slot.clone() else {
            continue;
        };
        if stack.count() == 0 || item_id(host, &stack) != PEARL {
            continue;
        }
        *slot = stack.shrink(1);
        return true;
    }
    false
}

/// Inject one pearl (`PearlInjectorTileEntity.injectPearl`): the pearl is taken first, and a
/// generator already holding one consumes it without firing (upstream's own order).
fn inject_pearl(
    host: &mut dyn ServerHost,
    level: LevelRef,
    generator: [i32; 3],
    items: &mut [Option<ItemStack>],
) -> bool {
    if !take_pearl(&*host, items) {
        return false;
    }
    let Some(mut state) = endergenic_at(host, level, generator) else {
        return true;
    };
    if state.charging == HOLDING {
        // Upstream's comment: "If the endergenic is already holding a pearl then this one is
        // lost." The pearl is consumed and nothing is fired, and no monitor is told: upstream's
        // holding branch returns without `discardPearl`.
        return true;
    }
    let fired = state.fire(true);
    write_endergenic_at(host, level, generator, &state);
    fire_monitors(
        host,
        level,
        generator,
        if fired {
            MonitorMode::PearlFired
        } else {
            MonitorMode::LostPearl
        },
    );
    true
}

/// One pearl-injector tick (`PearlInjectorTileEntity.tickOnServer`): a redstone rising edge
/// injects one pearl into the generator it points at.
pub(crate) fn tick_injector(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    pos: [i32; 3],
    saved: &mut Tag,
    items: &mut [Option<ItemStack>],
) -> bool {
    let before = flag(saved, KEY_PREV);
    let (edge, prev) = rising_edge(before, power_at(&*host, level, pos));
    set_flag(saved, KEY_PREV, prev);
    let mut changed = prev != before;
    if edge
        && let Some(level) = level
        && let Some(generator) = find_generator(&*host, level, pos)
    {
        changed |= inject_pearl(host, level, generator, items);
    }
    changed
}

/// An endergenic generator's report line, as `/rftoolspower endergenic` prints it.
pub(crate) fn endergenic_line(
    pos: [i32; 3],
    state: &Endergenic,
    t: i64,
    nonce: Option<&str>,
) -> String {
    let destination = match state.destination {
        Some(dest) => format!("{},{},{}", dest[0], dest[1], dest[2]),
        None => "none".to_owned(),
    };
    let reason = state.last_loss.map_or("none", |loss| loss.text());
    let suffix = nonce.map_or(String::new(), |nonce| format!(" nonce={nonce}"));
    format!(
        "Endergenic at {},{},{}: energy={}/{} charging={} age={} pearls={} fired={} dropped={} \
         gained={} spent={} arrived={} reason=\"{reason}\" dest={destination} distance={} \
         t={t}{suffix}",
        pos[0],
        pos[1],
        pos[2],
        state.energy,
        ENDERGENIC_CAPACITY,
        state.charging,
        state.age,
        state.pearls.len(),
        state.launched,
        state.dropped,
        state.gained,
        state.spent,
        state.arrived_at,
        state.distance,
    )
}

/// The generator at `pos` as `/rftoolspower endergenic` prints it, or [`NO_ENDERGENIC`].
pub(crate) fn endergenic_status_line(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    nonce: Option<&str>,
) -> String {
    let Some(state) = endergenic_at(host, level, pos) else {
        return NO_ENDERGENIC.to_owned();
    };
    let t = level.game_time(&*host).unwrap_or(0);
    endergenic_line(pos, &state, t, nonce)
}

/// Link a generator to its destination (`setDestination`, the wrench's link): the pearl it fires
/// flies there in `(int)(distance / 3) + 1` ticks, and a link of 5 ticks or more is refused.
pub(crate) fn set_link(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    destination: [i32; 3],
) -> String {
    let Some(mut state) = endergenic_at(host, level, pos) else {
        return NO_ENDERGENIC.to_owned();
    };
    if block_id(&*host, level, destination).as_deref() != Some(ENDERGENIC) {
        return format!(
            "Endergenic at {},{},{}: destination {},{},{} is not an endergenic generator",
            pos[0], pos[1], pos[2], destination[0], destination[1], destination[2]
        );
    }
    let distance = Endergenic::distance_between(pos, destination);
    if distance > MAX_DISTANCE {
        return format!(
            "Endergenic at {},{},{}: distance {distance} is too far (maximum {MAX_DISTANCE})",
            pos[0], pos[1], pos[2]
        );
    }
    state.destination = Some(destination);
    state.distance = distance;
    write_endergenic_at(host, level, pos, &state);
    let t = level.game_time(&*host).unwrap_or(0);
    format!(
        "Endergenic link at {},{},{}: destination {},{},{} (distance {distance} ticks, t={t})",
        pos[0], pos[1], pos[2], destination[0], destination[1], destination[2]
    )
}

/// A pearl injector's report line, as `/rftoolspower injector` prints it.
pub(crate) fn injector_line(
    pos: [i32; 3],
    pearls: i64,
    attached: Option<[i32; 3]>,
    t: i64,
    nonce: Option<&str>,
) -> String {
    let attached = match attached {
        Some(at) => format!("{},{},{}", at[0], at[1], at[2]),
        None => "none".to_owned(),
    };
    let suffix = nonce.map_or(String::new(), |nonce| format!(" nonce={nonce}"));
    format!(
        "Pearl Injector at {},{},{}: pearls={pearls} generator={attached} t={t}{suffix}",
        pos[0], pos[1], pos[2]
    )
}

/// The injector at `pos` as `/rftoolspower injector` prints it, or [`NO_INJECTOR`].
pub(crate) fn injector_status_line(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    nonce: Option<&str>,
) -> String {
    if block_id(&*host, level, pos).as_deref() != Some(INJECTOR) {
        return NO_INJECTOR.to_owned();
    }
    let Some(entity) = host.block_entity(level, pos) else {
        return NO_INJECTOR.to_owned();
    };
    let mut pearls = 0i64;
    for slot in 0..INJECTOR_SLOTS as u32 {
        let Some(stack) = entity.item_slot(&*host, slot).ok().flatten() else {
            continue;
        };
        if item_id(&*host, &stack) == PEARL {
            pearls += i64::from(stack.count());
        }
    }
    let attached = find_generator(&*host, level, pos);
    let t = level.game_time(&*host).unwrap_or(0);
    injector_line(pos, pearls, attached, t, nonce)
}

/// The injector's container: eighteen pearl slots every face reaches, insert-only (upstream's
/// 9×2 `GenericItemHandler`; the per-item filter is recorded in `notes.md` because a container
/// declaration has no slot predicate at this pin).
pub(crate) fn injector_container() -> ModContainer {
    ModContainer {
        slots: INJECTOR_SLOTS,
        faces: std::array::from_fn(|_| (0..INJECTOR_SLOTS).collect()),
        inputs: (0..INJECTOR_SLOTS).collect(),
        outputs: vec![],
        menu: None,
    }
}

/// The endergenic's buffer: upstream's `GenericEnergyStorage(this, false, 5000000, 0)` — it
/// stores, gives nothing out through the capability (it pushes on its own tick) and takes
/// nothing in.
pub(crate) fn endergenic_battery() -> ModEnergyBuffer {
    ModEnergyBuffer {
        capacity: ENDERGENIC_CAPACITY,
        max_insert: 0,
        max_extract: 0,
        insert_faces: [false; 6],
        extract_faces: [false; 6],
    }
}

// ---------------------------------------------------------------------------
// The ender monitor
// ---------------------------------------------------------------------------

/// One ender-monitor tick (`EnderMonitorTileEntity.tickOnServer`): an owed pulse is 15 for this
/// tick, 0 after it. True when the saved state moved (the engine discards a tick's edits unless
/// it says so).
pub(crate) fn tick_ender_monitor(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    pos: [i32; 3],
    saved: &mut Tag,
) -> bool {
    let before = read_ender_monitor(saved);
    let mut state = before.clone();
    let signal = state.tick();
    let changed = state != before;
    if changed {
        write_ender_monitor(saved, &state);
    }
    if let Some(level) = level {
        mirror_ender_monitor(host, level, pos, signal);
    }
    changed
}

/// Mirror the monitor's one-tick output into its `lit` state, and let the neighbours re-read the
/// redstone when it moved: a lamp on the display side lights on the pulse's tick and goes dark
/// when the next tick clears it.
fn mirror_ender_monitor(host: &mut dyn ServerHost, level: LevelRef, pos: [i32; 3], signal: i32) {
    let lit = signal > 0;
    let current = level
        .block_property(&*host, pos, KEY_LIT)
        .map(|value| value.as_str() == "true");
    if current == Some(lit) {
        return;
    }
    let _ = host.set_block_property(pos, KEY_LIT, if lit { "true" } else { "false" });
    if let Some(source) = level.block_state(&*host, pos) {
        let _ = level.update_neighbors(host, pos, source, NeighbourUpdate::Neighbours);
    }
}

/// A state decoded for `block_signal`, cached by ordinal: a state's properties never change.
#[derive(Clone, Copy)]
struct EnderMonitorFace {
    display: Direction,
    lit: bool,
}

static ENDER_MONITOR_FACES: LazyLock<Mutex<HashMap<BlockState, EnderMonitorFace>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Decode a serialized ender-monitor state into its display face and pulse
/// (`rftoolspower:ender_monitor[facing=east,lit=false]`).
pub(crate) fn parse_ender_monitor_state(text: &str) -> Option<(Direction, bool)> {
    let (block, rest) = text.split_once('[')?;
    if block != ENDER_MONITOR {
        return None;
    }
    let mut display = None;
    let mut lit = false;
    for property in rest.strip_suffix(']')?.split(',') {
        let (key, value) = property.split_once('=')?;
        match key {
            KEY_FACING => display = Some(dir_from_name(value)?),
            KEY_LIT => lit = value == "true",
            _ => {}
        }
    }
    Some((display?, lit))
}

/// The decoded state, through the cache `block_signal` (asked very often) reads.
fn ender_monitor_face(level: &dyn LevelHost, state: BlockState) -> Option<EnderMonitorFace> {
    if let Some(hit) = ENDER_MONITOR_FACES
        .lock()
        .expect("the ender monitor state cache is never held across a panic")
        .get(&state)
    {
        return Some(*hit);
    }
    let (display, lit) = parse_ender_monitor_state(&level.state_string(state)?)?;
    let face = EnderMonitorFace { display, lit };
    ENDER_MONITOR_FACES
        .lock()
        .expect("the ender monitor state cache is never held across a panic")
        .insert(state, face);
    Some(face)
}

/// `block_signal`: the pulse's 15 on the display side for the tick it fires, nothing elsewhere.
///
/// Upstream answers only `getSignal` (weak) and leaves `getDirectSignal` at 0; so does this. The
/// port answers on the display side for the reason slice 2's monitor does: upstream's
/// `getRedstoneOutput` names the input side while `setRedstoneState` notifies the display side,
/// and the two disagree (recorded in `notes.md`).
pub(crate) fn ender_monitor_signal(level: &dyn LevelHost, event: &mut BlockSignalEvent) {
    if event.direct {
        return;
    }
    let Some(face) = ender_monitor_face(level, event.state) else {
        return;
    };
    if face.lit && event.face == face.display {
        event.signal = MONITOR_SIGNAL;
    }
}

/// `is_signal_source`: an ender monitor answers the signal query, so redstone wire connects to it.
pub(crate) fn ender_monitor_signal_source(level: &dyn LevelHost, event: &mut IsSignalSourceEvent) {
    if level.state_block(event.state) == Some(ENDER_MONITOR) {
        event.source = true;
    }
}

/// `LogicSlabBlock.getStateForPlacement`: the placer's look is the monitor's display front, so
/// the generator it watches is the block behind it. Upstream also reads the click point for the
/// slab's vertical mountings; at this pin the placement carries the view angles only, so the
/// display is horizontal (recorded in `notes.md`).
pub(crate) fn ender_monitor_placement(
    level: &dyn LevelHost,
    event: &StateForPlacementEvent<'_>,
) -> Option<Option<BlockState>> {
    if level.state_block(event.state) != Some(ENDER_MONITOR) {
        return None;
    }
    let display = facing_from_yaw(event.context.yaw);
    Some(level.state_with_property(event.state, KEY_FACING, dir_name(display)))
}

/// The ender monitor's report line, as `/rftoolspower endermonitor` and a click print it.
pub(crate) fn ender_monitor_line(
    pos: [i32; 3],
    state: &EnderMonitor,
    facing: Option<Direction>,
    out: i32,
    t: i64,
    nonce: Option<&str>,
) -> String {
    let facing = facing.map_or("none", dir_name);
    let last = state.last.map_or("none", MonitorMode::command_name);
    let suffix = nonce.map_or(String::new(), |nonce| format!(" nonce={nonce}"));
    format!(
        "Ender Monitor at {},{},{}: mode={} facing={facing} pulses={} last={last} needpulse={} \
         out={out} t={t}{suffix}",
        pos[0],
        pos[1],
        pos[2],
        state.mode.command_name(),
        state.pulses,
        state.need_pulse,
    )
}

/// What a monitor's block state says: the display face and whether it is pulsing this tick.
fn monitor_state_of(host: &dyn Host, level: LevelRef, pos: [i32; 3]) -> (Option<Direction>, i32) {
    let display = level
        .block_property(host, pos, KEY_FACING)
        .and_then(|name| dir_from_name(name.as_str()));
    let lit = level
        .block_property(host, pos, KEY_LIT)
        .is_some_and(|value| value.as_str() == "true");
    (display, if lit { MONITOR_SIGNAL } else { 0 })
}

/// The monitor at `pos` as `/rftoolspower endermonitor` prints it, or [`NO_ENDER_MONITOR`].
pub(crate) fn ender_monitor_status_line(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    nonce: Option<&str>,
) -> String {
    let Some(state) = ender_monitor_at(host, level, pos) else {
        return NO_ENDER_MONITOR.to_owned();
    };
    let (facing, out) = monitor_state_of(&*host, level, pos);
    let t = level.game_time(&*host).unwrap_or(0);
    ender_monitor_line(pos, &state, facing, out, t, nonce)
}

/// Set a monitor's mode, the harness's stand-in for upstream's GUI picker (`setMode`). The reply is
/// the status line (with the caller's nonce), so a later read can prove it is fresh.
pub(crate) fn set_monitor_mode(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    word: &str,
    nonce: Option<&str>,
) -> String {
    let Some(mut state) = ender_monitor_at(host, level, pos) else {
        return NO_ENDER_MONITOR.to_owned();
    };
    let Some(mode) = MonitorMode::parse_command(word) else {
        return format!(
            "Ender Monitor at {},{},{}: unknown mode '{word}' (lost|fired|arrived|status)",
            pos[0], pos[1], pos[2]
        );
    };
    state.mode = mode;
    write_ender_monitor_at(host, level, pos, &state);
    ender_monitor_status_line(host, level, pos, nonce)
}

/// A click on an ender monitor reads its status (there is no GUI in this slice).
pub(crate) fn ender_monitor_click(
    host: &mut dyn ServerHost,
    click: &BlockClick<'_>,
) -> Option<InteractionResult> {
    let level = host.level(click.dimension.key().id())?;
    if block_id(&*host, level, click.pos).as_deref() != Some(ENDER_MONITOR) {
        return None;
    }
    let line = ender_monitor_status_line(host, level, click.pos, None);
    if let Some(player) = host.player(click.player) {
        let _ = player.action_bar(host, Text::literal(line));
    }
    Some(InteractionResult::Success)
}

/// A click on the endergenic reads its status (there is no GUI in this slice).
pub(crate) fn endergenic_click(
    host: &mut dyn ServerHost,
    click: &BlockClick<'_>,
) -> Option<InteractionResult> {
    let level = host.level(click.dimension.key().id())?;
    if block_id(&*host, level, click.pos).as_deref() != Some(ENDERGENIC) {
        return None;
    }
    let line = endergenic_status_line(host, level, click.pos, None);
    if let Some(player) = host.player(click.player) {
        let _ = player.action_bar(host, Text::literal(line));
    }
    Some(InteractionResult::Success)
}

/// A click on a pearl injector with an ender pearl puts it in the first free slot; anything else
/// is refused with a line and an empty hand reads the status.
pub(crate) fn injector_click(
    host: &mut dyn ServerHost,
    click: &BlockClick<'_>,
    held: Option<&ItemStack>,
) -> Option<InteractionResult> {
    let level = host.level(click.dimension.key().id())?;
    if block_id(&*host, level, click.pos).as_deref() != Some(INJECTOR) {
        return None;
    }
    match held.filter(|stack| stack.count() > 0) {
        Some(stack) if item_id(&*host, stack) == PEARL => {
            let hand = ItemPlace::PlayerHand {
                player: click.player,
                hand: click.hand,
            };
            insert_pearls(host, level, click.pos, stack, &hand);
        }
        Some(stack) => {
            let refused = item_id(&*host, stack);
            if let Some(player) = host.player(click.player) {
                let _ = player.action_bar(
                    host,
                    Text::literal(format!("{refused} is not an ender pearl")),
                );
            }
        }
        None => {
            let line = injector_status_line(host, level, click.pos, None);
            if let Some(player) = host.player(click.player) {
                let _ = player.action_bar(host, Text::literal(line));
            }
        }
    }
    Some(InteractionResult::Success)
}

/// Insert as much of the held pearls as the buffer takes, and take exactly that from the hand, in
/// one transaction (a creative player's hand gives without losing any).
pub(crate) fn insert_pearls(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    held: &ItemStack,
    hand: &ItemPlace,
) -> u32 {
    host.transaction(|host, tx| -> Result<u32, ()> {
        let entity = host.block_entity(level, pos).ok_or(())?;
        let key = held.item();
        let limit = host.max_stack_size(key).unwrap_or(DEFAULT_STACK);
        let mut inserted = 0u32;
        let mut left = held.count();
        for slot in 0..INJECTOR_SLOTS as u32 {
            if left == 0 {
                break;
            }
            let existing = entity.item_slot(&*host, slot).ok().flatten();
            let (room, after) = match existing {
                None => {
                    let count = left.min(limit);
                    let mut after = held.clone();
                    after.set_count(count).map_err(|_| ())?;
                    (count, Some(after))
                }
                Some(existing) if existing.is_stackable_with(held) => {
                    let room = limit.saturating_sub(existing.count()).min(left);
                    let mut after = existing;
                    after
                        .set_count(after.count().saturating_add(room))
                        .map_err(|_| ())?;
                    (room, Some(after))
                }
                Some(_) => (0, None),
            };
            if room == 0 {
                continue;
            }
            entity
                .set_item_slot(&mut *host, tx, slot, after)
                .map_err(|_| ())?;
            inserted += room;
            left -= room;
        }
        if inserted == 0 {
            return Ok(0);
        }
        let taken = hand.extract(&mut *host, tx, &ItemResource::of(held), inserted);
        if taken != inserted {
            return Err(());
        }
        let _ = entity.set_changed(&mut *host);
        Ok(inserted)
    })
    .unwrap_or(0)
}

/// The endergenic's item Part: clamp what a placed item's `block_entity_data` restored. Upstream's
/// loot carries the store only (`mcjtylib:item_energy`), so only the store is kept and clamped.
pub(crate) struct EndergenicItemPart;

#[mod_api::horizon_part]
impl ItemPart for EndergenicItemPart {
    fn on_block_placed_by(&self, host: &mut dyn ServerHost, event: &mut OnBlockPlacedByEvent<'_>) {
        let Some(level) = event
            .placer
            .and_then(|player| player.level(&*host))
            .or_else(|| in_place_level(host))
        else {
            return;
        };
        if block_id(&*host, level, event.pos).as_deref() != Some(ENDERGENIC) {
            return;
        }
        let Some(entity) = host.block_entity(level, event.pos) else {
            return;
        };
        let Some(saved) = entity.data(&*host) else {
            return;
        };
        let mut saved = Tag::Compound(saved);
        let clamped = clamp_endergenic(int(&saved, KEY_ENERGY));
        if clamped == int(&saved, KEY_ENERGY) {
            return;
        }
        set_int(&mut saved, KEY_ENERGY, clamped);
        if let Tag::Compound(data) = saved {
            let _ = entity.replace_data(host, data);
        }
    }
}

/// The endergenic generator: it ticks, and a click reads it.
pub(crate) struct EndergenicPart;

#[mod_api::horizon_part]
impl BlockPart for EndergenicPart {
    fn use_item_on(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseItemOnEvent<'_>,
    ) -> Option<InteractionResult> {
        endergenic_click(host, event.click)
    }

    fn use_without_item(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseWithoutItemEvent<'_>,
    ) -> Option<InteractionResult> {
        endergenic_click(host, event.click)
    }
}

#[mod_api::horizon_part]
impl BlockEntityPart for EndergenicPart {
    /// `EntityBlock.newBlockEntity`: an empty saved compound — idle, no FE, no link.
    fn block_entity(
        &self,
        _level: LevelSide,
        _event: &mut BlockEntityEvent<'_>,
    ) -> Option<Compound> {
        Some(Compound::new())
    }

    /// `EntityBlock.getTicker`: it ticks. Never clear a value an earlier mod set.
    fn block_entity_ticks(&self, _host: &dyn Host, event: &mut BlockEntityTicksEvent<'_>) {
        event.ticks = true;
    }

    /// One server tick: pearls in flight, the push, the loss chance, the redstone edge.
    fn block_entity_tick(&self, host: &mut dyn ServerHost, event: &mut BlockEntityTickEvent<'_>) {
        let pos = event.pos;
        let level = in_place_level(host);
        let mut saved = Tag::Compound(std::mem::take(&mut event.entity.nbt));
        let changed = tick_endergenic(host, level, pos, &mut saved);
        if let Tag::Compound(nbt) = saved {
            event.entity.nbt = nbt;
        }
        if !changed {
            *event.reply = BlockEntityTickReply::Unchanged;
        }
    }
}

/// The pearl injector: a redstone edge injects one pearl, and a click puts pearls in its buffer.
pub(crate) struct InjectorPart;

#[mod_api::horizon_part]
impl BlockPart for InjectorPart {
    fn use_item_on(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseItemOnEvent<'_>,
    ) -> Option<InteractionResult> {
        injector_click(host, event.click, event.click.stack)
    }

    fn use_without_item(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseWithoutItemEvent<'_>,
    ) -> Option<InteractionResult> {
        injector_click(host, event.click, None)
    }

    /// `BaseBlock.getStateForPlacement` with `RotationType.ROTATION`: `getFacingFromEntity` gives the
    /// front the direction **toward the placer**, so the generator the injector feeds is behind it
    /// (`facing.getOpposite()`). The event carries the placer's view angles, not its height, so
    /// upstream's vertical branches (placer above → UP, block above the eye → DOWN) are not
    /// expressible here and the front is horizontal — recorded in `notes.md`.
    fn state_for_placement(
        &self,
        level: &dyn LevelHost,
        event: &mut StateForPlacementEvent<'_>,
    ) -> Option<Option<BlockState>> {
        if level.state_block(event.state) != Some(INJECTOR) {
            return None;
        }
        let front = facing_from_yaw(event.context.yaw).opposite();
        Some(level.state_with_property(event.state, KEY_FACING, dir_name(front)))
    }
}

#[mod_api::horizon_part]
impl BlockEntityPart for InjectorPart {
    fn block_entity(
        &self,
        _level: LevelSide,
        _event: &mut BlockEntityEvent<'_>,
    ) -> Option<Compound> {
        Some(Compound::new())
    }

    fn block_entity_ticks(&self, _host: &dyn Host, event: &mut BlockEntityTicksEvent<'_>) {
        event.ticks = true;
    }

    /// One server tick: a redstone rising edge injects one pearl into the generator it points at.
    fn block_entity_tick(&self, host: &mut dyn ServerHost, event: &mut BlockEntityTickEvent<'_>) {
        let pos = event.pos;
        let level = in_place_level(host);
        if event.entity.items.len() != INJECTOR_SLOTS {
            event.entity.items.resize(INJECTOR_SLOTS, None);
        }
        let mut saved = Tag::Compound(std::mem::take(&mut event.entity.nbt));
        let items = &mut event.entity.items;
        let changed = tick_injector(host, level, pos, &mut saved, items);
        if let Tag::Compound(nbt) = saved {
            event.entity.nbt = nbt;
        }
        if !changed {
            *event.reply = BlockEntityTickReply::Unchanged;
        }
    }
}

/// The ender monitor: it ticks out the one-tick pulse the generator fires at it, and a click
/// reads its mode and counters.
pub(crate) struct EnderMonitorPart;

#[mod_api::horizon_part]
impl BlockPart for EnderMonitorPart {
    fn use_item_on(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseItemOnEvent<'_>,
    ) -> Option<InteractionResult> {
        ender_monitor_click(host, event.click)
    }

    fn use_without_item(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseWithoutItemEvent<'_>,
    ) -> Option<InteractionResult> {
        ender_monitor_click(host, event.click)
    }

    /// The placer's look is the display front; the generator it watches is behind it.
    fn state_for_placement(
        &self,
        level: &dyn LevelHost,
        event: &mut StateForPlacementEvent<'_>,
    ) -> Option<Option<BlockState>> {
        ender_monitor_placement(level, event)
    }

    /// The pulse's 15 on the display side, for the one tick it fires.
    fn block_signal(&self, level: &dyn LevelHost, event: &mut BlockSignalEvent) {
        ender_monitor_signal(level, event);
    }

    /// A monitor answers the signal query, so wire connects to it.
    fn is_signal_source(&self, level: &dyn LevelHost, event: &mut IsSignalSourceEvent) {
        ender_monitor_signal_source(level, event);
    }
}

#[mod_api::horizon_part]
impl BlockEntityPart for EnderMonitorPart {
    /// `EntityBlock.newBlockEntity`: an empty saved compound — watching lost pearls, no pulse.
    fn block_entity(
        &self,
        _level: LevelSide,
        _event: &mut BlockEntityEvent<'_>,
    ) -> Option<Compound> {
        Some(Compound::new())
    }

    /// `EntityBlock.getTicker`: it ticks. Never clear a value an earlier mod set.
    fn block_entity_ticks(&self, _host: &dyn Host, event: &mut BlockEntityTicksEvent<'_>) {
        event.ticks = true;
    }

    /// One server tick: spend an owed pulse as 15, and mirror it into `lit`.
    fn block_entity_tick(&self, host: &mut dyn ServerHost, event: &mut BlockEntityTickEvent<'_>) {
        let pos = event.pos;
        let level = in_place_level(host);
        let mut saved = Tag::Compound(std::mem::take(&mut event.entity.nbt));
        let changed = tick_ender_monitor(host, level, pos, &mut saved);
        if let Tag::Compound(nbt) = saved {
            event.entity.nbt = nbt;
        }
        if !changed {
            *event.reply = BlockEntityTickReply::Unchanged;
        }
    }
}

/// The blazing generator: it ticks, a click puts a rod in the first empty slot, and the front
/// faces its placer.
pub(crate) struct BlazingPart;

#[mod_api::horizon_part]
impl BlockPart for BlazingPart {
    /// `BaseBlock.getStateForPlacement` with `RotationType.ROTATION`: the front faces the placer.
    ///
    /// The click is not handled here: `on_right_click_block` takes it, so a click cannot be handled
    /// twice (a rod would land in the next slot as well).
    fn state_for_placement(
        &self,
        level: &dyn LevelHost,
        event: &mut StateForPlacementEvent<'_>,
    ) -> Option<Option<BlockState>> {
        blazing_placement(level, event)
    }
}

/// A blazing generator's own item: it carries the store (`BlazingGeneratorTileEntity`'s loot
/// copies `mcjtylib:item_energy`), clamped back to the buffer when it is placed again.
pub(crate) struct BlazingItemPart;

#[mod_api::horizon_part]
impl ItemPart for BlazingItemPart {
    fn on_block_placed_by(&self, host: &mut dyn ServerHost, event: &mut OnBlockPlacedByEvent<'_>) {
        clamp_placed_energy(host, event, BLAZING, clamp_blazing);
    }
}

/// A blazing agitator's own item: it carries its store (upstream's loot copies
/// `mcjtylib:item_energy`) and its nine locks (`rftoolspower:agitator_data`), clamped back to the
/// buffer when it is placed again.
pub(crate) struct AgitatorItemPart;

#[mod_api::horizon_part]
impl ItemPart for AgitatorItemPart {
    fn on_block_placed_by(&self, host: &mut dyn ServerHost, event: &mut OnBlockPlacedByEvent<'_>) {
        clamp_placed_energy(host, event, AGITATOR, clamp_agitator);
    }
}

/// Clamp a placed machine's `block_entity_data` store to its own buffer (`applyImplicitComponents`
/// then `GenericEnergyStorage.applyImplicitComponents`).
fn clamp_placed_energy(
    host: &mut dyn ServerHost,
    event: &OnBlockPlacedByEvent<'_>,
    block: &str,
    clamp: impl Fn(i32) -> i32,
) {
    let Some(level) = event
        .placer
        .and_then(|player| player.level(&*host))
        .or_else(|| in_place_level(host))
    else {
        return;
    };
    if block_id(&*host, level, event.pos).as_deref() != Some(block) {
        return;
    }
    let Some(entity) = host.block_entity(level, event.pos) else {
        return;
    };
    let Some(saved) = entity.data(&*host) else {
        return;
    };
    let mut saved = Tag::Compound(saved);
    let stored = int(&saved, KEY_ENERGY);
    let clamped = clamp(stored);
    if clamped == stored {
        return;
    }
    set_int(&mut saved, KEY_ENERGY, clamped);
    if let Tag::Compound(data) = saved {
        let _ = entity.replace_data(host, data);
    }
}

#[mod_api::horizon_part]
impl BlockEntityPart for BlazingPart {
    /// `EntityBlock.newBlockEntity`: an empty saved compound; the tick fills it.
    fn block_entity(
        &self,
        _level: LevelSide,
        _event: &mut BlockEntityEvent<'_>,
    ) -> Option<Compound> {
        Some(Compound::new())
    }

    /// `EntityBlock.getTicker`: it ticks. Never clear a value an earlier mod set.
    fn block_entity_ticks(&self, _host: &dyn Host, event: &mut BlockEntityTicksEvent<'_>) {
        event.ticks = true;
    }

    /// One server tick: the push, the ramp, the store and the rods' burn.
    fn block_entity_tick(&self, host: &mut dyn ServerHost, event: &mut BlockEntityTickEvent<'_>) {
        let pos = event.pos;
        let level = in_place_level(host);
        if event.entity.items.len() != BLAZING_SLOTS {
            event.entity.items.resize(BLAZING_SLOTS, None);
        }
        let mut saved = Tag::Compound(std::mem::take(&mut event.entity.nbt));
        let items = &mut event.entity.items;
        let changed = tick_blazing(host, level, pos, &mut saved, items);
        if let Tag::Compound(nbt) = saved {
            event.entity.nbt = nbt;
        }
        if !changed {
            *event.reply = BlockEntityTickReply::Unchanged;
        }
    }
}

/// The blazing agitator: it ticks, a click puts a rod in the first empty slot of its 3×3 box.
/// Upstream's `RotationType.NONE`: the block has no facing, so there is no placement hook.
pub(crate) struct AgitatorPart;

#[mod_api::horizon_part]
impl BlockPart for AgitatorPart {}

#[mod_api::horizon_part]
impl BlockEntityPart for AgitatorPart {
    /// `EntityBlock.newBlockEntity`: an empty saved compound; the tick fills it.
    fn block_entity(
        &self,
        _level: LevelSide,
        _event: &mut BlockEntityEvent<'_>,
    ) -> Option<Compound> {
        Some(Compound::new())
    }

    /// `EntityBlock.getTicker`: it ticks.
    fn block_entity_ticks(&self, _host: &dyn Host, event: &mut BlockEntityTicksEvent<'_>) {
        event.ticks = true;
    }

    /// One server tick: the 10 FE, the conversion, the agitation and the output box.
    fn block_entity_tick(&self, host: &mut dyn ServerHost, event: &mut BlockEntityTickEvent<'_>) {
        if event.entity.items.len() != AGITATOR_SLOTS + AGITATOR_OUTPUTS {
            event
                .entity
                .items
                .resize(AGITATOR_SLOTS + AGITATOR_OUTPUTS, None);
        }
        let mut saved = Tag::Compound(std::mem::take(&mut event.entity.nbt));
        let items = &mut event.entity.items;
        let changed = tick_agitator(host, &mut saved, items);
        if let Tag::Compound(nbt) = saved {
            event.entity.nbt = nbt;
        }
        if !changed {
            *event.reply = BlockEntityTickReply::Unchanged;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::{COAL_BLOCK_TICKS, MAX_LEVEL, PERCENT, TICKS_PER_COAL};
    fn compound() -> Tag {
        Tag::Compound(Compound::new())
    }

    #[test]
    fn the_generator_has_one_insert_only_fuel_slot() {
        let container = generator_container();
        assert_eq!(container.slots, SLOTS, "one fuel slot");
        assert_eq!(container.inputs, vec![FUEL_SLOT], "fuel may be inserted");
        assert_eq!(
            container.outputs,
            Vec::<usize>::new(),
            "automation takes nothing back out"
        );
        assert_eq!(
            container.faces,
            std::array::from_fn(|_| vec![FUEL_SLOT]),
            "automation reaches the slot from every face: there is no side configuration"
        );
        assert_eq!(container.menu, None, "no GUI in this slice");
    }

    #[test]
    fn the_buffer_is_upstreams_generator_max_rf() {
        let battery = generator_battery();
        assert_eq!(battery.capacity, CAPACITY, "generatorMaxRF");
        assert_eq!(battery.max_insert, 0, "the generator takes no FE in");
        assert_eq!(battery.max_extract, EXTRACT_PER_TICK, "generatorRFPerTick");
        assert_eq!(battery.insert_faces, [false; 6]);
        assert_eq!(battery.extract_faces, [true; 6], "every face gives FE out");
    }

    #[test]
    fn the_tick_state_reads_back_from_the_compound_it_wrote() {
        let mut saved = compound();
        assert_eq!(read_generator(&saved), Generator::new());
        let state = Generator {
            energy: 1_940,
            burn: 503,
            burn_max: TICKS_PER_COAL,
        };
        write_generator(&mut saved, &state);
        assert_eq!(read_generator(&saved), state);
        assert_eq!(
            saved.get(KEY_ENERGY),
            Some(&Tag::Int(1_940)),
            "the store is the int `energy` the energy capability reads"
        );
        assert_eq!(saved.get(KEY_BURN), Some(&Tag::Int(503)));
        assert_eq!(
            saved.get(KEY_BURN_MAX),
            Some(&Tag::Int(TICKS_PER_COAL as i32))
        );
    }

    #[test]
    fn a_stale_store_reads_clamped() {
        let mut saved = compound();
        set_int(&mut saved, KEY_ENERGY, CAPACITY + 20_000);
        assert_eq!(read_generator(&saved).energy, CAPACITY);
        set_int(&mut saved, KEY_ENERGY, -5);
        assert_eq!(read_generator(&saved).energy, 0);
        set_int(&mut saved, KEY_BURN, -3);
        assert_eq!(
            read_generator(&saved).burn,
            0,
            "a negative burn is empty, not huge"
        );
        set_int(&mut saved, KEY_BURN, 99_999);
        assert_eq!(read_generator(&saved).burn, COAL_BLOCK_TICKS);
    }

    #[test]
    fn the_readout_is_the_line_the_e2e_asserts() {
        let state = Generator {
            energy: 1_940,
            burn: 503,
            burn_max: TICKS_PER_COAL,
        };
        assert_eq!(
            generator_line(
                [0, 100, 0],
                &state,
                Some(("minecraft:coal", 4)),
                324,
                Some("1")
            ),
            "Coal Generator at 0,100,0: 1940/500000 FE (burning 503/600 ticks, lit true, fuel \
             minecraft:coal x4, t=324 nonce=1)"
        );
        assert_eq!(
            generator_line([200, 101, 0], &Generator::new(), None, 7, None),
            "Coal Generator at 200,101,0: 0/500000 FE (burning 0/0 ticks, lit false, fuel empty, \
             t=7)"
        );
    }

    #[test]
    fn the_command_is_the_readout_at_the_operator_level() {
        let mut commands = Vec::new();
        declare_commands(&mut commands);
        assert_eq!(
            commands[0].usage, "rftoolspower info <pos:block_pos> [nonce:word]",
            "the harness's spelling, with the three words parsed as one block position"
        );
        assert_eq!(
            commands[0].level, OPERATOR_LEVEL,
            "the readout names another player's machine contents, so it needs an operator"
        );
    }

    #[test]
    fn the_readout_needs_an_operator() {
        use mod_api::PermissionLevel;
        assert!(!may_read(PermissionLevel::All));
        assert!(!may_read(PermissionLevel::Moderators));
        assert!(may_read(PermissionLevel::Gamemasters));
        assert!(may_read(PermissionLevel::Owners));
        assert_eq!(OPERATOR_LEVEL, 2);
    }

    #[test]
    fn a_broken_generators_drop_carries_its_store_tagged_with_the_type() {
        let mut saved = compound();
        let state = Generator {
            energy: 1_940,
            burn: 503,
            burn_max: TICKS_PER_COAL,
        };
        write_generator(&mut saved, &state);
        let Tag::Compound(saved) = saved else {
            panic!("write_generator keeps the compound");
        };
        let patch = Tag::Compound(entity_data_patch(&saved, GENERATOR_TYPE_ID));
        let Some(Tag::Compound(payload)) = patch.get(BLOCK_ENTITY_DATA) else {
            panic!("the patch names the vanilla component");
        };
        let payload = Tag::Compound(payload.clone());
        assert_eq!(
            payload.get("id"),
            Some(&Tag::String(GENERATOR_TYPE_ID.into())),
            "the payload names the block entity type it is placed as"
        );
        assert_eq!(
            read_generator(&payload),
            state,
            "the item carries exactly the FE and burn the machine held"
        );
    }

    // --- the power monitor -------------------------------------------------

    #[test]
    fn the_monitors_saved_state_reads_back_and_a_doctored_one_is_clamped() {
        let mut saved = compound();
        assert_eq!(read_monitor(&saved), Monitor::new(), "a fresh monitor");
        let state = Monitor::restored(3, 40, 60, true, 7);
        write_monitor(&mut saved, &state);
        assert_eq!(read_monitor(&saved), state);
        assert_eq!(saved.get(KEY_LEVEL), Some(&Tag::Int(3)));
        assert_eq!(saved.get(KEY_MINIMUM), Some(&Tag::Int(40)));
        assert_eq!(saved.get(KEY_MAXIMUM), Some(&Tag::Int(60)));
        assert_eq!(saved.get(KEY_ALARM), Some(&Tag::Byte(1)));
        assert_eq!(saved.get(KEY_COUNTER), Some(&Tag::Int(7)));

        let mut doctored = compound();
        set_int(&mut doctored, KEY_LEVEL, 12);
        set_int(&mut doctored, KEY_MINIMUM, -20);
        set_int(&mut doctored, KEY_MAXIMUM, 900);
        set_int(&mut doctored, KEY_COUNTER, 0);
        let read = read_monitor(&doctored);
        assert_eq!(read.level, MAX_LEVEL);
        assert_eq!((read.minimum, read.maximum), (0, PERCENT as i32));
        assert_eq!(read.counter, 1, "a zero counter is due next tick");
    }

    #[test]
    fn the_monitor_readout_is_the_line_the_e2e_asserts() {
        let state = Monitor::restored(3, 0, 0, false, 20);
        assert_eq!(
            monitor_line(
                [303, 101, 0],
                &state,
                Some((MONITOR_GENERATOR_LINE, Some((250_000, 500_000)))),
                324,
                Some("1")
            ),
            "Power Monitor at 303,101,0: level=3 band=0..0 (unset) \
             target=rftoolspower:coalgenerator stored=250000 max=500000 alarm=false t=324 nonce=1"
        );
        assert_eq!(
            monitor_line(
                [303, 101, -6],
                &Monitor::restored(0, 40, 60, false, 20),
                Some(("minecraft:stone", None)),
                7,
                None
            ),
            "Power Monitor at 303,101,-6: level=0 band=40..60 \
             target=minecraft:stone (not an energy block) stored=- max=- alarm=false t=7"
        );
    }

    /// The test's target id, a constant so the expected line reads as upstream's block.
    const MONITOR_GENERATOR_LINE: &str = "rftoolspower:coalgenerator";

    #[test]
    fn the_display_face_is_set_from_the_placer_and_the_alarm_leaves_through_it() {
        assert_eq!(facing_from_yaw(0.0), Direction::South);
        assert_eq!(facing_from_yaw(90.0), Direction::West);
        assert_eq!(facing_from_yaw(180.0), Direction::North);
        assert_eq!(facing_from_yaw(-90.0), Direction::East);
        assert_eq!(facing_from_yaw(270.0), Direction::East);
        for read in [
            Direction::North,
            Direction::South,
            Direction::West,
            Direction::East,
        ] {
            assert_eq!(
                output_face(read),
                read.opposite(),
                "the alarm leaves through the display face, opposite the block the monitor reads"
            );
        }
        // A placer looking west is the monitor's display side: the watched machine is east.
        assert_eq!(Direction::West.opposite(), Direction::East);
    }

    #[test]
    fn a_monitor_state_decodes_its_read_side_and_alarm() {
        assert_eq!(
            parse_monitor_state("rftoolspower:power_monitor[facing=west,level=3,lit=true]"),
            Some((Direction::West, true))
        );
        assert_eq!(
            parse_monitor_state("rftoolspower:power_monitor[facing=east,level=0,lit=false]"),
            Some((Direction::East, false))
        );
        assert_eq!(
            parse_monitor_state("minecraft:furnace[facing=west,lit=true]"),
            None,
            "another block's state is not a monitor"
        );
        assert_eq!(parse_monitor_state("rftoolspower:power_monitor"), None);
    }

    // --- the power level ---------------------------------------------------

    #[test]
    fn the_power_levels_saved_state_reads_back_and_a_doctored_one_is_clamped() {
        let mut saved = compound();
        assert_eq!(
            read_power_level(&saved),
            PowerLevel::new(),
            "a fresh power level is ratio 0, first observation in 20 ticks"
        );
        let state = PowerLevel::restored(5, 10);
        write_power_level(&mut saved, &state);
        assert_eq!(read_power_level(&saved), state);
        assert_eq!(saved.get(KEY_POWER), Some(&Tag::Int(5)));
        assert_eq!(saved.get(KEY_COUNTER), Some(&Tag::Int(10)));

        let mut doctored = compound();
        set_int(&mut doctored, KEY_POWER, 99);
        set_int(&mut doctored, KEY_COUNTER, 0);
        let read = read_power_level(&doctored);
        assert_eq!(read.power, 9, "no ratio above 9");
        assert_eq!(read.counter, 1, "a zero counter is due next tick");
    }

    #[test]
    fn the_power_level_readout_is_the_line_the_e2e_asserts() {
        let state = PowerLevel::restored(5, 10);
        assert_eq!(
            power_level_line(
                [303, 101, 140],
                &state,
                Some(Direction::East),
                Some((MONITOR_GENERATOR_LINE, Some((250_000, 500_000)))),
                400,
                Some("1")
            ),
            "Power Level at 303,101,140: power=5 facing=east \
             target=rftoolspower:coalgenerator stored=250000 max=500000 t=400 nonce=1"
        );
        assert_eq!(
            power_level_line([303, 101, 140], &PowerLevel::new(), None, None, 9, None),
            "Power Level at 303,101,140: power=0 facing=none target=none stored=- max=- t=9"
        );
    }

    #[test]
    fn a_power_level_state_decodes_its_display_face_and_ratio() {
        assert_eq!(
            parse_power_level_state("rftoolspower:power_level[facing=east,power=5]"),
            Some((Direction::East, 5))
        );
        assert_eq!(
            parse_power_level_state("rftoolspower:power_level[facing=north,power=0]"),
            Some((Direction::North, 0))
        );
        assert_eq!(
            parse_power_level_state("rftoolspower:power_monitor[facing=east,level=3,lit=true]"),
            None,
            "another block's state is not a power level"
        );
        assert_eq!(parse_power_level_state("rftoolspower:power_level"), None);
    }

    #[test]
    fn the_commands_are_the_thirteen_the_harness_types() {
        let mut commands = Vec::new();
        declare_commands(&mut commands);
        assert_eq!(commands.len(), 13);
        assert_eq!(
            commands[0].usage, "rftoolspower info <pos:block_pos> [nonce:word]",
            "the generator readout stays as it was"
        );
        assert_eq!(
            commands[1].usage,
            "rftoolspower monitor <pos:block_pos> [nonce:word]"
        );
        assert_eq!(
            commands[2].usage, "rftoolspower powerlevel <pos:block_pos> [nonce:word]",
            "the power level's readout"
        );
        assert_eq!(
            commands[3].usage,
            "rftoolspower band <pos:block_pos> <minimum:integer> <maximum:integer>",
            "the band is set the way upstream's GUI sliders set it"
        );
        assert_eq!(
            commands[4].usage, "rftoolspower cell <pos:block_pos> [nonce:word]",
            "the cell's readout"
        );
        assert_eq!(
            commands[5].usage, "rftoolspower side <pos:block_pos> <face:word> <mode:word>",
            "the side mode is set the way the smart wrench toggles it"
        );
        assert_eq!(
            commands[6].usage, "rftoolspower endergenic <pos:block_pos> [nonce:word]",
            "the endergenic's readout"
        );
        assert_eq!(
            commands[7].usage, "rftoolspower injector <pos:block_pos> [nonce:word]",
            "the pearl injector's readout"
        );
        assert_eq!(
            commands[8].usage, "rftoolspower enderlink <pos:block_pos> <destination:block_pos>",
            "the wrench's link, as a command"
        );
        assert_eq!(
            commands[9].usage,
            "rftoolspower endermonitor <pos:block_pos> <action:word> [nonce:word]",
            "the monitor's readout is `status <nonce>`; a mode word sets its GUI picker"
        );
        assert_eq!(
            commands[10].usage, "rftoolspower blazing <pos:block_pos> [nonce:word]",
            "the blazing generator's readout"
        );
        assert_eq!(
            commands[11].usage, "rftoolspower agitator <pos:block_pos> [nonce:word]",
            "the agitator's readout"
        );
        assert_eq!(
            commands[12].usage,
            "rftoolspower agitatelock <pos:block_pos> <slot:integer> <lock:word> [nonce:word]",
            "the GUI's lock checkbox, as a command"
        );
        for command in &commands {
            assert_eq!(command.level, OPERATOR_LEVEL);
        }
    }

    // --- the ender monitor ---------------------------------------------------

    #[test]
    fn the_ender_monitor_state_reads_back_from_the_compound_it_wrote() {
        let mut saved = compound();
        assert_eq!(
            read_ender_monitor(&saved),
            EnderMonitor::new(),
            "a fresh monitor watches lost pearls"
        );
        let mut state = EnderMonitor::new();
        state.mode = MonitorMode::PearlArrived;
        state.need_pulse = true;
        state.pulses = 4;
        state.last = Some(MonitorMode::PearlArrived);
        write_ender_monitor(&mut saved, &state);
        assert_eq!(read_ender_monitor(&saved), state);
        assert_eq!(
            saved.get(KEY_MONITOR_MODE),
            Some(&Tag::String("MODE_PEARLARRIVED".into())),
            "the mode is saved under upstream's serialised name"
        );
        assert_eq!(saved.get(KEY_NEED_PULSE), Some(&Tag::Byte(1)));
        assert_eq!(saved.get(KEY_PULSES), Some(&Tag::Int(4)));
    }

    #[test]
    fn a_monitor_with_no_last_mode_carries_no_stale_key() {
        let mut saved = compound();
        let mut state = EnderMonitor::new();
        state.pulses = 1;
        state.last = Some(MonitorMode::PearlFired);
        write_ender_monitor(&mut saved, &state);
        write_ender_monitor(&mut saved, &EnderMonitor::new());
        assert_eq!(
            saved.get(KEY_LAST),
            None,
            "a monitor that never fired carries no last mode"
        );
    }

    #[test]
    fn a_doctored_monitor_save_reads_back_as_the_default_mode() {
        let mut saved = compound();
        set_text(&mut saved, KEY_MONITOR_MODE, "MODE_MADEUP");
        set_int(&mut saved, KEY_PULSES, -3);
        set_text(&mut saved, KEY_LAST, "MODE_PEARLARRIVED");
        let state = read_ender_monitor(&saved);
        assert_eq!(
            state.mode,
            MonitorMode::LostPearl,
            "an unknown mode falls back to upstream's default"
        );
        assert_eq!(state.pulses, 0, "a negative counter is 0");
        assert_eq!(state.last, None, "no pulse, no last mode");
    }

    #[test]
    fn the_ender_monitor_readout_is_the_line_the_e2e_asserts() {
        let mut state = EnderMonitor::new();
        state.mode = MonitorMode::PearlArrived;
        state.pulses = 1;
        state.last = Some(MonitorMode::PearlArrived);
        assert_eq!(
            ender_monitor_line(
                [304, 101, 97],
                &state,
                Some(Direction::East),
                0,
                15,
                Some("3")
            ),
            "Ender Monitor at 304,101,97: mode=arrived facing=east pulses=1 last=arrived \
             needpulse=false out=0 t=15 nonce=3"
        );
        assert_eq!(
            ender_monitor_line([304, 101, 94], &EnderMonitor::new(), None, 0, 0, None),
            "Ender Monitor at 304,101,94: mode=lost facing=none pulses=0 last=none \
             needpulse=false out=0 t=0"
        );
    }

    #[test]
    fn the_ender_monitor_state_string_decodes_its_face_and_pulse() {
        assert_eq!(
            parse_ender_monitor_state("rftoolspower:ender_monitor[facing=east,lit=true]"),
            Some((Direction::East, true)),
            "the display face and the pulse this tick"
        );
        assert_eq!(
            parse_ender_monitor_state("rftoolspower:ender_monitor[facing=north,lit=false]"),
            Some((Direction::North, false))
        );
        assert_eq!(
            parse_ender_monitor_state("rftoolspower:power_monitor[facing=east,level=3,lit=true]"),
            None,
            "another block's state is not an ender monitor"
        );
        assert_eq!(
            parse_ender_monitor_state("rftoolspower:ender_monitor"),
            None
        );
    }

    #[test]
    fn the_cells_store_and_modes_read_back_from_the_compound_they_wrote() {
        let mut saved = compound();
        assert_eq!(read_cell(&saved, Tier::One).energy, 0);
        assert_eq!(
            read_sides_from(&saved),
            Sides::fresh(),
            "a fresh cell is all NONE"
        );
        let cell = Cell {
            tier: Tier::One,
            energy: 12_345,
        };
        write_cell(&mut saved, &cell);
        let mut sides = Sides::fresh();
        assert!(sides.set(4, SideMode::Input), "west");
        assert!(sides.set(5, SideMode::Output), "east");
        write_sides(&mut saved, sides);
        assert_eq!(saved.get(KEY_ENERGY), Some(&Tag::Int(12_345)));
        assert_eq!(
            saved.get(KEY_MODE),
            Some(&Tag::String("000021".into())),
            "upstream's six digits, Direction order (west INPUT=2, east OUTPUT=1)"
        );
        assert_eq!(read_cell(&saved, Tier::One), cell);
        assert_eq!(read_sides_from(&saved), sides);
    }

    #[test]
    fn a_doctored_cell_reads_clamped_to_its_tier() {
        let mut saved = compound();
        set_int(&mut saved, KEY_ENERGY, 9_000_000);
        assert_eq!(read_cell(&saved, Tier::One).energy, 500_000);
        assert_eq!(read_cell(&saved, Tier::Two).energy, 4_000_000);
        set_int(&mut saved, KEY_ENERGY, -40);
        assert_eq!(read_cell(&saved, Tier::One).energy, 0);
        set_text(&mut saved, KEY_MODE, "999999");
        assert_eq!(
            read_sides_from(&saved),
            Sides::fresh(),
            "an unreadable mode string is a fresh cell, not half-applied"
        );
    }

    #[test]
    fn the_cell_readout_is_the_line_the_e2e_asserts() {
        let mut sides = Sides::fresh();
        assert!(sides.set(4, SideMode::Input));
        let cell = Cell {
            tier: Tier::One,
            energy: 12_500,
        };
        assert_eq!(
            cell_line(
                [302, 101, 0],
                Tier::One,
                &cell,
                12_500,
                500_000,
                1,
                sides,
                324,
                Some("7")
            ),
            "Power Cell at 302,101,0: tier=1 local=12500/500000 network=12500/500000 cells=1 \
             sides=none,none,none,none,input,none t=324 nonce=7"
        );
        assert_eq!(
            cell_line(
                [303, 101, 0],
                Tier::Two,
                &Cell {
                    tier: Tier::Two,
                    energy: 0
                },
                12_500,
                4_500_000,
                2,
                Sides::fresh(),
                7,
                None
            ),
            "Power Cell at 303,101,0: tier=2 local=0/4000000 network=12500/4500000 cells=2 \
             sides=none,none,none,none,none,none t=7"
        );
    }

    #[test]
    fn a_cells_store_rides_alone_on_its_item() {
        let mut payload = Compound::new();
        payload.insert(KEY_ENERGY.into(), Tag::Int(3_000));
        let patch = Tag::Compound(entity_data_patch(&payload, CELL1_TYPE_ID));
        let Some(Tag::Compound(data)) = patch.get(BLOCK_ENTITY_DATA) else {
            panic!("the patch names the vanilla component");
        };
        let data = Tag::Compound(data.clone());
        assert_eq!(
            data.get("id"),
            Some(&Tag::String(CELL1_TYPE_ID.into())),
            "the payload names the cell's block entity type"
        );
        assert_eq!(read_cell(&data, Tier::One).energy, 3_000);
        assert_eq!(
            data.get(KEY_MODE),
            None,
            "the face modes are client data and do not travel on the item"
        );
    }

    #[test]
    fn the_face_number_is_vanillas_direction_ordinal() {
        assert_eq!(face_index(Direction::Down), 0);
        assert_eq!(face_index(Direction::Up), 1);
        assert_eq!(face_index(Direction::North), 2);
        assert_eq!(face_index(Direction::South), 3);
        assert_eq!(face_index(Direction::West), 4);
        assert_eq!(face_index(Direction::East), 5);
        for direction in Direction::ALL {
            assert_eq!(
                dir_from_name(dir_name(direction)),
                Some(direction),
                "the command's face words round-trip"
            );
        }
        assert_eq!(dir_from_name("westx"), None);
    }

    #[test]
    fn a_broken_monitors_band_rides_on_its_item_tagged_with_the_monitor_type() {
        let mut saved = compound();
        let state = Monitor::restored(3, 40, 60, false, 11);
        write_monitor(&mut saved, &state);
        let Tag::Compound(saved) = saved else {
            panic!("write_monitor keeps the compound");
        };
        let patch = Tag::Compound(entity_data_patch(&saved, MONITOR_TYPE_ID));
        let Some(Tag::Compound(payload)) = patch.get(BLOCK_ENTITY_DATA) else {
            panic!("the patch names the vanilla component");
        };
        let payload = Tag::Compound(payload.clone());
        assert_eq!(
            payload.get("id"),
            Some(&Tag::String(MONITOR_TYPE_ID.into()))
        );
        assert_eq!(read_monitor(&payload), state);
    }

    // --- the endergenic generator and the pearl injector --------------------

    fn linked() -> Endergenic {
        let mut state = Endergenic::new();
        state.destination = Some([10, 101, 6]);
        state.distance = 2;
        state
    }

    #[test]
    fn the_endergenic_state_reads_back_from_the_compound_it_wrote() {
        let mut saved = compound();
        assert_eq!(
            read_endergenic(&saved),
            Endergenic::new(),
            "a fresh generator"
        );
        let mut state = linked();
        state.energy = 1_600;
        state.charging = HOLDING;
        state.age = 3;
        state.prev_in = true;
        state.gained = 1_600;
        state.spent = 500;
        state.launched = 2;
        state.dropped = 1;
        state.arrived_at = 4;
        state
            .pearls
            .push(crate::runtime::Pearl::new(2, [10, 101, 6], 1));
        write_endergenic(&mut saved, &state);
        assert_eq!(read_endergenic(&saved), state);
        assert_eq!(
            saved.get(KEY_ENERGY),
            Some(&Tag::Int(1_600)),
            "the store is the int `energy` the energy capability reads"
        );
        assert_eq!(
            position(&saved, KEY_DEST),
            Some([10, 101, 6]),
            "the link is saved as three ints"
        );
    }

    #[test]
    fn a_generator_with_no_link_saves_no_destination() {
        let mut saved = compound();
        write_endergenic(&mut saved, &linked());
        assert!(position(&saved, KEY_DEST).is_some());
        write_endergenic(&mut saved, &Endergenic::new());
        assert_eq!(
            position(&saved, KEY_DEST),
            None,
            "an unlinked generator carries no stale destination"
        );
    }

    #[test]
    fn a_doctored_endergenic_reads_back_clamped() {
        let mut saved = compound();
        set_int(&mut saved, KEY_ENERGY, 9_000_000);
        set_int(&mut saved, KEY_CHARGING, 40);
        set_int(&mut saved, KEY_AGE, -5);
        set_int(&mut saved, KEY_DISTANCE, 99);
        set_position(&mut saved, KEY_DEST, [1, 2, 3]);
        let state = read_endergenic(&saved);
        assert_eq!(state.energy, ENDERGENIC_CAPACITY);
        assert_eq!(
            state.charging,
            crate::runtime::MAX_CHARGE,
            "40 is past the window"
        );
        assert_eq!(state.age, 0);
        assert_eq!(state.distance, MAX_DISTANCE);
        assert_eq!(state.pearls.len(), 0);
    }

    #[test]
    fn the_endergenic_readout_is_the_line_the_e2e_asserts() {
        let mut state = linked();
        state.energy = 800;
        state.charging = HOLDING;
        state.gained = 800;
        state.arrived_at = 4;
        assert_eq!(
            endergenic_line([300, 101, 2], &state, 4242, Some("9")),
            "Endergenic at 300,101,2: energy=800/5000000 charging=-1 age=0 pearls=0 fired=0 \
             dropped=0 gained=800 spent=0 arrived=4 reason=\"none\" dest=10,101,6 distance=2 \
             t=4242 nonce=9"
        );
        let mut fresh = Endergenic::new();
        fresh.last_loss = Some(Loss::WhileIdle);
        assert_eq!(
            endergenic_line([300, 101, 4], &fresh, 7, None),
            "Endergenic at 300,101,4: energy=0/5000000 charging=0 age=0 pearls=0 fired=0 \
             dropped=0 gained=0 spent=0 arrived=-2 reason=\"Pearl arrived while idle\" dest=none \
             distance=0 t=7"
        );
    }

    #[test]
    fn the_injector_readout_is_the_line_the_e2e_asserts() {
        assert_eq!(
            injector_line([300, 102, 2], 3, Some([300, 101, 2]), 9, Some("2")),
            "Pearl Injector at 300,102,2: pearls=3 generator=300,101,2 t=9 nonce=2"
        );
        assert_eq!(
            injector_line([300, 102, 4], 0, None, 1, None),
            "Pearl Injector at 300,102,4: pearls=0 generator=none t=1"
        );
    }

    #[test]
    fn the_injector_has_eighteen_insert_only_pearl_slots() {
        let container = injector_container();
        assert_eq!(container.slots, 18, "upstream's 9x2 buffer");
        assert_eq!(container.inputs.len(), 18, "every slot takes pearls in");
        assert!(container.outputs.is_empty(), "automation takes nothing out");
        for face in &container.faces {
            assert_eq!(face.len(), 18, "every face reaches every slot");
        }
        assert!(container.menu.is_none(), "no GUI in this slice");
    }

    #[test]
    fn the_endergenic_buffer_is_a_store_that_gives_nothing_out() {
        let battery = endergenic_battery();
        assert_eq!(battery.capacity, ENDERGENIC_CAPACITY);
        assert_eq!(battery.max_insert, 0, "the capability takes nothing in");
        assert_eq!(
            battery.max_extract, 0,
            "the generator pushes on its own tick, not through the capability"
        );
        assert_eq!(battery.insert_faces, [false; 6]);
        assert_eq!(battery.extract_faces, [false; 6]);
    }

    #[test]
    fn a_broken_endergenics_store_rides_on_its_item_tagged_with_its_type() {
        let mut payload = Compound::new();
        payload.insert(KEY_ENERGY.into(), Tag::Int(3_000));
        let patch = Tag::Compound(entity_data_patch(&payload, ENDERGENIC_TYPE_ID));
        let Some(Tag::Compound(payload)) = patch.get(BLOCK_ENTITY_DATA) else {
            panic!("the patch names the vanilla component");
        };
        let payload = Tag::Compound(payload.clone());
        assert_eq!(
            payload.get("id"),
            Some(&Tag::String(ENDERGENIC_TYPE_ID.into())),
            "the payload names the block entity type it is placed as"
        );
        assert_eq!(read_endergenic(&payload).energy, 3_000);
    }

    #[test]
    fn a_broken_monitors_mode_rides_on_its_item_tagged_with_its_type() {
        let mut payload = Compound::new();
        payload.insert(
            KEY_MONITOR_MODE.into(),
            Tag::String(MonitorMode::PearlFired.saved().into()),
        );
        let patch = Tag::Compound(entity_data_patch(&payload, ENDER_MONITOR_TYPE_ID));
        let Some(Tag::Compound(payload)) = patch.get(BLOCK_ENTITY_DATA) else {
            panic!("the patch names the vanilla component");
        };
        let payload = Tag::Compound(payload.clone());
        assert_eq!(
            payload.get("id"),
            Some(&Tag::String(ENDER_MONITOR_TYPE_ID.into())),
            "the payload names the block entity type it is placed as"
        );
        let restored = read_ender_monitor(&payload);
        assert_eq!(restored.mode, MonitorMode::PearlFired);
        assert!(!restored.need_pulse, "no event is owed by a placed item");
        assert_eq!(
            restored.pulses, 0,
            "the readout's counters stay on the block"
        );
        assert_eq!(restored.last, None);
    }

    #[test]
    fn the_endergenic_commands_are_declared_at_the_operator_level() {
        let mut commands = Vec::new();
        declare_commands(&mut commands);
        let ender: Vec<&str> = commands
            .iter()
            .map(|command| command.usage.as_str())
            .filter(|usage| {
                usage.contains("endergenic")
                    || usage.contains("injector")
                    || usage.contains("enderlink")
            })
            .collect();
        assert_eq!(
            ender,
            vec![
                "rftoolspower endergenic <pos:block_pos> [nonce:word]",
                "rftoolspower injector <pos:block_pos> [nonce:word]",
                "rftoolspower enderlink <pos:block_pos> <destination:block_pos>",
            ]
        );
        for command in &commands {
            assert_eq!(command.level, OPERATOR_LEVEL);
        }
    }

    #[test]
    fn the_blazing_generator_has_four_insert_only_rod_slots() {
        let container = blazing_container();
        assert_eq!(container.slots, BLAZING_SLOTS);
        assert_eq!(
            container.inputs,
            vec![0, 1, 2, 3],
            "a hopper feeds every slot"
        );
        assert!(container.outputs.is_empty(), "nothing is ever taken out");
        assert_eq!(container.menu, None, "no GUI in this slice");
        for face in container.faces {
            assert_eq!(face, vec![0, 1, 2, 3], "every face reaches the four slots");
        }
    }

    #[test]
    fn the_blazing_buffer_is_a_million_that_gives_nothing_out() {
        let battery = blazing_battery();
        assert_eq!(battery.capacity, BLAZING_CAPACITY);
        assert_eq!(battery.max_insert, 0, "the capability takes nothing in");
        assert_eq!(
            battery.max_extract, 0,
            "the generator pushes on its own tick (upstream's extractEnergy is 0)"
        );
        assert_eq!(battery.insert_faces, [false; 6]);
        assert_eq!(battery.extract_faces, [false; 6]);
    }

    #[test]
    fn the_rod_component_round_trips_and_takes_any_numeric_type() {
        let rod = Rod {
            steps: 7,
            time: 123.5,
            quality: 120_000.0,
            duration: 400.0,
        };
        let encoded = RodData.encode(rod);
        assert_eq!(RodData.decode(&encoded), Some(rod));
        // SNBT's `60000` is an int: upstream's codec takes it, and so does this decode.
        let from_ints = Tag::compound([
            ("steps", Tag::Int(64)),
            ("time", Tag::Int(600)),
            ("quality", Tag::Int(60_000)),
            ("duration", Tag::Int(400)),
        ]);
        assert_eq!(
            RodData.decode(&from_ints),
            Some(Rod {
                steps: 64,
                time: 600.0,
                quality: 60_000.0,
                duration: 400.0,
            })
        );
        // A missing field is the default row's (`getOrDefault(…, DEFAULT)`).
        let partial = Tag::compound([("duration", Tag::Float(3.0_f32.to_bits()))]);
        let decoded = RodData.decode(&partial).expect("a compound decodes");
        assert_eq!(decoded.duration, 3.0);
        assert_eq!(decoded.quality, Rod::default().quality);
        // SNBT's `0.05` (no `f`) is a double, and a `Double` tag carries f64 *bits* — the slice-8
        // e2e caught this arm handing the raw bits to the clock, which read 4.58e18 ticks.
        let from_double = Tag::compound([("time", Tag::Double(0.05_f64.to_bits()))]);
        let decoded = RodData.decode(&from_double).expect("a compound decodes");
        assert_eq!(decoded.time, 0.05);
        assert_eq!(RodData.decode(&Tag::Int(1)), None, "not a rod's data");
    }

    #[test]
    fn the_blazing_state_reads_back_from_the_compound_it_wrote() {
        let mut state = Blazing {
            energy: 12_345,
            ..Blazing::default()
        };
        state.slots[0].max = 60;
        state.slots[0].rft = 12.5;
        state.slots[0].ticks = 377;
        let mut saved = compound();
        write_blazing(&mut saved, &state);
        assert_eq!(read_blazing(&saved), state);
        // A doctored store is clamped to the buffer on the way in.
        let mut doctored = compound();
        set_int(&mut doctored, KEY_ENERGY, 9_999_999);
        assert_eq!(read_blazing(&doctored).energy, BLAZING_CAPACITY);
        let mut negative = compound();
        set_int(&mut negative, KEY_ENERGY, -5);
        assert_eq!(read_blazing(&negative).energy, 0);
    }

    #[test]
    fn the_blazing_readout_is_the_line_the_e2e_asserts() {
        let mut state = Blazing {
            energy: 1_234,
            ..Blazing::default()
        };
        state.slots[0].max = 60;
        state.slots[0].rft = 0.41;
        state.slots[0].ticks = 399;
        let rods = [Some(BLAZING_ROD.to_owned()), None, None, None];
        let line = blazing_line([302, 101, 0], &state, &rods, true, 1_234, Some("n1"));
        assert_eq!(
            line,
            "Blazing Generator at 302,101,0: 1234/1000000 FE (working true, \
             rft=0.410000,0.000000,0.000000,0.000000, rftmax=60,0,0,0, ticks=399,0,0,0, \
             rods=rftoolspower:blazing_rod,empty,empty,empty, t=1234 nonce=n1)"
        );
    }

    #[test]
    fn the_blazing_command_is_declared_at_the_operator_level() {
        let mut commands = Vec::new();
        declare_commands(&mut commands);
        let blazing: Vec<&str> = commands
            .iter()
            .map(|command| command.usage.as_str())
            .filter(|usage| usage.contains("blazing"))
            .collect();
        assert_eq!(
            blazing,
            vec!["rftoolspower blazing <pos:block_pos> [nonce:word]"]
        );
        let mut types = Vec::new();
        declare_component(&mut types);
        declare_component(&mut types);
        assert_eq!(types, vec![ROD_DATA.to_owned()], "registered once");
    }

    #[test]
    fn the_agitator_has_nine_rod_slots_and_nine_output_slots() {
        let container = agitator_container();
        assert_eq!(container.slots, 18, "two 3×3 boxes");
        assert_eq!(container.inputs, (0..9).collect::<Vec<usize>>());
        assert_eq!(container.outputs, (9..18).collect::<Vec<usize>>());
        assert_eq!(
            container.faces,
            std::array::from_fn(|_| (0..18).collect::<Vec<usize>>()),
            "automation reaches the box from every face, as upstream's ITEMS_AUTOMATION does"
        );
        assert_eq!(container.menu, None, "no GUI in this slice");
    }

    #[test]
    fn the_agitator_buffer_is_fifty_thousand_and_takes_a_hundred_a_tick() {
        let battery = agitator_battery();
        assert_eq!(
            battery.capacity, AGITATOR_CAPACITY,
            "blazingAgitatorMaxPower"
        );
        assert_eq!(
            battery.max_insert, AGITATOR_INSERT_PER_TICK,
            "blazingAgitatorRFPerTick is what one insert moves"
        );
        assert_eq!(battery.max_extract, 0, "the agitator gives nothing out");
        assert_eq!(battery.insert_faces, [true; 6], "every face takes FE in");
        assert_eq!(battery.extract_faces, [false; 6]);
    }

    #[test]
    fn the_agitators_store_and_locks_read_back_from_the_compound_it_wrote() {
        let mut saved = compound();
        let mut state = Agitator {
            energy: 4_321,
            ..Agitator::default()
        };
        state.locks[0] = true;
        state.locks[4] = true;
        write_agitator(&mut saved, &state);
        assert_eq!(read_agitator(&saved), state);
        assert_eq!(
            saved.get("lock4"),
            Some(&Tag::Byte(1)),
            "a lock is vanilla's byte"
        );
        assert_eq!(saved.get("lock1"), Some(&Tag::Byte(0)));
        let mut doctored = compound();
        set_int(&mut doctored, "energy", 999_999);
        assert_eq!(
            read_agitator(&doctored).energy,
            AGITATOR_CAPACITY,
            "a doctored store is clamped"
        );
        let mut negative = compound();
        set_int(&mut negative, "energy", -5);
        assert_eq!(read_agitator(&negative).energy, 0);
    }

    #[test]
    fn a_slot_write_leaves_a_foreign_item_alone() {
        let rod = Rod::default();
        let spent = Rod {
            time: 0.0,
            ..Rod::default()
        };
        // Unchanged: nothing is rebuilt (an agitated rod's data is written once, not every tick).
        assert_eq!(
            slot_write(RodSlot::Rod(rod), RodSlot::Rod(rod)),
            SlotWrite::Leave
        );
        assert_eq!(slot_write(RodSlot::Empty, RodSlot::Empty), SlotWrite::Leave);
        assert_eq!(
            slot_write(RodSlot::Foreign, RodSlot::Foreign),
            SlotWrite::Leave,
            "the tick never touches another item"
        );
        assert_eq!(
            slot_write(RodSlot::BlazeRod, RodSlot::Rod(rod)),
            SlotWrite::Rod(rod),
            "a converted blaze rod becomes a blazing rod"
        );
        assert_eq!(
            slot_write(RodSlot::Rod(spent), RodSlot::Empty),
            SlotWrite::Clear,
            "a rod that moved to the output box clears its slot"
        );
        assert_eq!(
            slot_write(RodSlot::Rod(spent), RodSlot::Rod(rod)),
            SlotWrite::Rod(rod)
        );
    }

    #[test]
    fn the_agitator_line_is_the_line_the_e2e_asserts() {
        let mut state = Agitator {
            energy: 4_990,
            ..Agitator::default()
        };
        state.locks[3] = true;
        let mut slots = [None; AGITATOR_SLOTS];
        slots[0] = Some(Rod::default());
        slots[1] = Some(Rod {
            quality: 60_000.5,
            time: 599.5,
            duration: 20.0625,
            ..Rod::default()
        });
        let mut rods: [Option<String>; AGITATOR_SLOTS] = std::array::from_fn(|_| None);
        rods[0] = Some(BLAZING_ROD.to_owned());
        rods[1] = Some(BLAZING_ROD.to_owned());
        let mut outputs: [Option<String>; AGITATOR_OUTPUTS] = std::array::from_fn(|_| None);
        outputs[0] = Some(BLAZING_ROD.to_owned());
        let line = agitator_line(
            [302, 101, 150],
            &state,
            &slots,
            &rods,
            &outputs,
            9_001,
            Some("n2"),
        );
        assert_eq!(
            line,
            "Blazing Agitator at 302,101,150: 4990/50000 FE (ready true, \
             time=600.000000,599.500000,-,-,-,-,-,-,-, \
             quality=60000.000000,60000.500000,-,-,-,-,-,-,-, \
             duration=20.000000,20.062500,-,-,-,-,-,-,-, \
             locks=000100000, \
             rods=rftoolspower:blazing_rod,rftoolspower:blazing_rod,empty,empty,empty,empty,empty,empty,empty, \
             out=rftoolspower:blazing_rod,empty,empty,empty,empty,empty,empty,empty,empty, \
             t=9001 nonce=n2)"
        );
    }

    #[test]
    fn the_agitator_commands_are_declared_at_the_operator_level() {
        let mut commands = Vec::new();
        declare_commands(&mut commands);
        let agitator: Vec<&str> = commands
            .iter()
            .map(|command| command.usage.as_str())
            .filter(|usage| usage.contains("agitat"))
            .collect();
        assert_eq!(
            agitator,
            vec![
                "rftoolspower agitator <pos:block_pos> [nonce:word]",
                "rftoolspower agitatelock <pos:block_pos> <slot:integer> <lock:word> [nonce:word]",
            ]
        );
    }
}
