//! Field validation and typed errors for generated components
//! (`rust_bindings.md` §2, §5, §9). [`entity`](crate::entity) resolves
//! *which* component a DM handle names; this module is what a generated
//! `set_*` uses to validate the value it carries before it ever becomes a
//! command.

use std::fmt;

use crate::entity::EntityError;

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
    Field { field: &'static str, reason: FieldError },
}

impl fmt::Display for ComponentError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Entity(e) => write!(f, "{e}"),
            Self::Field { field, reason } => write!(f, "field `{field}`: {reason}"),
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
}

/// One field of a generated component schema.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FieldSchema {
    pub name: &'static str,
    pub role: FieldRole,
    pub unit: Option<&'static str>,
}

/// A component's full schema, as `#[vg::component]` records it. Used by
/// `vg_describe()` and by tests that check every bound type's `init_*`
/// values against the declared ranges (§9).
#[derive(Clone, Debug, PartialEq)]
pub struct Schema {
    pub domain: &'static str,
    pub kind: u16,
    pub dm_type: &'static str,
    pub fields: Vec<FieldSchema>,
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
            Err(FieldError::OutOfRange { min: 0.0, max: 10.0 })
        );
        assert_eq!(reject_range(f32::NAN, 0.0, 10.0), Err(FieldError::NotFinite));
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
            Err(FieldError::OutOfRange { min: 0.0, max: 10.0 })
        );
        assert_eq!(reject_range(5.0f64, 0.0, 10.0), Ok(5.0));
    }
}
