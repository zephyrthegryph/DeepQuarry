//! The `min compatibility vV B` header line: the oldest client a world admits.
//!
//! DreamMaker derives it from the features a program uses. Each feature carries a version (514, 515, 516) and a
//! build tag. Features are first combined per unit (one procedure): the unit's version is the greatest feature
//! version and its build the greatest build tag. A unit whose build reaches its own version is *version-tied*
//! (`a.pixel_z` alone is 514/514, `icon_w` 516/516, `load_resource(a, b)` 514/514). The line is then:
//!
//! * the greatest unit version;
//! * the build of the greatest tied unit's version, i.e. the printed version, when any unit is tied;
//! * otherwise the greatest build over the units.
//!
//! So `tan` and `a.pixel_z` in separate procedures print `v516 516`, while the same two features in one procedure
//! print `v516 514` (the unit is 516/514, not tied). Measured with DreamMaker 516.1687, see
//! `fixtures/native_compiler/header_compat/`. Other interactions between pairs of 500-511 features were seen
//! (`animate` with `color`) and are not modelled.
//!
//! Evidence: probes compiled with DreamMaker 516.1687 (`tools/dmb/fixtures/native_compiler/header_compat/`) and the
//! header of every captured fixture under `tools/dmb/fixtures`. The tables list only features that raise the line
//! above the engine baseline `v514 468`; absence from a table means "baseline". They cover opcodes whose presence
//! is unambiguous and built-in variables that DreamMaker prices by name. Two cases are deliberately not modelled
//! and documented in `native_compiler_issues.md`: class variable defaults other than the world settings the
//! driver already tracks, and method calls on built-in receivers (`list.RemoveAll`, `client.RenderIcon`).

use crate::SymbolId;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::OnceLock;

/// The engine baseline every native world starts from (`fixtures/native_template.bin`).
pub const BASE_VERSION: u16 = 514;
pub const BASE_BUILD: u16 = 468;

/// The features of one unit (a procedure). `seal` turns it into a value that merges across units.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct UnitCompat {
    version: u16,
    build: u16,
    /// Instructions left in which an `IsIn` still consumes the `range()`/`orange()` just produced.
    pending_in: u8,
}

impl UnitCompat {
    pub fn note(&mut self, version: u16, build: u16) {
        self.version = self.version.max(version);
        self.build = self.build.max(build);
    }

    /// The feature the opcode implies, if any.
    pub fn note_opcode(&mut self, opcode: u32) {
        self.note_instruction(opcode, None);
    }

    /// One instruction in code order. `first_word` is its first fixed operand word when it has one.
    ///
    /// Beyond the opcode table, two shapes are 515 (probes in `fixtures/native_compiler/header_compat/`):
    /// an iterator over `range()`, `orange()` or `block()` and `x in range(...)` / `/turf in orange(...)`.
    /// DreamMaker fuses the first into `IterLoad` kinds 13 to 19 (`view()` is kind 7 and free); this compiler emits
    /// `Range`/`ORange` followed directly by a generic `IterLoad`, which is the same source construct.
    pub fn note_instruction(&mut self, opcode: u32, first_word: Option<u32>) {
        if let Some((version, build)) = opcode_feature(opcode) {
            self.note(version, build);
        }
        match opcode {
            0x52 if matches!(first_word, Some(13..=19)) || self.pending_in == 3 => {
                self.pending_in = 0;
                self.note(515, BASE_BUILD)
            }
            0x59 | 0xad => self.pending_in = 3,
            0xa9 if self.pending_in > 0 => {
                self.pending_in = 0;
                self.note(515, BASE_BUILD);
            }
            _ => self.pending_in = self.pending_in.saturating_sub(1),
        }
    }

    /// A built-in variable read or written. `explicit` is true when the receiver is another object
    /// (`a.pixel_z`), false for the implicit form (`pixel_z` or `src.pixel_z` in an atom proc, or a type default).
    /// DreamMaker prices `src.pixel_z` as explicit (514/514) but the bytecode this compiler emits for it is
    /// identical to a bare `pixel_z`, so that spelling reads as implicit here (507).
    pub fn note_field(&mut self, name: SymbolId, explicit: bool) {
        if let Some(feature) = field_features().get(&name) {
            let (version, build) = if explicit {
                feature.explicit
            } else {
                feature.implicit
            };
            self.note(version, build);
        }
    }

    /// Close the unit. A unit that observed nothing is empty and changes no line.
    pub fn seal(self) -> HeaderCompat {
        if self.version == 0 {
            return HeaderCompat::default();
        }
        if self.build >= self.version {
            HeaderCompat {
                version: self.version,
                build: 0,
                tied: true,
            }
        } else {
            HeaderCompat {
                version: self.version,
                build: self.build,
                tied: false,
            }
        }
    }
}

/// Requirements merged over units. `Default` is "nothing observed"; merging never lowers a line.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct HeaderCompat {
    version: u16,
    /// Greatest build among units that are not version-tied.
    build: u16,
    tied: bool,
}

impl HeaderCompat {
    /// One stand-alone feature (a world setting the driver applies directly) as its own unit.
    pub fn note(&mut self, version: u16, build: u16) {
        let mut unit = UnitCompat::default();
        unit.note(version, build);
        self.union(unit.seal());
    }

    pub fn union(&mut self, other: Self) {
        self.version = self.version.max(other.version);
        self.build = self.build.max(other.build);
        self.tied |= other.tied;
    }

    pub fn is_empty(&self) -> bool {
        *self == Self::default()
    }

    /// The header line for this requirement merged with the engine baseline.
    pub fn line(&self) -> Vec<u8> {
        let mut merged = *self;
        merged.note(BASE_VERSION, BASE_BUILD);
        let build = if merged.tied {
            merged.version
        } else {
            merged.build
        };
        format!("min compatibility v{} {}\n", merged.version, build).into_bytes()
    }

    /// Parse an existing header line. A build at or above the version is the version-tied form.
    pub fn parse(line: &[u8]) -> Option<Self> {
        let text = std::str::from_utf8(line).ok()?;
        let tail = text.trim_end().strip_prefix("min compatibility v")?;
        let mut parts = tail.split_whitespace();
        let version: u16 = parts.next()?.parse().ok()?;
        let build: u16 = parts.next()?.parse().ok()?;
        if parts.next().is_some() {
            return None;
        }
        let mut value = Self::default();
        value.note(version, build);
        Some(value)
    }
}

/// Opcode-implied features (version, build tag). Sin/Cos/Tan at 0xC2/0xC3/0x144 are the pre-516 forms and are free.
fn opcode_feature(opcode: u32) -> Option<(u16, u16)> {
    Some(match opcode {
        // 516: alist, key/value loops, pixloc, vectors, trigonometry on vectors, sign/lerp, values_*, astype, load_ext.
        0x179 | 0x17a | 0x17b | 0x17c | 0x17e | 0x17f | 0x180 | 0x181 | 0x182 | 0x183 | 0x184
        | 0x185 | 0x186 | 0x187 | 0x188 | 0x189 | 0x18a | 0x18b | 0x18c => (516, BASE_BUILD),
        // 515: ceil/trunc/fract/isnan/isinf/trimtext/ftime/refcount/ispointer/get_steps_to/block coordinates,
        // json_encode flags.
        0x166 | 0x167 | 0x169 | 0x16a | 0x16b | 0x16c | 0x16d | 0x16e | 0x16f | 0x170 | 0x175
        | 0x178 => (515, BASE_BUILD),
        // animate()
        0x128 | 0x129 => (514, 500),
        // winexists()
        0x118 => (514, 507),
        // load_resource() with arguments: version-tied.
        0x165 => (514, 514),
        _ => return None,
    })
}

struct FieldFeature {
    explicit: (u16, u16),
    implicit: (u16, u16),
}

/// The built-in variable families that carry priced variables.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Family {
    /// `/atom`, `/atom/movable`, `/mob`, `/obj`, `/turf`, `/area`, `/image`, `/mutable_appearance`.
    Atom,
    Client,
    World,
}

/// (name, explicit-receiver feature, implicit/default feature). A build equal to the version is version-tied.
/// Measured per owner with `fixtures/native_compiler/header_compat/probe_vars.py`-style probes: read `a.NAME`,
/// write `a.NAME = 1`, and the type default `/obj/NAME = 1`, against DreamMaker 516.1687.
const ATOM: &[(&str, (u16, u16), (u16, u16))] = &[
    ("alpha", (514, 500), (514, 500)),
    ("appearance_flags", (514, 509), (514, 509)),
    ("blend_mode", (514, 501), (514, 501)),
    ("color", (514, 500), (514, 500)),
    ("filters", (514, 512), (514, 512)),
    ("icon_w", (516, 516), (516, 516)),
    ("icon_z", (516, 516), (516, 516)),
    ("maptext", (514, 494), (514, 494)),
    ("maptext_height", (514, 494), (514, 494)),
    ("maptext_width", (514, 494), (514, 494)),
    ("maptext_x", (514, 508), (514, 508)),
    ("maptext_y", (514, 508), (514, 508)),
    ("override", (514, 482), (514, 482)),
    ("particles", (514, 514), (514, 514)),
    ("pixel_w", (514, 511), (514, 511)),
    ("pixel_z", (514, 514), (514, 507)),
    ("pixloc", (516, 468), (516, 468)),
    ("plane", (514, 509), (514, 509)),
    ("render_source", (514, 513), (514, 513)),
    ("render_target", (514, 513), (514, 513)),
    ("transform", (514, 500), (514, 514)),
    ("vis_contents", (514, 512), (514, 512)),
    ("vis_flags", (514, 513), (514, 513)),
    ("vis_locs", (514, 512), (514, 512)),
];
const CLIENT: &[(&str, (u16, u16), (u16, u16))] = &[
    ("color", (514, 509), (514, 509)),
    ("control_freak", (514, 514), (514, 507)),
    ("fps", (514, 511), (514, 511)),
    ("pixel_w", (514, 511), (514, 511)),
    ("pixel_x", (514, 514), (514, 507)),
    ("pixel_y", (514, 514), (514, 507)),
    ("pixel_z", (514, 514), (514, 507)),
    ("tick_lag", (514, 511), (514, 511)),
    ("timezone", (514, 514), (514, 514)),
];
const WORLD: &[(&str, (u16, u16), (u16, u16))] = &[
    ("icon_size", (514, 514), (514, 507)),
    ("map_format", (514, 514), (514, 507)),
    ("process", (515, 468), (515, 468)),
];

fn family_table(family: Family) -> &'static [(&'static str, (u16, u16), (u16, u16))] {
    match family {
        Family::Atom => ATOM,
        Family::Client => CLIENT,
        Family::World => WORLD,
    }
}

/// Name-only lookup for bytecode, where the receiver type is not recorded. The atom table plus the world settings
/// that exist only on `/world`; names shared with a cheaper variable on another type (`fps`, `tick_lag`,
/// `pixel_x`, `timezone`, `byond_version`) are left out because the same spelling is free on the other owner.
fn field_features() -> &'static HashMap<SymbolId, FieldFeature> {
    static TABLE: OnceLock<HashMap<SymbolId, FieldFeature>> = OnceLock::new();
    TABLE.get_or_init(|| {
        // `transform` is also the name of ordinary datum variables, so only its type default is priced (`ATOM`).
        ATOM.iter()
            .filter(|&&(name, _, _)| name != "transform")
            .chain(WORLD.iter())
            .map(|&(name, explicit, implicit)| {
                (SymbolId::of(name), FieldFeature { explicit, implicit })
            })
            .collect()
    })
}

impl UnitCompat {
    /// An authored default for a built-in variable of `family` (`/obj/plane = 5`).
    pub fn note_default(&mut self, family: Family, name: SymbolId) {
        for &(spelling, _, implicit) in family_table(family) {
            if SymbolId::of(spelling) == name {
                self.note(implicit.0, implicit.1);
                return;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// One procedure's worth of features.
    fn line(build: impl FnOnce(&mut UnitCompat)) -> String {
        let mut unit = UnitCompat::default();
        build(&mut unit);
        String::from_utf8(unit.seal().line()).unwrap()
    }

    fn lines(units: Vec<Box<dyn FnOnce(&mut UnitCompat)>>) -> String {
        let mut compat = HeaderCompat::default();
        for unit in units {
            let mut one = UnitCompat::default();
            unit(&mut one);
            compat.union(one.seal());
        }
        String::from_utf8(compat.line()).unwrap()
    }

    #[test]
    fn nothing_observed_is_the_engine_baseline() {
        assert_eq!(line(|_| {}), "min compatibility v514 468\n");
    }

    #[test]
    fn version_tied_unit_prints_the_final_version_as_build() {
        // Measured with DreamMaker 516.1687: tan alone, pixel_z alone.
        assert_eq!(line(|c| c.note_opcode(0x184)), "min compatibility v516 468
");
        assert_eq!(
            line(|c| c.note_field(SymbolId::of("pixel_z"), true)),
            "min compatibility v514 514
"
        );
        // Both in separate procedures: the pixel_z procedure is tied, so the build follows the version.
        assert_eq!(
            lines(vec![
                Box::new(|c| c.note_opcode(0x184)),
                Box::new(|c| c.note_field(SymbolId::of("pixel_z"), true)),
            ]),
            "min compatibility v516 516
"
        );
        // Both in one procedure: that procedure is 516/514, not tied.
        assert_eq!(
            line(|c| {
                c.note_opcode(0x184);
                c.note_field(SymbolId::of("pixel_z"), true);
            }),
            "min compatibility v516 514
"
        );
        // trunc (515 468) and pixel_z in separate procedures is v515 515.
        assert_eq!(
            lines(vec![
                Box::new(|c| c.note_opcode(0x16a)),
                Box::new(|c| c.note_field(SymbolId::of("pixel_z"), true)),
            ]),
            "min compatibility v515 515
"
        );
    }

    #[test]
    fn untied_features_take_the_greatest_build() {
        assert_eq!(
            line(|c| {
                c.note_opcode(0x184);
                c.note_field(SymbolId::of("pixel_w"), true);
                c.note_field(SymbolId::of("alpha"), false);
            }),
            "min compatibility v516 511\n"
        );
        assert_eq!(line(|c| c.note_opcode(0x128)), "min compatibility v514 500\n");
    }

    #[test]
    fn receiver_form_changes_pixel_z_pricing() {
        // `a.pixel_z` is version-tied; `pixel_z` in an atom proc or a type default is build 507.
        assert_eq!(
            line(|c| c.note_field(SymbolId::of("pixel_z"), false)),
            "min compatibility v514 507\n"
        );
    }

    #[test]
    fn parse_round_trips_and_merges_without_lowering() {
        for text in [
            "min compatibility v514 468\n",
            "min compatibility v515 468\n",
            "min compatibility v516 516\n",
            "min compatibility v514 507\n",
        ] {
            let parsed = HeaderCompat::parse(text.as_bytes()).unwrap();
            assert_eq!(String::from_utf8(parsed.line()).unwrap(), text);
        }
        let mut merged = HeaderCompat::parse(b"min compatibility v516 516\n").unwrap();
        merged.union(HeaderCompat::parse(b"min compatibility v514 468\n").unwrap());
        assert_eq!(merged.line(), b"min compatibility v516 516\n");
        assert!(HeaderCompat::parse(b"world bin v516\n").is_none());
    }

    #[test]
    fn unrelated_names_and_opcodes_never_raise_the_line() {
        assert_eq!(
            line(|c| {
                c.note_field(SymbolId::of("pixel_x"), true);
                c.note_field(SymbolId::of("name"), false);
                c.note_opcode(0xc2); // pre-516 Sin
                c.note_opcode(0x30); // CallGlob
            }),
            "min compatibility v514 468\n"
        );
    }
}
