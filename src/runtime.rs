//! RFTools Power — the coal generator's rules, as plain Rust with no `mod_api` types.
//!
//! Every number is upstream's own default from `CoalGeneratorConfig` (1.21-7.0.6): 60 FE a tick,
//! 600 ticks a coal (a coal block burns nine times as long), a 500,000 FE buffer, and 2,000 FE a
//! tick the block will give out through its energy capability. The rules that decide what a tick
//! does live here so `cargo test` alone proves them; [`crate::support`] only reads the game, calls
//! these and writes the result back.
//!
//! Behaviour extracted from `CoalGeneratorTileEntity.tickServer`/`handlePowerGeneration` (analysis
//! only; the port is a clean-room rewrite — see `FINDINGS.md`).

/// The buffer's capacity (`CoalGeneratorConfig.MAXENERGY`, `generatorMaxRF`).
pub const CAPACITY: i32 = 500_000;
/// FE made per burning tick (`CoalGeneratorConfig.RFPERTICK`, `generatePerTick`).
pub const FE_PER_TICK: i32 = 60;
/// Ticks one coal burns (`CoalGeneratorConfig.TICKSPERCOAL`, `ticksPerCoal`).
pub const TICKS_PER_COAL: u32 = 600;
/// A coal block multiplies the burn by nine (`handlePowerGeneration`'s `burning *= 9`).
pub const COAL_BLOCK_TICKS: u32 = TICKS_PER_COAL * 9;
/// The most FE one extract moves (`CoalGeneratorConfig.SENDPERTICK`, `generatorRFPerTick`).
pub const EXTRACT_PER_TICK: i32 = 2_000;

/// Coal (`Items.COAL`).
pub const COAL: &str = "minecraft:coal";
/// Charcoal (`Items.CHARCOAL`).
pub const CHARCOAL: &str = "minecraft:charcoal";
/// A coal block (`Items.COAL_BLOCK`) — one item, nine coals' worth of burn.
pub const COAL_BLOCK: &str = "minecraft:coal_block";

/// The three items `CoalGeneratorTileEntity.isValidFuel` accepts.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Fuel {
    /// One coal.
    Coal,
    /// One charcoal — the same burn as coal.
    Charcoal,
    /// One coal block: nine times a coal's burn.
    CoalBlock,
}

impl Fuel {
    /// The fuel `item` is, or `None` for anything the generator refuses.
    ///
    /// Upstream's test is the item, not the `minecraft:coals` tag: a modded coal-named thing is
    /// not fuel unless it *is* one of the three items.
    #[must_use]
    pub fn of(item: &str) -> Option<Self> {
        match item {
            COAL => Some(Self::Coal),
            CHARCOAL => Some(Self::Charcoal),
            COAL_BLOCK => Some(Self::CoalBlock),
            _ => None,
        }
    }

    /// How many ticks one item of this fuel burns for.
    #[must_use]
    pub fn burn_ticks(self) -> u32 {
        match self {
            Self::Coal | Self::Charcoal => TICKS_PER_COAL,
            Self::CoalBlock => COAL_BLOCK_TICKS,
        }
    }

    /// The item id this fuel is, for the readout and the tests.
    #[must_use]
    pub const fn item(self) -> &'static str {
        match self {
            Self::Coal => COAL,
            Self::Charcoal => CHARCOAL,
            Self::CoalBlock => COAL_BLOCK,
        }
    }
}

/// What the generator's saved compound holds: `energy`, `burn` and `burn_max`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Generator {
    /// Stored FE, 0…[`CAPACITY`].
    pub energy: i32,
    /// Ticks of burn left.
    pub burn: u32,
    /// The burn the current fuel started with (the burn bar's denominator).
    pub burn_max: u32,
}

impl Generator {
    /// An empty generator.
    #[must_use]
    pub const fn new() -> Self {
        Self {
            energy: 0,
            burn: 0,
            burn_max: 0,
        }
    }

    /// Whether it is burning right now.
    #[must_use]
    pub const fn burning(&self) -> bool {
        self.burn > 0
    }

    /// The block's `lit` state: burning, and enabled. Upstream's default redstone mode is
    /// `REDSTONE_IGNORED`, so nothing else gates it in this slice.
    #[must_use]
    pub const fn lit(&self) -> bool {
        self.burning()
    }

    /// Whether the tick should take one item from the fuel slot: upstream loads fuel only when
    /// nothing is burning, and does not consult the buffer (a full generator still eats coal).
    #[must_use]
    pub const fn wants_fuel(&self) -> bool {
        !self.burning()
    }

    /// Light one item of fuel. False when it is already burning (one item at a time).
    pub fn load(&mut self, fuel: Fuel) -> bool {
        if self.burning() {
            return false;
        }
        self.burn = fuel.burn_ticks();
        self.burn_max = self.burn;
        true
    }

    /// One server tick: spend a tick of burn and store [`FE_PER_TICK`], never past the capacity.
    /// Returns the FE actually stored (0 when nothing burned or the buffer was full).
    pub fn tick(&mut self) -> i32 {
        if self.burn == 0 {
            return 0;
        }
        self.burn -= 1;
        let before = self.energy;
        self.energy = clamp_energy(self.energy.saturating_add(FE_PER_TICK));
        self.energy - before
    }
}

/// An amount clamped into the buffer's range.
#[must_use]
pub fn clamp_energy(energy: i32) -> i32 {
    energy.clamp(0, CAPACITY)
}

/// The generator a saved compound describes, with a doctored value clamped the way upstream's
/// `GenericEnergyStorage.load` and the burn counter's own range do.
#[must_use]
pub fn restored(energy: i32, burn: i32, burn_max: i32) -> Generator {
    let burn = u32::try_from(burn).unwrap_or(0).min(COAL_BLOCK_TICKS);
    let burn_max = if burn == 0 {
        0
    } else {
        u32::try_from(burn_max)
            .unwrap_or(0)
            .clamp(burn, COAL_BLOCK_TICKS)
    };
    Generator {
        energy: clamp_energy(energy),
        burn,
        burn_max,
    }
}

/// Whether a broken generator's item must carry the store: anything held is worth keeping
/// (upstream's loot table copies its energy and burn components unconditionally; the port moves
/// them only when there is something to move, so an idle generator drops a plain item).
#[must_use]
pub const fn carried(state: &Generator) -> bool {
    state.energy > 0 || state.burn > 0
}

// ---------------------------------------------------------------------------
// The power monitor (`PowerMonitorTileEntity`)
// ---------------------------------------------------------------------------

/// The steps the monitor's level adds above an empty store (upstream's `stored * 5 / max`).
pub const LEVEL_STEPS: u32 = 5;
/// The highest level a monitor shows; upstream clamps the ratio to 1..=5.
pub const MAX_LEVEL: i32 = 5;
/// Ticks between two observations (upstream's `counter = 20`).
pub const OBSERVE_TICKS: u32 = 20;
/// The band's scale: percentages, as upstream's GUI reads them (`stored * 100 / max`).
pub const PERCENT: u32 = 100;

/// The monitor's saved state: the level it shows, its alarm band and the tick counter.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Monitor {
    /// The level the `level` block state mirrors, 0…[`MAX_LEVEL`].
    pub level: i32,
    /// The band's lower percentage; both 0 is upstream's unconfigured default.
    pub minimum: i32,
    /// The band's upper percentage.
    pub maximum: i32,
    /// Whether the band held at the last observation (the `lit` state and the signal).
    pub alarm: bool,
    /// Ticks left until the next observation.
    pub counter: u32,
}

impl Monitor {
    /// A fresh monitor: level 0, band 0..0 (unset), no alarm, an observation due in 20 ticks.
    #[must_use]
    pub const fn new() -> Self {
        Self {
            level: 0,
            minimum: 0,
            maximum: 0,
            alarm: false,
            counter: OBSERVE_TICKS,
        }
    }

    /// The level upstream's tick sets: `1 + stored * 5 / capacity`, clamped to 1…=5, and 0 when
    /// the target has no capacity (upstream leaves the ratio at 0 when `maxEnergy <= 0`).
    #[must_use]
    pub fn ratio(stored: u32, capacity: u32) -> i32 {
        if capacity == 0 {
            return 0;
        }
        // u64: `stored * 5` overflows a u32 for a doctored store above ~859 million FE.
        let steps = u64::from(stored) * u64::from(LEVEL_STEPS) / u64::from(capacity);
        i32::try_from(1 + steps)
            .unwrap_or(MAX_LEVEL)
            .clamp(1, MAX_LEVEL)
    }

    /// The percentage upstream's alarm compares: `stored * 100 / capacity`, 0 with no capacity.
    #[must_use]
    pub fn percentage(stored: u32, capacity: u32) -> i32 {
        if capacity == 0 {
            return 0;
        }
        i32::try_from(u64::from(stored) * u64::from(PERCENT) / u64::from(capacity))
            .unwrap_or(i32::MAX)
    }

    /// Whether a band is configured. A band of 0..0 is upstream's unconfigured default; with no
    /// GUI in this slice the port reads it as "no alarm" rather than "alarm at exactly 0 %".
    #[must_use]
    pub const fn band_set(minimum: i32, maximum: i32) -> bool {
        !(minimum == 0 && maximum == 0)
    }

    /// Whether `stored` of `capacity` is inside the band.
    #[must_use]
    pub fn alarm(stored: u32, capacity: u32, minimum: i32, maximum: i32) -> bool {
        if capacity == 0 || !Self::band_set(minimum, maximum) {
            return false;
        }
        let percentage = Self::percentage(stored, capacity);
        percentage >= minimum && percentage <= maximum
    }

    /// A monitor a saved compound describes, with every doctored value clamped.
    #[must_use]
    pub fn restored(level: i32, minimum: i32, maximum: i32, alarm: bool, counter: u32) -> Self {
        let level = level.clamp(0, MAX_LEVEL);
        let minimum = minimum.clamp(0, PERCENT as i32);
        let maximum = maximum.clamp(0, PERCENT as i32);
        let (minimum, maximum) = if minimum <= maximum {
            (minimum, maximum)
        } else {
            (maximum, minimum)
        };
        Self {
            // A saved alarm flag under no level describes nothing; the next observation sets it.
            alarm: alarm && level > 0,
            level,
            minimum,
            maximum,
            counter: counter.clamp(1, OBSERVE_TICKS),
        }
    }

    /// One server tick: count down; true when this tick is an observation and the counter reset.
    pub fn tick(&mut self) -> bool {
        self.counter = self.counter.saturating_sub(1);
        if self.counter == 0 {
            self.counter = OBSERVE_TICKS;
            true
        } else {
            false
        }
    }

    /// Apply one observation: `None` when the facing block has no energy capability (upstream's
    /// `setInvalid`), else its store and capacity. Returns whether the level or the alarm changed.
    pub fn observe(&mut self, target: Option<(u32, u32)>) -> bool {
        let before = (self.level, self.alarm);
        match target {
            None => {
                self.level = 0;
                self.alarm = false;
            }
            Some((stored, capacity)) => {
                self.level = Self::ratio(stored, capacity);
                self.alarm = Self::alarm(stored, capacity, self.minimum, self.maximum);
            }
        }
        (self.level, self.alarm) != before
    }
}

// ---------------------------------------------------------------------------
// The power level (`PowerLevelTileEntity`)
// ---------------------------------------------------------------------------

/// The steps the power level's reading takes across the whole store (upstream's `stored * 10`).
pub const POWER_LEVEL_STEPS: u32 = 10;
/// The highest a power level shows; upstream clamps the ratio to 0..=9.
pub const MAX_POWER_LEVEL: i32 = 9;
/// Ticks before a fresh power level's first observation (upstream's `counter = 20` field).
pub const FIRST_POWER_OBSERVE_TICKS: u32 = 20;
/// Ticks between two observations after the first (upstream resets `counter = 10`).
pub const POWER_OBSERVE_TICKS: u32 = 10;

/// The power level's saved state: the ratio it shows and the tick counter (upstream keeps both
/// in the tile entity; the counter is saved here because the tick reply discards payload edits
/// that are not reported as changed).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PowerLevel {
    /// The ratio the `power` block state mirrors and the redstone output answers, 0…=9.
    pub power: i32,
    /// Ticks left until the next observation.
    pub counter: u32,
}

impl PowerLevel {
    /// A fresh power level: ratio 0, and its first observation due in 20 ticks.
    #[must_use]
    pub fn new() -> Self {
        Self {
            power: 0,
            counter: FIRST_POWER_OBSERVE_TICKS,
        }
    }

    /// The ratio upstream's tick sets: `stored * 10 / capacity` in integer arithmetic, clamped
    /// to 0…=9, and 0 when the target has no capacity (upstream leaves the ratio at 0 when
    /// `maxEnergy <= 0`). At 250,000 of 500,000 FE this is **5**, not 4.
    #[must_use]
    pub fn ratio(stored: u32, capacity: u32) -> i32 {
        if capacity == 0 {
            return 0;
        }
        // u64: `stored * 10` overflows a u32 for a doctored store above ~429 million FE.
        let steps = u64::from(stored) * u64::from(POWER_LEVEL_STEPS) / u64::from(capacity);
        i32::try_from(steps)
            .unwrap_or(MAX_POWER_LEVEL)
            .clamp(0, MAX_POWER_LEVEL)
    }

    /// A power level a saved compound describes, with every doctored value clamped.
    #[must_use]
    pub fn restored(power: i32, counter: u32) -> Self {
        Self {
            power: power.clamp(0, MAX_POWER_LEVEL),
            counter: counter.clamp(1, FIRST_POWER_OBSERVE_TICKS),
        }
    }

    /// One server tick: count down; true when this tick is an observation and the counter reset.
    /// The first observation lands at [`FIRST_POWER_OBSERVE_TICKS`], later ones every
    /// [`POWER_OBSERVE_TICKS`] (upstream's field starts at 20 and is reset to 10).
    pub fn tick(&mut self) -> bool {
        self.counter = self.counter.saturating_sub(1);
        if self.counter == 0 {
            self.counter = POWER_OBSERVE_TICKS;
            true
        } else {
            false
        }
    }

    /// Apply one observation: `None` when the facing block has no energy capability (upstream's
    /// `setRedstoneState(this, 0)`), else its store and capacity. Returns whether the ratio
    /// changed.
    pub fn observe(&mut self, target: Option<(u32, u32)>) -> bool {
        let before = self.power;
        self.power = target.map_or(0, |(stored, capacity)| Self::ratio(stored, capacity));
        self.power != before
    }
}

/// What one neighbour of the generator is offered this tick: `min(stored, send)`.
#[must_use]
pub fn send_amount(stored: i32, send_per_tick: i32) -> u32 {
    u32::try_from(stored.max(0).min(send_per_tick.max(0))).unwrap_or(0)
}

// ---------------------------------------------------------------------------
// The powercell (`PowerCellTileEntity`, `PowerCellBlock`, `PowerCellConfig`)
// ---------------------------------------------------------------------------

/// The most blocks upstream lets one powercell network hold (`networkMax`, `9*9*9`); a larger
/// network is `!isValid()` and takes nothing in and gives nothing out.
pub const NETWORK_MAX: usize = 9 * 9 * 9;
/// The extra a network's throughput gains per extra cell, in percent (`rfPerTickScale`, `0.25`).
pub const SCALE_PERCENT: u32 = 25;

/// A powercell's tier (`data/Tier.java`), read from the block's own id.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tier {
    /// `rftoolspower:cell1`.
    One,
    /// `rftoolspower:cell2`.
    Two,
    /// `rftoolspower:cell3`.
    Three,
}

impl Tier {
    /// The tier a cell block is, or `None` for a block that is not a powercell.
    #[must_use]
    pub fn of_block(block: &str) -> Option<Self> {
        match block {
            "rftoolspower:cell1" => Some(Self::One),
            "rftoolspower:cell2" => Some(Self::Two),
            "rftoolspower:cell3" => Some(Self::Three),
            _ => None,
        }
    }

    /// The tier's saved digit (`Tier.getSuffix`: 1, 2, 3), also the readout's `tier=`.
    #[must_use]
    pub const fn suffix(self) -> u8 {
        match self {
            Self::One => 1,
            Self::Two => 2,
            Self::Three => 3,
        }
    }

    /// One cell's capacity: `tierNMaxRF` (500,000 / 4,000,000 / 20,000,000).
    #[must_use]
    pub const fn capacity(self) -> i32 {
        match self {
            Self::One => 500_000,
            Self::Two => 4_000_000,
            Self::Three => 20_000_000,
        }
    }

    /// The most one side of one cell moves a tick: `tierNMaxRFPerTick` (250 / 1,000 / 4,000).
    #[must_use]
    pub const fn per_side(self) -> i32 {
        match self {
            Self::One => 250,
            Self::Two => 1_000,
            Self::Three => 4_000,
        }
    }
}

/// A cell face's mode (`data/SideType.java`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SideMode {
    /// Takes nothing in and gives nothing out (`NONE`, upstream's default on every fresh face).
    None,
    /// Takes FE in from the block on that face (`INPUT`).
    Input,
    /// Gives FE out to the block on that face (`OUTPUT`).
    Output,
}

impl SideMode {
    /// The mode as a command and the readout spell it.
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::None => "none",
            Self::Input => "input",
            Self::Output => "output",
        }
    }

    /// The mode a word spells (`none`/`input`/`output`, case-insensitive).
    #[must_use]
    pub fn parse(text: &str) -> Option<Self> {
        match text.to_ascii_lowercase().as_str() {
            "none" => Some(Self::None),
            "input" => Some(Self::Input),
            "output" => Some(Self::Output),
            _ => None,
        }
    }

    /// Upstream's saved digit for the mode (`SideType.ordinal()`: NONE 0, OUTPUT 1, INPUT 2).
    #[must_use]
    const fn digit(self) -> char {
        match self {
            Self::None => '0',
            Self::Output => '1',
            Self::Input => '2',
        }
    }

    /// The mode a saved digit spells.
    #[must_use]
    fn of_digit(digit: char) -> Option<Self> {
        match digit {
            '0' => Some(Self::None),
            '1' => Some(Self::Output),
            '2' => Some(Self::Input),
            _ => None,
        }
    }

    /// What the smart wrench's right click makes of this mode (`PowerCellTileEntity.toggleMode`:
    /// NONE → INPUT → OUTPUT → NONE).
    #[must_use]
    pub const fn next(self) -> Self {
        match self {
            Self::None => Self::Input,
            Self::Input => Self::Output,
            Self::Output => Self::None,
        }
    }
}

/// A cell's six face modes, by `Direction` number: 0 down, 1 up, 2 north, 3 south, 4 west,
/// 5 east — vanilla's enum order, which upstream indexes with `side.ordinal()`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Sides([SideMode; 6]);

impl Sides {
    /// A fresh cell: every face `NONE`, upstream's `modes` initialiser.
    #[must_use]
    pub const fn fresh() -> Self {
        Self([SideMode::None; 6])
    }

    /// The mode of one face; a face number out of range reads `NONE`.
    #[must_use]
    pub fn get(self, face: usize) -> SideMode {
        self.0.get(face).copied().unwrap_or(SideMode::None)
    }

    /// Set one face's mode. False (and nothing changed) for a face number out of range.
    pub fn set(&mut self, face: usize, mode: SideMode) -> bool {
        let Some(slot) = self.0.get_mut(face) else {
            return false;
        };
        *slot = mode;
        true
    }

    /// Whether any face gives FE out — upstream's `outputCount > 0`, which is what makes the
    /// block tick a send at all.
    #[must_use]
    pub fn any_output(self) -> bool {
        self.0.contains(&SideMode::Output)
    }

    /// How many faces give FE out.
    #[must_use]
    pub fn output_count(self) -> usize {
        self.0
            .iter()
            .filter(|mode| **mode == SideMode::Output)
            .count()
    }

    /// The modes a saved compound's `mode` string holds: upstream writes one digit per face in
    /// `Direction` order (`saveClientDataToNBT`) and needs six of them; anything else is a fresh
    /// cell's six `NONE`s.
    #[must_use]
    pub fn from_saved(text: &str) -> Self {
        let mut sides = Self::fresh();
        let digits: Vec<char> = text.chars().collect();
        if digits.len() != 6 {
            return sides;
        }
        for (face, digit) in digits.into_iter().enumerate() {
            // One unreadable digit is a doctored string; do not half-apply it.
            let Some(mode) = SideMode::of_digit(digit) else {
                return Self::fresh();
            };
            sides.0[face] = mode;
        }
        sides
    }

    /// The saved form: one digit per face, upstream's own six-character string.
    #[must_use]
    pub fn to_saved(self) -> String {
        self.0.into_iter().map(SideMode::digit).collect()
    }

    /// The modes as the readout prints them, in face order.
    #[must_use]
    pub fn names(self) -> String {
        self.0
            .into_iter()
            .map(SideMode::name)
            .collect::<Vec<_>>()
            .join(",")
    }
}

/// One cell of a network, as the rules need it: its tier and its own stored FE.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cell {
    /// The cell's tier.
    pub tier: Tier,
    /// The cell's own store, 0…[`Tier::capacity`].
    pub energy: i32,
}

/// An amount clamped into one cell's range.
#[must_use]
pub fn clamped_energy(tier: Tier, energy: i32) -> i32 {
    energy.clamp(0, tier.capacity())
}

/// Whether a network of `cells` blocks is one upstream would use: `networkMax`.
#[must_use]
pub fn network_valid(cells: usize) -> bool {
    cells <= NETWORK_MAX
}

/// The most one side of a network of `cells` moves a tick: upstream's `getRfPerTickReal`,
/// `per_side + (cells - 1) * per_side * rfPerTickScale`, truncated to an integer by its `(long)`
/// cast — so a lone tier-1 cell moves 250 and a pair moves 312 (312.5 cut down).
#[must_use]
pub fn rf_per_tick(tier: Tier, cells: usize) -> u32 {
    let per_side = f64::from(tier.per_side());
    let extra = u32::try_from(cells.saturating_sub(1)).map_or(0.0, f64::from);
    let scaled = per_side + extra * per_side * f64::from(SCALE_PERCENT) / 100.0;
    // `as u64` truncates toward zero, as upstream's `(long)` cast does.
    u32::try_from(scaled as u64).unwrap_or(u32::MAX)
}

/// What the network holds, as upstream's `PowerCellNetwork.getEnergy` sums its cells' locals.
#[must_use]
pub fn stored(cells: &[Cell]) -> u64 {
    cells
        .iter()
        .map(|cell| u64::try_from(cell.energy.max(0)).unwrap_or(0))
        .sum()
}

/// What the network can hold: the sum of its cells' capacities, which is why a mixed-tier
/// network's total is the sum of each tier's own capacity.
#[must_use]
pub fn capacity(cells: &[Cell]) -> u64 {
    cells
        .iter()
        .map(|cell| u64::try_from(cell.tier.capacity()).unwrap_or(0))
        .sum()
}

/// A network total as the energy capability answers it: upstream's `getStoredPower`/
/// `getCapacity` cast to `int` with `Math.min(Integer.MAX_VALUE, …)`, so a network past 2.1
/// billion FE reads as 2,147,483,647 rather than wrapping.
#[must_use]
pub fn as_capability(total: u64) -> u32 {
    u32::try_from(total.min(i32::MAX as u64)).unwrap_or(i32::MAX as u32)
}

/// Take up to `request` into a network, the cell asked first and then the rest of the network,
/// as upstream's `receiveEnergyFacing` fills its own block and then walks the network. Capped by
/// [`rf_per_tick`] (the budget is per side, not shared between the cell's faces) and by the
/// network's free room; returns how much actually went in.
///
/// `cells[0]` is the cell that was asked, and its tier decides the budget.
pub fn receive(cells: &mut [Cell], request: u32) -> u32 {
    let Some(asked) = cells.first() else {
        return 0;
    };
    // Upstream's `network == null || !network.isValid()` guard: nothing moves at all.
    if !network_valid(cells.len()) || request == 0 {
        return 0;
    }
    let mut left = request.min(rf_per_tick(asked.tier, cells.len()));
    let mut taken = 0;
    for cell in cells.iter_mut() {
        if left == 0 {
            break;
        }
        let room = u32::try_from(cell.tier.capacity().saturating_sub(cell.energy)).unwrap_or(0);
        let put = left.min(room);
        cell.energy = cell.energy.saturating_add(i32::try_from(put).unwrap_or(0));
        left -= put;
        taken += put;
    }
    taken
}

/// Take up to `amount` out of a network, the cell asked first and then the rest, as upstream's
/// `extractEnergyFromNetwork` drains its own block before its neighbours. Returns how much came.
pub fn take(cells: &mut [Cell], amount: u32) -> u32 {
    let mut left = amount;
    let mut taken = 0;
    for cell in cells.iter_mut() {
        if left == 0 {
            break;
        }
        let got = left.min(u32::try_from(cell.energy.max(0)).unwrap_or(0));
        cell.energy -= i32::try_from(got).unwrap_or(0);
        left -= got;
        taken += got;
    }
    taken
}

// ---------------------------------------------------------------------------
// The endergenic generator (`EndergenicTileEntity`, `EndergenicConfiguration`)
// ---------------------------------------------------------------------------

/// `EndergenicConfiguration.MAXENERGY` (`endergenicMaxPower`).
pub const ENDERGENIC_CAPACITY: i32 = 5_000_000;
/// `rfToHoldPearl` (`endergenicRfHolding`): the FE one held pearl costs every tick.
pub const RF_TO_HOLD: i32 = 500;
/// `ENDERGENIC_KEEPRF` (`endergenicKeepRf`): the reserve the generator never sends out.
pub const KEEP_RF: i32 = 2_000;
/// `ENDERGENIC_SENDPERTICK` (`endergenicSendPerTick`): the most one tick offers its neighbours.
pub const SEND_PER_TICK: i32 = 20_000;
/// `powergenFactor` (default 2.0), as an integer multiplier: every hit is worth twice its table.
pub const POWERGEN_FACTOR: i32 = 2;
/// `chanceLost` (`endergenicChanceLost`): in thousandths, so 5 is upstream's 0.6 %.
pub const CHANCE_LOST: u32 = 5;
/// `EndergenicTileEntity.rfPerHit`: what a pearl that arrives at each charging mode is worth,
/// before `powergenFactor` and the age bonus. Index 0 (idle) pays nothing.
pub const RF_PER_HIT: [i32; 16] = [
    0, 100, 150, 200, 400, 800, 1_600, 3_200, 6_400, 8_000, 12_800, 8_000, 6_400, 2_500, 1_000, 100,
];
/// The last charging mode a pearl can arrive at: a generator charges 1…=15 and then goes idle
/// (`chargingMode >= 16`). This window is the mechanic — an arrival outside it is a lost pearl.
pub const MAX_CHARGE: i32 = 15;
/// `CHARGE_IDLE`: nothing is happening.
pub const IDLE: i32 = 0;
/// `CHARGE_HOLDING`: a pearl is held and paid for every tick.
pub const HOLDING: i32 = -1;
/// The longest link upstream accepts: `distance >= 5` is refused ("maximum 4").
pub const MAX_DISTANCE: i32 = 4;
/// The age bonus per pearl age step, in percent (`age * 5`).
pub const AGE_STEP: i32 = 5;
/// The age bonus's ceiling, in percent (200 % at most: `a` is clamped to 100).
pub const AGE_CAP: i32 = 100;
/// The only item a pearl injector loads (`Items.ENDER_PEARL`).
pub const PEARL: &str = "minecraft:ender_pearl";
/// The injector's buffer (`PearlInjectorTileEntity.BUFFER_SIZE`, a 9×2 grid of pearls).
pub const INJECTOR_SLOTS: usize = 9 * 2;
/// A doctored saved pearl list is clamped to this many travelling pearls (upstream's list is
/// unbounded; a broken item must not make the tick loop unbounded).
pub const MAX_PEARLS: usize = 64;

/// One pearl in flight (`data/EndergenicPearl.java`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Pearl {
    /// Ticks left before it arrives; the pearl arrives on the tick it reaches 0.
    pub ticks_left: i32,
    /// The generator it was fired at.
    pub destination: [i32; 3],
    /// How many generators it has already powered (upstream's age bonus).
    pub age: i32,
}

impl Pearl {
    /// A pearl `distance` ticks from `destination`, aged `age`.
    #[must_use]
    pub const fn new(distance: i32, destination: [i32; 3], age: i32) -> Self {
        Self {
            ticks_left: distance,
            destination,
            age,
        }
    }

    /// One tick of flight; true when it arrived.
    #[must_use]
    pub fn tick(mut self) -> (Self, bool) {
        self.ticks_left -= 1;
        (self, self.ticks_left <= 0)
    }
}

/// Why a pearl was dropped (`discardPearl`'s reasons).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Loss {
    /// Fired from a generator with no destination (`"Missing destination"`).
    MissingDestination,
    /// `"Pearl arrived while holding"`.
    WhileHolding,
    /// `"Pearl arrived while idle"`.
    WhileIdle,
    /// `"Not enough energy to hold pearl"`.
    NotEnoughEnergy,
    /// `"Random pearl discard"` — the configured chance.
    Chance,
}

impl Loss {
    /// The reason as the readout spells it.
    #[must_use]
    pub const fn text(self) -> &'static str {
        match self {
            Self::MissingDestination => "Missing destination",
            Self::WhileHolding => "Pearl arrived while holding",
            Self::WhileIdle => "Pearl arrived while idle",
            Self::NotEnoughEnergy => "Not enough energy to hold pearl",
            Self::Chance => "Random pearl discard",
        }
    }

    /// The reason a saved string spells, for the readout of a generator that was saved after a drop.
    #[must_use]
    pub fn parse(text: &str) -> Option<Self> {
        [
            Self::MissingDestination,
            Self::WhileHolding,
            Self::WhileIdle,
            Self::NotEnoughEnergy,
            Self::Chance,
        ]
        .into_iter()
        .find(|loss| loss.text() == text)
    }
}

/// What a tick's redstone edge asks the generator to do.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Pulse {
    /// No rising edge.
    None,
    /// A rising edge while idle: begin charging.
    Start,
    /// A rising edge while holding: fire the held pearl.
    Fire,
}

/// Whether a tick is a rising edge, and the input state to keep (`prevIn`).
///
/// Upstream reads `powerLevel > 0 && !prevIn`; the signal is `Level.getBestNeighborSignal`.
#[must_use]
pub const fn rising_edge(prev: bool, power: i32) -> (bool, bool) {
    (power > 0 && !prev, power > 0)
}

/// The saved state of one endergenic generator (`EndergenicTileEntity`).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Endergenic {
    /// Stored FE, 0…[`ENDERGENIC_CAPACITY`].
    pub energy: i32,
    /// [`IDLE`], [`HOLDING`], or a charging mode 1…=[`MAX_CHARGE`].
    pub charging: i32,
    /// The age the held pearl arrived with (upstream's `currentAge`).
    pub age: i32,
    /// Where the next fired pearl goes (upstream's `destination`; a wrench link).
    pub destination: Option<[i32; 3]>,
    /// The link's flight time in ticks (upstream's `distance`).
    pub distance: i32,
    /// The redstone input at the last tick (`prevIn`).
    pub prev_in: bool,
    /// Pearls in flight.
    pub pearls: Vec<Pearl>,
    /// Every FE a pearl has ever paid this generator.
    pub gained: i64,
    /// Every FE spent holding pearls.
    pub spent: i64,
    /// Pearls fired.
    pub launched: u32,
    /// Pearls dropped.
    pub dropped: u32,
    /// The charging mode the last pearl arrived at (upstream's `pearlArrivedAt`; −2 = none).
    pub arrived_at: i32,
    /// Why the last pearl was dropped.
    pub last_loss: Option<Loss>,
}

impl Endergenic {
    /// A fresh generator: idle, empty, no link, no pearls.
    #[must_use]
    pub const fn new() -> Self {
        Self {
            energy: 0,
            charging: IDLE,
            age: 0,
            destination: None,
            distance: 0,
            prev_in: false,
            pearls: Vec::new(),
            gained: 0,
            spent: 0,
            launched: 0,
            dropped: 0,
            arrived_at: -2,
            last_loss: None,
        }
    }

    /// Whether it is in the charging window right now.
    #[must_use]
    pub const fn charging_window(&self) -> bool {
        self.charging >= 1 && self.charging <= MAX_CHARGE
    }

    /// Whether it holds a pearl.
    #[must_use]
    pub const fn holding(&self) -> bool {
        self.charging == HOLDING
    }

    /// One tick's redstone edge, keeping `prev_in`.
    pub fn pulse(&mut self, power: i32) -> Pulse {
        let (edge, prev) = rising_edge(self.prev_in, power);
        self.prev_in = prev;
        if !edge {
            return Pulse::None;
        }
        match self.charging {
            IDLE => Pulse::Start,
            HOLDING => Pulse::Fire,
            _ => Pulse::None,
        }
    }

    /// `startCharging`: enter the window at mode 1.
    pub fn start_charging(&mut self) {
        self.charging = 1;
    }

    /// One tick of charging: mode + 1, idle once past the window.
    pub fn charge_step(&mut self) {
        self.charging += 1;
        if self.charging > MAX_CHARGE {
            self.charging = IDLE;
        }
    }

    /// Pay [`RF_TO_HOLD`]; false when the store cannot, which loses the pearl.
    pub fn hold(&mut self) -> bool {
        if self.energy < RF_TO_HOLD {
            return false;
        }
        self.energy -= RF_TO_HOLD;
        self.spent += i64::from(RF_TO_HOLD);
        true
    }

    /// Drop the held pearl, counting it and keeping the reason.
    pub fn discard(&mut self, why: Loss) {
        self.charging = IDLE;
        self.dropped += 1;
        self.last_loss = Some(why);
    }

    /// Fire the held pearl (or an injected one) at the destination.
    ///
    /// A generator with no destination loses the pearl (`"Missing destination"`). `from_injector`
    /// launches an age-0 pearl and does not need a held one, as upstream's
    /// `firePearlFromInjector` does; a held pearl keeps its age + 1.
    pub fn fire(&mut self, from_injector: bool) -> bool {
        let Some(destination) = self.destination else {
            self.charging = IDLE;
            self.discard(Loss::MissingDestination);
            return false;
        };
        let age = if from_injector { 0 } else { self.age + 1 };
        self.charging = IDLE;
        self.launched += 1;
        self.pearls
            .push(Pearl::new(self.distance.max(1), destination, age));
        true
    }

    /// The FE a pearl arriving at `mode` with `age` is worth: the table times the powergen
    /// factor, plus up to a doubling for the pearl's age (upstream's `receivePearl`).
    #[must_use]
    pub fn gain(mode: i32, age: i32) -> i32 {
        if mode <= IDLE || mode > MAX_CHARGE {
            return 0;
        }
        let index = usize::try_from(mode).unwrap_or(0);
        let base = RF_PER_HIT.get(index).copied().unwrap_or(0) * POWERGEN_FACTOR;
        let bonus = (age.max(0) * AGE_STEP).min(AGE_CAP);
        base + base * bonus / 100
    }

    /// A pearl arrives (`receivePearl`): inside the window it pays and the generator starts
    /// holding; at idle or while already holding both pearls are lost and nothing is paid.
    pub fn receive(&mut self, age: i32) -> Option<i32> {
        match self.charging {
            HOLDING => {
                self.discard(Loss::WhileHolding);
                None
            }
            IDLE => {
                self.discard(Loss::WhileIdle);
                None
            }
            mode => {
                self.arrived_at = mode;
                let gained = Self::gain(mode, age);
                self.gained += i64::from(gained);
                self.energy = clamp_endergenic(self.energy.saturating_add(gained));
                self.charging = HOLDING;
                self.age = age;
                Some(gained)
            }
        }
    }

    /// One tick of flight for every pearl in the air; the arrivals as `(destination, age)`.
    pub fn tick_pearls(&mut self) -> Vec<([i32; 3], i32)> {
        let mut arrivals = Vec::new();
        self.pearls.retain_mut(|pearl| {
            let (next, arrived) = pearl.tick();
            *pearl = next;
            if arrived {
                arrivals.push((pearl.destination, pearl.age));
                false
            } else {
                true
            }
        });
        arrivals
    }

    /// `calculateDistance`: the flight time between two blocks, `(int)(distance / 3) + 1`.
    #[must_use]
    pub fn distance_between(from: [i32; 3], to: [i32; 3]) -> i32 {
        let square: f64 = (0..3)
            .map(|axis| {
                let delta = f64::from(to[axis] - from[axis]);
                delta * delta
            })
            .sum();
        (square.sqrt() / 3.0) as i32 + 1
    }

    /// What one tick may offer each neighbour: the store above [`KEEP_RF`], at most
    /// [`SEND_PER_TICK`] (upstream's `storedPower = energy - ENDERGENIC_KEEPRF`).
    #[must_use]
    pub fn send_amount(&self) -> u32 {
        u32::try_from((self.energy - KEEP_RF).clamp(0, SEND_PER_TICK)).unwrap_or(0)
    }

    /// The state a saved compound describes, with every doctored value clamped the way upstream's
    /// `GenericEnergyStorage.load` and the field ranges do.
    #[must_use]
    #[expect(
        clippy::too_many_arguments,
        reason = "one saved field per argument: the compound's own shape"
    )]
    pub fn restored(
        energy: i32,
        charging: i32,
        age: i32,
        destination: Option<[i32; 3]>,
        distance: i32,
        prev_in: bool,
        pearls: Vec<Pearl>,
        gained: i64,
        spent: i64,
        launched: i32,
        dropped: i32,
        arrived_at: i32,
    ) -> Self {
        let charging = if charging == HOLDING {
            HOLDING
        } else {
            charging.clamp(IDLE, MAX_CHARGE)
        };
        let mut pearls: Vec<Pearl> = pearls
            .into_iter()
            .filter(|pearl| pearl.ticks_left >= 1)
            .map(|pearl| Pearl {
                ticks_left: pearl.ticks_left.min(MAX_DISTANCE * 8),
                destination: pearl.destination,
                age: pearl.age.max(0),
            })
            .take(MAX_PEARLS)
            .collect();
        pearls.shrink_to_fit();
        Self {
            energy: clamp_endergenic(energy),
            charging,
            age: age.max(0),
            destination,
            distance: destination.map_or(0, |_| distance.clamp(0, MAX_DISTANCE)),
            prev_in,
            pearls,
            gained: gained.max(0),
            spent: spent.max(0),
            launched: u32::try_from(launched).unwrap_or(0),
            dropped: u32::try_from(dropped).unwrap_or(0),
            arrived_at: arrived_at.clamp(-2, MAX_CHARGE),
            // The reason is a readout of the last drop, not saved state; a fresh load has none.
            last_loss: None,
        }
    }
}

/// An amount clamped into the endergenic buffer.
#[must_use]
pub fn clamp_endergenic(energy: i32) -> i32 {
    energy.clamp(0, ENDERGENIC_CAPACITY)
}

/// A deterministic draw in 0…999 for the pearl-loss chance (splitmix64).
///
/// Upstream uses `java.util.Random`; a fixed hash of the generator's position and the world time
/// is the same 6-in-1000 chance and makes a run reproducible, so a lost pearl can be replayed
/// instead of appearing once in a test run.
#[must_use]
pub const fn chance_roll(seed: u64) -> u32 {
    let mut z = seed.wrapping_add(0x9E37_79B9_7F4A_7C15);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^= z >> 31;
    (z % 1000) as u32
}

/// Whether this draw loses the held pearl: upstream's `random.nextInt(1000) <= chanceLost`.
#[must_use]
pub const fn pearl_lost(seed: u64) -> bool {
    chance_roll(seed) <= CHANCE_LOST
}

// ---------------------------------------------------------------------------
// The ender monitor (`EnderMonitorTileEntity`, `EnderMonitorMode`, `EnderMonitorData`)
// ---------------------------------------------------------------------------

/// The strongest signal the monitor's one-tick output gives (`support.setRedstoneState(this, 15)`).
pub const MONITOR_SIGNAL: i32 = 15;

/// What an ender monitor watches: one of upstream's three `EnderMonitorMode`s.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum MonitorMode {
    /// A pearl was dropped (`MODE_LOSTPEARL`).
    #[default]
    LostPearl,
    /// A pearl left a generator (`MODE_PEARLFIRED`).
    PearlFired,
    /// A pearl landed on a generator, inside or outside its window (`MODE_PEARLARRIVED`).
    PearlArrived,
}

impl MonitorMode {
    /// The three modes, in upstream's declaration order.
    pub const ALL: [Self; 3] = [Self::LostPearl, Self::PearlFired, Self::PearlArrived];

    /// The mode's serialised name, which is what upstream's `StringRepresentable` codec writes.
    #[must_use]
    pub const fn saved(self) -> &'static str {
        match self {
            Self::LostPearl => "MODE_LOSTPEARL",
            Self::PearlFired => "MODE_PEARLFIRED",
            Self::PearlArrived => "MODE_PEARLARRIVED",
        }
    }

    /// The mode a saved string names.
    #[must_use]
    pub fn parse_saved(text: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|mode| mode.saved() == text)
    }

    /// The word `/rftoolspower endermonitor` accepts: `lost`, `fired`, `arrived`.
    #[must_use]
    pub const fn command_name(self) -> &'static str {
        match self {
            Self::LostPearl => "lost",
            Self::PearlFired => "fired",
            Self::PearlArrived => "arrived",
        }
    }

    /// The mode a command word names.
    #[must_use]
    pub fn parse_command(text: &str) -> Option<Self> {
        Self::ALL
            .into_iter()
            .find(|mode| mode.command_name() == text)
    }
}

/// The ender monitor's saved state: the mode it watches, the pulse it owes and the readout's
/// counters.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct EnderMonitor {
    /// The mode it watches.
    pub mode: MonitorMode,
    /// Upstream's saved `needPulse`: an event it watches happened and this tick owes 15.
    pub need_pulse: bool,
    /// How many one-tick outputs it has given (the readout's counter).
    pub pulses: u32,
    /// The mode of the last event it armed for.
    pub last: Option<MonitorMode>,
}

impl EnderMonitor {
    /// A fresh monitor: watches lost pearls, owes no pulse (upstream's attachment default).
    #[must_use]
    pub const fn new() -> Self {
        Self {
            mode: MonitorMode::LostPearl,
            need_pulse: false,
            pulses: 0,
            last: None,
        }
    }

    /// `fireFromEndergenic(mode)`: arm the next tick only when this is the mode it watches.
    ///
    /// True when it armed.
    pub fn notice(&mut self, mode: MonitorMode) -> bool {
        if self.mode != mode {
            return false;
        }
        self.need_pulse = true;
        self.last = Some(mode);
        true
    }

    /// One server tick: spend an owed pulse as [`MONITOR_SIGNAL`] for this tick, else 0.
    pub fn tick(&mut self) -> i32 {
        if !self.need_pulse {
            return 0;
        }
        self.need_pulse = false;
        self.pulses += 1;
        MONITOR_SIGNAL
    }

    /// The state a saved compound describes.
    ///
    /// A "last" mode is kept while it still describes something: a pulse already given, or the one
    /// the next tick owes (a notice is written a tick before the tick spends it). A saved "last"
    /// with neither is a doctored save and is dropped — in game this rule was written the wrong way
    /// round first, and the e2e caught it: the notice wrote `last=arrived` with `pulses=0`, the
    /// tick's own read dropped it, and the monitor then read `pulses=1 last=none`.
    #[must_use]
    pub fn restored(
        mode: MonitorMode,
        need_pulse: bool,
        pulses: u32,
        last: Option<MonitorMode>,
    ) -> Self {
        Self {
            mode,
            need_pulse,
            pulses,
            last: if pulses == 0 && !need_pulse {
                None
            } else {
                last
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A generator burning one coal, filled to `energy`.
    fn burning(energy: i32) -> Generator {
        let mut generator = Generator {
            energy,
            ..Generator::new()
        };
        assert!(generator.load(Fuel::Coal));
        generator
    }

    #[test]
    fn a_coal_burns_600_ticks_for_36_000_fe() {
        let mut generator = Generator::new();
        assert!(generator.load(Fuel::Coal));
        assert_eq!(generator.burn_max, 600, "the burn bar's denominator");
        let mut made = 0;
        for _ in 0..600 {
            made += generator.tick();
        }
        assert_eq!(made, 36_000, "600 ticks x 60 FE");
        assert_eq!(generator.energy, 36_000);
        assert!(!generator.burning(), "the coal is spent");
        assert_eq!(generator.tick(), 0, "and now it makes nothing");
    }

    #[test]
    fn a_coal_block_burns_nine_times_as_long() {
        let mut generator = Generator::new();
        assert!(generator.load(Fuel::CoalBlock));
        assert_eq!(generator.burn_max, 5_400);
        let mut made = 0;
        for _ in 0..5_400 {
            made += generator.tick();
        }
        assert_eq!(made, 324_000, "5,400 ticks x 60 FE");
        assert_eq!(generator.energy, 324_000);
    }

    #[test]
    fn charcoal_burns_like_coal_and_stone_is_no_fuel() {
        assert_eq!(Fuel::of("minecraft:charcoal"), Some(Fuel::Charcoal));
        assert_eq!(
            Fuel::Charcoal.burn_ticks(),
            Fuel::Coal.burn_ticks(),
            "charcoal is the same 600 ticks"
        );
        assert_eq!(Fuel::of("minecraft:coal_block"), Some(Fuel::CoalBlock));
        for other in [
            "minecraft:stone",
            "minecraft:stick",
            "minecraft:charcoal_block",
            "rftoolspower:coalgenerator",
        ] {
            assert_eq!(Fuel::of(other), None, "{other} is not fuel");
        }
    }

    #[test]
    fn an_unfuelled_generator_makes_nothing() {
        let mut generator = Generator::new();
        for _ in 0..100 {
            assert_eq!(generator.tick(), 0);
        }
        assert_eq!(generator.energy, 0, "no fuel, no FE — the differential");
        assert!(!generator.lit());
        assert!(generator.wants_fuel(), "an idle generator wants fuel");
    }

    #[test]
    fn the_buffer_clamps_at_the_capacity_and_still_burns() {
        let mut generator = burning(CAPACITY - 5);
        assert_eq!(generator.tick(), 5, "five FE of room");
        assert_eq!(generator.energy, CAPACITY);
        assert_eq!(generator.tick(), 0, "a full buffer stores nothing more");
        assert_eq!(generator.energy, CAPACITY);
        assert!(
            generator.burning(),
            "upstream keeps burning — the fuel is spent anyway"
        );
    }

    #[test]
    fn one_fuel_item_at_a_time() {
        let mut generator = Generator::new();
        assert!(generator.wants_fuel());
        assert!(generator.load(Fuel::Coal));
        assert!(!generator.wants_fuel(), "still burning");
        assert!(
            !generator.load(Fuel::Charcoal),
            "no second item while burning"
        );
        assert_eq!(
            generator.burn, TICKS_PER_COAL,
            "the second load changed nothing"
        );
        for _ in 0..TICKS_PER_COAL {
            generator.tick();
        }
        assert!(
            generator.wants_fuel(),
            "spent: the next tick loads the next item"
        );
    }

    #[test]
    fn the_burn_bar_keeps_its_denominator() {
        let mut generator = burning(0);
        for _ in 0..100 {
            generator.tick();
        }
        assert_eq!(generator.burn, 500);
        assert_eq!(
            generator.burn_max, 600,
            "the bar shrinks, the denominator does not"
        );
    }

    #[test]
    fn a_doctored_item_is_clamped_on_restore() {
        assert_eq!(
            restored(999_999, 0, 0).energy,
            CAPACITY,
            "an edited amount is clamped"
        );
        assert_eq!(restored(-5, 0, 0).energy, 0, "a negative amount is empty");
        let huge = restored(0, 999_999, 999_999);
        assert_eq!(
            huge.burn, COAL_BLOCK_TICKS,
            "no burn longer than a coal block's"
        );
        let short = restored(0, 300, 999_999);
        assert_eq!(
            short.burn_max, COAL_BLOCK_TICKS,
            "a doctored denominator is clamped too"
        );
        let odd = restored(0, 0, 600);
        assert_eq!(odd.burn_max, 0, "no denominator over an empty bar");
        let burned = restored(0, 400, 600);
        assert_eq!(burned.burn_max, 600, "a real state is untouched");
    }

    #[test]
    fn only_a_generator_holding_something_carries_it_on_its_item() {
        assert!(
            !carried(&Generator::new()),
            "an idle generator drops a plain item"
        );
        assert!(carried(&burning(0)), "burn left is worth keeping");
        assert!(
            carried(&Generator {
                energy: 1,
                ..Generator::new()
            }),
            "one FE is worth keeping"
        );
    }

    #[test]
    fn a_coal_block_is_one_item_and_nine_coals_of_burn() {
        assert_eq!(Fuel::CoalBlock.burn_ticks(), Fuel::Coal.burn_ticks() * 9);
        assert_eq!(Fuel::CoalBlock.item(), "minecraft:coal_block");
        assert_eq!(
            Fuel::CoalBlock.burn_ticks() * u32::try_from(FE_PER_TICK).unwrap(),
            324_000
        );
    }

    // --- the power monitor -------------------------------------------------

    #[test]
    fn the_ratio_is_one_plus_five_steps_of_charge() {
        assert_eq!(Monitor::ratio(0, 500_000), 1, "an empty battery is level 1");
        assert_eq!(Monitor::ratio(100_000, 500_000), 2, "a fifth is level 2");
        assert_eq!(
            Monitor::ratio(250_000, 500_000),
            3,
            "half is level 3 — the leg's 250,000 FE"
        );
        assert_eq!(
            Monitor::ratio(400_000, 500_000),
            5,
            "four fifths is level 5"
        );
        assert_eq!(
            Monitor::ratio(500_000, 500_000),
            5,
            "a full battery clamps at 5, never 6"
        );
        assert_eq!(
            Monitor::ratio(900_000, 500_000),
            5,
            "a doctored store above the capacity still clamps"
        );
        assert_eq!(
            Monitor::ratio(0, 0),
            0,
            "no capacity is no reading — upstream's maxEnergy > 0 guard"
        );
        assert_eq!(Monitor::ratio(5, 0), 0);
    }

    #[test]
    fn the_percentage_is_upstreams_integer_percentage() {
        assert_eq!(Monitor::percentage(250_000, 500_000), 50);
        assert_eq!(Monitor::percentage(100_000, 500_000), 20);
        assert_eq!(
            Monitor::percentage(1, 3),
            33,
            "integer division, as upstream"
        );
        assert_eq!(Monitor::percentage(0, 500_000), 0);
        assert_eq!(Monitor::percentage(5, 0), 0, "no capacity is no percentage");
    }

    #[test]
    fn an_unconfigured_band_never_alarms() {
        assert!(!Monitor::band_set(0, 0), "upstream's default is 0..0");
        assert!(Monitor::band_set(0, 100));
        assert!(Monitor::band_set(40, 60));
        for stored in [0, 1, 250_000, 500_000] {
            assert!(
                !Monitor::alarm(stored, 500_000, 0, 0),
                "{stored} FE: the unset band is silent"
            );
        }
    }

    #[test]
    fn a_configured_band_alarms_inside_it_and_not_at_its_edges_outside() {
        assert!(
            Monitor::alarm(250_000, 500_000, 40, 60),
            "50 % is inside 40..60"
        );
        assert!(
            !Monitor::alarm(100_000, 500_000, 40, 60),
            "20 % is below the band"
        );
        assert!(
            !Monitor::alarm(400_000, 500_000, 40, 60),
            "80 % is above the band"
        );
        assert!(
            Monitor::alarm(200_000, 500_000, 40, 60),
            "40 % is inclusive, as upstream's >= minimum"
        );
        assert!(
            Monitor::alarm(300_000, 500_000, 40, 60),
            "60 % is inclusive, as upstream's <= maximum"
        );
        assert!(
            !Monitor::alarm(0, 0, 40, 60),
            "a capacity of 0 has no percentage"
        );
    }

    #[test]
    fn the_observation_runs_every_twenty_ticks() {
        let mut monitor = Monitor::new();
        assert_eq!(monitor.counter, OBSERVE_TICKS);
        for tick in 1..OBSERVE_TICKS {
            assert!(!monitor.tick(), "tick {tick} is not the observation");
        }
        assert!(monitor.tick(), "the twentieth tick observes");
        assert_eq!(monitor.counter, OBSERVE_TICKS, "the counter resets");
        for _ in 1..OBSERVE_TICKS {
            assert!(!monitor.tick());
        }
        assert!(monitor.tick(), "and the next window observes again");
    }

    #[test]
    fn an_observation_only_says_changed_when_the_state_moved() {
        let mut monitor = Monitor::new();
        assert!(
            monitor.observe(Some((250_000, 500_000))),
            "level 0 -> 3 is a change"
        );
        assert_eq!(monitor.level, 3);
        assert!(!monitor.alarm, "an unset band stays silent");
        assert!(
            !monitor.observe(Some((250_000, 500_000))),
            "the same store changes nothing"
        );
        assert!(
            monitor.observe(None),
            "a target that is not an energy block is a change"
        );
        assert_eq!(monitor.level, 0, "upstream's setInvalid sets level 0");
        assert!(!monitor.alarm);
        assert!(
            !monitor.observe(None),
            "and staying invalid changes nothing"
        );
        assert!(monitor.observe(Some((0, 500_000))));
        assert_eq!(monitor.level, 1, "an empty battery is level 1");
    }

    #[test]
    fn a_band_reaches_the_alarm_on_the_next_observation() {
        let mut monitor = Monitor::restored(3, 40, 60, false, 1);
        assert!(
            monitor.observe(Some((250_000, 500_000))),
            "50 % is in the band"
        );
        assert!(monitor.alarm);
        assert!(
            monitor.observe(Some((100_000, 500_000))),
            "leaving the band is a change"
        );
        assert!(!monitor.alarm, "20 % is out of the band");
        assert_eq!(monitor.level, 2, "and the level followed the store");
    }

    #[test]
    fn a_doctored_monitor_is_clamped() {
        let high = Monitor::restored(9, -10, 500, true, 0);
        assert_eq!(high.level, MAX_LEVEL, "no level above 5");
        assert_eq!(high.minimum, 0, "no percentage below 0");
        assert_eq!(high.maximum, PERCENT as i32, "no percentage above 100");
        assert_eq!(high.counter, 1, "a zero counter is due on the next tick");
        let low = Monitor::restored(-4, 0, 0, false, 999);
        assert_eq!(low.level, 0);
        assert_eq!(low.counter, OBSERVE_TICKS, "no counter beyond one window");
        let swapped = Monitor::restored(3, 80, 20, false, 5);
        assert!(
            swapped.minimum <= swapped.maximum,
            "a reversed band is ordered, not left impossible"
        );
    }

    // --- the power level ---------------------------------------------------

    #[test]
    fn the_power_level_ratio_is_ten_steps_of_charge() {
        assert_eq!(PowerLevel::ratio(0, 500_000), 0, "an empty store is 0");
        assert_eq!(
            PowerLevel::ratio(250_000, 500_000),
            5,
            "half of 500,000 FE is 5 — the artefact's stored * 10 / max, not the brief's 4"
        );
        assert_eq!(PowerLevel::ratio(50_000, 500_000), 1, "a tenth is 1");
        assert_eq!(
            PowerLevel::ratio(500_000, 500_000),
            9,
            "a full store is 10 clamped to 9, never 10"
        );
        assert_eq!(
            PowerLevel::ratio(900_000, 500_000),
            9,
            "a doctored store above the capacity still clamps"
        );
        assert_eq!(
            PowerLevel::ratio(1, 3),
            3,
            "integer arithmetic, as upstream's (int) cast"
        );
        assert_eq!(
            PowerLevel::ratio(0, 0),
            0,
            "no capacity is no reading — upstream's maxEnergy > 0 guard"
        );
        assert_eq!(PowerLevel::ratio(5, 0), 0);
    }

    #[test]
    fn a_fresh_power_level_observes_at_twenty_ticks_then_every_ten() {
        let mut level = PowerLevel::new();
        assert_eq!(level.counter, FIRST_POWER_OBSERVE_TICKS);
        for tick in 1..FIRST_POWER_OBSERVE_TICKS {
            assert!(!level.tick(), "tick {tick} is not the first observation");
        }
        assert!(level.tick(), "the twentieth tick observes");
        assert_eq!(
            level.counter, POWER_OBSERVE_TICKS,
            "the counter resets to 10"
        );
        for tick in 1..POWER_OBSERVE_TICKS {
            assert!(!level.tick(), "tick {tick} of the second window");
        }
        assert!(level.tick(), "the tenth tick of the second window observes");
        assert_eq!(level.counter, POWER_OBSERVE_TICKS);
    }

    #[test]
    fn a_power_level_observation_only_says_changed_when_the_ratio_moved() {
        let mut level = PowerLevel::new();
        assert!(
            level.observe(Some((250_000, 500_000))),
            "0 -> 5 is a change"
        );
        assert_eq!(level.power, 5);
        assert!(
            !level.observe(Some((250_000, 500_000))),
            "the same store changes nothing"
        );
        assert!(
            level.observe(None),
            "a target that is not an energy block is a change"
        );
        assert_eq!(level.power, 0, "upstream's no-capability branch sets 0");
        assert!(!level.observe(None), "and staying invalid changes nothing");
        assert!(
            !level.observe(Some((0, 500_000))),
            "an empty store is still 0, not a change"
        );
        assert!(
            level.observe(Some((500_000, 500_000))),
            "0 -> 9 is a change"
        );
        assert_eq!(level.power, MAX_POWER_LEVEL);
    }

    #[test]
    fn a_doctored_power_level_is_clamped() {
        let low = PowerLevel::restored(-4, 0);
        assert_eq!(low.power, 0, "no ratio below 0");
        assert_eq!(low.counter, 1, "a zero counter is due on the next tick");
        let high = PowerLevel::restored(99, 999);
        assert_eq!(high.power, MAX_POWER_LEVEL, "no ratio above 9");
        assert_eq!(
            high.counter, FIRST_POWER_OBSERVE_TICKS,
            "no counter beyond one window"
        );
    }

    #[test]
    fn the_generator_offers_at_most_its_send_and_never_more_than_it_holds() {
        assert_eq!(send_amount(10_000, EXTRACT_PER_TICK), 2_000);
        assert_eq!(send_amount(500, EXTRACT_PER_TICK), 500);
        assert_eq!(send_amount(0, EXTRACT_PER_TICK), 0);
        assert_eq!(
            send_amount(-5, EXTRACT_PER_TICK),
            0,
            "a negative store is empty"
        );
    }

    // --- the powercell -----------------------------------------------------

    fn cell(tier: Tier, energy: i32) -> Cell {
        Cell { tier, energy }
    }

    #[test]
    fn a_fresh_cell_has_six_none_faces() {
        let fresh = Sides::fresh();
        for face in 0..6 {
            assert_eq!(fresh.get(face), SideMode::None, "face {face}");
        }
        assert!(!fresh.any_output(), "a fresh cell gives nothing out");
        assert_eq!(fresh.output_count(), 0);
        assert_eq!(fresh.to_saved(), "000000", "upstream's six digits");
        assert_eq!(fresh.names(), "none,none,none,none,none,none");
        assert_eq!(Sides::fresh().get(9), SideMode::None, "no tenth face");
    }

    #[test]
    fn a_side_mode_is_set_one_face_at_a_time_and_reads_back_from_the_saved_string() {
        let mut sides = Sides::fresh();
        assert!(sides.set(4, SideMode::Input), "west");
        assert!(sides.set(0, SideMode::Output), "down");
        assert_eq!(sides.get(4), SideMode::Input);
        assert_eq!(sides.get(0), SideMode::Output);
        assert_eq!(sides.get(5), SideMode::None, "east untouched");
        assert_eq!(
            sides.to_saved(),
            "100020",
            "one digit per face, Direction order"
        );
        assert_eq!(sides.names(), "output,none,none,none,input,none");
        assert_eq!(Sides::from_saved("100020"), sides);
        assert_eq!(sides.output_count(), 1);
        assert!(sides.any_output());
        assert!(!sides.set(6, SideMode::Input), "there is no seventh face");
        assert_eq!(
            sides.to_saved(),
            "100020",
            "an out-of-range face changes nothing"
        );
    }

    #[test]
    fn a_saved_mode_string_is_upstreams_and_a_broken_one_is_a_fresh_cell() {
        assert_eq!(Sides::from_saved(""), Sides::fresh());
        assert_eq!(
            Sides::from_saved("0021"),
            Sides::fresh(),
            "four digits is not six"
        );
        assert_eq!(
            Sides::from_saved("2222221"),
            Sides::fresh(),
            "seven digits is not six"
        );
        assert_eq!(
            Sides::from_saved("999999"),
            Sides::fresh(),
            "9 is not a SideType ordinal"
        );
        let mixed = Sides::from_saved("012012");
        assert_eq!(mixed.get(0), SideMode::None);
        assert_eq!(mixed.get(1), SideMode::Output);
        assert_eq!(mixed.get(2), SideMode::Input);
        assert_eq!(mixed.get(3), SideMode::None);
        assert_eq!(mixed.get(4), SideMode::Output);
        assert_eq!(mixed.get(5), SideMode::Input);
        assert_eq!(mixed.names(), "none,output,input,none,output,input");
    }

    #[test]
    fn the_wrench_cycles_none_input_output() {
        assert_eq!(SideMode::None.next(), SideMode::Input);
        assert_eq!(SideMode::Input.next(), SideMode::Output);
        assert_eq!(SideMode::Output.next(), SideMode::None);
        assert_eq!(SideMode::parse("NONE"), Some(SideMode::None));
        assert_eq!(SideMode::parse("input"), Some(SideMode::Input));
        assert_eq!(SideMode::parse("Output"), Some(SideMode::Output));
        assert_eq!(SideMode::parse("in"), None);
        assert_eq!(
            SideMode::parse("0"),
            None,
            "the saved digit is not a mode word"
        );
        assert_eq!(SideMode::None.name(), "none");
        assert_eq!(SideMode::Input.name(), "input");
        assert_eq!(SideMode::Output.name(), "output");
    }

    #[test]
    fn the_three_tiers_are_upstreams_config_numbers() {
        assert_eq!(Tier::of_block("rftoolspower:cell1"), Some(Tier::One));
        assert_eq!(Tier::of_block("rftoolspower:cell2"), Some(Tier::Two));
        assert_eq!(Tier::of_block("rftoolspower:cell3"), Some(Tier::Three));
        assert_eq!(Tier::of_block("rftoolspower:coalgenerator"), None);
        assert_eq!(Tier::of_block("minecraft:stone"), None);
        assert_eq!(Tier::of_block("rftoolspower:cell10"), None);
        assert_eq!(
            [Tier::One, Tier::Two, Tier::Three].map(Tier::capacity),
            [500_000, 4_000_000, 20_000_000],
            "tier1MaxRF / tier2MaxRF / tier3MaxRF"
        );
        assert_eq!(
            [Tier::One, Tier::Two, Tier::Three].map(Tier::per_side),
            [250, 1_000, 4_000],
            "tierNMaxRFPerTick"
        );
        assert_eq!(
            [Tier::One, Tier::Two, Tier::Three].map(Tier::suffix),
            [1, 2, 3]
        );
    }

    #[test]
    fn a_tier_one_cell_takes_two_hundred_and_fifty_of_a_two_thousand_push() {
        let mut network = [cell(Tier::One, 0)];
        assert_eq!(
            receive(&mut network, 2_000),
            250,
            "the per-side number caps the take, not the generator's 2,000"
        );
        assert_eq!(network[0].energy, 250);
        assert_eq!(
            receive(&mut network, 100),
            100,
            "a smaller request is taken whole"
        );
        assert_eq!(network[0].energy, 350);
        assert_eq!(receive(&mut network, 0), 0, "nothing asked, nothing taken");
    }

    #[test]
    fn the_network_budget_grows_a_quarter_of_the_per_side_number_per_extra_cell() {
        assert_eq!(rf_per_tick(Tier::One, 1), 250);
        assert_eq!(
            rf_per_tick(Tier::One, 2),
            312,
            "250 + 62.5, truncated as upstream's (long) cast"
        );
        assert_eq!(rf_per_tick(Tier::One, 9), 750, "250 + 8 * 62.5");
        assert_eq!(rf_per_tick(Tier::Two, 1), 1_000);
        assert_eq!(rf_per_tick(Tier::Two, 2), 1_250);
        assert_eq!(rf_per_tick(Tier::Three, 3), 6_000, "4,000 + 2 * 1,000");
        let mut pair = [cell(Tier::One, 0), cell(Tier::One, 0)];
        assert_eq!(receive(&mut pair, 2_000), 312, "the pair's own budget");
        let mut mixed = [cell(Tier::One, 0), cell(Tier::Two, 0)];
        assert_eq!(
            receive(&mut mixed, 2_000),
            312,
            "the asking cell's tier sets the budget, not the biggest cell's"
        );
    }

    #[test]
    fn a_full_cell_passes_the_rest_of_its_budget_to_the_network() {
        let mut network = [cell(Tier::One, 500_000), cell(Tier::One, 499_000)];
        assert_eq!(
            receive(&mut network, 2_000),
            312,
            "the asking cell is full, the neighbour has room"
        );
        assert_eq!(network[0].energy, 500_000);
        assert_eq!(network[1].energy, 499_312);
        let mut full = [cell(Tier::One, 500_000), cell(Tier::One, 500_000)];
        assert_eq!(receive(&mut full, 2_000), 0, "no room anywhere");
        let mut nearly = [cell(Tier::One, 500_000 - 40), cell(Tier::One, 500_000)];
        assert_eq!(
            receive(&mut nearly, 2_000),
            40,
            "room decides the take, not the budget"
        );
    }

    #[test]
    fn a_network_is_the_sum_of_its_cells_whatever_their_tier() {
        let network = [
            cell(Tier::One, 1_000),
            cell(Tier::One, 2_000),
            cell(Tier::Two, 4_000),
        ];
        assert_eq!(stored(&network), 7_000);
        assert_eq!(
            capacity(&network),
            5_000_000,
            "500,000 + 500,000 + 4,000,000 — tiers share one network"
        );
        assert_eq!(as_capability(stored(&network)), 7_000);
        assert_eq!(
            as_capability(u64::from(u32::MAX)),
            i32::MAX as u32,
            "upstream's Math.min(Integer.MAX_VALUE, …)"
        );
    }

    #[test]
    fn a_network_past_upstreams_limit_takes_nothing() {
        let mut big = vec![cell(Tier::One, 0); NETWORK_MAX + 1];
        assert!(!network_valid(big.len()));
        assert_eq!(receive(&mut big, 2_000), 0, "!isValid(): no insert at all");
        assert!(big.iter().all(|cell| cell.energy == 0));
        let mut limit = vec![cell(Tier::One, 0); NETWORK_MAX];
        assert!(network_valid(limit.len()));
        assert_eq!(
            receive(&mut limit, 2_000),
            2_000,
            "the request caps the take, not the network's 45,750 budget"
        );
        assert_eq!(receive(&mut [], 2_000), 0, "no cell, no take");
    }

    #[test]
    fn the_cell_asked_drains_first_and_then_the_network() {
        let mut network = [
            cell(Tier::One, 100),
            cell(Tier::One, 1_000),
            cell(Tier::One, 1_000),
        ];
        assert_eq!(take(&mut network, 450), 450);
        assert_eq!(network[0].energy, 0, "the asking cell is drained first");
        assert_eq!(network[1].energy, 650);
        assert_eq!(network[2].energy, 1_000);
        assert_eq!(
            take(&mut network, 10_000),
            1_650,
            "never more than it holds"
        );
        assert_eq!(stored(&network), 0);
        assert_eq!(take(&mut network, 10), 0, "an empty network gives nothing");
    }

    #[test]
    fn a_doctored_cell_energy_is_clamped_to_its_own_tier() {
        assert_eq!(clamped_energy(Tier::One, 999_999), 500_000);
        assert_eq!(clamped_energy(Tier::One, -5), 0);
        assert_eq!(
            clamped_energy(Tier::Two, 999_999),
            999_999,
            "a tier-2 cell holds more than a tier-1 one"
        );
        assert_eq!(clamped_energy(Tier::Three, 25_000_000), 20_000_000);
    }

    // --- the endergenic generator -------------------------------------------------------------

    #[test]
    fn the_hit_table_is_upstreams_own() {
        assert_eq!(RF_PER_HIT[0], 0, "an idle generator pays nothing");
        assert_eq!(RF_PER_HIT[1], 100);
        assert_eq!(RF_PER_HIT[10], 12_800, "the peak is the eleventh mode");
        assert_eq!(
            RF_PER_HIT[15], 100,
            "the window's last mode is the weakest again"
        );
        // The table times the powergen factor: a pearl at mode 1 is 200 FE, at mode 10 25,600.
        assert_eq!(Endergenic::gain(1, 0), 200);
        assert_eq!(Endergenic::gain(10, 0), 25_600);
        assert_eq!(Endergenic::gain(15, 0), 200);
        for outside in [IDLE, HOLDING, 16, 100] {
            assert_eq!(
                Endergenic::gain(outside, 0),
                0,
                "mode {outside} is outside the window"
            );
        }
    }

    #[test]
    fn a_pearl_that_arrives_inside_the_window_is_worth_its_table_slot() {
        let mut generator = Endergenic::new();
        generator.start_charging();
        generator.charge_step();
        generator.charge_step();
        generator.charge_step();
        generator.charge_step();
        assert_eq!(generator.charging, 5, "five ticks into the window");
        let gained = generator.receive(0);
        assert_eq!(gained, Some(1_600), "mode 5's 800 FE times two");
        assert_eq!(
            generator.energy, 1_600,
            "the store rose by the per-pearl amount"
        );
        assert_eq!(generator.gained, 1_600);
        assert_eq!(generator.arrived_at, 5);
        assert!(generator.holding(), "the generator now holds the pearl");
        assert_eq!(generator.dropped, 0);
    }

    #[test]
    fn the_age_bonus_caps_at_doubling() {
        assert_eq!(Endergenic::gain(10, 0), 25_600, "age 0: no bonus");
        assert_eq!(Endergenic::gain(10, 10), 38_400, "age 10: +50 %");
        assert_eq!(Endergenic::gain(10, 20), 51_200, "age 20: +100 %");
        assert_eq!(
            Endergenic::gain(10, 100),
            51_200,
            "the bonus stops at 200 %"
        );
        assert_eq!(
            Endergenic::gain(10, -5),
            25_600,
            "a doctored age is no bonus"
        );
    }

    #[test]
    fn a_pearl_arriving_at_idle_or_while_holding_pays_nothing_and_is_lost() {
        let mut idle = Endergenic::new();
        assert_eq!(idle.receive(0), None, "an idle generator loses the pearl");
        assert_eq!(idle.energy, 0, "and pays nothing — the differential");
        assert_eq!(idle.dropped, 1);
        assert_eq!(idle.last_loss, Some(Loss::WhileIdle));
        assert_eq!(idle.charging, IDLE);

        let mut holding = Endergenic::new();
        holding.start_charging();
        holding.receive(0);
        let energy = holding.energy;
        assert_eq!(holding.receive(0), None, "a held pearl means both are lost");
        assert_eq!(holding.energy, energy, "the second pearl pays nothing");
        assert_eq!(holding.dropped, 1);
        assert_eq!(holding.last_loss, Some(Loss::WhileHolding));
        assert_eq!(holding.charging, IDLE);
    }

    #[test]
    fn charging_runs_fifteen_modes_and_then_goes_idle() {
        let mut generator = Endergenic::new();
        generator.start_charging();
        assert_eq!(generator.charging, 1);
        for _ in 0..14 {
            generator.charge_step();
        }
        assert_eq!(
            generator.charging, MAX_CHARGE,
            "fifteen ticks in the window"
        );
        generator.charge_step();
        assert_eq!(
            generator.charging, IDLE,
            "past the window the generator is idle"
        );
        assert!(!generator.charging_window());
    }

    #[test]
    fn a_rising_edge_starts_charging_and_another_fires_the_held_pearl() {
        let mut generator = Endergenic::new();
        assert_eq!(generator.pulse(0), Pulse::None);
        assert_eq!(generator.pulse(15), Pulse::Start, "0 -> 15 starts a charge");
        generator.start_charging();
        assert_eq!(
            generator.pulse(15),
            Pulse::None,
            "a held signal is not an edge"
        );
        assert_eq!(generator.pulse(0), Pulse::None, "falling is not an edge");
        generator.charging = HOLDING;
        assert_eq!(generator.pulse(15), Pulse::Fire, "a new edge fires");
    }

    #[test]
    fn holding_costs_500_a_tick_and_an_empty_buffer_drops_the_pearl() {
        let mut generator = Endergenic::new();
        generator.energy = 1_200;
        generator.charging = HOLDING;
        assert!(generator.hold());
        assert_eq!(generator.energy, 700);
        assert_eq!(generator.spent, 500);
        assert!(generator.hold());
        assert_eq!(generator.energy, 200);
        assert!(!generator.hold(), "200 FE cannot pay the 500 a tick");
        assert_eq!(generator.energy, 200, "a failed hold spends nothing");
        assert_eq!(generator.spent, 1_000);
    }

    #[test]
    fn a_pearl_flies_for_the_links_distance_and_arrives_at_its_destination() {
        assert_eq!(Endergenic::distance_between([0, 0, 0], [1, 0, 0]), 1);
        assert_eq!(Endergenic::distance_between([0, 0, 0], [3, 0, 0]), 2);
        assert_eq!(Endergenic::distance_between([0, 0, 0], [9, 0, 0]), 4);
        assert_eq!(
            Endergenic::distance_between([0, 0, 0], [12, 0, 0]),
            5,
            "twelve blocks is the first distance upstream refuses"
        );

        let mut generator = Endergenic::new();
        generator.destination = Some([3, 0, 0]);
        generator.distance = 2;
        assert!(generator.fire(true));
        assert_eq!(generator.pearls.len(), 1);
        let mut arrivals = generator.tick_pearls();
        assert!(
            arrivals.is_empty(),
            "the first tick of a two-tick flight is in the air"
        );
        assert_eq!(generator.pearls.len(), 1);
        arrivals = generator.tick_pearls();
        assert_eq!(arrivals, vec![([3, 0, 0], 0)]);
        assert!(
            generator.pearls.is_empty(),
            "an arrived pearl leaves the list"
        );
        assert_eq!(generator.launched, 1);
    }

    #[test]
    fn a_loss_reason_survives_its_text() {
        for loss in [
            Loss::MissingDestination,
            Loss::WhileHolding,
            Loss::WhileIdle,
            Loss::NotEnoughEnergy,
            Loss::Chance,
        ] {
            assert_eq!(Loss::parse(loss.text()), Some(loss), "{}", loss.text());
        }
        assert_eq!(Loss::parse("none"), None);
        assert_eq!(Loss::parse("Pearl arrived"), None);
    }

    #[test]
    fn a_pearl_fired_with_no_destination_is_dropped() {
        let mut generator = Endergenic::new();
        generator.charging = HOLDING;
        assert!(!generator.fire(false));
        assert_eq!(generator.dropped, 1);
        assert_eq!(generator.last_loss, Some(Loss::MissingDestination));
        assert_eq!(generator.charging, IDLE);
        assert!(generator.pearls.is_empty(), "nothing is launched");
        assert_eq!(generator.launched, 0);
    }

    #[test]
    fn a_held_pearl_is_fired_aged_and_an_injected_one_at_age_zero() {
        let mut generator = Endergenic::new();
        generator.destination = Some([0, 0, 1]);
        generator.distance = 1;
        generator.age = 3;
        generator.charging = HOLDING;
        assert!(generator.fire(false));
        assert_eq!(
            generator.pearls[0].age, 4,
            "a held pearl is fired aged one more"
        );
        generator.age = 7;
        assert!(generator.fire(true));
        assert_eq!(
            generator.pearls[1].age, 0,
            "an injected pearl starts at age 0"
        );
    }

    #[test]
    fn the_loss_chance_is_six_in_a_thousand_and_reproducible() {
        assert_eq!(chance_roll(7), chance_roll(7), "the draw is deterministic");
        let lost = (0..100_000).filter(|seed| pearl_lost(*seed)).count();
        // 6 draws in 1000 (roll <= 5) is 0.6 %; a hash may drift a little over 100,000 seeds.
        assert!(
            (450..=750).contains(&lost),
            "the loss chance over 100,000 ticks was {lost}, expected about 600"
        );
    }

    #[test]
    fn the_buffer_clamps_at_five_million_and_the_send_keeps_two_thousand() {
        assert_eq!(clamp_endergenic(9_000_000), ENDERGENIC_CAPACITY);
        assert_eq!(clamp_endergenic(-1), 0);
        let mut generator = Endergenic::new();
        generator.energy = 2_000;
        assert_eq!(generator.send_amount(), 0, "the reserve is never sent");
        generator.energy = 2_001;
        assert_eq!(generator.send_amount(), 1);
        generator.energy = 100_000;
        assert_eq!(
            generator.send_amount(),
            SEND_PER_TICK as u32,
            "at most 20,000 a tick"
        );
    }

    #[test]
    fn a_doctored_generator_reads_back_clamped() {
        let state = Endergenic::restored(
            9_999_999,
            40,
            -3,
            Some([1, 2, 3]),
            9,
            true,
            vec![Pearl::new(0, [1, 2, 3], -4), Pearl::new(3, [1, 2, 3], 2)],
            -5,
            -5,
            -1,
            -1,
            99,
        );
        assert_eq!(state.energy, ENDERGENIC_CAPACITY, "the store is clamped");
        assert_eq!(state.charging, MAX_CHARGE, "40 is past the window");
        assert_eq!(state.age, 0);
        assert_eq!(
            state.distance, MAX_DISTANCE,
            "a doctored distance is clamped"
        );
        assert_eq!(
            state.pearls.len(),
            1,
            "a pearl with no flight left is dropped"
        );
        assert_eq!(state.pearls[0].age, 2);
        assert_eq!(state.gained, 0);
        assert_eq!(state.launched, 0);
        assert_eq!(state.dropped, 0);
        assert_eq!(state.arrived_at, MAX_CHARGE);
    }

    #[test]
    fn a_window_pearl_pays_and_the_store_can_then_hold_it() {
        // The whole mechanic in one place: pulse -> charge -> a pearl lands at mode 4 (400 x 2),
        // and the generator then pays 500 a tick to keep it.
        let mut generator = Endergenic::new();
        generator.destination = Some([0, 0, 1]);
        generator.distance = 1;
        assert_eq!(generator.pulse(15), Pulse::Start);
        generator.start_charging();
        for _ in 0..3 {
            generator.charge_step();
        }
        assert_eq!(generator.charging, 4);
        assert_eq!(generator.receive(0), Some(800));
        assert!(generator.hold());
        assert_eq!(generator.energy, 300, "800 gained, 500 spent holding");
        assert_eq!(
            generator.gained - generator.spent,
            i64::from(generator.energy)
        );
    }

    // --- the ender monitor ---------------------------------------------------

    #[test]
    fn a_fresh_ender_monitor_watches_the_lost_pearl() {
        let monitor = EnderMonitor::new();
        assert_eq!(
            monitor.mode,
            MonitorMode::LostPearl,
            "upstream's attachment default is MODE_LOSTPEARL"
        );
        assert!(!monitor.need_pulse);
        assert_eq!(monitor.pulses, 0);
        assert_eq!(monitor.last, None);
    }

    #[test]
    fn the_monitor_mode_parses_the_command_words_and_the_saved_names() {
        assert_eq!(
            MonitorMode::parse_command("lost"),
            Some(MonitorMode::LostPearl)
        );
        assert_eq!(
            MonitorMode::parse_command("fired"),
            Some(MonitorMode::PearlFired)
        );
        assert_eq!(
            MonitorMode::parse_command("arrived"),
            Some(MonitorMode::PearlArrived)
        );
        assert_eq!(
            MonitorMode::parse_command("Lost Pearl"),
            None,
            "upstream's GUI label is not a command word"
        );
        assert_eq!(MonitorMode::PearlArrived.command_name(), "arrived");
        assert_eq!(
            MonitorMode::parse_saved("MODE_PEARLARRIVED"),
            Some(MonitorMode::PearlArrived)
        );
        assert_eq!(
            MonitorMode::parse_saved("arrived"),
            None,
            "the saved name is the enum's, not the command's"
        );
    }

    #[test]
    fn a_notice_arms_only_the_mode_the_monitor_watches() {
        let mut monitor = EnderMonitor::new();
        assert!(
            !monitor.notice(MonitorMode::PearlArrived),
            "it watches lost pearls"
        );
        assert!(!monitor.need_pulse);
        assert_eq!(monitor.last, None);
        assert!(monitor.notice(MonitorMode::LostPearl));
        assert!(monitor.need_pulse);
        assert_eq!(monitor.last, Some(MonitorMode::LostPearl));
    }

    #[test]
    fn the_pulse_is_fifteen_for_exactly_one_tick() {
        let mut monitor = EnderMonitor::new();
        monitor.mode = MonitorMode::PearlArrived;
        assert_eq!(monitor.tick(), 0, "nothing has happened yet");
        assert!(monitor.notice(MonitorMode::PearlArrived));
        assert_eq!(monitor.tick(), MONITOR_SIGNAL);
        assert!(!monitor.need_pulse, "the tick spent it");
        assert_eq!(monitor.tick(), 0, "the next tick is silent");
        assert_eq!(monitor.tick(), 0);
        assert_eq!(monitor.pulses, 1);
    }

    #[test]
    fn two_notices_before_a_tick_make_one_pulse() {
        let mut monitor = EnderMonitor::new();
        monitor.mode = MonitorMode::LostPearl;
        assert!(monitor.notice(MonitorMode::LostPearl));
        assert!(monitor.notice(MonitorMode::LostPearl));
        assert_eq!(monitor.tick(), MONITOR_SIGNAL);
        assert_eq!(monitor.tick(), 0);
        assert_eq!(monitor.pulses, 1, "one owed pulse, one output");
    }

    #[test]
    fn a_monitor_watching_another_mode_never_pulses() {
        let mut monitor = EnderMonitor::new();
        for _ in 0..5 {
            assert!(!monitor.notice(MonitorMode::PearlFired));
            assert_eq!(monitor.tick(), 0);
        }
        assert_eq!(monitor.pulses, 0);
        assert_eq!(monitor.last, None);
    }

    #[test]
    fn a_doctored_monitor_reads_back_without_a_phantom_last_mode() {
        // The armed-but-not-yet-pulsed state keeps its `last`: the notice is written a tick before
        // the tick spends it, and dropping it there loses the event's name (the e2e caught this).
        let armed = EnderMonitor::restored(
            MonitorMode::PearlFired,
            true,
            0,
            Some(MonitorMode::PearlArrived),
        );
        assert_eq!(armed.mode, MonitorMode::PearlFired);
        assert!(armed.need_pulse);
        assert_eq!(armed.pulses, 0);
        assert_eq!(
            armed.last,
            Some(MonitorMode::PearlArrived),
            "an owed pulse still names its event"
        );
        // A saved "last" with neither a pulse given nor one owed describes nothing.
        let doctored = EnderMonitor::restored(
            MonitorMode::PearlFired,
            false,
            0,
            Some(MonitorMode::PearlArrived),
        );
        assert_eq!(doctored.last, None);
        let kept = EnderMonitor::restored(
            MonitorMode::PearlFired,
            false,
            3,
            Some(MonitorMode::PearlFired),
        );
        assert_eq!(kept.pulses, 3);
        assert_eq!(kept.last, Some(MonitorMode::PearlFired));
    }
}
