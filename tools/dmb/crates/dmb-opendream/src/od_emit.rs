//! Program table construction for an OpenDream compiled program.
//!
//! This deliberately starts with a version-matched Dream Maker native scaffold.
//! The scaffold supplies native interfaces and built-in procedures which the
//! OpenDream JSON represents differently. Callers must supply it explicitly.

use byond_dmb::dmb::{
    DmString, Dmb, GridRun, Instance, MapObject, MobType, Proc, ResourceRef, Variable,
};
use crate::opendream::{OpenDreamArgument, OpenDreamMapObject, OpenDreamProgram};
use byond_dmb::operands::Value;
use byond_dmb::rsc::{Entry, NamedResource};
use serde_json::Value as JsonValue;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fmt;
use std::path::{Path, PathBuf};

use byond_dmb::ids::NONE;
#[cfg(test)]
mod native_view_tests {
    #[test]
    fn invalid_native_view_shapes_remain_rejected() {
        for value in [
            serde_json::json!(-1.5),
            serde_json::json!(35.5),
            serde_json::json!("256x1"),
            serde_json::json!("1x256"),
            serde_json::json!("71x72"),
            serde_json::json!("101x50"),
            serde_json::json!("5X5"),
            serde_json::json!("5.5x5"),
            serde_json::json!("5x"),
            serde_json::Value::Null,
        ] {
            assert!(super::native_world_view(&value).is_err(), "{value}");
        }
    }
}
/// Native client setup visits descendants before their parents, preserving
/// sibling creation order. Only authored settings participate in this fold.
// Native decimal strtol parsing: signed prefixes, leading ASCII whitespace,
// negative dimensions clamped to zero, and trailing second-axis text allowed.
mod values;
use values::*;

#[derive(Debug)]
pub enum EmitError {
    Invalid(String),
    Unsupported(String),
    Io(std::io::Error),
}
impl fmt::Display for EmitError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Invalid(s) | Self::Unsupported(s) => write!(f, "{s}"),
            Self::Io(e) => e.fmt(f),
        }
    }
}
impl std::error::Error for EmitError {}
impl From<std::io::Error> for EmitError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value)
    }
}

#[derive(Clone, Debug)]
pub struct EmissionIds {
    pub strings: Vec<u32>,
    pub resources: Vec<u32>,
    pub classes: Vec<u32>,
    pub instances: Vec<u32>,
    pub globals: Vec<u32>,
    /// Intrinsic global.vars record, allocated after all variable reindexing.
    pub global_vars: Option<u32>,
    pub procs: Vec<u32>,
    /// Native dynamic-call name for each OpenDream procedure target.
    pub method_call_names: Vec<u32>,
    pub global_init_proc: Option<u32>,
    /// OpenDream Proc indices used only as argument `in` expressions.
    pub argument_source_procs: HashSet<usize>,
    /// Inline `new /path{field=value}` values, keyed by OD TypeID and the
    /// exact JSON string operand preceding PushType/CreateObject.
    pub modified_instances: HashMap<(usize, String), u32>,
}
pub struct Emission {
    pub dmb: Dmb,
    pub resources: Vec<Entry>,
    pub ids: EmissionIds,
}

type MapInstanceSignature = (u8, u32, Vec<(String, String)>);

fn read_u32_le(bytes: &[u8], at: usize) -> Option<u32> {
    Some(u32::from_le_bytes(
        bytes.get(at..at.checked_add(4)?)?.try_into().ok()?,
    ))
}

struct Builder<'a> {
    input: &'a OpenDreamProgram,
    dmb: Dmb,
    archive: Vec<Entry>,
    ids: EmissionIds,
    strings: HashMap<Vec<u8>, u32>,
    procedure_variables: HashMap<Vec<u8>, u32>,
    shared_variables: HashMap<(u8, u32, Vec<u8>), u32>,
    instance_index: HashMap<(u8, u32, u32), u32>,
    map_instance_index: HashMap<MapInstanceSignature, u32>,
    map_initializer_index: HashMap<Vec<u32>, u32>,
    paths: HashMap<String, u32>,
    resource_root: PathBuf,
    resource_mode: ResourceMode,
    baseline: Option<&'a OpenDreamProgram>,
    baseline_type_by_path: HashMap<&'a str, usize>,
    native: NativeBoundaries,
    authored: AuthoredBoundaries,
    new_fields: Vec<u32>,
    new_globals: Vec<u32>,
    new_args: Vec<u32>,
    predicted_variable_ids: Vec<u32>,
    pending_proc_vars: Vec<(u32, usize)>,
    pending_proc_lists: Vec<(u32, usize, usize)>,
    pending_class_markers: Vec<(u32, usize)>,
}

#[derive(Clone, Copy)]
struct NativeBoundaries {
    variables: usize,
    globals: usize,
    classes: usize,
    instances: usize,
    procs: usize,
}

#[derive(Clone, Copy)]
struct AuthoredBoundaries {
    prototypes: usize,
    procs: usize,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum ResourceMode {
    Placeholder,
    HashOnly,
    Materialize,
}

/// Build a DMB and RSC table from OpenDream's compiled JSON. The supplied
/// scaffold must be a *native-only* Dream Maker v516 DMB; it is never inferred
/// from a compiled game or silently loaded from the developer's machine.
pub fn emit(
    input: &OpenDreamProgram,
    native_template: &Dmb,
    resource_root: &Path,
) -> Result<Emission, EmitError> {
    emit_with_baseline(input, None, native_template, resource_root)
}

/// Passing the same-version OpenDream native baseline distinguishes authored
/// changes to built-in types from OpenDream's own built-in defaults.
pub fn emit_with_baseline(
    input: &OpenDreamProgram,
    baseline: Option<&OpenDreamProgram>,
    native_template: &Dmb,
    resource_root: &Path,
) -> Result<Emission, EmitError> {
    emit_with_baseline_named(input, baseline, native_template, resource_root, None)
}

/// `project_name` supplies Dream Maker's default world name, normally the
/// DME file stem. An authored `/world.name` still takes precedence.
pub fn emit_with_baseline_named(
    input: &OpenDreamProgram,
    baseline: Option<&OpenDreamProgram>,
    native_template: &Dmb,
    resource_root: &Path,
    project_name: Option<&str>,
) -> Result<Emission, EmitError> {
    emit_with_baseline_named_mode(
        input,
        baseline,
        native_template,
        resource_root,
        project_name,
        ResourceMode::Materialize,
    )
}

/// Inspect program tables without reading asset bytes. Resource IDs in the
/// returned DMB are placeholders, and `resources` is empty: this result must
/// never be written as a runnable DMB/RSC pair.
pub fn emit_diagnostic_with_baseline_named(
    input: &OpenDreamProgram,
    baseline: Option<&OpenDreamProgram>,
    native_template: &Dmb,
    resource_root: &Path,
    project_name: Option<&str>,
) -> Result<Emission, EmitError> {
    emit_with_baseline_named_mode(
        input,
        baseline,
        native_template,
        resource_root,
        project_name,
        ResourceMode::Placeholder,
    )
}

/// Hash asset bytes and deduplicate resource references for a table audit,
/// without retaining an RSC archive. The returned pair cannot be written.
pub fn emit_diagnostic_hashed_with_baseline_named(
    input: &OpenDreamProgram,
    baseline: Option<&OpenDreamProgram>,
    native_template: &Dmb,
    resource_root: &Path,
    project_name: Option<&str>,
) -> Result<Emission, EmitError> {
    emit_with_baseline_named_mode(
        input,
        baseline,
        native_template,
        resource_root,
        project_name,
        ResourceMode::HashOnly,
    )
}

fn emit_with_baseline_named_mode(
    input: &OpenDreamProgram,
    baseline: Option<&OpenDreamProgram>,
    native_template: &Dmb,
    resource_root: &Path,
    project_name: Option<&str>,
    resource_mode: ResourceMode,
) -> Result<Emission, EmitError> {
    let timing = std::env::var_os("DMB_DIAG_TIMING").is_some();
    let mut phase_start = std::time::Instant::now();
    macro_rules! mark_phase {
        ($name:literal) => {
            if timing {
                eprintln!("dmb-emitter {}: {:?}", $name, phase_start.elapsed());
                phase_start = std::time::Instant::now();
            }
        };
    }
    let mut baseline_type_by_path = HashMap::new();
    if let Some(base) = baseline {
        for (index, typ) in base.types.iter().enumerate() {
            baseline_type_by_path
                .entry(typ.path.as_str())
                .or_insert(index);
        }
    }
    for value in &input.strings {
        let mut characters = value.chars().peekable();
        while let Some(ch) = characters.next() {
            if ch == '\u{ff5e}'
                && characters
                    .peek()
                    .is_some_and(|next| ('\u{ff00}'..='\u{ff5e}').contains(next))
            {
                characters.next();
                continue;
            }
            if (0xff00..=0xff1f).contains(&(ch as u32)) && native_format_marker(ch).is_none() {
                return Err(EmitError::Unsupported(format!(
                    "OpenDream string format marker U+{:04X} has no paired DMB encoding",
                    ch as u32
                )));
            }
        }
    }
    if baseline.is_none()
        && (!input.procs.is_empty()
            || !input.global_procs.is_empty()
            || input.globals.is_some()
            || input.global_init_proc.is_some()
            || input.types.iter().any(|typ| {
                matches!(
                    typ.path.as_str(),
                    "/datum"
                        | "/atom"
                        | "/atom/movable"
                        | "/obj"
                        | "/mob"
                        | "/turf"
                        | "/area"
                        | "/client"
                        | "/list"
                        | "/image"
                        | "/sound"
                        | "/icon"
                        | "/matrix"
                        | "/regex"
                        | "/savefile"
                        | "/database"
                        | "/database/query"
                        | "/exception"
                        | "/generator"
                        | "/mutable_appearance"
                ) && (!typ.variables.is_empty() || !typ.global_variables.is_empty())
            }))
    {
        return Err(EmitError::Unsupported(
            "OpenDream baseline is required to separate native definitions from authored code"
                .into(),
        ));
    }
    if let Some(base) = baseline {
        if input.metadata.version != base.metadata.version {
            return Err(EmitError::Unsupported(
                "OpenDream compiler metadata version differs from baseline".into(),
            ));
        }
        let input_world = input.types.iter().find(|typ| typ.path == "/world");
        let baseline_world = base.types.iter().find(|typ| typ.path == "/world");
        for field in ["byond_version", "byond_build"] {
            if input_world.and_then(|typ| typ.variables.get(field))
                != baseline_world.and_then(|typ| typ.variables.get(field))
            {
                return Err(EmitError::Unsupported(format!(
                    "OpenDream target {field} differs from baseline; recompile both for the same BYOND version"
                )));
            }
        }
        if input.optional_errors != base.optional_errors {
            return Err(EmitError::Unsupported(
                "OpenDream optional error table differs from baseline".into(),
            ));
        }
        for typ in &input.types {
            if let Some(original) = baseline_type_by_path
                .get(typ.path.as_str())
                .and_then(|&index| base.types.get(index))
            {
                let parent_path = typ
                    .parent
                    .and_then(|id| input.types.get(id))
                    .map(|parent| &parent.path);
                let original_parent_path = original
                    .parent
                    .and_then(|id| base.types.get(id))
                    .map(|parent| &parent.path);
                if parent_path != original_parent_path
                    && !(typ.path == "/client"
                        && parent_path.is_some_and(|path| path == "/datum")
                        && original_parent_path.is_some_and(|path| path == "/"))
                {
                    return Err(EmitError::Unsupported(format!(
                        "type {} changes its native parent",
                        typ.path
                    )));
                }
                // Game code may add declarations to a native class. Preserve
                // the scaffold's existing declarations and their flags, while
                // allowing new names to be emitted with their authored flags.
                // Removing or reclassifying a native declaration would make
                // the scaffold's slots disagree with OpenDream's metadata.
                if !original.const_variables.is_subset(&typ.const_variables)
                    || !original.tmp_variables.is_subset(&typ.tmp_variables)
                    || original.const_variables.iter().any(|name| {
                        typ.tmp_variables.contains(name) != original.tmp_variables.contains(name)
                    })
                    || original.tmp_variables.iter().any(|name| {
                        typ.const_variables.contains(name)
                            != original.const_variables.contains(name)
                    })
                {
                    return Err(EmitError::Unsupported(format!(
                        "type {} removes or reclassifies native const/tmp declarations",
                        typ.path
                    )));
                }
            }
        }
    } else if !input.optional_errors.is_empty() {
        return Err(EmitError::Unsupported(
            "OpenDream optional error table has no baseline comparison".into(),
        ));
    }
    if let Some(proc) = &input.global_init_proc {
        if proc.bytecode.is_none() {
            return Err(EmitError::Unsupported(
                "OpenDream global initializer has no bytecode".into(),
            ));
        }
        if proc.name != "<init>"
            || input
                .types
                .get(proc.owning_type_id)
                .is_none_or(|owner| owner.path != "/")
            || proc.attributes != 0
            || proc.max_variable_id != 0
            || !proc.arguments.is_empty()
            || !proc.locals.is_empty()
            || proc.is_verb
            || proc.verb_src.is_some()
            || proc.verb_range.is_some()
            || proc.verb_name.is_some()
            || proc.verb_category.is_some()
            || proc.verb_desc.is_some()
            || proc.invisibility != 0
            || proc.explicit_invisibility
        {
            return Err(EmitError::Unsupported(
                "OpenDream global initializer has unsupported procedure metadata".into(),
            ));
        }
    }
    for (id, proc_id) in input.global_procs.iter().copied().enumerate() {
        if input.procs.get(proc_id).is_none_or(|proc| {
            input
                .types
                .get(proc.owning_type_id)
                .is_none_or(|typ| typ.path != "/")
        }) {
            return Err(EmitError::Invalid(format!(
                "global procedure table entry {id} is invalid"
            )));
        }
    }
    for proc in &input.procs {
        if proc
            .source_info
            .iter()
            .any(|info| info.file.is_some_and(|id| id >= input.strings.len()))
        {
            return Err(EmitError::Invalid(format!(
                "procedure {} has source file ID outside Strings",
                proc.name
            )));
        }
    }
    for (type_id, typ) in input.types.iter().enumerate() {
        if !typ.explicit_world_fields.is_empty()
            && (typ.path != "/world"
                || typ
                    .explicit_world_fields
                    .iter()
                    .any(|name| !typ.variables.contains_key(name)))
        {
            return Err(EmitError::Invalid(format!(
                "type {} has invalid ExplicitWorldFields annotation",
                typ.path
            )));
        }
        for (name, &old) in &typ.global_variables {
            if input
                .globals
                .as_ref()
                .is_none_or(|globals| globals.names.get(old) != Some(name))
            {
                return Err(EmitError::Invalid(format!(
                    "type {} has invalid global variable {name}",
                    typ.path
                )));
            }
        }
        if let Some(proc_id) = typ.init_proc {
            if input
                .procs
                .get(proc_id)
                .is_none_or(|proc| proc.owning_type_id != type_id || proc.name != "<init>")
            {
                return Err(EmitError::Invalid(format!(
                    "type {} has invalid initializer",
                    typ.path
                )));
            }
        }
    }
    if native_template.header.version_line != b"world bin v516\n" {
        return Err(EmitError::Invalid("native scaffold is not DMB v516".into()));
    }
    if native_template.dimensions != [0, 0, 0]
        || !native_template.map_objects.is_empty()
        || !native_template.resources.is_empty()
    {
        return Err(EmitError::Invalid(
            "native scaffold contains game map or resources".into(),
        ));
    }
    mark_phase!("preflight");
    let mut builder = Builder {
        input,
        dmb: native_template.clone(),
        archive: Vec::new(),
        ids: EmissionIds {
            strings: Vec::new(),
            resources: Vec::new(),
            classes: Vec::new(),
            instances: Vec::new(),
            globals: Vec::new(),
            global_vars: None,
            procs: Vec::new(),
            method_call_names: Vec::new(),
            global_init_proc: None,
            argument_source_procs: HashSet::new(),
            modified_instances: HashMap::new(),
        },
        strings: HashMap::new(),
        procedure_variables: HashMap::new(),
        shared_variables: HashMap::new(),
        instance_index: HashMap::new(),
        map_instance_index: HashMap::new(),
        map_initializer_index: HashMap::new(),
        paths: HashMap::new(),
        resource_root: resource_root.to_owned(),
        resource_mode,
        baseline,
        baseline_type_by_path,
        native: NativeBoundaries {
            variables: native_template.variables.len(),
            globals: native_template.lists[native_template.variable_footer as usize].len() / 2,
            classes: native_template.classes.len(),
            instances: native_template.instances.len(),
            procs: native_template.procs.len(),
        },
        authored: AuthoredBoundaries {
            prototypes: native_template.instances.len(),
            procs: native_template.procs.len(),
        },
        new_fields: Vec::new(),
        new_globals: Vec::new(),
        new_args: Vec::new(),
        predicted_variable_ids: Vec::new(),
        pending_proc_vars: Vec::new(),
        pending_proc_lists: Vec::new(),
        pending_class_markers: Vec::new(),
    };
    builder.index_scaffold();
    for value in &input.strings {
        let id = builder.string(value);
        builder.ids.strings.push(id);
    }
    mark_phase!("strings");
    builder.build_resources()?;
    mark_phase!("resources");
    builder.build_classes()?;
    mark_phase!("classes");
    builder.build_instances()?;
    mark_phase!("instances");
    builder.authored.prototypes = builder.dmb.instances.len();
    builder.build_world(project_name)?;
    mark_phase!("world");
    builder.build_procs()?;
    mark_phase!("procs");
    builder.resolve_pending_proc_constants()?;
    builder.authored.procs = builder.dmb.procs.len();
    builder.build_globals()?;
    mark_phase!("globals");
    builder.mark_initializer_variables()?;
    builder.mark_class_dynamic_initials()?;
    builder.resolve_mob_type_constants()?;
    builder.preview_variable_ids()?;
    builder.resolve_modified_type_constants()?;
    builder.build_maps()?;
    mark_phase!("maps");
    builder.reindex_procs()?;
    builder.reindex_instances()?;
    builder.reindex_classes()?;
    builder.reindex_variables()?;
    builder.assign_class_initializer_markers()?;
    builder.intern_initializer_identities()?;
    for index in 0..input.procs.len() {
        let proc_id = builder.ids.procs[index];
        let name_id = if proc_id != NONE && builder.dmb.procs[proc_id as usize].strings[1] != NONE {
            builder.dmb.procs[proc_id as usize].strings[1]
        } else {
            let metadata = builder.resolved_verb_metadata(index);
            let name = metadata
                .name
                .unwrap_or_else(|| input.procs[index].name.replace('_', " "));
            builder.string(&name)
        };
        builder.ids.method_call_names.push(name_id);
    }
    // A conservative byte hint avoids a second OD instruction decoder. The
    // translation endpoint removes this proxy if no actual instruction used it.
    if input
        .procs
        .iter()
        .chain(input.global_init_proc.iter())
        .any(|proc| {
            proc.bytecode
                .as_ref()
                .is_some_and(|code| code.contains(&0x5f))
        })
    {
        if builder.dmb.variables.len() == NONE as usize {
            builder.dmb.variables.push(Variable {
                kind: 0,
                value: 0,
                name: NONE,
            });
        }
        builder.ids.global_vars = Some(builder.variable(
            "vars",
            &Value {
                tag_word: 82,
                data_word: 0,
                extra_word: None,
            },
        ));
    }
    mark_phase!("reindex");
    if requires_wide_object_ids(&builder.dmb) {
        builder.dmb.header.flags |= 0x4000_0000;
    }
    builder.dmb.validate_references()?;
    if timing {
        eprintln!("dmb-emitter validate: {:?}", phase_start.elapsed());
    }
    Ok(Emission {
        dmb: builder.dmb,
        resources: builder.archive,
        ids: builder.ids,
    })
}

/// Dream Maker's ordinary interpolation selects its sentence form from the
/// preceding template bytes. This is a backwards delimiter scan, not HTML
/// parsing: even unmatched `>` discards the preceding prefix, while an inner
/// `<` in a comment or attribute terminates the scan at that nearest opening.
fn native_interpolation_starts_sentence(mut prefix: &[u8]) -> bool {
    loop {
        while prefix
            .last()
            .is_some_and(|byte| matches!(byte, b' ' | b'\n' | b'\t' | b'\'' | b'"'))
        {
            prefix = &prefix[..prefix.len() - 1];
        }
        match prefix.last() {
            None | Some(b'.' | b'!' | b'?') => return true,
            Some(b'>') => {
                if let Some(opening) = prefix.iter().rposition(|&byte| byte == b'<') {
                    prefix = &prefix[..opening];
                } else {
                    return true;
                }
            }
            _ => return false,
        }
    }
}

fn native_format_marker(ch: char) -> Option<u8> {
    match ch as u32 {
        0xff00 => Some(0x01),
        0xff01 => Some(0x03),
        0xff03 => Some(0x2a),
        0xff04 => Some(0x09),
        0xff05 => Some(0x08),
        0xff06 => Some(0x07),
        0xff07 => Some(0x06),
        0xff09 => Some(0x0a),
        0xff0b => Some(0x0c),
        0xff0d => Some(0x11),
        0xff0f => Some(0x0e),
        0xff10 => Some(0x15),
        0xff11 => Some(0x16),
        0xff12 => Some(0x2c),
        0xff13 => Some(0x2d),
        0xff14 => Some(0x05),
        0xff15 => Some(0x14),
        0xff1f => Some(0x17), // bold/b text style
        0xff21 => Some(0x12), // authored escaped ellipsis
        _ => None,
    }
}

// Native executor retains the first ASCII space as its argument separator,
// then removes further spaces. Tabs/newlines are preserved, across lines.
fn native_executor_bytes(value: &str) -> Vec<u8> {
    let mut data = native_string_bytes(value);
    let mut separator_seen = false;
    data.retain(|byte| {
        if *byte != b' ' {
            return true;
        }
        if separator_seen {
            return false;
        }
        separator_seen = true;
        true
    });
    data
}

fn native_string_bytes(value: &str) -> Vec<u8> {
    // OpenDream stores format controls as U+FFxx; paired Dream Maker
    // output uses FF followed by a different control byte.
    let mut data = Vec::with_capacity(value.len());
    let mut roman_marker = None;
    let mut characters = value.chars().peekable();
    while let Some(ch) = characters.next() {
        if ch == '\u{ff5e}'
            && characters
                .peek()
                .is_some_and(|next| ('\u{ff00}'..='\u{ff5e}').contains(next))
        {
            // The patched parser escapes literal characters before interning,
            // so fullwidth Unicode cannot alias interpolation or Roman controls.
            let literal = characters.next().unwrap();
            let mut encoded = [0; 4];
            data.extend(literal.encode_utf8(&mut encoded).as_bytes());
            continue;
        }
        if matches!(ch, '\u{ff12}' | '\u{ff13}') {
            roman_marker = native_format_marker(ch);
            continue;
        }
        let native_marker = if ch == '\u{ff01}' && roman_marker.is_some() {
            roman_marker.take()
        } else if ch == '\u{ff00}' && native_interpolation_starts_sentence(&data) {
            // The sentence form depends on preceding punctuation and
            // markup delimiters, independently of the operand type.
            Some(0x02)
        } else {
            native_format_marker(ch)
        };
        if let Some(marker) = native_marker {
            data.extend([0xff, marker]);
        } else {
            let mut encoded = [0; 4];
            data.extend(ch.encode_utf8(&mut encoded).as_bytes());
        }
    }
    data
}

fn native_reserved_string_id(id: u32) -> bool {
    (0xffcd..=0xfff1).contains(&id) || id == 0xffff
}

impl Builder<'_> {
    fn reserve_class_sentinel(&mut self) {
        if self.dmb.classes.len() == NONE as usize {
            self.dmb.classes.push(native_blank_class());
        }
    }
    fn reserve_proc_sentinel(&mut self) {
        if self.dmb.procs.len() == NONE as usize {
            self.dmb.procs.push(native_blank_proc());
        }
    }
    fn index_scaffold(&mut self) {
        for (id, value) in self.dmb.strings.iter().enumerate() {
            if native_reserved_string_id(id as u32) {
                continue;
            }
            self.strings.entry(value.data.clone()).or_insert(id as u32);
        }
        for (id, class) in self.dmb.classes.iter().enumerate() {
            if let Some(path) = self.dmb.string(class.path_string_id()) {
                self.paths
                    .insert(String::from_utf8_lossy(path).into_owned(), id as u32);
            }
        }
        for (id, variable) in self.dmb.variables.iter().enumerate() {
            if variable.kind != 62 {
                if let Some(name) = self.dmb.string(variable.name) {
                    self.shared_variables
                        .entry((variable.kind, variable.value, name.to_vec()))
                        .or_insert(id as u32);
                }
            }
            if variable.kind == 0 && variable.value == 0 {
                if let Some(name) = self.dmb.string(variable.name) {
                    self.procedure_variables
                        .entry(name.to_vec())
                        .or_insert(id as u32);
                }
            }
        }
        for (id, instance) in self.dmb.instances.iter().enumerate() {
            self.instance_index
                .entry((instance.kind, instance.class, instance.initializer))
                .or_insert(id as u32);
        }
    }
    fn string(&mut self, value: &str) -> u32 {
        let data = native_string_bytes(value);
        self.string_bytes(data)
    }
    fn string_bytes(&mut self, data: Vec<u8>) -> u32 {
        if let Some(id) = self.strings.get(&data) {
            return *id;
        }
        // A bare field reference is a StringID in the same word space as
        // native variable modifiers. Optional proc strings also reserve FFFF.
        // Keep these slots unassigned to authored strings rather than emitting
        // a field which the VM would decode as a modifier.
        while native_reserved_string_id(self.dmb.strings.len() as u32) {
            self.dmb.strings.push(DmString {
                data: Vec::new(),
                long_chunks: 0,
            });
        }
        let id = self.dmb.strings.len() as u32;
        self.dmb.strings.push(DmString {
            long_chunks: u16::try_from(data.len() / u16::MAX as usize).unwrap_or(u16::MAX),
            data: data.clone(),
        });
        self.strings.insert(data, id);
        id
    }
    fn list(&mut self, words: Vec<u32>) -> u32 {
        if self.dmb.lists.len() == NONE as usize {
            // Optional list links reserve FFFF even when object IDs are wide.
            self.dmb.lists.push(Vec::new());
        }
        let id = self.dmb.lists.len() as u32;
        self.dmb.lists.push(words);
        id
    }
    fn variable(&mut self, name: &str, value: &Value) -> u32 {
        let id = self.dmb.variables.len() as u32;
        let name_id = self.string(name);
        self.dmb.variables.push(Variable {
            kind: value.tag(),
            value: value.number_bits().unwrap_or_else(|| value.id()),
            name: name_id,
        });
        if value.tag() == 0 && value.id() == 0 {
            self.procedure_variables
                .entry(name.as_bytes().to_vec())
                .or_insert(id);
        }
        id
    }
    fn class_variable(&mut self, name: &str, value: &Value) -> u32 {
        let kind = value.tag();
        let raw = value.number_bits().unwrap_or_else(|| value.id());
        let key = (kind, raw, name.as_bytes().to_vec());
        if kind != 62 && kind != 41 {
            if let Some(&id) = self.shared_variables.get(&key) {
                return id;
            }
        }
        let id = self.variable(name, value);
        if kind != 62 && kind != 41 {
            self.shared_variables.insert(key, id);
        }
        id
    }
    fn procedure_variable(&mut self, name: &str) -> u32 {
        if let Some(id) = self.procedure_variables.get(name.as_bytes()) {
            return *id;
        }
        self.variable(
            name,
            &Value {
                tag_word: 0,
                data_word: 0,
                extra_word: None,
            },
        )
    }
}

mod classes;
mod globals;
mod instances;
mod maps;
mod procs;
mod resources;
mod world;

#[cfg(test)]
#[path = "od_emit_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "od_emit_world_tests.rs"]
mod world_header_field_tests;
