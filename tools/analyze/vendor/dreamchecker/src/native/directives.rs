//! `set SpacemanDMM_*` directives, the tables DreamChecker keeps of them (`ProcDirective`), and the per-proc settings pass.
use dm::{DMError, Location, Severity};
use foldhash::{HashMap, HashMapExt};

use super::model::{Model, ProcId};

pub fn error<S: Into<String>>(location: Location, desc: S) -> DMError {
    DMError::new(location, desc).with_component(dm::Component::DreamChecker)
}

#[derive(Clone)]
pub struct ProcDirective {
    pub directive: HashMap<ProcId, (bool, Location)>,
    can_be_disabled: bool,
    pub set_at_definition: bool,
    can_be_global: bool,
    pub directive_string: &'static str,
}

impl ProcDirective {
    pub fn new(directive_string: &'static str, can_be_disabled: bool, set_at_definition: bool, can_be_global: bool) -> ProcDirective {
        ProcDirective { directive: HashMap::new(), directive_string, can_be_disabled, set_at_definition, can_be_global }
    }

    pub fn insert(&mut self, m: &Model, proc: ProcId, enable: bool, location: Location) -> Result<(), DMError> {
        if m.ty(proc.ty).is_root() && !self.can_be_global {
            return Err(error(location, format!("{} sets {}, which cannot be set on global procs", m.proc_display(proc), self.directive_string))
                .with_errortype("incompatible_directive"));
        }
        if !enable && !self.can_be_disabled {
            return Err(error(location, format!("{} sets {} false, but it cannot be disabled.", m.proc_display(proc), self.directive_string))
                .with_errortype("disabled_directive")
                .set_severity(Severity::Warning));
        }
        if let Some((_, original)) = self.directive.get(&proc) {
            return Err(error(location, format!("{} sets {} twice", m.proc_display(proc), self.directive_string))
                .with_note(*original, "first definition here")
                .with_errortype("sets_directive_twice")
                .set_severity(Severity::Warning));
        }
        self.directive.insert(proc, (enable, location));
        Ok(())
    }

    pub fn get(&self, proc: ProcId) -> Option<&(bool, Location)> {
        self.directive.get(&proc)
    }

    /// This proc's directive, or the nearest one up its `..()` chain.
    pub fn get_self_or_parent(&self, m: &Model, proc: ProcId) -> Option<(ProcId, bool, Location)> {
        let mut next = Some(proc);
        while let Some(current) = next {
            if let Some(&(truthy, location)) = self.get(current) {
                return Some((current, truthy, location));
            }
            next = m.parent_proc(current);
        }
        None
    }

    pub fn try_copy_from_parent(&mut self, m: &Model, proc: ProcId) {
        if !self.directive.contains_key(&proc) {
            if let Some(parent) = m.parent_proc(proc) {
                if let Some((_, true, location)) = self.get_self_or_parent(m, parent) {
                    let _ = self.insert(m, proc, true, location);
                }
            }
        }
    }
}

impl Directives {
    /// Every directive's location, through `f`.
    pub fn map_locations(&mut self, f: &mut dyn FnMut(&mut Location)) {
        for table in [
            &mut self.must_call_parent,
            &mut self.must_not_override,
            &mut self.private,
            &mut self.protected,
            &mut self.must_not_sleep,
            &mut self.sleep_exempt,
            &mut self.must_be_pure,
            &mut self.can_be_redefined,
        ] {
            for (_, l) in table.directive.values_mut() {
                f(l);
            }
        }
    }
}

/// The eight directive tables, by name.
#[derive(Clone)]
pub struct Directives {
    pub must_call_parent: ProcDirective,
    pub must_not_override: ProcDirective,
    pub private: ProcDirective,
    pub protected: ProcDirective,
    pub must_not_sleep: ProcDirective,
    pub sleep_exempt: ProcDirective,
    pub must_be_pure: ProcDirective,
    pub can_be_redefined: ProcDirective,
}

impl Default for Directives {
    fn default() -> Self {
        Directives {
            must_call_parent: ProcDirective::new("SpacemanDMM_should_call_parent", true, false, false),
            must_not_override: ProcDirective::new("SpacemanDMM_should_not_override", false, false, false),
            private: ProcDirective::new("SpacemanDMM_private_proc", false, true, false),
            protected: ProcDirective::new("SpacemanDMM_protected_proc", false, true, false),
            must_not_sleep: ProcDirective::new("SpacemanDMM_should_not_sleep", false, true, true),
            sleep_exempt: ProcDirective::new("SpacemanDMM_allowed_to_sleep", false, true, true),
            must_be_pure: ProcDirective::new("SpacemanDMM_should_be_pure", false, true, true),
            can_be_redefined: ProcDirective::new("SpacemanDMM_can_be_redefined", false, false, false),
        }
    }
}

impl Directives {
    pub fn by_name(&mut self, name: &str) -> Option<&mut ProcDirective> {
        Some(match name {
            "SpacemanDMM_should_not_override" => &mut self.must_not_override,
            "SpacemanDMM_should_call_parent" => &mut self.must_call_parent,
            "SpacemanDMM_private_proc" => &mut self.private,
            "SpacemanDMM_protected_proc" => &mut self.protected,
            "SpacemanDMM_should_not_sleep" => &mut self.must_not_sleep,
            "SpacemanDMM_allowed_to_sleep" => &mut self.sleep_exempt,
            "SpacemanDMM_should_be_pure" => &mut self.must_be_pure,
            "SpacemanDMM_can_be_redefined" => &mut self.can_be_redefined,
            _ => return None,
        })
    }
}

pub const KNOWN_SETTING_NAMES: &[&str] = &["name", "desc", "category", "hidden", "popup_menu", "instant", "invisibility", "src", "background", "waitfor"];

pub static VALID_FILTER_TYPES: &[(&str, &[&str])] = &[
    ("alpha", &["x", "y", "icon", "render_source", "flags"]),
    ("angular_blur", &["x", "y", "size"]),
    ("bloom", &["threshold", "size", "offset", "alpha"]),
    ("color", &["color", "space"]),
    ("displace", &["x", "y", "size", "icon", "render_source"]),
    ("drop_shadow", &["x", "y", "size", "offset", "color"]),
    ("blur", &["size"]),
    ("layer", &["x", "y", "icon", "render_source", "flags", "color", "transform", "blend_mode"]),
    ("motion_blur", &["x", "y"]),
    ("outline", &["size", "color", "flags"]),
    ("radial_blur", &["x", "y", "size"]),
    ("rays", &["x", "y", "size", "color", "offset", "density", "threshold", "factor", "flags"]),
    ("ripple", &["x", "y", "size", "repeat", "radius", "falloff", "flags"]),
    ("wave", &["x", "y", "size", "offset", "flags"]),
];

/// filter type => (flag field name, exclusive, can be 0, valid flag names)
pub static VALID_FILTER_FLAGS: &[(&str, (&str, bool, bool, &[&str]))] = &[
    ("alpha", ("flags", false, true, &["MASK_INVERSE", "MASK_SWAP"])),
    ("color", ("space", true, false, &["FILTER_COLOR_RGB", "FILTER_COLOR_HSV", "FILTER_COLOR_HSL", "FILTER_COLOR_HCY"])),
    ("layer", ("flags", true, true, &["FILTER_OVERLAY", "FILTER_UNDERLAY"])),
    ("rays", ("flags", false, true, &["FILTER_OVERLAY", "FILTER_UNDERLAY"])),
    ("outline", ("flags", false, true, &["OUTLINE_SHARP", "OUTLINE_SQUARE"])),
    ("ripple", ("flags", false, true, &["WAVE_BOUNDED"])),
    ("wave", ("flags", false, true, &["WAVE_SIDEWAYS", "WAVE_BOUNDED"])),
];

/// BYOND's values of the filter flag constants: an integer is a valid flag when it is one of the field's flags' values (or, for a
/// non-exclusive field, a combination of them), as the vendored checker accepts it.
pub static FILTER_FLAG_VALUES: &[(&str, i32)] = &[
    ("MASK_INVERSE", 1),
    ("MASK_SWAP", 2),
    ("FILTER_COLOR_RGB", 0),
    ("FILTER_COLOR_HSV", 1),
    ("FILTER_COLOR_HSL", 2),
    ("FILTER_COLOR_HCY", 3),
    ("FILTER_OVERLAY", 1),
    ("FILTER_UNDERLAY", 2),
    ("OUTLINE_SHARP", 1),
    ("OUTLINE_SQUARE", 2),
    ("WAVE_SIDEWAYS", 1),
    ("WAVE_BOUNDED", 2),
];

pub fn lookup<'a, T>(table: &'a [(&str, T)], key: &str) -> Option<&'a T> {
    table.iter().find(|(k, _)| *k == key).map(|(_, v)| v)
}
