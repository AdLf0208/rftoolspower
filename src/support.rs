//! The coal generator's glue: its Part, the block's container and buffer declarations, the saved
//! state, the tick, the `lit` mirror, the click, the drop and the `/rftoolspower info` command.
//!
//! Every rule lives in [`crate::runtime`]; this file reads the game, calls it and writes the result
//! back. Its tests pin what it *declares* (one insert-only fuel slot, a store that gives out 2,000
//! FE a tick and takes nothing in), that the state written to the saved compound reads back, and the
//! exact line `/rftoolspower info` prints.
use mod_api::{
    self, BlockClick, BlockDropsEvent, BlockEntityEvent, BlockEntityPart, BlockEntityTickEvent,
    BlockEntityTickReply, BlockEntityTicksEvent, BlockPart, Command, CommandArgumentValue,
    Compound, Flow, Host, HostTransaction, InteractionResult, ItemPart, ItemPlace, ItemResource,
    ItemStack, LevelHost, LevelRef, LevelSide, ModContainer, ModEnergyBuffer, OnBlockPlacedByEvent,
    Registrar, RegistrationContext, RunModCommandEvent, ServerHost, Tag, Text, UseItemOnEvent,
    UseWithoutItemEvent,
};

use crate::runtime::{CAPACITY, EXTRACT_PER_TICK, Fuel, Generator, restored};

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

/// `saved` tagged as the generator's data, under the vanilla component's name: the patch a broken
/// generator's drop carries (upstream's loot table copies its energy component; this is the
/// vanilla carrier).
pub(crate) fn entity_data_patch(saved: &Compound) -> Compound {
    let mut payload = saved.clone();
    payload.insert("id".into(), Tag::String(GENERATOR_TYPE_ID.into()));
    let mut patch = Compound::new();
    patch.insert(BLOCK_ENTITY_DATA.into(), Tag::Compound(payload));
    patch
}

/// `Hooks::block_drops`: a broken generator keeps its store on its own item, so a player who breaks
/// a burning or charged generator and places it again does not lose the FE or the burn.
pub(crate) fn on_block_drops(level: &dyn LevelHost, event: &mut BlockDropsEvent<'_>) -> Flow {
    if level.state_block(event.state) != Some(GENERATOR) {
        return Flow::Continue;
    }
    let Some(entity) = event.block_entity else {
        return Flow::Continue;
    };
    let Some(saved) = level.block_entity_data(entity) else {
        return Flow::Continue;
    };
    if !crate::runtime::carried(&read_generator(&Tag::Compound(saved.clone()))) {
        return Flow::Continue;
    }
    let patch = entity_data_patch(&saved);
    // The generator's loot is the generator itself, so its store goes on every drop the table made.
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

// ---------------------------------------------------------------------------
// The command
// ---------------------------------------------------------------------------

/// `/rftoolspower info <pos> [nonce]`: the harness's readout of one generator (a harness addition;
/// there is no GUI in this slice).
pub(crate) fn declare_commands(commands: &mut Vec<Command>) {
    commands.push(Command::op(
        "rftoolspower info <pos:block_pos> [nonce:word]",
        OPERATOR_LEVEL,
    ));
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

/// Run `/rftoolspower info <pos> [nonce]`; `Flow::Cancel` when it was ours.
pub(crate) fn run_command(host: &mut dyn ServerHost, event: &mut RunModCommandEvent<'_>) -> Flow {
    let literals: Vec<&str> = event.command.literals.iter().map(String::as_str).collect();
    if literals.as_slice() != ["rftoolspower", "info"] {
        return Flow::Continue;
    }
    if !may_read(event.source.permission()) {
        let _ = host.commands().feedback(Text::literal(format!(
            "rftoolspower info needs an operator (permission level {OPERATOR_LEVEL})"
        )));
        return Flow::Cancel;
    }
    let Some(CommandArgumentValue::BlockPos(pos)) = event.command.argument("pos") else {
        return Flow::Continue;
    };
    let Some(level) = host
        .levels()
        .list_levels()
        .into_iter()
        .find(|level| level.dimension() == event.command.dimension)
    else {
        let _ = host.commands().feedback(Text::literal(NO_GENERATOR));
        return Flow::Cancel;
    };
    let nonce = match event.command.argument("nonce") {
        Some(CommandArgumentValue::String(word)) => Some(word.as_str()),
        _ => None,
    };
    let line = status_line(host, level, *pos, nonce);
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::{COAL_BLOCK_TICKS, TICKS_PER_COAL};

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
        assert_eq!(commands.len(), 1);
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
        let patch = Tag::Compound(entity_data_patch(&saved));
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
}
