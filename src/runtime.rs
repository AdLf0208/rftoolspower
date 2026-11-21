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
}
