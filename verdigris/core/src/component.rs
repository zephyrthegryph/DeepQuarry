//! Components (`rust_architecture.md` §4.2, §5): the [`Component`] trait
//! `#[vg::component]` implements, its schema, field validation and typed
//! errors.
//!
//! A component is a plain struct of `config`, `input` and `state` fields.
//! The macro generates everything else, **with no `byondapi` in the domain
//! crate**:
//! - the `Domain` marker (`FooKind`) and command enum (`FooCommand`, with a
//!   generic `Adjust` variant for take reconciliation);
//! - [`Component`]: the numeric field table, `get_field`/`set_command`/
//!   `adjust_command` by [`FieldId`], and the conserved-quantity visitor;
//! - a [`Channels`](crate::channel::Channels) table (one channel per
//!   numeric field), so every component kind is watchable with no extra
//!   code (`crate::watch`).
//!
//! The FFI surface is generic: `vg-ffi` resolves `(entity, kind, field)`
//! through [`crate::world::World`] and calls these, and the DM generator
//! emits typed wrappers from the same declaration.

use std::fmt;

use crate::channel::Channels;
use crate::entity::EntityError;
use crate::owner::Domain;

/// Numeric domain ids (`rust_architecture.md` §5): the high byte of every
/// event header and the `domain` a DM handle check names. One table, so two
/// domains can never pick the same number.
pub mod domains {
    /// @dm-define VG_DOMAIN_GAS
    pub const GAS: u8 = 0;
    pub const POWER: u8 = 1;
    pub const HEAT: u8 = 2;
    pub const LIFE: u8 = 3;
    /// Components declared by core's own tests.
    pub const TEST_DOMAIN: u8 = 15;

    /// Every `(name, id)`, for [`super::domain_id`] and the generator.
    pub const ALL: [(&str, u8); 5] = [
        ("gas", GAS),
        ("power", POWER),
        ("heat", HEAT),
        ("life", LIFE),
        ("test_domain", TEST_DOMAIN),
    ];
}

/// The numeric id of domain `name` (a `#[vg::component(domain = ...)]`
/// ident). Evaluated at compile time by the generated code, so an unknown
/// domain is a compile error, not a runtime one.
///
/// # Panics
/// If `name` is not in [`domains::ALL`] (at compile time, in a const).
#[must_use]
pub const fn domain_id(name: &str) -> u8 {
    let mut i = 0;
    while i < domains::ALL.len() {
        if const_str_eq(domains::ALL[i].0, name) {
            return domains::ALL[i].1;
        }
        i += 1;
    }
    panic!("unknown domain: add it to vg_core::component::domains")
}

/// The name of domain `id`, if it is in [`domains::ALL`].
#[must_use]
pub fn domain_name(id: u8) -> Option<&'static str> {
    domains::ALL.iter().find(|(_, d)| *d == id).map(|(n, _)| *n)
}

const fn const_str_eq(a: &str, b: &str) -> bool {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    if a.len() != b.len() {
        return false;
    }
    let mut i = 0;
    while i < a.len() {
        if a[i] != b[i] {
            return false;
        }
        i += 1;
    }
    true
}

/// Who writes a component kind's rows (`rust_architecture.md` §4.2).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Ownership {
    /// Main-thread synchronous: DM reads and writes immediately, and laws
    /// over it run in the driver's main phase (tanks, lungs, power).
    Main,
    /// Stepped in frames on the pool: DM writes become commands and DM
    /// reads see its own writes through the overlay.
    Worker,
}

/// A field's index in its component's [`Component::FIELDS`] (declaration
/// order; computed readouts follow the stored fields).
pub type FieldId = u16;

/// A component kind, implemented by `#[vg::component]`.
pub trait Component: Clone + Default + PartialEq + fmt::Debug + Send + Sync + 'static {
    /// The `Domain` marker the stores, overlay and watches key on.
    type Kind: Channels + Domain<Value = Self>;
    /// `snake_case` struct name (`pump`, `gas_mix`): generated DM names.
    const NAME: &'static str;
    /// Domain name (`gas`).
    const DOMAIN: &'static str;
    /// Numeric domain id ([`domains`]).
    const DOMAIN_ID: u8;
    /// Kind number within the domain (a generated `VG_<DOMAIN>_<NAME>`).
    const KIND: u16;
    /// The DM type the component binds to.
    const DM_TYPE: &'static str;
    const OWNER: Ownership;
    /// Every field, stored and computed, by [`FieldId`].
    const FIELDS: &'static [FieldSchema];

    /// Field `field` (element `index` of an array field; `0` otherwise) as
    /// a number. `None` for an unknown field, an out-of-range index or a
    /// non-numeric field.
    fn get_field(&self, field: FieldId, index: usize) -> Option<f64>;

    /// The validated command DM's write of `value` to `field` becomes:
    /// `config` fields are range-checked (`on_invalid`), `input` fields pass
    /// through, `state` and computed fields are read-only. `index` selects
    /// an element of an array field (`None` writes every element).
    ///
    /// # Errors
    /// [`ComponentError::Field`] for a rejected value,
    /// [`ComponentError::ReadOnly`]/[`ComponentError::NoField`] otherwise.
    fn set_command(
        field: FieldId,
        index: Option<usize>,
        value: f64,
    ) -> Result<<Self::Kind as Domain>::Command, ComponentError>;

    /// The take-reconciliation command (§4.2): adds `delta` (negative:
    /// removes) to a `conserve`d field. It is applied to the owner's
    /// *current* value, so a removal DM computed against an older view
    /// corrects the worker instead of overwriting what it did since; a
    /// removal below zero clamps and reports the shortfall.
    ///
    /// # Errors
    /// [`ComponentError::NotConserved`] for a field without `conserve`.
    fn adjust_command(
        field: FieldId,
        index: usize,
        delta: f64,
    ) -> Result<<Self::Kind as Domain>::Command, ComponentError>;

    /// Visits `(quantity, amount)` for every `conserve`d field of this row
    /// (conservation auto-wiring, §4.9).
    fn conserved(&self, visit: &mut dyn FnMut(&'static str, f64));

    /// The field named `name`.
    #[must_use]
    fn field_id(name: &str) -> Option<FieldId> {
        Self::FIELDS
            .iter()
            .position(|f| f.name == name)
            .and_then(|i| FieldId::try_from(i).ok())
    }
}

/// Why a config value failed validation (`on_invalid`, §2). `min`/`max`
/// are `f64` regardless of the field's own type (`f32` or `f64`, see
/// [`RangedField`]): widening an `f32` bound loses nothing, and this is
/// an error message, not a stored quantity.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum FieldError {
    /// NaN or infinite: never acceptable, `clamp` or `reject` alike.
    NotFinite,
    /// Outside the declared range (`on_invalid = reject` only; `clamp`
    /// never produces this).
    OutOfRange { min: f64, max: f64 },
}

impl fmt::Display for FieldError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotFinite => write!(f, "value must be finite"),
            Self::OutOfRange { min, max } => write!(f, "value must be in {min}..={max}"),
        }
    }
}

impl std::error::Error for FieldError {}

/// A field type `clamp`/`reject_range` can validate: `f32` and `f64`
/// alike (`rust_bindings.md` §16 "units everywhere" moved several
/// domains' config fields onto `f64`; a component's generated validator
/// must work for either). Sealed: every field the `#[vg::component]`
/// macro accepts a `range` on is one of these two.
pub trait RangedField: Copy + PartialOrd {
    fn is_finite_value(self) -> bool;
    fn clamped(self, min: Self, max: Self) -> Self;
    fn widen(self) -> f64;
}

impl RangedField for f32 {
    fn is_finite_value(self) -> bool {
        self.is_finite()
    }
    fn clamped(self, min: Self, max: Self) -> Self {
        self.clamp(min, max)
    }
    fn widen(self) -> f64 {
        f64::from(self)
    }
}

impl RangedField for f64 {
    fn is_finite_value(self) -> bool {
        self.is_finite()
    }
    fn clamped(self, min: Self, max: Self) -> Self {
        self.clamp(min, max)
    }
    fn widen(self) -> f64 {
        self
    }
}

/// `on_invalid = clamp`: a non-finite value is refused; anything else is
/// clamped into range (so this never itself returns `OutOfRange`).
///
/// # Errors
/// [`FieldError::NotFinite`] if `v` is NaN or infinite.
pub fn clamp<T: RangedField>(v: T, min: T, max: T) -> Result<T, FieldError> {
    if !v.is_finite_value() {
        return Err(FieldError::NotFinite);
    }
    Ok(v.clamped(min, max))
}

/// `on_invalid = reject`: the value is used as-is or not at all.
///
/// # Errors
/// [`FieldError::NotFinite`] or [`FieldError::OutOfRange`].
pub fn reject_range<T: RangedField>(v: T, min: T, max: T) -> Result<T, FieldError> {
    if !v.is_finite_value() {
        return Err(FieldError::NotFinite);
    }
    if v < min || v > max {
        return Err(FieldError::OutOfRange {
            min: min.widen(),
            max: max.widen(),
        });
    }
    Ok(v)
}

/// A value with no declared range (a `bool`/enum config field, or a `reject`
/// field with only the finiteness check): passes anything.
///
/// # Errors
/// Never; kept for uniform call sites in generated code.
pub fn identity<T>(v: T) -> Result<T, FieldError> {
    Ok(v)
}

/// Everything a generated `get_*`/`set_*`/query/event bind can fail with,
/// typed as (component, field, handle, reason) so the FFI wrapper can build
/// a DM runtime naming the atom (§9).
#[derive(Clone, Debug, PartialEq)]
pub enum ComponentError {
    /// The `vg_entity` handle didn't resolve to this component.
    Entity(EntityError),
    /// A config value failed validation.
    Field {
        field: &'static str,
        reason: FieldError,
    },
    /// No field with that id (or an index past an array field's length).
    NoField { field: FieldId },
    /// A `state` or computed field: laws write it, DM does not.
    ReadOnly { field: &'static str },
    /// [`Component::adjust_command`] on a field that declares no
    /// `conserve` quantity.
    NotConserved { field: &'static str },
    /// The entity has no component of this kind.
    Missing { kind: &'static str },
}

impl fmt::Display for ComponentError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Entity(e) => write!(f, "{e}"),
            Self::Field { field, reason } => write!(f, "field `{field}`: {reason}"),
            Self::NoField { field } => write!(f, "no field {field}"),
            Self::ReadOnly { field } => write!(f, "field `{field}` is read-only (state)"),
            Self::NotConserved { field } => {
                write!(
                    f,
                    "field `{field}` is not conserved; only conserved fields take adjustments"
                )
            }
            Self::Missing { kind } => write!(f, "entity has no {kind} component"),
        }
    }
}

impl std::error::Error for ComponentError {}

impl From<EntityError> for ComponentError {
    fn from(e: EntityError) -> Self {
        Self::Entity(e)
    }
}

// --- Generated schema and query support (used by the `#[vg::component]`
// and `#[vg::query]` macros; see `verdigris/ffi/macros`). --------------------

/// A field's role (`rust_bindings.md` §1).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FieldRole {
    Config,
    State,
    Input,
    /// A read-only readout computed from the stored fields
    /// (`computed = [...]` on the component).
    Computed,
}

/// One field of a generated component schema.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FieldSchema {
    pub name: &'static str,
    pub role: FieldRole,
    pub unit: Option<&'static str>,
    /// Elements: 1 for a scalar, `N` for `[T; N]`.
    pub len: u16,
    /// Whether the value crosses as a number (`f32`/`f64`/integers/`bool`).
    pub numeric: bool,
    /// The conserved quantity this field counts toward (`conserve = "..."`):
    /// summed by the driver's conservation check, and the only kind of field
    /// [`Component::adjust_command`] accepts.
    pub conserve: Option<&'static str>,
}

/// A component's full schema, as `#[vg::component]` records it. Used by
/// `vg_describe()` and by tests that check every bound type's `init_*`
/// values against the declared ranges (§9).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Schema {
    pub domain: &'static str,
    pub kind: u16,
    pub dm_type: &'static str,
    pub fields: &'static [FieldSchema],
}

impl Schema {
    /// The schema of component `C`.
    #[must_use]
    pub fn of<C: Component>() -> Self {
        Self {
            domain: C::DOMAIN,
            kind: C::KIND,
            dm_type: C::DM_TYPE,
            fields: C::FIELDS,
        }
    }
}

/// Converts between a DM number and a stored field type. The generated
/// `get_field`/`set_command`/`Adjust` use it, so every numeric field type
/// crosses the same way: `bool` is non-zero, integers truncate.
pub trait FieldValue: Copy {
    fn from_f64(v: f64) -> Self;
    fn to_f64(self) -> f64;
}

macro_rules! field_value_num {
    ($($t:ty),*) => {$(
        impl FieldValue for $t {
            #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss, clippy::cast_lossless, clippy::cast_precision_loss)]
            fn from_f64(v: f64) -> Self {
                v as $t
            }
            #[allow(clippy::cast_lossless, clippy::cast_precision_loss)]
            fn to_f64(self) -> f64 {
                self as f64
            }
        }
    )*};
}

field_value_num!(f32, f64, u8, u16, u32, u64, i8, i16, i32, i64, usize);

impl FieldValue for bool {
    fn from_f64(v: f64) -> Self {
        v != 0.0
    }
    fn to_f64(self) -> f64 {
        if self { 1.0 } else { 0.0 }
    }
}

/// The generated `Adjust` command's apply: adds `delta` to a conserved
/// field, clamping at zero and returning the unmet part of a removal (the
/// [`crate::owner::Applied::shortfall`], `rust_core.md` §3.10).
#[must_use]
#[allow(clippy::cast_possible_truncation)]
pub fn adjust_value<T: FieldValue>(slot: &mut T, delta: f64) -> f32 {
    let next = slot.to_f64() + delta;
    if next < 0.0 {
        *slot = T::from_f64(0.0);
        (-next) as f32
    } else {
        *slot = T::from_f64(next);
        0.0
    }
}

/// Maps a declared unit string to the watch channel unit conditions on that
/// field are checked against (an unknown unit, e.g. `mol/s`, is
/// [`crate::channel::Unit::None`]).
#[must_use]
pub const fn channel_unit(unit: &str) -> crate::channel::Unit {
    use crate::channel::Unit;
    if const_str_eq(unit, "K") {
        Unit::Kelvin
    } else if const_str_eq(unit, "kPa") {
        Unit::Kpa
    } else if const_str_eq(unit, "mol") {
        Unit::Moles
    } else if const_str_eq(unit, "J") {
        Unit::Joules
    } else if const_str_eq(unit, "W") {
        Unit::Watts
    } else if const_str_eq(unit, "J/K") {
        Unit::JoulesPerKelvin
    } else if const_str_eq(unit, "L") {
        Unit::Litres
    } else if const_str_eq(unit, "ticks") {
        Unit::Ticks
    } else if const_str_eq(unit, "count") {
        Unit::Count
    } else {
        Unit::None
    }
}

/// A query field's value, typed loosely enough to cover every field type a
/// component declares today (`rust_bindings.md` §3, §6).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum QueryValue {
    F32(f32),
    F64(f64),
    Bool(bool),
}

impl From<f32> for QueryValue {
    fn from(v: f32) -> Self {
        Self::F32(v)
    }
}

impl From<f64> for QueryValue {
    fn from(v: f64) -> Self {
        Self::F64(v)
    }
}

impl From<bool> for QueryValue {
    fn from(v: bool) -> Self {
        Self::Bool(v)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clamp_never_rejects_a_finite_out_of_range_value() {
        assert_eq!(clamp(-5.0, 0.0, 10.0), Ok(0.0));
        assert_eq!(clamp(15.0, 0.0, 10.0), Ok(10.0));
        assert_eq!(clamp(5.0, 0.0, 10.0), Ok(5.0));
        assert_eq!(clamp(f32::NAN, 0.0, 10.0), Err(FieldError::NotFinite));
        assert_eq!(clamp(f32::INFINITY, 0.0, 10.0), Err(FieldError::NotFinite));
    }

    #[test]
    fn reject_range_refuses_out_of_range_and_non_finite() {
        assert_eq!(reject_range(5.0, 0.0, 10.0), Ok(5.0));
        assert_eq!(
            reject_range(15.0, 0.0, 10.0),
            Err(FieldError::OutOfRange {
                min: 0.0,
                max: 10.0
            })
        );
        assert_eq!(
            reject_range(f32::NAN, 0.0, 10.0),
            Err(FieldError::NotFinite)
        );
    }

    /// `f64` fields (`rust_bindings.md` §16 "units everywhere": several
    /// domains' config crosses the FFI boundary as `f64`, not `f32`) go
    /// through the exact same generic validators.
    #[test]
    fn clamp_and_reject_range_work_for_f64_fields_too() {
        let v: f64 = 15.0;
        assert_eq!(clamp(v, 0.0, 10.0), Ok(10.0));
        assert_eq!(clamp(f64::NAN, 0.0, 10.0), Err(FieldError::NotFinite));
        assert_eq!(
            reject_range(v, 0.0, 10.0),
            Err(FieldError::OutOfRange {
                min: 0.0,
                max: 10.0
            })
        );
        assert_eq!(reject_range(5.0f64, 0.0, 10.0), Ok(5.0));
    }
}
