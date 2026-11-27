//! The per-proc results the native checker can keep between runs, in a form that encodes: a diagnostic as data ([`Diag`]), a
//! proc's settings as the events they make ([`SettingsFacts`]). See [`super::Store`].
use dm::{DMError, Location, Severity};
use serde::{Deserialize, Serialize};

use super::type_expr::TypeExpr;

/// A diagnostic as data.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Diag {
    location: Location,
    severity: u8,
    checker: bool,
    description: String,
    errortype: Option<String>,
    notes: Vec<(Location, String)>,
}

/// The error types DreamChecker names (a decoded diagnostic's error type is one of these, so it stays `&'static`).
const ERRORTYPES: &[&str] = &[
    "ambiguous_in_lhs",
    "ambiguous_not_bitwise",
    "control_condition_static",
    "disabled_directive",
    "field_access_static_type",
    "final_var",
    "if_condition_determinate",
    "incompatible_directive",
    "invalid_lint_directive_value",
    "invalid_set_value",
    "loop_condition_determinate",
    "must_be_pure",
    "must_call_parent",
    "must_not_override",
    "must_not_sleep",
    "no_typehint_implicit_new",
    "override_missing_keyword_arg",
    "override_precedes_definition",
    "private_proc",
    "private_var",
    "proc_call_static_type",
    "proc_has_no_parent",
    "protected_proc",
    "protected_var",
    "redefined_proc",
    "set_has_no_effect",
    "sets_directive_twice",
    "unknown_linter_setting",
    "unreachable_code",
];

fn errortype(name: &str) -> &'static str {
    ERRORTYPES.iter().copied().find(|t| *t == name).unwrap_or_else(|| Box::leak(name.to_owned().into_boxed_str()))
}

impl Diag {
    /// Every location (the diagnostic's, then its notes'), in order, through `f` (a store keeps the ones inside a proc relative
    /// to it; see `SettingsFacts::map_locations`).
    pub fn map_locations(&mut self, f: &mut dyn FnMut(&mut Location)) {
        f(&mut self.location);
        for (l, _) in &mut self.notes {
            f(l);
        }
    }

    pub fn of(e: &DMError) -> Diag {
        Diag {
            location: e.location(),
            severity: e.severity() as u8,
            checker: e.component() == dm::Component::DreamChecker,
            description: e.description().to_owned(),
            errortype: e.errortype().map(str::to_owned),
            notes: e.notes().iter().map(|n| (n.location(), n.description().to_owned())).collect(),
        }
    }
    pub fn error(&self) -> DMError {
        let severity = match self.severity {
            2 => Severity::Warning,
            3 => Severity::Info,
            4 => Severity::Hint,
            _ => Severity::Error,
        };
        let mut e = DMError::new(self.location, self.description.clone()).set_severity(severity);
        if self.checker {
            e = e.with_component(dm::Component::DreamChecker);
        }
        if let Some(t) = &self.errortype {
            e = e.with_errortype(errortype(t));
        }
        for (l, d) in &self.notes {
            e.add_note(*l, d.clone());
        }
        e
    }
}

/// What one proc's settings do, in order: applied to the settings tables by [`super::apply_settings`], where a directive set twice
/// or where it is not allowed is reported.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct SettingsFacts {
    pub events: Vec<SettingEvent>,
}

impl SettingsFacts {
    /// Every location of every event, in order, through `f`.
    pub fn map_locations(&mut self, f: &mut dyn FnMut(&mut Location)) {
        for e in &mut self.events {
            match e {
                SettingEvent::Diag(d) => d.map_locations(f),
                SettingEvent::Final(l) => f(l),
                SettingEvent::ReturnType(_) => {}
                SettingEvent::Directive { location, .. } => f(location),
            }
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum SettingEvent {
    Diag(Diag),
    /// The proc is declared final: it may not be overridden (at the proc's place).
    Final(Location),
    ReturnType(TypeExpr),
    /// `set <directive> = <enable>`.
    Directive { name: String, enable: bool, location: Location },
}
