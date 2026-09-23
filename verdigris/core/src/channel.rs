//! Channels: the typed, unit-tagged values a domain exposes to watches
//! (`rust_core.md` §6.1, §6.3).
//!
//! A domain declares its channels once with [`channels!`]. Each channel has
//! a value kind (scalar, vector or enum), a [`Unit`], a hysteresis and an
//! extractor that reads it out of one cell. The declaration is checked by
//! [`validate_channels`] when the domain's watches are registered with the
//! sim ([`SimBuilder::add_watches`](crate::sim::SimBuilder::add_watches)),
//! so a bad declaration fails the boot instead of surfacing in play.
//!
//! ```
//! use vg_core::channel::{Channels, Unit, ValueKind};
//! use vg_core::channels;
//! # use vg_core::owner::{Applied, Domain};
//! # #[derive(Clone, Default, PartialEq, Debug)] struct Cell { t: f32, moles: [f32; 2] }
//! # struct Gas;
//! # impl Domain for Gas { type Value = Cell; type Command = (); const NAME: &'static str = "gas";
//! #   fn apply(_: &mut Cell, _: &()) -> Applied { Applied::default() } }
//! channels! { pub mod gas_ch for Gas {
//!     TEMPERATURE: Scalar<Kelvin> hysteresis 0.5 => |c, out| out[0] = c.t,
//!     COMPOSITION: Vector(2)<Moles> hysteresis 0.01 => |c, out| out.copy_from_slice(&c.moles),
//! }}
//! assert_eq!(gas_ch::COMPOSITION.index(), 1);
//! assert_eq!(Gas::CHANNELS[0].unit, Unit::Kelvin);
//! assert_eq!(Gas::CHANNELS[1].kind, ValueKind::Vector(2));
//! ```

use std::fmt;

use crate::owner::Domain;

/// Channels per domain. Reason masks cross to DM as `f32` and must stay
/// exact (below 2^24), and bits 20-23 are the reason-class flags in
/// [`crate::outbox::reason`].
pub const MAX_CHANNELS: usize = 20;

/// Components per vector channel.
pub const MAX_WIDTH: usize = 32;

/// A channel of one domain, by declaration order.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct ChannelId(pub u8);

impl ChannelId {
    #[must_use]
    pub const fn index(self) -> usize {
        self.0 as usize
    }

    /// This channel's bit in a `Changed` mask and in wake reasons.
    #[must_use]
    pub const fn bit(self) -> u32 {
        1 << self.0
    }
}

/// Physical units, as numeric registry IDs DM constants carry
/// (`KPA(x)` is `(x, UNIT_KPA)`).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum Unit {
    /// Dimensionless: ratios, fractions, flags.
    None = 0,
    Kelvin = 1,
    Kpa = 2,
    Moles = 3,
    Joules = 4,
    Watts = 5,
    JoulesPerKelvin = 6,
    /// Litres (volumes).
    Litres = 7,
    /// Ticks (durations).
    Ticks = 8,
    /// A count of things.
    Count = 9,
}

impl Unit {
    pub const ALL: [Self; 10] = [
        Self::None,
        Self::Kelvin,
        Self::Kpa,
        Self::Moles,
        Self::Joules,
        Self::Watts,
        Self::JoulesPerKelvin,
        Self::Litres,
        Self::Ticks,
        Self::Count,
    ];

    /// The unit with numeric ID `id` (as DM sends it).
    #[must_use]
    pub fn from_id(id: u8) -> Option<Self> {
        Self::ALL.get(usize::from(id)).copied()
    }

    #[must_use]
    pub const fn id(self) -> u8 {
        self as u8
    }

    /// The DM constructor macro name (`KPA` for `KPA(x)`).
    #[must_use]
    pub const fn dm_name(self) -> &'static str {
        match self {
            Self::None => "UNITLESS",
            Self::Kelvin => "KELVIN",
            Self::Kpa => "KPA",
            Self::Moles => "MOLES",
            Self::Joules => "JOULES",
            Self::Watts => "WATTS",
            Self::JoulesPerKelvin => "JOULES_PER_KELVIN",
            Self::Litres => "LITRES",
            Self::Ticks => "TICKS",
            Self::Count => "COUNT",
        }
    }
}

/// A number with its unit, as a condition constant.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Quantity {
    pub value: f32,
    pub unit: Unit,
}

impl Quantity {
    #[must_use]
    pub const fn new(value: f32, unit: Unit) -> Self {
        Self { value, unit }
    }
}

/// What one channel holds.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ValueKind {
    /// One number.
    Scalar,
    /// A fixed number of components (a composition, per-gas moles).
    Vector(u8),
    /// One of `n` discrete states, extracted as `0.0..n as f32`.
    Enum(u8),
}

impl ValueKind {
    /// Components the extractor writes.
    #[must_use]
    pub const fn width(self) -> usize {
        match self {
            Self::Scalar | Self::Enum(_) => 1,
            Self::Vector(n) => n as usize,
        }
    }
}

/// One declared channel of a domain whose cells are `V`.
pub struct ChannelDecl<V> {
    pub name: &'static str,
    pub kind: ValueKind,
    pub unit: Unit,
    /// How far a value must move from its baseline before `Changed` fires,
    /// and the default hysteresis of conditions on this channel.
    pub hysteresis: f32,
    /// Writes the channel's [`width`](ValueKind::width) components.
    pub extract: fn(&V, &mut [f32]),
}

impl<V> ChannelDecl<V> {
    /// The type-erased description (no extractor).
    #[must_use]
    pub const fn info(&self) -> ChannelInfo {
        ChannelInfo {
            name: self.name,
            kind: self.kind,
            unit: self.unit,
            hysteresis: self.hysteresis,
        }
    }
}

impl<V> fmt::Debug for ChannelDecl<V> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.info().fmt(f)
    }
}

/// A channel's declaration without its extractor, for validation of
/// conditions of any domain.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ChannelInfo {
    pub name: &'static str,
    pub kind: ValueKind,
    pub unit: Unit,
    pub hysteresis: f32,
}

/// A domain's channel table. Implemented by [`channels!`].
pub trait Channels: Domain {
    const CHANNELS: &'static [ChannelDecl<Self::Value>];

    /// A scalar channel's value in `cell` (the first component otherwise).
    fn scalar(cell: &Self::Value, ch: ChannelId) -> f32 {
        let decl = &Self::CHANNELS[ch.index()];
        let mut buf = [0.0f32; MAX_WIDTH];
        (decl.extract)(cell, &mut buf[..decl.kind.width()]);
        buf[0]
    }
}

/// The erased channel table of a domain.
#[must_use]
pub fn channel_infos<D: Channels>() -> Vec<ChannelInfo> {
    D::CHANNELS.iter().map(ChannelDecl::info).collect()
}

/// Why a channel declaration is rejected.
#[derive(Clone, Debug, PartialEq)]
pub enum ChannelError {
    TooMany {
        domain: &'static str,
        count: usize,
    },
    Empty {
        domain: &'static str,
    },
    BadName {
        domain: &'static str,
        name: &'static str,
    },
    Duplicate {
        domain: &'static str,
        name: &'static str,
    },
    BadHysteresis {
        domain: &'static str,
        name: &'static str,
        hysteresis: f32,
    },
    BadWidth {
        domain: &'static str,
        name: &'static str,
    },
    /// An enum channel must have hysteresis 0 and a unit of `None`.
    BadEnum {
        domain: &'static str,
        name: &'static str,
    },
    /// The extractor returned a non-finite or out-of-range value for a
    /// default cell.
    BadExtract {
        domain: &'static str,
        name: &'static str,
        value: f32,
    },
}

impl fmt::Display for ChannelError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::TooMany { domain, count } => write!(
                f,
                "{domain}: {count} channels declared, at most {MAX_CHANNELS} allowed"
            ),
            Self::Empty { domain } => write!(f, "{domain}: watches need at least one channel"),
            Self::BadName { domain, name } => write!(
                f,
                "{domain}: channel name `{name}` must be UPPER_SNAKE_CASE"
            ),
            Self::Duplicate { domain, name } => {
                write!(f, "{domain}: channel `{name}` declared twice")
            }
            Self::BadHysteresis {
                domain,
                name,
                hysteresis,
            } => write!(
                f,
                "{domain}.{name}: hysteresis {hysteresis} must be finite and >= 0"
            ),
            Self::BadWidth { domain, name } => write!(
                f,
                "{domain}.{name}: vector and enum widths must be 1..={MAX_WIDTH}"
            ),
            Self::BadEnum { domain, name } => write!(
                f,
                "{domain}.{name}: enum channels take hysteresis 0 and unit None"
            ),
            Self::BadExtract {
                domain,
                name,
                value,
            } => write!(
                f,
                "{domain}.{name}: extractor gave {value} for a default cell"
            ),
        }
    }
}

impl std::error::Error for ChannelError {}

fn upper_snake(name: &str) -> bool {
    !name.is_empty()
        && name.starts_with(|c: char| c.is_ascii_uppercase())
        && name
            .chars()
            .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_')
}

/// Checks a domain's channel table. Every error is reported, not just the
/// first.
///
/// # Errors
/// The list of problems found.
pub fn validate_channels<D: Channels>() -> Result<(), Vec<ChannelError>> {
    let domain = D::NAME;
    let chans = D::CHANNELS;
    let mut errors = Vec::new();
    if chans.is_empty() {
        errors.push(ChannelError::Empty { domain });
    }
    if chans.len() > MAX_CHANNELS {
        errors.push(ChannelError::TooMany {
            domain,
            count: chans.len(),
        });
    }
    let default = D::Value::default();
    for (i, c) in chans.iter().enumerate() {
        let name = c.name;
        if !upper_snake(name) {
            errors.push(ChannelError::BadName { domain, name });
        }
        if chans[..i].iter().any(|o| o.name == name) {
            errors.push(ChannelError::Duplicate { domain, name });
        }
        if !c.hysteresis.is_finite() || c.hysteresis < 0.0 {
            errors.push(ChannelError::BadHysteresis {
                domain,
                name,
                hysteresis: c.hysteresis,
            });
        }
        let width_ok = match c.kind {
            ValueKind::Scalar => true,
            ValueKind::Vector(n) | ValueKind::Enum(n) => (1..=MAX_WIDTH).contains(&usize::from(n)),
        };
        if !width_ok {
            errors.push(ChannelError::BadWidth { domain, name });
            continue;
        }
        if matches!(c.kind, ValueKind::Enum(_)) && (c.hysteresis != 0.0 || c.unit != Unit::None) {
            errors.push(ChannelError::BadEnum { domain, name });
        }
        let mut buf = [0.0f32; MAX_WIDTH];
        (c.extract)(&default, &mut buf[..c.kind.width()]);
        for &value in &buf[..c.kind.width()] {
            let in_range = match c.kind {
                ValueKind::Enum(n) => value >= 0.0 && value < f32::from(n) && value.fract() == 0.0,
                _ => value.is_finite(),
            };
            if !in_range {
                errors.push(ChannelError::BadExtract {
                    domain,
                    name,
                    value,
                });
                break;
            }
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

/// DM defines for a domain's channels and for every unit (§6.1):
/// `#define CH_<DOMAIN>_<NAME> (1<<i)` masks and `KPA(x)`-style
/// constructors. The FFI crate's binding generator writes these into
/// `_bindings.dm`.
#[must_use]
pub fn dm_defines<D: Channels>() -> String {
    use std::fmt::Write;
    let domain = D::NAME.to_ascii_uppercase();
    let mut out = String::new();
    for (i, c) in D::CHANNELS.iter().enumerate() {
        let _ = writeln!(
            out,
            "#define CH_{domain}_{} {} // {:?} {:?}, hysteresis {}",
            c.name,
            1u32 << i,
            c.kind,
            c.unit,
            c.hysteresis
        );
    }
    out
}

/// DM unit constructors: `#define KPA(x) list(x, 2)`.
#[must_use]
pub fn dm_unit_defines() -> String {
    use std::fmt::Write;
    let mut out = String::new();
    for u in Unit::ALL {
        let _ = writeln!(out, "#define {}(x) list(x, {})", u.dm_name(), u.id());
    }
    out
}

/// Declares a domain's channels (§6.1): implements [`Channels`] for the
/// domain and generates a module of [`ChannelId`] constants.
///
/// Each line is `NAME: Kind<Unit> hysteresis h => extractor`, where `Kind`
/// is `Scalar`, `Vector(n)` or `Enum(n)`, `Unit` is a [`Unit`] variant, and
/// the extractor is a non-capturing `|cell, out: &mut [f32]|` closure.
#[macro_export]
macro_rules! channels {
    (
        $vis:vis mod $module:ident for $domain:ty {
            $( $name:ident : $kind:ident $( ( $n:literal ) )? < $unit:ident >
               hysteresis $h:literal => $extract:expr ),+ $(,)?
        }
    ) => {
        #[allow(non_upper_case_globals)]
        $vis mod $module {
            #[allow(non_camel_case_types, clippy::upper_case_acronyms, dead_code)]
            #[repr(u8)]
            enum Index { $( $name ),+ }
            $(
                pub const $name: $crate::channel::ChannelId =
                    $crate::channel::ChannelId(Index::$name as u8);
            )+
        }
        impl $crate::channel::Channels for $domain {
            const CHANNELS: &'static [$crate::channel::ChannelDecl<
                <$domain as $crate::owner::Domain>::Value,
            >] = &[
                $( $crate::channel::ChannelDecl {
                    name: stringify!($name),
                    kind: $crate::channels!(@kind $kind $( $n )?),
                    unit: $crate::channel::Unit::$unit,
                    hysteresis: $h,
                    extract: $extract,
                } ),+
            ];
        }
    };
    (@kind Scalar) => { $crate::channel::ValueKind::Scalar };
    (@kind Vector $n:literal) => { $crate::channel::ValueKind::Vector($n) };
    (@kind Enum $n:literal) => { $crate::channel::ValueKind::Enum($n) };
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::owner::Applied;

    #[derive(Clone, Default, PartialEq, Debug)]
    struct Cell {
        t: f32,
        mode: u8,
    }

    struct Good;
    impl Domain for Good {
        type Value = Cell;
        type Command = ();
        const NAME: &'static str = "good";
        fn apply(_: &mut Cell, (): &()) -> Applied {
            Applied::default()
        }
    }
    crate::channels! { mod good_ch for Good {
        TEMP: Scalar<Kelvin> hysteresis 0.5 => |c, o| o[0] = c.t,
        MODE: Enum(3)<None> hysteresis 0.0 => |c, o| o[0] = f32::from(c.mode),
    }}

    struct Bad;
    impl Domain for Bad {
        type Value = Cell;
        type Command = ();
        const NAME: &'static str = "bad";
        fn apply(_: &mut Cell, (): &()) -> Applied {
            Applied::default()
        }
    }
    impl Channels for Bad {
        const CHANNELS: &'static [ChannelDecl<Cell>] = &[
            ChannelDecl {
                name: "temp",
                kind: ValueKind::Scalar,
                unit: Unit::Kelvin,
                hysteresis: -1.0,
                extract: |c, o| o[0] = c.t,
            },
            ChannelDecl {
                name: "MODE",
                kind: ValueKind::Enum(2),
                unit: Unit::Kpa,
                hysteresis: 0.1,
                extract: |_, o| o[0] = f32::NAN,
            },
            ChannelDecl {
                name: "MODE",
                kind: ValueKind::Vector(0),
                unit: Unit::None,
                hysteresis: 0.0,
                extract: |_, _| {},
            },
        ];
    }

    #[test]
    fn a_good_declaration_passes_and_generates_defines() {
        assert_eq!(validate_channels::<Good>(), Ok(()));
        assert_eq!(good_ch::MODE, ChannelId(1));
        let defs = dm_defines::<Good>();
        assert!(defs.contains("#define CH_GOOD_TEMP 1"));
        assert!(defs.contains("#define CH_GOOD_MODE 2"));
        assert!(dm_unit_defines().contains("#define KPA(x) list(x, 2)"));
        assert_eq!(Good::scalar(&Cell { t: 4.0, mode: 0 }, good_ch::TEMP), 4.0);
    }

    #[test]
    fn every_problem_in_a_bad_declaration_is_reported() {
        let errors = validate_channels::<Bad>().unwrap_err();
        let has = |p: fn(&ChannelError) -> bool| errors.iter().any(p);
        assert!(has(|e| matches!(
            e,
            ChannelError::BadName { name: "temp", .. }
        )));
        assert!(has(|e| matches!(e, ChannelError::BadHysteresis { .. })));
        assert!(has(|e| matches!(e, ChannelError::BadEnum { .. })));
        assert!(has(|e| matches!(e, ChannelError::BadExtract { .. })));
        assert!(has(|e| matches!(
            e,
            ChannelError::Duplicate { name: "MODE", .. }
        )));
        assert!(has(|e| matches!(e, ChannelError::BadWidth { .. })));
        assert!(errors.iter().all(|e| !e.to_string().is_empty()));
    }
}
