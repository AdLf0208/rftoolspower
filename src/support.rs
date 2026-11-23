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
    BlockState, Command, CommandArgumentValue, Compound, Direction, ENERGY, EnergyHandler, Flow,
    Host, HostTransaction, InteractionResult, IsSignalSourceEvent, ItemPart, ItemPlace,
    ItemResource, ItemStack, LevelHost, LevelRef, LevelSide, ModContainer, ModEnergyBuffer,
    NeighbourUpdate, OnBlockPlacedByEvent, Registrar, RegistrationContext, RunModCommandEvent,
    ServerHost, StateForPlacementEvent, Tag, Text, Transaction, UseItemOnEvent,
    UseWithoutItemEvent,
};

use crate::runtime::{
    CAPACITY, Cell, ENDERGENIC_CAPACITY, EXTRACT_PER_TICK, EnderMonitor, Endergenic, Fuel,
    Generator, HOLDING, IDLE, INJECTOR_SLOTS, Loss, MAX_DISTANCE, MONITOR_SIGNAL, Monitor,
    MonitorMode, NETWORK_MAX, OBSERVE_TICKS, PEARL, Pulse, SideMode, Sides, Tier, as_capability,
    capacity as network_capacity, clamp_endergenic, clamped_energy, network_valid, pearl_lost,
    receive as network_receive, restored, rf_per_tick, rising_edge, send_amount,
    stored as network_stored, take as network_take,
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
        "rftoolspower band <pos:block_pos> <minimum:integer> <maximum:integer>",
        "rftoolspower cell <pos:block_pos> [nonce:word]",
        "rftoolspower side <pos:block_pos> <face:word> <mode:word>",
        "rftoolspower endergenic <pos:block_pos> [nonce:word]",
        "rftoolspower injector <pos:block_pos> [nonce:word]",
        "rftoolspower enderlink <pos:block_pos> <destination:block_pos>",
        "rftoolspower endermonitor <pos:block_pos> <action:word> [nonce:word]",
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
            | "band"
            | "cell"
            | "side"
            | "endergenic"
            | "injector"
            | "enderlink"
            | "endermonitor"
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
            "cell" | "side" => NO_CELL,
            "endergenic" | "enderlink" => NO_ENDERGENIC,
            "injector" => NO_INJECTOR,
            "endermonitor" => NO_ENDER_MONITOR,
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

    #[test]
    fn the_commands_are_the_nine_the_harness_types() {
        let mut commands = Vec::new();
        declare_commands(&mut commands);
        assert_eq!(commands.len(), 9);
        assert_eq!(
            commands[0].usage, "rftoolspower info <pos:block_pos> [nonce:word]",
            "the generator readout stays as it was"
        );
        assert_eq!(
            commands[1].usage,
            "rftoolspower monitor <pos:block_pos> [nonce:word]"
        );
        assert_eq!(
            commands[2].usage,
            "rftoolspower band <pos:block_pos> <minimum:integer> <maximum:integer>",
            "the band is set the way upstream's GUI sliders set it"
        );
        assert_eq!(
            commands[3].usage, "rftoolspower cell <pos:block_pos> [nonce:word]",
            "the cell's readout"
        );
        assert_eq!(
            commands[4].usage, "rftoolspower side <pos:block_pos> <face:word> <mode:word>",
            "the side mode is set the way the smart wrench toggles it"
        );
        assert_eq!(
            commands[5].usage, "rftoolspower endergenic <pos:block_pos> [nonce:word]",
            "the endergenic's readout"
        );
        assert_eq!(
            commands[6].usage, "rftoolspower injector <pos:block_pos> [nonce:word]",
            "the pearl injector's readout"
        );
        assert_eq!(
            commands[7].usage, "rftoolspower enderlink <pos:block_pos> <destination:block_pos>",
            "the wrench's link, as a command"
        );
        assert_eq!(
            commands[8].usage,
            "rftoolspower endermonitor <pos:block_pos> <action:word> [nonce:word]",
            "the monitor's readout is `status <nonce>`; a mode word sets its GUI picker"
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
}
