//! Static semantic comparison of two DMB files.
//!
//! Table IDs are compiler allocations, so classes and procedures are paired
//! by path. Typed string/type/proc/resource operands are resolved before
//! comparison. Bare bytecode words remain raw because their meaning depends
//! on the opcode and is not always established.

use crate::bytecode::{self, Operand};
use crate::dmb::{Dmb, ProcArgument};
use crate::operands::{Value, ValueKind, Variable};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Debug)]
pub struct CompareOptions {
    /// Empty compares the whole program. Prefixes include a path and children.
    pub authored_prefixes: Vec<String>,
    pub compare_bytecode: bool,
    pub max_discrepancies: usize,
}

impl Default for CompareOptions {
    fn default() -> Self {
        Self {
            authored_prefixes: Vec::new(),
            compare_bytecode: true,
            max_discrepancies: 100,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, serde::Serialize)]
pub struct Discrepancy {
    pub path: String,
    pub field: String,
    pub expected: String,
    pub actual: String,
}

struct Collector {
    output: Vec<Discrepancy>,
    limit: usize,
    report: Option<structural::StructuralReport>,
}

impl Collector {
    fn add(
        &mut self,
        path: &str,
        field: &str,
        expected: impl std::fmt::Debug,
        actual: impl std::fmt::Debug,
    ) {
        if let Some(report) = &mut self.report {
            report.record(path, field, format!("{expected:?}"), format!("{actual:?}"));
            return;
        }
        if self.output.len() < self.limit {
            self.output.push(Discrepancy {
                path: path.into(),
                field: field.into(),
                expected: format!("{expected:?}"),
                actual: format!("{actual:?}"),
            });
        }
    }
    fn check<T: Eq + std::fmt::Debug>(&mut self, path: &str, field: &str, expected: T, actual: T) {
        if expected != actual {
            self.add(path, field, expected, actual);
        }
    }
    fn full(&self) -> bool {
        self.report.is_none() && self.output.len() >= self.limit
    }
}

fn bytes(dmb: &Dmb, id: u32) -> Option<Vec<u8>> {
    dmb.string(id).map(<[u8]>::to_vec)
}

fn optional_proc_string(dmb: &Dmb, id: u32) -> Option<Vec<u8>> {
    (id != 0xffff).then(|| bytes(dmb, id)).flatten()
}

fn path(dmb: &Dmb, id: u32) -> Option<Vec<u8>> {
    dmb.classes
        .get(id as usize)
        .and_then(|class| bytes(dmb, class.path_string_id()))
}

fn proc_path(dmb: &Dmb, id: u32) -> Option<Vec<u8>> {
    dmb.procs
        .get(id as usize)
        .and_then(|proc_| optional_proc_string(dmb, proc_.strings[0]))
}

fn label(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

fn selected(path: &[u8], options: &CompareOptions) -> bool {
    options.authored_prefixes.is_empty()
        || options.authored_prefixes.iter().any(|prefix| {
            let prefix = prefix.as_bytes();
            path == prefix
                || path.starts_with(prefix)
                    && (prefix.ends_with(b"/") || path.get(prefix.len()) == Some(&b'/'))
        })
}

#[path = "compare_values.rs"]
mod values;
use values::*;
#[path = "compare_procedures.rs"]
mod procedures;
pub use procedures::compare_proc_code;
use procedures::*;
#[path = "compare_maps.rs"]
mod maps;
use maps::*;
pub use maps::{
    compare_maps, compare_maps_semantic, constant_initializer_signature,
    constant_instance_signature,
};

fn class_index(dmb: &Dmb, options: &CompareOptions) -> BTreeMap<Vec<u8>, Vec<usize>> {
    let mut result = BTreeMap::<Vec<u8>, Vec<usize>>::new();
    for (id, class) in dmb.classes.iter().enumerate() {
        if let Some(name) = bytes(dmb, class.path_string_id()).filter(|p| selected(p, options)) {
            result.entry(name).or_default().push(id);
        }
    }
    result
}

fn proc_index(dmb: &Dmb, options: &CompareOptions) -> BTreeMap<Vec<u8>, Vec<usize>> {
    let mut result = BTreeMap::<Vec<u8>, Vec<usize>>::new();
    for (id, proc_) in dmb.procs.iter().enumerate() {
        if let Some(name) =
            optional_proc_string(dmb, proc_.strings[0]).filter(|p| selected(p, options))
        {
            result
                .entry(canonical_proc_path(name))
                .or_default()
                .push(id);
        }
    }
    order_proc_groups_by_binding(dmb, result.values_mut());
    result
}

/// Resolve the exact duplicate rank used by structural reports, without decoding code.
/// Explicit /proc/ and /verb/ path markers use the comparator's canonical spelling.
pub fn ranked_proc_by_path(dmb: &Dmb, path: &[u8], rank: usize) -> Option<usize> {
    let wanted = canonical_proc_path(path.to_vec());
    let mut group: Vec<_> = dmb
        .procs
        .iter()
        .enumerate()
        .filter_map(|(id, procedure)| {
            optional_proc_string(dmb, procedure.strings[0])
                .filter(|name| canonical_proc_path(name.clone()) == wanted)
                .map(|_| id)
        })
        .collect();
    order_proc_group_by_binding(dmb, &mut group);
    group.get(rank).copied()
}

fn canonical_proc_path(mut path: Vec<u8>) -> Vec<u8> {
    for marker in [b"/proc/".as_slice(), b"/verb/".as_slice()] {
        if let Some(at) = path.windows(marker.len()).position(|part| part == marker) {
            if at != 0 {
                path.drain(at..at + marker.len() - 1);
            }
        }
    }
    path
}

/// Pair duplicate procedure paths by their ordered owning-class bindings.
/// Unbound groups retain table order; body metadata is never a pairing key.
pub fn order_proc_group_by_binding(dmb: &Dmb, ids: &mut [usize]) {
    let mut group = ids.to_vec();
    order_proc_groups_by_binding(dmb, std::iter::once(&mut group));
    ids.copy_from_slice(&group);
}

/// Precompute binding ranks once for a whole procedure index.
pub fn order_proc_groups_by_binding<'a>(
    dmb: &Dmb,
    groups: impl Iterator<Item = &'a mut Vec<usize>>,
) {
    let groups: Vec<_> = groups.filter(|ids| ids.len() > 1).collect();
    if groups.is_empty() {
        return;
    }
    let wanted: BTreeSet<usize> = groups.iter().flat_map(|ids| ids.iter().copied()).collect();
    let mut ranks = BTreeMap::<usize, Vec<(Vec<u8>, u8, usize)>>::new();
    for class in &dmb.classes {
        let owner = dmb
            .string(class.path_string_id())
            .unwrap_or_default()
            .to_vec();
        for (kind, list) in [(0, class.proc_list_id()), (1, class.verb_list_id())] {
            if let Some(members) = dmb.lists.get(list as usize) {
                for (ordinal, &id) in members.iter().enumerate() {
                    if wanted.contains(&(id as usize)) {
                        ranks
                            .entry(id as usize)
                            .or_default()
                            .push((owner.clone(), kind, ordinal));
                    }
                }
            }
        }
    }
    for rank in ranks.values_mut() {
        rank.sort();
    }
    for ids in groups {
        if ids.iter().all(|id| ranks.contains_key(id)) {
            ids.sort_by_cached_key(|id| ranks[id].clone());
        }
    }
}
fn declaration(dmb: &Dmb, class_id: usize) -> Option<BTreeMap<Vec<u8>, (u32, NormalValue)>> {
    let mut result = BTreeMap::new();
    for (var_id, flags) in dmb
        .class_variable_declarations(class_id)
        .unwrap_or_default()
    {
        let variable = dmb.variables.get(var_id as usize)?;
        let initial = if variable.kind == 42 {
            NormalValue::Number(variable.value)
        } else {
            value(
                dmb,
                Value {
                    tag_word: u32::from(variable.kind) | ((variable.value >> 16) << 8),
                    data_word: variable.value & 0xffff,
                    extra_word: None,
                },
            )
        };
        result.insert(bytes(dmb, variable.name)?, (flags, initial));
    }
    Some(result)
}

/// Dedicated appearance fields are separate from the declaration/override lists.
/// Resolve compiler-allocated IDs, but preserve every scalar and optional payload.
fn compare_class_header(
    expected: &Dmb,
    actual: &Dmb,
    ids: (usize, usize),
    name: &str,
    out: &mut Collector,
) {
    let left = &expected.classes[ids.0];
    let right = &actual.classes[ids.1];
    for (field, a, b) in [
        ("name", left.name_string_id(), right.name_string_id()),
        (
            "description",
            left.description_string_id(),
            right.description_string_id(),
        ),
        (
            "icon_state",
            left.icon_state_string_id(),
            right.icon_state_string_id(),
        ),
        ("text", left.text, right.text),
        ("maptext", left.maptext, right.maptext),
        ("suffix", left.suffix, right.suffix),
    ] {
        out.check(
            name,
            &format!("class.header.{field}"),
            bytes(expected, a),
            bytes(actual, b),
        );
    }
    let resource = |dmb: &Dmb, id| dmb.resources.get(id as usize).map(|r| (r.kind, r.id));
    out.check(
        name,
        "class.header.icon",
        resource(expected, left.icon_resource_id()),
        resource(actual, right.icon_resource_id()),
    );
    out.check(
        name,
        "class.header.direction",
        left.direction,
        right.direction,
    );
    out.check(
        name,
        "class.header.interface",
        (left.interface, left.extended_interface),
        (right.interface, right.extended_interface),
    );
    out.check(name, "class.header.flags", left.flags, right.flags);
    out.check(
        name,
        "class.header.layer_bits",
        left.layer_bits,
        right.layer_bits,
    );
    out.check(
        name,
        "class.header.maptext_geometry",
        left.maptext_geometry,
        right.maptext_geometry,
    );
    out.check(
        name,
        "class.header.transform",
        (left.transform_flag, left.transform),
        (right.transform_flag, right.transform),
    );
    out.check(
        name,
        "class.header.color_matrix",
        (left.color_matrix_flag, left.color_matrix),
        (right.color_matrix_flag, right.color_matrix),
    );
}

fn defaults(dmb: &Dmb, class_id: usize) -> Option<BTreeMap<Vec<u8>, NormalValue>> {
    let mut result = BTreeMap::new();
    for initial in dmb.class_initial_values(class_id).unwrap_or_default() {
        let variable = dmb.variables.get(initial.variable_id as usize)?;
        result.insert(bytes(dmb, variable.name)?, value(dmb, initial.value));
    }
    for override_ in dmb.class_builtin_overrides(class_id).unwrap_or_default() {
        result.insert(
            bytes(dmb, override_.name_string_id)?,
            value(dmb, override_.value),
        );
    }
    Some(result)
}

fn compare_world(expected: &Dmb, actual: &Dmb, out: &mut Collector) {
    let a = &expected.world;
    let b = &actual.world;
    let mob_path = |dmb: &Dmb, id: u32| {
        dmb.mobs
            .get(id as usize)
            .and_then(|mob| path(dmb, mob.class))
    };
    out.check(
        "/world",
        "mob",
        mob_path(expected, a.mob_type_id()),
        mob_path(actual, b.mob_type_id()),
    );
    for (field, left, right) in [
        ("turf", a.turf_class_id(), b.turf_class_id()),
        ("area", a.area_class_id(), b.area_class_id()),
        ("client", a.client, b.client),
        ("image", a.image, b.image),
    ] {
        out.check("/world", field, path(expected, left), path(actual, right));
    }
    for (field, left, right) in [
        ("domain", a.domain_string_id(), b.domain_string_id()),
        ("name", a.name_string_id(), b.name_string_id()),
        ("client_script", a.client_script, b.client_script),
        ("hub_password", a.hub_password, b.hub_password),
        ("server_name", a.server_name, b.server_name),
        (
            "command_text",
            a.client_command_text_id(),
            b.client_command_text_id(),
        ),
        (
            "command_prompt",
            a.client_command_prompt_id(),
            b.client_command_prompt_id(),
        ),
        ("hub", a.hub_string_id(), b.hub_string_id()),
        ("channel", a.channel_string_id(), b.channel_string_id()),
    ] {
        out.check("/world", field, bytes(expected, left), bytes(actual, right));
    }
    out.check(
        "/world",
        "skin_resource",
        expected
            .resources
            .get(a.skin_resource_id() as usize)
            .map(|resource| (resource.kind, resource.id)),
        actual
            .resources
            .get(b.skin_resource_id() as usize)
            .map(|resource| (resource.kind, resource.id)),
    );
    let procedures = |dmb: &Dmb| {
        dmb.lists
            .get(dmb.world.proc_list_id() as usize)
            .map(|ids| ids.iter().map(|&id| proc_path(dmb, id)).collect::<Vec<_>>())
    };
    out.check(
        "/world",
        "procedures",
        procedures(expected),
        procedures(actual),
    );
    out.check(
        "/world",
        "script_files",
        a.client_script_files
            .iter()
            .map(|&id| {
                expected
                    .resources
                    .get(id as usize)
                    .map(|resource| (resource.kind, resource.id))
            })
            .collect::<Vec<_>>(),
        b.client_script_files
            .iter()
            .map(|&id| {
                actual
                    .resources
                    .get(id as usize)
                    .map(|resource| (resource.kind, resource.id))
            })
            .collect::<Vec<_>>(),
    );
    out.check(
        "/world",
        "client_import_handler",
        a.unknown_byte,
        b.unknown_byte,
    );
    out.check(
        "/world",
        "numeric_settings",
        (
            a.tick_lag,
            a.savefile_byond_version,
            a.eye,
            a.direction,
            a.control,
            a.view_dimensions,
            a.hub_number,
            a.version,
            a.cache_lifespan,
            a.icon_dimensions_format,
        ),
        (
            b.tick_lag,
            b.savefile_byond_version,
            b.eye,
            b.direction,
            b.control,
            b.view_dimensions,
            b.hub_number,
            b.version,
            b.cache_lifespan,
            b.icon_dimensions_format,
        ),
    );
}

type NormalDeclarations = BTreeMap<Vec<u8>, Vec<(u32, NormalValue)>>;

fn global_declarations(dmb: &Dmb) -> Option<NormalDeclarations> {
    let mut result = BTreeMap::<Vec<u8>, Vec<(u32, NormalValue)>>::new();
    for (var_id, flags) in dmb.global_variable_flags()? {
        let variable = dmb.variables.get(var_id as usize)?;
        let initial = if variable.kind == 42 {
            NormalValue::Number(variable.value)
        } else {
            value(
                dmb,
                Value {
                    tag_word: u32::from(variable.kind) | ((variable.value >> 16) << 8),
                    data_word: variable.value & 0xffff,
                    extra_word: None,
                },
            )
        };
        result
            .entry(bytes(dmb, variable.name)?)
            .or_default()
            .push((flags, initial));
    }
    // Footer entries are referenced by VarID. Their relative order does not
    // affect the value of distinct declarations sharing a source name.
    for entries in result.values_mut() {
        entries.sort_by_cached_key(|entry| format!("{entry:?}"));
    }
    Some(result)
}

type NormalMob = (Option<Vec<u8>>, u32, Option<u8>, Option<u8>);
type NormalMobs = BTreeMap<Vec<u8>, Vec<NormalMob>>;

fn mob_types(dmb: &Dmb) -> NormalMobs {
    let mut result = BTreeMap::new();
    for mob in &dmb.mobs {
        if let Some(class) = path(dmb, mob.class) {
            result.entry(class).or_insert_with(Vec::new).push((
                bytes(dmb, mob.key),
                mob.sight_bits(),
                mob.see_in_dark_setting(),
                mob.see_invisible_setting(),
            ));
        }
    }
    result
}

fn compare_mob_types(expected: &Dmb, actual: &Dmb, out: &mut Collector) {
    let left = mob_types(expected);
    let right = mob_types(actual);
    for key in left.keys().chain(right.keys()).collect::<BTreeSet<_>>() {
        if out.full() {
            break;
        }
        out.check(&label(key), "mob.record", left.get(key), right.get(key));
    }
}

fn compare_global_declarations(expected: &Dmb, actual: &Dmb, out: &mut Collector) {
    let left = global_declarations(expected);
    let right = global_declarations(actual);
    let (Some(left), Some(right)) = (left.as_ref(), right.as_ref()) else {
        out.add(
            "/globals",
            "declarations.decode",
            left.is_some(),
            right.is_some(),
        );
        return;
    };
    for key in left.keys().chain(right.keys()).collect::<BTreeSet<_>>() {
        if out.full() {
            break;
        }
        out.check(
            &format!("/globals/{}", label(key)),
            "declaration",
            left.get(key),
            right.get(key),
        );
    }
}

/// Compare logical classes and procedures. The first DMB is the expected
/// reference; the second is the translation. Results are bounded by options.
pub fn compare_dmbs(expected: &Dmb, actual: &Dmb, options: &CompareOptions) -> Vec<Discrepancy> {
    let mut out = Collector {
        output: Vec::new(),
        limit: options.max_discrepancies,
        report: None,
    };
    collect_dmbs(expected, actual, options, &mut out);
    out.output
}

fn collect_dmbs(expected: &Dmb, actual: &Dmb, options: &CompareOptions, out: &mut Collector) {
    let ac = class_index(expected, options);
    let bc = class_index(actual, options);
    let keys: BTreeSet<_> = ac.keys().chain(bc.keys()).cloned().collect();
    for key in keys {
        if out.full() {
            break;
        }
        let name = label(&key);
        let a = ac.get(&key).map(Vec::as_slice).unwrap_or_default();
        let b = bc.get(&key).map(Vec::as_slice).unwrap_or_default();
        out.check(&name, "class.count", a.len(), b.len());
        for (&ai, &bi) in a.iter().zip(b) {
            let left = &expected.classes[ai];
            let right = &actual.classes[bi];
            out.check(
                &name,
                "class.parent",
                path(expected, left.parent_class_id()),
                path(actual, right.parent_class_id()),
            );
            compare_class_header(expected, actual, (ai, bi), &name, out);
            match (declaration(expected, ai), declaration(actual, bi)) {
                (Some(left), Some(right)) => {
                    for field in left.keys().chain(right.keys()).collect::<BTreeSet<_>>() {
                        out.check(
                            &name,
                            &format!("class.declaration.{}", label(field)),
                            left.get(field),
                            right.get(field),
                        );
                    }
                }
                (left, right) => out.check(&name, "class.declarations", left, right),
            }
            match (defaults(expected, ai), defaults(actual, bi)) {
                (Some(left), Some(right)) => {
                    for field in left.keys().chain(right.keys()).collect::<BTreeSet<_>>() {
                        let field_name = format!("class.default.{}", label(field));
                        match (left.get(field), right.get(field)) {
                            (
                                Some(NormalValue::String(Some(a))),
                                Some(NormalValue::String(Some(b))),
                            ) if a != b && out.report.is_none() => {
                                let at = a
                                    .iter()
                                    .zip(b)
                                    .position(|(x, y)| x != y)
                                    .unwrap_or(a.len().min(b.len()));
                                let start = at.saturating_sub(16);
                                let left_end = a.len().min(at + 48);
                                let right_end = b.len().min(at + 48);
                                out.add(
                                    &name,
                                    &field_name,
                                    (a.len(), at, &a[start..left_end]),
                                    (b.len(), at, &b[start..right_end]),
                                );
                            }
                            (a, b) => out.check(&name, &field_name, a, b),
                        }
                    }
                }
                (left, right) => out.check(&name, "class.defaults", left, right),
            }
            compare_initializer(
                expected,
                left.initializer_proc_id(),
                actual,
                right.initializer_proc_id(),
                &format!("{name}::<init>"),
                options,
                out,
            );
        }
    }
    if selected(b"/world", options) {
        compare_initializer(
            expected,
            expected.world.global_initializer_proc_id(),
            actual,
            actual.world.global_initializer_proc_id(),
            "/world::<global-init>",
            options,
            out,
        );
    }
    let ap = proc_index(expected, options);
    let bp = proc_index(actual, options);
    let keys: BTreeSet<_> = ap.keys().chain(bp.keys()).cloned().collect();
    for key in keys {
        if out.full() {
            break;
        }
        let name = label(&key);
        let a = ap.get(&key).map(Vec::as_slice).unwrap_or_default();
        let b = bp.get(&key).map(Vec::as_slice).unwrap_or_default();
        out.check(&name, "proc.count", a.len(), b.len());
        for (rank, (&ai, &bi)) in a.iter().zip(b).enumerate() {
            let paired_name = if out.report.is_some() {
                format!("{name}#{rank}")
            } else {
                name.clone()
            };
            compare_proc(expected, actual, (ai, bi), &paired_name, options, true, out);
        }
    }
    if options.authored_prefixes.is_empty() {
        // Compare only flag meanings established by paired native probes.
        // ID width, debug-marker presence, extension-word presence, and opaque
        // bits are wire/diagnostic details rather than this semantic contract.
        const SEMANTIC_HEADER_FLAGS: u32 = 0x3bf4_ffef;
        out.check(
            "/header",
            "header.semantic_flags",
            expected.header.flags & SEMANTIC_HEADER_FLAGS,
            actual.header.flags & SEMANTIC_HEADER_FLAGS,
        );
        out.check(
            "/header",
            "header.semantic_extended_flags",
            expected.header.extended_flags.unwrap_or(0) & 0xf,
            actual.header.extended_flags.unwrap_or(0) & 0xf,
        );
        compare_world(expected, actual, out);
        compare_mob_types(expected, actual, out);
        compare_global_declarations(expected, actual, out);
        out.check(
            "/markers",
            "hidden_initializer_identity",
            marker_integrity(expected),
            marker_integrity(actual),
        );
    }
}

/// Compare class tables before all procedures can be lowered. This includes
/// declaration and default values, but omits initializer procedure bodies.
pub fn compare_class_tables(
    expected: &Dmb,
    actual: &Dmb,
    max_discrepancies: usize,
) -> Vec<Discrepancy> {
    let mut out = Collector {
        output: Vec::new(),
        limit: max_discrepancies,
        report: None,
    };
    let options = CompareOptions::default();
    let ac = class_index(expected, &options);
    let bc = class_index(actual, &options);
    for key in ac.keys().chain(bc.keys()).collect::<BTreeSet<_>>() {
        if out.full() {
            break;
        }
        let name = label(key);
        let a = ac.get(key).map(Vec::as_slice).unwrap_or_default();
        let b = bc.get(key).map(Vec::as_slice).unwrap_or_default();
        out.check(&name, "class.count", a.len(), b.len());
        for (&ai, &bi) in a.iter().zip(b) {
            let left = &expected.classes[ai];
            let right = &actual.classes[bi];
            out.check(
                &name,
                "class.parent",
                path(expected, left.parent_class_id()),
                path(actual, right.parent_class_id()),
            );
            compare_class_header(expected, actual, (ai, bi), &name, &mut out);
            match (declaration(expected, ai), declaration(actual, bi)) {
                (Some(left), Some(right)) => {
                    for field in left.keys().chain(right.keys()).collect::<BTreeSet<_>>() {
                        out.check(
                            &name,
                            &format!("class.declaration.{}", label(field)),
                            left.get(field),
                            right.get(field),
                        );
                    }
                }
                (left, right) => out.check(&name, "class.declarations", left, right),
            }
            match (defaults(expected, ai), defaults(actual, bi)) {
                (Some(left), Some(right)) => {
                    for field in left.keys().chain(right.keys()).collect::<BTreeSet<_>>() {
                        let field_name = format!("class.default.{}", label(field));
                        match (left.get(field), right.get(field)) {
                            (
                                Some(NormalValue::String(Some(a))),
                                Some(NormalValue::String(Some(b))),
                            ) if a != b => {
                                let at = a
                                    .iter()
                                    .zip(b)
                                    .position(|(x, y)| x != y)
                                    .unwrap_or(a.len().min(b.len()));
                                let start = at.saturating_sub(16);
                                let left_end = a.len().min(at + 48);
                                let right_end = b.len().min(at + 48);
                                out.add(
                                    &name,
                                    &field_name,
                                    (a.len(), at, &a[start..left_end]),
                                    (b.len(), at, &b[start..right_end]),
                                );
                            }
                            (a, b) => out.check(&name, &field_name, a, b),
                        }
                    }
                }
                (left, right) => out.check(&name, "class.defaults", left, right),
            }
            out.check(
                &name,
                "class.init_presence",
                expected
                    .procs
                    .get(left.initializer_proc_id() as usize)
                    .is_some(),
                actual
                    .procs
                    .get(right.initializer_proc_id() as usize)
                    .is_some(),
            );
        }
    }
    compare_global_declarations(expected, actual, &mut out);
    out.output
}

/// Compare procedure table structure before every body can be lowered.
pub fn compare_proc_tables(
    expected: &Dmb,
    actual: &Dmb,
    max_discrepancies: usize,
) -> Vec<Discrepancy> {
    let mut out = Collector {
        output: Vec::new(),
        limit: max_discrepancies,
        report: None,
    };
    let options = CompareOptions {
        compare_bytecode: false,
        max_discrepancies,
        ..Default::default()
    };
    let ac = class_index(expected, &options);
    let bc = class_index(actual, &options);
    for key in ac.keys().chain(bc.keys()).collect::<BTreeSet<_>>() {
        if out.full() {
            break;
        }
        let name = label(key);
        for (&ai, &bi) in ac
            .get(key)
            .into_iter()
            .flatten()
            .zip(bc.get(key).into_iter().flatten())
        {
            let left = &expected.classes[ai];
            let right = &actual.classes[bi];
            for (field, left_id, right_id) in [
                ("class.procs", left.proc_list_id(), right.proc_list_id()),
                ("class.verbs", left.verb_list_id(), right.verb_list_id()),
            ] {
                let members = |dmb: &Dmb, id| {
                    if id == 0xffff {
                        return Vec::new();
                    }
                    dmb.lists
                        .get(id as usize)
                        .into_iter()
                        .flatten()
                        .map(|&proc_id| proc_path(dmb, proc_id).map(canonical_proc_path))
                        .collect::<Vec<_>>()
                };
                let mut expected_members = members(expected, left_id);
                let mut actual_members = members(actual, right_id);
                expected_members.sort();
                actual_members.sort();
                out.check(&name, field, expected_members, actual_members);
            }
            compare_initializer(
                expected,
                left.initializer_proc_id(),
                actual,
                right.initializer_proc_id(),
                &format!("{name}::<init>"),
                &options,
                &mut out,
            );
        }
    }
    compare_initializer(
        expected,
        expected.world.global_initializer_proc_id(),
        actual,
        actual.world.global_initializer_proc_id(),
        "/world::<global-init>",
        &options,
        &mut out,
    );
    let ap = proc_index(expected, &options);
    let bp = proc_index(actual, &options);
    for key in ap.keys().chain(bp.keys()).collect::<BTreeSet<_>>() {
        if out.full() {
            break;
        }
        let name = label(key);
        let a = ap.get(key).map(Vec::as_slice).unwrap_or_default();
        let b = bp.get(key).map(Vec::as_slice).unwrap_or_default();
        out.check(&name, "proc.count", a.len(), b.len());
        let a = a.to_vec();
        let b = b.to_vec();
        for (&ai, &bi) in a.iter().zip(&b) {
            compare_proc(expected, actual, (ai, bi), &name, &options, true, &mut out);
        }
    }
    out.output
}

/// Native reuses declaration marker tokens for identical initializer expressions
/// across independent variables. Compare marker counts; initializer procedures
/// separately establish construction, assignment targets, and aliasing semantics.
fn marker_integrity(dmb: &Dmb) -> (usize, usize) {
    let declarations = dmb
        .variables
        .iter()
        .filter(|variable| variable.kind == 62)
        .count();
    let class_values = (0..dmb.classes.len())
        .flat_map(|class_id| dmb.class_initial_values(class_id).unwrap_or_default())
        .filter(|initial| initial.value.kind() == ValueKind::HiddenInitializer)
        .count();
    (class_values, declarations)
}
/// Count class and procedure paths selected by the supplied prefixes.
/// Callers can reject a mistyped filter instead of reporting a vacuous match.
pub fn selected_path_count(dmb: &Dmb, options: &CompareOptions) -> usize {
    class_index(dmb, options).len() + proc_index(dmb, options).len()
}

#[path = "compare_structural.rs"]
mod structural;
pub use structural::{structural_report, StructuralReport};

#[path = "compare_anonymous.rs"]
mod anonymous;
#[path = "compare_missing.rs"]
mod missing;
#[path = "compare_operand_roles.rs"]
mod operand_roles;

#[cfg(test)]
#[path = "compare_tests.rs"]
mod tests;
