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
}

impl Collector {
    fn add(
        &mut self,
        path: &str,
        field: &str,
        expected: impl std::fmt::Debug,
        actual: impl std::fmt::Debug,
    ) {
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
        self.output.len() >= self.limit
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

#[derive(Clone, Debug, Eq, PartialEq)]
enum NormalValue {
    Null,
    Number(u32),
    String(Option<Vec<u8>>),
    Type(u8, Option<Vec<u8>>),
    InstanceType(u8, Option<Vec<u8>>, InstanceInitializer),
    Proc(Option<Vec<u8>>),
    Resource(Option<(u8, u32)>),
    /// Compiler allocation identity for a runtime initializer, not a table ID.
    HiddenInitializer,
    Raw(Value),
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum InstanceInitializer {
    Absent,
    Constants(String),
    // Preserve the allocation and wire body when constant semantics are unknown.
    Opaque(u32, Option<Vec<u32>>),
}

fn value(dmb: &Dmb, value: Value) -> NormalValue {
    match value.kind() {
        ValueKind::Null => NormalValue::Null,
        ValueKind::Number => NormalValue::Number(value.number_bits().unwrap_or(0)),
        ValueKind::String => NormalValue::String(bytes(dmb, value.id())),
        ValueKind::MobPath => NormalValue::Type(
            value.tag(),
            dmb.mobs
                .get(value.id() as usize)
                .and_then(|mob| path(dmb, mob.class)),
        ),
        ValueKind::ClientPath if value.id() == 0 => {
            NormalValue::Type(value.tag(), Some(b"/client".to_vec()))
        }
        ValueKind::ClientPath => NormalValue::Raw(value),
        // Native list/file/savefile type constants carry a zero singleton payload,
        // independent of whichever class happens to occupy table slot zero.
        ValueKind::ListPath if value.id() == 0 => {
            NormalValue::Type(value.tag(), Some(b"/list".to_vec()))
        }
        ValueKind::FilePath if value.id() == 0 => {
            NormalValue::Type(value.tag(), Some(b"/file".to_vec()))
        }
        ValueKind::SavefilePath if value.id() == 0 => {
            NormalValue::Type(value.tag(), Some(b"/savefile".to_vec()))
        }
        ValueKind::MovablePath
        | ValueKind::AtomPath
        | ValueKind::AreaPath
        | ValueKind::DatumPath
        | ValueKind::SavefilePath
        | ValueKind::FilePath
        | ValueKind::ListPath
        | ValueKind::ImagePath
        | ValueKind::BuiltinPath => NormalValue::Type(value.tag(), path(dmb, value.id())),
        ValueKind::InstanceTypePath => {
            let Some(instance) = dmb.instances.get(value.id() as usize) else {
                return NormalValue::Raw(value);
            };
            let class = if instance.kind == 8 {
                dmb.mobs.get(instance.class as usize).map(|mob| mob.class)
            } else {
                Some(instance.class)
            };
            let initializer = if instance.initializer == 0xffff {
                InstanceInitializer::Absent
            } else if let Some(assignments) = constant_map_assignments(dmb, instance.initializer) {
                InstanceInitializer::Constants(format!("{assignments:?}"))
            } else {
                InstanceInitializer::Opaque(
                    instance.initializer,
                    dmb.proc_code_words(instance.initializer as usize)
                        .map(<[u32]>::to_vec),
                )
            };
            NormalValue::InstanceType(
                instance.kind,
                class.and_then(|id| path(dmb, id)),
                initializer,
            )
        }
        ValueKind::ProcPath => NormalValue::Proc(proc_path(dmb, value.id())),
        ValueKind::Resource => NormalValue::Resource(
            dmb.resources
                .get(value.id() as usize)
                .map(|r| (r.kind, r.id)),
        ),
        ValueKind::HiddenInitializer => NormalValue::HiddenInitializer,
        _ => NormalValue::Raw(value),
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum NormalVariable {
    Field(Option<Vec<u8>>),
    Global(Option<Vec<u8>>),
    DynamicProc(Option<Vec<u8>>),
    DynamicVerb(Option<Vec<u8>>),
    StaticProc(Option<Vec<u8>>),
    StaticVerb(Option<Vec<u8>>),
    Named(&'static str),
    Indexed(&'static str, u32),
    Nested(
        &'static str,
        Box<NormalVariable>,
        Option<Box<NormalVariable>>,
    ),
}

fn variable(dmb: &Dmb, input: &Variable) -> NormalVariable {
    use Variable::*;
    match input {
        Field(id) => NormalVariable::Field(bytes(dmb, *id)),
        Global(id) => NormalVariable::Global(
            dmb.variables
                .get(*id as usize)
                .and_then(|v| bytes(dmb, v.name)),
        ),
        DynamicProc(id) => NormalVariable::DynamicProc(bytes(dmb, *id)),
        DynamicVerb(id) => NormalVariable::DynamicVerb(bytes(dmb, *id)),
        StaticProc(id) => {
            // The native VM converts ProcID to its descriptor's display StringID
            // before entering the same receiver/name dispatcher as DynamicProc.
            // Invalid/missing names retain a distinct form instead of matching None.
            dmb.procs
                .get(*id as usize)
                .and_then(|proc| optional_proc_string(dmb, proc.strings[1]))
                .map_or_else(
                    || NormalVariable::StaticProc(proc_path(dmb, *id)),
                    |display| NormalVariable::DynamicProc(Some(display)),
                )
        }
        StaticVerb(id) => {
            // Like StaticProc, the VM reads descriptor+4 before name dispatch,
            // but verb modes 1/9 remain distinct from proc modes 2/10.
            dmb.procs
                .get(*id as usize)
                .and_then(|proc| optional_proc_string(dmb, proc.strings[1]))
                .map_or_else(
                    || NormalVariable::StaticVerb(proc_path(dmb, *id)),
                    |display| NormalVariable::DynamicVerb(Some(display)),
                )
        }
        Arg(id) => NormalVariable::Indexed("arg", *id),
        Local(id) => NormalVariable::Indexed("local", *id),
        SetCache(left, right) => NormalVariable::Nested(
            "set-cache",
            Box::new(variable(dmb, left)),
            Some(Box::new(variable(dmb, right))),
        ),
        Initial(inner) => NormalVariable::Nested("initial", Box::new(variable(dmb, inner)), None),
        IsSaved(inner) => NormalVariable::Nested("is-saved", Box::new(variable(dmb, inner)), None),
        Usr => NormalVariable::Named("usr"),
        Src => NormalVariable::Named("src"),
        Args => NormalVariable::Named("args"),
        Dot => NormalVariable::Named("dot"),
        Cache => NormalVariable::Named("cache"),
        CacheKey => NormalVariable::Named("cache-key"),
        CacheIndex => NormalVariable::Named("cache-index"),
        World => NormalVariable::Named("world"),
        Caller => NormalVariable::Named("caller"),
        Callee => NormalVariable::Named("callee"),
        Null => NormalVariable::Named("null"),
    }
}

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

#[derive(Clone, Debug, Eq, PartialEq)]
struct NormalArgument {
    name: Option<Vec<u8>>,
    type_flags: u32,
    source_kind: u8,
    source_parameter: u8,
    source_expression: Option<Vec<u8>>,
    reserved: u32,
}

fn argument(dmb: &Dmb, arg: &ProcArgument) -> NormalArgument {
    let expression = dmb
        .argument_source_proc_id(arg)
        .and_then(|id| proc_path(dmb, id));
    NormalArgument {
        name: dmb
            .variables
            .get(arg.variable_id as usize)
            .and_then(|v| bytes(dmb, v.name)),
        type_flags: arg.type_flags,
        source_kind: arg.value_source_kind(),
        source_parameter: if arg.source_expression_index().is_some() {
            0
        } else {
            arg.value_source_parameter()
        },
        source_expression: expression,
        reserved: arg.reserved,
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum NormalOperand {
    Word(u32),
    Branch(usize),
    Offsets(Vec<u32>),
    Branches(Vec<usize>),
    String(Option<Vec<u8>>),
    Proc(Option<Vec<u8>>),
    Value(NormalValue),
    Variable(NormalVariable),
    Switch(Vec<(NormalValue, NormalTarget)>, NormalTarget),
    PickSwitch(Vec<(u32, NormalTarget)>, NormalTarget),
    RangeSwitch(
        Vec<(NormalValue, NormalValue, NormalTarget)>,
        Vec<(NormalValue, NormalTarget)>,
        NormalTarget,
    ),
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum NormalTarget {
    Raw(u32),
    Instruction(usize),
}

fn normalize_target(target: &mut NormalTarget, offsets: &BTreeMap<usize, usize>) {
    if let NormalTarget::Raw(raw) = target {
        if let Some(&index) = offsets.get(&(*raw as usize)) {
            *target = NormalTarget::Instruction(index);
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct NormalInstruction {
    opcode: u32,
    operands: Vec<NormalOperand>,
}

/// A decoded instruction suitable for an offline correctness report. Wire offsets
/// are diagnostic locations; `opcode` and `operands` form the comparison key.
/// Established table references use their resolved identities. Unknown immediate
/// words remain numeric, and this is not a proof of execution equivalence.
#[derive(Clone, Debug, Eq, PartialEq, serde::Serialize)]
pub struct ProcedureInstruction {
    pub ordinal: usize,
    pub wire_offset: usize,
    pub opcode: u32,
    pub operands: String,
}

/// An aligned region of changed code. These regions describe encoding changes,
/// not independent semantic defects. Local slots and branch targets remain exact.
#[derive(Clone, Debug, Eq, PartialEq, serde::Serialize)]
pub struct ProcedureCodeHunk {
    pub expected_start: usize,
    pub expected_end: usize,
    pub actual_start: usize,
    pub actual_end: usize,
    pub paired_operand_changes: usize,
    pub expected_unpaired: usize,
    pub actual_unpaired: usize,
}

#[derive(Clone, Debug, Eq, PartialEq, serde::Serialize)]
pub struct ProcedureCodeAlignment {
    pub algorithm: &'static str,
    pub work_limit_exceeded: bool,
    pub matched_opcodes: usize,
    pub changed_regions: usize,
    pub hunks: Vec<ProcedureCodeHunk>,
    pub hunks_truncated: bool,
}

/// Align by opcode, preferring exact operands. Insertions no longer make every
/// subsequent instruction appear changed. Equality and gate decisions must still
/// use the original normalized instructions, not this diagnostic alignment.
///
/// The dynamic-programming matrix is capped at one million u32 cells (4 MB).
/// Larger bodies use one prefix/suffix region instead of unbounded quadratic work.
pub fn align_procedure_instructions(
    expected: &[ProcedureInstruction],
    actual: &[ProcedureInstruction],
    max_hunks: usize,
) -> ProcedureCodeAlignment {
    let exact = |a: &ProcedureInstruction, b: &ProcedureInstruction| {
        a.opcode == b.opcode && a.operands == b.operands
    };
    let mut result = ProcedureCodeAlignment {
        algorithm: "weighted_opcode_sequence",
        work_limit_exceeded: false,
        matched_opcodes: 0,
        changed_regions: 0,
        hunks: Vec::new(),
        hunks_truncated: false,
    };
    let cells = expected.len().checked_add(1).and_then(|rows| {
        actual
            .len()
            .checked_add(1)
            .and_then(|columns| rows.checked_mul(columns))
    });
    if cells.is_none_or(|cells| cells > 1_000_000) {
        result.algorithm = "bounded_prefix_suffix";
        result.work_limit_exceeded = true;
        let prefix = expected
            .iter()
            .zip(actual)
            .take_while(|(a, b)| exact(a, b))
            .count();
        let suffix = expected[prefix..]
            .iter()
            .rev()
            .zip(actual[prefix..].iter().rev())
            .take_while(|(a, b)| exact(a, b))
            .count();
        result.matched_opcodes = prefix + suffix;
        if prefix + suffix < expected.len() || prefix + suffix < actual.len() {
            result.changed_regions = 1;
            if max_hunks > 0 {
                result.hunks.push(ProcedureCodeHunk {
                    expected_start: prefix,
                    expected_end: expected.len() - suffix,
                    actual_start: prefix,
                    actual_end: actual.len() - suffix,
                    paired_operand_changes: 0,
                    expected_unpaired: expected.len() - prefix - suffix,
                    actual_unpaired: actual.len() - prefix - suffix,
                });
            } else {
                result.hunks_truncated = true;
            }
        }
        return result;
    }
    let columns = actual.len() + 1;
    let mut scores = vec![0_u32; cells.unwrap()];
    let weight = |a: &ProcedureInstruction, b: &ProcedureInstruction| {
        if a.opcode != b.opcode {
            0
        } else if exact(a, b) {
            3
        } else {
            1
        }
    };
    for i in (0..expected.len()).rev() {
        for j in (0..actual.len()).rev() {
            let diagonal = scores[(i + 1) * columns + j + 1] + weight(&expected[i], &actual[j]);
            scores[i * columns + j] = diagonal
                .max(scores[(i + 1) * columns + j])
                .max(scores[i * columns + j + 1]);
        }
    }
    let (mut i, mut j) = (0, 0);
    let mut pending: Option<ProcedureCodeHunk> = None;
    let flush = |pending: &mut Option<ProcedureCodeHunk>, result: &mut ProcedureCodeAlignment| {
        if let Some(hunk) = pending.take() {
            result.changed_regions += 1;
            if result.hunks.len() < max_hunks {
                result.hunks.push(hunk);
            } else {
                result.hunks_truncated = true;
            }
        }
    };
    while i < expected.len() || j < actual.len() {
        let paired = i < expected.len()
            && j < actual.len()
            && expected[i].opcode == actual[j].opcode
            && scores[i * columns + j]
                == scores[(i + 1) * columns + j + 1] + weight(&expected[i], &actual[j]);
        if paired && exact(&expected[i], &actual[j]) {
            flush(&mut pending, &mut result);
            result.matched_opcodes += 1;
            i += 1;
            j += 1;
            continue;
        }
        let hunk = pending.get_or_insert_with(|| ProcedureCodeHunk {
            expected_start: i,
            expected_end: i,
            actual_start: j,
            actual_end: j,
            paired_operand_changes: 0,
            expected_unpaired: 0,
            actual_unpaired: 0,
        });
        if paired {
            hunk.paired_operand_changes += 1;
            result.matched_opcodes += 1;
            i += 1;
            j += 1;
        } else if i < expected.len()
            && (j == actual.len() || scores[(i + 1) * columns + j] >= scores[i * columns + j + 1])
        {
            hunk.expected_unpaired += 1;
            i += 1;
        } else {
            hunk.actual_unpaired += 1;
            j += 1;
        }
        hunk.expected_end = i;
        hunk.actual_end = j;
    }
    flush(&mut pending, &mut result);
    result
}

/// Ordered procedure groups, paired by owning bindings rather than by body content.
/// Paths are lossless bytes. Initializers and argument-source helpers get synthetic
/// identities so they participate in the same offline gates as named procedures.
pub fn procedure_groups(dmb: &Dmb, options: &CompareOptions) -> BTreeMap<Vec<u8>, Vec<usize>> {
    let mut groups = proc_index(dmb, options);
    for class in &dmb.classes {
        let Some(owner) = dmb.string(class.path_string_id()) else {
            continue;
        };
        if !selected(owner, options) || class.initializer_proc_id() == 0xffff {
            continue;
        }
        let mut key = owner.to_vec();
        key.extend_from_slice(b"::<class initializer>");
        groups
            .entry(key)
            .or_default()
            .push(class.initializer_proc_id() as usize);
    }
    if selected(b"/world", options) && dmb.world.global_initializer_proc_id() != 0xffff {
        groups
            .entry(b"/world::<global initializer>".to_vec())
            .or_default()
            .push(dmb.world.global_initializer_proc_id() as usize);
    }
    let mut helpers = Vec::new();
    for (path, ids) in &groups {
        for (occurrence, &id) in ids.iter().enumerate() {
            for (argument, metadata) in dmb
                .proc_arguments(id)
                .unwrap_or_default()
                .iter()
                .enumerate()
            {
                if let Some(helper) = dmb.argument_source_proc_id(metadata) {
                    let mut key = path.clone();
                    key.extend_from_slice(
                        format!("::<definition {occurrence} argument {argument} source>")
                            .as_bytes(),
                    );
                    helpers.push((key, helper as usize));
                }
            }
        }
    }
    for (key, id) in helpers {
        groups.entry(key).or_default().push(id);
    }
    groups
}

fn normalize_instruction_targets(
    normalized: &mut NormalInstruction,
    targets: &BTreeMap<usize, usize>,
) {
    for operand in &mut normalized.operands {
        match operand {
            NormalOperand::Switch(cases, default) => {
                for (_, target) in cases {
                    normalize_target(target, targets);
                }
                normalize_target(default, targets);
            }
            NormalOperand::PickSwitch(cases, default) => {
                for (_, target) in cases {
                    normalize_target(target, targets);
                }
                normalize_target(default, targets);
            }
            NormalOperand::RangeSwitch(ranges, exact, default) => {
                for (_, _, target) in ranges {
                    normalize_target(target, targets);
                }
                for (_, target) in exact {
                    normalize_target(target, targets);
                }
                normalize_target(default, targets);
            }
            _ => {}
        }
    }
    if normalized.opcode == 0xb1 {
        if let Some(NormalOperand::Offsets(offsets)) = normalized.operands.first() {
            if let Some(branches) = offsets
                .iter()
                .map(|offset| targets.get(&(*offset as usize)).copied())
                .collect::<Option<Vec<_>>>()
            {
                normalized.operands[0] = NormalOperand::Branches(branches);
            }
        }
    }
    if crate::bytecode::is_branch_opcode(normalized.opcode) {
        if let Some(NormalOperand::Word(offset)) = normalized.operands.first() {
            if let Some(&target) = targets.get(&(*offset as usize)) {
                normalized.operands[0] = NormalOperand::Branch(target);
            }
        }
    }
}

/// Normalize one procedure with the same operand/target rules as compare_proc_code.
/// Reject missing bodies and undecodable operands instead of treating them as an
/// empty procedure. Debug stripping preserves targets into/across debug markers.
pub fn procedure_instructions(
    dmb: &Dmb,
    id: usize,
    ignore_debug: bool,
) -> Result<Vec<ProcedureInstruction>, String> {
    let code = dmb
        .proc_code_words(id)
        .ok_or_else(|| format!("procedure {id} has no code list"))?;
    let decoded = bytecode::decode(code).map_err(|error| format!("procedure {id}: {error:?}"))?;
    let mut offsets = BTreeMap::new();
    let mut ordinal = 0;
    for item in &decoded {
        offsets.insert(item.offset, ordinal);
        if !ignore_debug || !matches!(item.opcode, 0x84 | 0x85) {
            ordinal += 1;
        }
    }
    offsets.insert(code.len(), ordinal);
    decoded
        .iter()
        .filter(|item| !ignore_debug || !matches!(item.opcode, 0x84 | 0x85))
        .enumerate()
        .map(|(ordinal, item)| {
            let mut normalized = instruction(dmb, item)
                .map_err(|error| format!("procedure {id} at {}: {error:?}", item.offset))?;
            normalize_instruction_targets(&mut normalized, &offsets);
            Ok(ProcedureInstruction {
                ordinal,
                wire_offset: item.offset,
                opcode: normalized.opcode,
                operands: format!("{:?}", normalized.operands),
            })
        })
        .collect()
}

fn operand(dmb: &Dmb, operand: Operand) -> NormalOperand {
    match operand {
        Operand::Word(word) => NormalOperand::Word(word),
        Operand::Value(v) => NormalOperand::Value(value(dmb, v)),
        Operand::Variable(v) => NormalOperand::Variable(variable(dmb, &v)),
        Operand::PickProb(offsets) => NormalOperand::Offsets(offsets),
        Operand::Switch { cases, default } => NormalOperand::Switch(
            cases
                .into_iter()
                .map(|(v, target)| (value(dmb, v), NormalTarget::Raw(target)))
                .collect(),
            NormalTarget::Raw(default),
        ),
        Operand::PickSwitch { cases, default } => NormalOperand::PickSwitch(
            cases
                .into_iter()
                .map(|(weight, target)| (weight, NormalTarget::Raw(target)))
                .collect(),
            NormalTarget::Raw(default),
        ),
        Operand::RangeSwitch {
            ranges,
            exact,
            default,
        } => NormalOperand::RangeSwitch(
            ranges
                .into_iter()
                .map(|(low, high, target)| {
                    (value(dmb, low), value(dmb, high), NormalTarget::Raw(target))
                })
                .collect(),
            exact
                .into_iter()
                .map(|(v, target)| (value(dmb, v), NormalTarget::Raw(target)))
                .collect(),
            NormalTarget::Raw(default),
        ),
    }
}

fn instruction(
    dmb: &Dmb,
    input: &bytecode::Instruction,
) -> Result<NormalInstruction, bytecode::DecodeError> {
    if input.opcode == 0x50 {
        // Dream Maker may use PushInt for a whole number where another build
        // emits the equivalent floating point PushVal.
        let integer = input.operands[0] as u16;
        return Ok(NormalInstruction {
            opcode: 0x60,
            operands: vec![NormalOperand::Value(NormalValue::Number(
                (integer as f32).to_bits(),
            ))],
        });
    }
    let mut operands = input
        .typed_operands()?
        .into_iter()
        .map(|item| operand(dmb, item))
        .collect::<Vec<_>>();
    if matches!(input.opcode, 0x2 | 0x4 | 0x84) {
        // Format, OutputFormat, and DbgFile carry a StringID first.
        if let Some(NormalOperand::Word(id)) = operands.first() {
            operands[0] = NormalOperand::String(bytes(dmb, *id));
        }
    }
    let proc_operand = match input.opcode {
        0x30 => Some(1), // CallGlob: argument count, ProcID.
        0xcd => Some(0), // CallGlobalArgList: ProcID.
        _ => None,
    };
    if let Some(index) = proc_operand {
        if let Some(NormalOperand::Word(id)) = operands.get(index) {
            if let Some(path) = proc_path(dmb, *id) {
                operands[index] = NormalOperand::Proc(Some(path));
            }
        }
    }
    Ok(NormalInstruction {
        opcode: input.opcode,
        operands,
    })
}

fn compare_code(a: &Dmb, ai: usize, b: &Dmb, bi: usize, name: &str, out: &mut Collector) {
    compare_code_options(a, ai, b, bi, name, out, false);
}

fn compare_code_options(
    a: &Dmb,
    ai: usize,
    b: &Dmb,
    bi: usize,
    name: &str,
    out: &mut Collector,
    ignore_debug: bool,
) {
    let acode = a.proc_code_words(ai).unwrap_or_default();
    let bcode = b.proc_code_words(bi).unwrap_or_default();
    let (left, right) = match (bytecode::decode(acode), bytecode::decode(bcode)) {
        (Ok(left), Ok(right)) => (left, right),
        (left, right) => {
            out.add(name, "bytecode.decode", left.err(), right.err());
            return;
        }
    };
    let offsets = |instructions: &[bytecode::Instruction], end: usize| {
        let mut map = BTreeMap::new();
        let mut index = 0;
        for instruction in instructions {
            map.insert(instruction.offset, index);
            if !ignore_debug || !matches!(instruction.opcode, 0x84 | 0x85) {
                index += 1;
            }
        }
        map.insert(end, index);
        map
    };
    let left_offsets = offsets(&left, acode.len());
    let right_offsets = offsets(&right, bcode.len());
    let left = left
        .into_iter()
        .filter(|item| !ignore_debug || !matches!(item.opcode, 0x84 | 0x85))
        .collect::<Vec<_>>();
    let right = right
        .into_iter()
        .filter(|item| !ignore_debug || !matches!(item.opcode, 0x84 | 0x85))
        .collect::<Vec<_>>();
    out.check(name, "bytecode.instruction_count", left.len(), right.len());
    for (index, (a_instruction, b_instruction)) in left.iter().zip(right.iter()).enumerate() {
        if out.full() {
            break;
        }
        let (Ok(mut a_instruction), Ok(mut b_instruction)) =
            (instruction(a, a_instruction), instruction(b, b_instruction))
        else {
            out.add(
                name,
                &format!("bytecode[{index}].operands"),
                &a_instruction.operands,
                &b_instruction.operands,
            );
            continue;
        };
        for (normalized, targets) in [
            (&mut a_instruction, &left_offsets),
            (&mut b_instruction, &right_offsets),
        ] {
            normalize_instruction_targets(normalized, targets);
        }
        out.check(
            name,
            &format!("bytecode[{index}].opcode"),
            a_instruction.opcode,
            b_instruction.opcode,
        );
        out.check(
            name,
            &format!("bytecode[{index}].operands"),
            a_instruction.operands,
            b_instruction.operands,
        );
    }
}

/// Compare one paired procedure without traversing unrelated tables.
pub fn compare_proc_code(
    expected: &Dmb,
    expected_id: usize,
    actual: &Dmb,
    actual_id: usize,
    name: &str,
    limit: usize,
    ignore_debug: bool,
) -> Vec<Discrepancy> {
    let mut out = Collector {
        output: Vec::new(),
        limit,
    };
    compare_code_options(
        expected,
        expected_id,
        actual,
        actual_id,
        name,
        &mut out,
        ignore_debug,
    );
    out.output
}

fn compare_proc(
    expected: &Dmb,
    actual: &Dmb,
    ids: (usize, usize),
    name: &str,
    options: &CompareOptions,
    compare_sources: bool,
    out: &mut Collector,
) {
    let (ai, bi) = ids;
    let left = &expected.procs[ai];
    let right = &actual.procs[bi];
    out.check(
        name,
        "proc.display",
        optional_proc_string(expected, left.strings[1]),
        optional_proc_string(actual, right.strings[1]),
    );
    out.check(
        name,
        "proc.description",
        optional_proc_string(expected, left.strings[2]),
        optional_proc_string(actual, right.strings[2]),
    );
    out.check(
        name,
        "proc.category",
        optional_proc_string(expected, left.strings[3]),
        optional_proc_string(actual, right.strings[3]),
    );
    out.check(
        name,
        "proc.source",
        left.source_location(),
        right.source_location(),
    );
    out.check(
        name,
        "proc.flags",
        left.effective_flags(),
        right.effective_flags(),
    );
    out.check(
        name,
        "proc.invisibility",
        left.invisibility_setting(),
        right.invisibility_setting(),
    );
    let arguments = |dmb: &Dmb, id| {
        dmb.proc_arguments(id)
            .unwrap_or_default()
            .iter()
            .map(|arg| argument(dmb, arg))
            .collect::<Vec<_>>()
    };
    out.check(
        name,
        "proc.arguments",
        arguments(expected, ai),
        arguments(actual, bi),
    );
    if compare_sources {
        for (index, (left_arg, right_arg)) in expected
            .proc_arguments(ai)
            .unwrap_or_default()
            .iter()
            .zip(actual.proc_arguments(bi).unwrap_or_default().iter())
            .enumerate()
        {
            match (
                expected.argument_source_proc_id(left_arg),
                actual.argument_source_proc_id(right_arg),
            ) {
                (Some(left_id), Some(right_id)) => compare_proc(
                    expected,
                    actual,
                    (left_id as usize, right_id as usize),
                    &format!("{name}::<argument {index} source>"),
                    options,
                    false,
                    out,
                ),
                (None, None) => {}
                (left, right) => out.add(
                    name,
                    &format!("argument[{index}].source_presence"),
                    left.is_some(),
                    right.is_some(),
                ),
            }
        }
    }
    let locals = |dmb: &Dmb, proc_: &crate::dmb::Proc| {
        dmb.lists
            .get(proc_.code_locals_args[1] as usize)
            .into_iter()
            .flatten()
            .map(|&id| {
                dmb.variables
                    .get(id as usize)
                    .and_then(|v| bytes(dmb, v.name))
            })
            .collect::<Vec<_>>()
    };
    out.check(
        name,
        "proc.locals",
        locals(expected, left),
        locals(actual, right),
    );
    if options.compare_bytecode {
        compare_code(expected, ai, actual, bi, name, out);
    }
}

fn compare_initializer(
    expected: &Dmb,
    ai: u32,
    actual: &Dmb,
    bi: u32,
    name: &str,
    options: &CompareOptions,
    out: &mut Collector,
) {
    let a = expected.procs.get(ai as usize);
    let b = actual.procs.get(bi as usize);
    match (a, b) {
        (None, None) => {}
        (Some(_), Some(_)) => compare_proc(
            expected,
            actual,
            (ai as usize, bi as usize),
            name,
            options,
            true,
            out,
        ),
        _ => out.add(name, "proc.presence", a.is_some(), b.is_some()),
    }
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
    };
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
            compare_initializer(
                expected,
                left.initializer_proc_id(),
                actual,
                right.initializer_proc_id(),
                &format!("{name}::<init>"),
                options,
                &mut out,
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
            &mut out,
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
        for (&ai, &bi) in a.iter().zip(b) {
            compare_proc(expected, actual, (ai, bi), &name, options, true, &mut out);
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
        compare_world(expected, actual, &mut out);
        compare_mob_types(expected, actual, &mut out);
        compare_global_declarations(expected, actual, &mut out);
        out.check(
            "/markers",
            "hidden_initializer_identity",
            marker_integrity(expected),
            marker_integrity(actual),
        );
    }
    out.output
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

fn map_instance(dmb: &Dmb, id: u32) -> Option<(u8, Option<Vec<u8>>, bool)> {
    dmb.instances.get(id as usize).map(|instance| {
        let class = if instance.kind == 8 {
            dmb.mobs.get(instance.class as usize).map(|mob| mob.class)
        } else {
            Some(instance.class)
        };
        (
            instance.kind,
            class.and_then(|id| path(dmb, id)),
            instance.initializer != 0xffff,
        )
    })
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum MapConstant {
    Value(NormalValue),
    List(Vec<Self>),
    Assoc(Vec<(Self, Self)>),
}

/// Decode only straight-line constant map override assignments. A procedure
/// with branches, calls, reads, or other effects is left to strict bytecode
/// comparison, since reordering those operations may change behavior.
fn constant_map_assignments(dmb: &Dmb, proc_id: u32) -> Option<BTreeMap<Vec<u8>, MapConstant>> {
    let code = dmb.proc_code_words(proc_id as usize)?;
    let instructions = bytecode::decode(code).ok()?;
    let mut stack = Vec::<MapConstant>::new();
    let mut assignments = BTreeMap::new();
    for instruction in instructions {
        match instruction.opcode {
            0x84 | 0x85 => {}
            0x50 => stack.push(MapConstant::Value(NormalValue::Number(
                (instruction.operands.first().copied()? as u16 as f32).to_bits(),
            ))),
            0x60 => {
                let Operand::Value(raw) = instruction.typed_operands().ok()?.into_iter().next()?
                else {
                    return None;
                };
                // Nested modified types and hidden runtime initializer values
                // need graph-aware comparison. Avoid recursive cycles and keep
                // their owning initializer opaque instead of dropping identity.
                if matches!(
                    raw.kind(),
                    ValueKind::InstanceTypePath | ValueKind::HiddenInitializer
                ) {
                    return None;
                }
                stack.push(MapConstant::Value(value(dmb, raw)));
            }
            0x19 => stack.push(MapConstant::List(Vec::new())),
            0x1a | 0xc8 | 0x17c => {
                let count = instruction.operands.first().copied()? as usize;
                let width = if instruction.opcode == 0x1a { 1 } else { 2 };
                let start = stack.len().checked_sub(count.checked_mul(width)?)?;
                let entries = stack.split_off(start);
                if width == 1 {
                    stack.push(MapConstant::List(entries));
                } else {
                    stack.push(MapConstant::Assoc(
                        entries
                            .chunks_exact(2)
                            .map(|pair| (pair[0].clone(), pair[1].clone()))
                            .collect(),
                    ));
                }
            }
            0x34 => {
                let Operand::Variable(target) =
                    instruction.typed_operands().ok()?.into_iter().next()?
                else {
                    return None;
                };
                let mut target = target;
                let name = loop {
                    let Variable::SetCache(owner, field) = target else {
                        return None;
                    };
                    if *owner != Variable::Src {
                        return None;
                    }
                    match *field {
                        Variable::Field(name) => break name,
                        nested @ Variable::SetCache(_, _) => target = nested,
                        _ => return None,
                    }
                };
                assignments.insert(bytes(dmb, name)?, stack.pop()?);
            }
            0 | 0x12 if stack.is_empty() => {}
            _ => return None,
        }
    }
    stack.is_empty().then_some(assignments)
}

/// Diagnostic identity for an instance with only independent constant overrides.
/// This excludes allocation IDs and assignment order, but retains its type,
/// field names, values, and ordered list contents. Effectful initializers return
/// None rather than being treated as equivalent.
pub fn constant_instance_signature(dmb: &Dmb, instance_id: u32) -> Option<String> {
    let instance = dmb.instances.get(instance_id as usize)?;
    let assignments = constant_map_assignments(dmb, instance.initializer)?;
    Some(format!(
        "{:?}:{assignments:?}",
        map_instance(dmb, instance_id)?
    ))
}

/// Read-only diagnostic for a procedure containing independent constant stores.
/// Effectful or unrecognized initializer bodies retain an unknown signature.
pub fn constant_initializer_signature(dmb: &Dmb, proc_id: u32) -> Option<String> {
    Some(format!("{:?}", constant_map_assignments(dmb, proc_id)?))
}

#[allow(clippy::too_many_arguments)]
fn compare_map_instance(
    expected: &Dmb,
    left: u32,
    actual: &Dmb,
    right: u32,
    name: &str,
    independent_constants: bool,
    seen: &mut BTreeSet<(u32, u32)>,
    out: &mut Collector,
) {
    out.check(
        name,
        "instance",
        map_instance(expected, left),
        map_instance(actual, right),
    );
    let (Some(a), Some(b)) = (
        expected.instances.get(left as usize),
        actual.instances.get(right as usize),
    ) else {
        return;
    };
    if a.initializer != 0xffff
        && b.initializer != 0xffff
        && seen.insert((a.initializer, b.initializer))
    {
        match (
            independent_constants.then(|| constant_map_assignments(expected, a.initializer)),
            independent_constants.then(|| constant_map_assignments(actual, b.initializer)),
        ) {
            (Some(Some(left)), Some(Some(right))) => out.check(
                &format!("{name}::<instance init>"),
                "constant_assignments",
                left,
                right,
            ),
            _ => compare_initializer(
                expected,
                a.initializer,
                actual,
                b.initializer,
                &format!("{name}::<instance init>"),
                &CompareOptions::default(),
                out,
            ),
        }
    }
}

/// Compare decoded map cells and objects by linear coordinate, resolving
/// instance and class IDs. Anonymous map override initializers are paired by
/// their first shared cell or object and compared once per procedure pair.
fn compare_maps_mode(
    expected: &Dmb,
    actual: &Dmb,
    max_discrepancies: usize,
    independent_constants: bool,
) -> Vec<Discrepancy> {
    let mut out = Collector {
        output: Vec::new(),
        limit: max_discrepancies,
    };
    out.check("/map", "dimensions", expected.dimensions, actual.dimensions);
    let expand = |dmb: &Dmb| {
        dmb.grid
            .iter()
            .flat_map(|run| {
                std::iter::repeat_n((run.turf, run.area, run.contents), run.copies as usize)
            })
            .collect::<Vec<_>>()
    };
    let left = expand(expected);
    let right = expand(actual);
    out.check("/map", "cell_count", left.len(), right.len());
    let mut seen = BTreeSet::new();
    let coordinate = |index: usize| format!("/map/flat#{index}");
    for (index, (&a, &b)) in left.iter().zip(&right).enumerate() {
        if out.full() {
            break;
        }
        let name = coordinate(index);
        compare_map_instance(
            expected,
            a.0,
            actual,
            b.0,
            &format!("{name}/turf"),
            independent_constants,
            &mut seen,
            &mut out,
        );
        compare_map_instance(
            expected,
            a.1,
            actual,
            b.1,
            &format!("{name}/area"),
            independent_constants,
            &mut seen,
            &mut out,
        );
        out.check(&name, "contents_presence", a.2 != 0xffff, b.2 != 0xffff);
        if a.2 != 0xffff && b.2 != 0xffff {
            out.add(
                &name,
                "contents",
                "unverified nonempty list",
                "unverified nonempty list",
            );
        }
    }
    let objects = |dmb: &Dmb| {
        let mut at = 0usize;
        dmb.map_objects
            .iter()
            .map(|object| {
                at += usize::from(object.offset);
                (at, object.instance)
            })
            .collect::<Vec<_>>()
    };
    let left = objects(expected);
    let right = objects(actual);
    out.check("/map", "object_count", left.len(), right.len());
    if independent_constants {
        let grouped = |objects: Vec<(usize, u32)>, dmb: &Dmb| {
            let mut cells = BTreeMap::<usize, Vec<u32>>::new();
            for (cell, instance) in objects {
                cells.entry(cell).or_default().push(instance);
            }
            for instances in cells.values_mut() {
                instances.sort_by_key(|&id| map_instance(dmb, id));
            }
            cells
        };
        let left = grouped(left, expected);
        let right = grouped(right, actual);
        for cell in left
            .keys()
            .chain(right.keys())
            .copied()
            .collect::<BTreeSet<_>>()
        {
            if out.full() {
                break;
            }
            let a = left.get(&cell).map(Vec::as_slice).unwrap_or_default();
            let b = right.get(&cell).map(Vec::as_slice).unwrap_or_default();
            out.check(&coordinate(cell), "object_count", a.len(), b.len());
            for (index, (&a, &b)) in a.iter().zip(b).enumerate() {
                compare_map_instance(
                    expected,
                    a,
                    actual,
                    b,
                    &format!("{}/object[{index}]", coordinate(cell)),
                    true,
                    &mut seen,
                    &mut out,
                );
            }
        }
    } else {
        for (index, (&a, &b)) in left.iter().zip(&right).enumerate() {
            if out.full() {
                break;
            }
            out.check("/map", &format!("object[{index}].cell"), a.0, b.0);
            compare_map_instance(
                expected,
                a.1,
                actual,
                b.1,
                &format!("/map/object[{index}]"),
                false,
                &mut seen,
                &mut out,
            );
        }
    }
    out.output
}

/// Strictly compare map instance initializer metadata and bytecode order.
pub fn compare_maps(expected: &Dmb, actual: &Dmb, max_discrepancies: usize) -> Vec<Discrepancy> {
    compare_maps_mode(expected, actual, max_discrepancies, false)
}

/// Treat independent constant writes to distinct map fields as equivalent
/// regardless of instruction order. Complex initializers still compare
/// strictly, so this never hides calls, reads, or branches.
pub fn compare_maps_semantic(
    expected: &Dmb,
    actual: &Dmb,
    max_discrepancies: usize,
) -> Vec<Discrepancy> {
    compare_maps_mode(expected, actual, max_discrepancies, true)
}

#[cfg(test)]
mod tests {
    #[test]
    fn procedure_alignment_groups_insertions_and_keeps_operand_changes() {
        let code = |items: &[(u32, &str)]| {
            items
                .iter()
                .enumerate()
                .map(|(ordinal, (opcode, operands))| ProcedureInstruction {
                    ordinal,
                    wire_offset: ordinal,
                    opcode: *opcode,
                    operands: (*operands).into(),
                })
                .collect::<Vec<_>>()
        };
        let expected = code(&[
            (0x33, "events"),
            (0x33, "at"),
            (0x7b, ""),
            (0x34, "Local10"),
            (0x12, ""),
        ]);
        let actual = code(&[
            (0x50, "selector"),
            (0x34, "Local8"),
            (0x33, "events"),
            (0x33, "at"),
            (0x7b, ""),
            (0x34, "Local11"),
            (0x12, ""),
        ]);
        let result = align_procedure_instructions(&expected, &actual, 8);
        assert_eq!(result.changed_regions, 2);
        assert_eq!(result.matched_opcodes, 5);
        assert_eq!(result.hunks[0].expected_unpaired, 0);
        assert_eq!(result.hunks[0].actual_unpaired, 2);
        assert_eq!(result.hunks[1].paired_operand_changes, 1);
        assert!(!result.hunks_truncated);
        assert_eq!(
            align_procedure_instructions(&expected, &actual, 1).changed_regions,
            2
        );
        assert!(align_procedure_instructions(&expected, &actual, 1).hunks_truncated);
    }

    #[test]
    fn procedure_alignment_bounds_quadratic_work() {
        let mut expected = vec![
            ProcedureInstruction {
                ordinal: 0,
                wire_offset: 0,
                opcode: 0x33,
                operands: "events".into()
            };
            1_100
        ];
        let mut actual = expected.clone();
        expected[500].operands = "Local10".into();
        actual[500].operands = "Local11".into();
        let result = align_procedure_instructions(&expected, &actual, 8);
        assert!(result.work_limit_exceeded);
        assert_eq!(result.changed_regions, 1);
        assert_eq!(result.hunks[0].expected_start, 500);
        assert_eq!(result.hunks[0].expected_end, 501);
        assert_eq!(result.matched_opcodes, 1_099);
    }

    #[test]
    fn procedure_snapshot_normalizes_targets_and_rejects_missing_code() {
        let mut expected = template();
        let mut actual = expected.clone();
        expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
        expected.lists.push(vec![0x50, 2, 0xf, 6, 0x85, 7, 0x12]);
        actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
        actual.lists.push(vec![0x60, 42, 0x4000, 0, 0xf, 6, 0x12]);
        let left = procedure_instructions(&expected, 0, true).unwrap();
        let right = procedure_instructions(&actual, 0, true).unwrap();
        assert_eq!(left.len(), right.len());
        assert!(left
            .iter()
            .zip(&right)
            .all(|(a, b)| a.opcode == b.opcode && a.operands == b.operands));
        assert_ne!(left[1].wire_offset, right[1].wire_offset);
        assert!(compare_proc_code(&expected, 0, &actual, 0, "/probe", 32, true).is_empty());
        assert!(procedure_instructions(&actual, usize::MAX, true).is_err());
        actual.procs[0].code_locals_args[0] = u32::MAX;
        assert!(procedure_instructions(&actual, 0, true).is_err());
    }

    #[test]
    fn procedure_snapshot_resolves_string_ids_and_keeps_index_arithmetic() {
        let mut expected = template();
        let name = expected.strings.len() as u32;
        expected.strings.push(crate::dmb::DmString {
            data: b"power_regions".to_vec(),
            long_chunks: 0,
        });
        let code = expected.lists.len() as u32;
        expected.procs[0].code_locals_args[0] = code;
        expected
            .lists
            .push(vec![0x33, 0xffdc, 0xffce, name, 0x50, 3, 0x7b, 0x12]);
        let mut actual = expected.clone();
        actual.strings.push(actual.strings[name as usize].clone());
        actual.lists[code as usize][3] = (actual.strings.len() - 1) as u32;
        let left = procedure_instructions(&expected, 0, true).unwrap();
        assert_eq!(left, procedure_instructions(&actual, 0, true).unwrap());
        actual.lists[code as usize][5] = 4;
        assert_ne!(left, procedure_instructions(&actual, 0, true).unwrap());
    }

    #[test]
    fn duplicate_proc_pairing_uses_bindings_and_detects_body_swaps() {
        let native = Dmb::from_bytes(include_bytes!(
            "../fixtures/translation/procedure_membership_order.native.bin"
        ))
        .unwrap();
        let index = proc_index(&native, &CompareOptions::default());
        let (path, group) = index
            .iter()
            .find(|(_, ids)| {
                ids.len() > 1 && ids.iter().all(|&id| native.procs[id].strings[0] != 0xffff)
            })
            .expect("paired duplicate path");
        let mut reversed = group.clone();
        reversed.reverse();
        order_proc_group_by_binding(&native, &mut reversed);
        assert_eq!(&reversed, group);
        let mut corrupted = native.clone();
        let first = group[0];
        let second = group[1];
        let left = corrupted.procs[first].code_locals_args;
        corrupted.procs[first].code_locals_args = corrupted.procs[second].code_locals_args;
        corrupted.procs[second].code_locals_args = left;
        let discrepancies = compare_dmbs(&native, &corrupted, &CompareOptions::default());
        assert!(
            discrepancies
                .iter()
                .any(|difference| difference.path.as_bytes() == path.as_slice()
                    && (difference.field.contains("arguments")
                        || difference.field.contains("locals")
                        || difference.field.contains("bytecode"))),
            "{discrepancies:#?}"
        );
    }
    #[test]
    fn shared_marker_tokens_do_not_hide_constructor_aliasing() {
        let native = Dmb::from_bytes(include_bytes!(
            "../fixtures/translation/marker_tokens.native.bin"
        ))
        .unwrap();
        let field = |name: &[u8]| {
            native
                .variables
                .iter()
                .position(|variable| native.string(variable.name) == Some(name))
                .unwrap()
        };
        let a = field(b"a");
        let b = field(b"b");
        let x = field(b"x");
        let d = field(b"d");
        let e = field(b"e");
        assert_eq!(native.variables[a].value, native.variables[x].value);
        assert_ne!(native.variables[a].value, native.variables[b].value);
        assert_eq!(native.variables[d].value, native.variables[e].value);
        let id = native.world.ids[4] as usize;
        let code_id = native.procs[id].code_locals_args[0] as usize;
        let code = native.proc_code_words(id).unwrap();
        let instructions = crate::bytecode::decode(code).unwrap();
        let constructors: Vec<_> = instructions
            .iter()
            .filter(|instruction| instruction.opcode == 1)
            .collect();
        assert!(constructors.len() >= 2);
        let mut aliased = native.clone();
        let offset = constructors[1].offset;
        aliased.lists[code_id].splice(offset..offset + 2, [0x33, 0xffdb, a as u32]);
        assert_eq!(marker_integrity(&native), marker_integrity(&aliased));
        assert!(
            !compare_proc_code(&native, id, &aliased, id, "global initializer", 100, true)
                .is_empty()
        );
    }
    #[test]
    fn authored_proc_marker_is_canonicalized_for_identity() {
        assert_eq!(
            super::canonical_proc_path(b"/area/proc/Adjacent".to_vec()),
            b"/area/Adjacent"
        );
        assert_eq!(
            super::canonical_proc_path(b"/proc/global_proc".to_vec()),
            b"/proc/global_proc"
        );
        assert_eq!(
            super::canonical_proc_path(b"/mob/verb/whisper".to_vec()),
            b"/mob/whisper"
        );
    }
    use super::*;

    fn template() -> Dmb {
        Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap()
    }

    #[test]
    fn procedure_and_verb_selectors_are_not_field_reads() {
        let dmb = template();
        let selectors = [
            Variable::Field(0),
            Variable::DynamicProc(0),
            Variable::DynamicVerb(0),
            Variable::StaticProc(0),
            Variable::StaticVerb(0),
        ];
        for (index, left) in selectors.iter().enumerate() {
            for right in &selectors[index + 1..] {
                if matches!(
                    (left, right),
                    (Variable::DynamicProc(_), Variable::StaticProc(_))
                        | (Variable::DynamicVerb(_), Variable::StaticVerb(_))
                ) {
                    continue;
                }
                assert_ne!(variable(&dmb, left), variable(&dmb, right));
            }
        }
    }

    #[test]
    fn static_proc_normalization_requires_its_actual_display_name() {
        let mut dmb = template();
        let display = dmb.strings.len() as u32;
        dmb.strings.push(crate::dmb::DmString {
            data: b"Actual Display".to_vec(),
            long_chunks: 0,
        });
        let wrong = dmb.strings.len() as u32;
        dmb.strings.push(crate::dmb::DmString {
            data: b"identifier_only".to_vec(),
            long_chunks: 0,
        });
        dmb.procs[0].strings[1] = display;
        assert_eq!(
            variable(&dmb, &Variable::StaticProc(0)),
            variable(&dmb, &Variable::DynamicProc(display))
        );
        assert_ne!(
            variable(&dmb, &Variable::StaticProc(0)),
            variable(&dmb, &Variable::DynamicProc(wrong))
        );
        assert_ne!(
            variable(&dmb, &Variable::StaticProc(0)),
            variable(&dmb, &Variable::StaticVerb(0))
        );
        dmb.procs[0].strings[1] = 0xffff;
        assert_ne!(
            variable(&dmb, &Variable::StaticProc(0)),
            variable(&dmb, &Variable::DynamicProc(0xffff))
        );
    }

    #[test]
    fn static_verb_normalization_preserves_namespace_and_actual_display_name() {
        let mut dmb = template();
        let display = dmb.strings.len() as u32;
        dmb.strings.push(crate::dmb::DmString {
            data: b"Shared Alias".to_vec(),
            long_chunks: 0,
        });
        let wrong = dmb.strings.len() as u32;
        dmb.strings.push(crate::dmb::DmString {
            data: b"identifier_only".to_vec(),
            long_chunks: 0,
        });
        dmb.procs[0].strings[1] = display;
        assert_eq!(
            variable(&dmb, &Variable::StaticVerb(0)),
            variable(&dmb, &Variable::DynamicVerb(display))
        );
        for other in [
            Variable::DynamicVerb(wrong),
            Variable::DynamicProc(display),
            Variable::StaticProc(0),
        ] {
            assert_ne!(
                variable(&dmb, &Variable::StaticVerb(0)),
                variable(&dmb, &other)
            );
        }
        dmb.procs[0].strings[1] = 0xffff;
        assert_ne!(
            variable(&dmb, &Variable::StaticVerb(0)),
            variable(&dmb, &Variable::DynamicVerb(0xffff))
        );
        assert_ne!(
            variable(&dmb, &Variable::StaticVerb(u32::MAX)),
            variable(&dmb, &Variable::DynamicVerb(0xffff))
        );
    }

    #[test]
    fn colliding_display_aliases_follow_native_dynamic_call_encoding() {
        let native = Dmb::from_bytes(include_bytes!(
            "../fixtures/lowering/selector_alias_collision.bin"
        ))
        .unwrap();
        let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
            "../fixtures/lowering/selector_alias_collision.json"
        ))
        .unwrap();
        let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
            "../fixtures/native_template_savefile_5161687.json"
        ))
        .unwrap();
        let emitted = crate::translate::translate_named_debug(
            &input,
            &baseline,
            &template(),
            std::path::Path::new("fixtures/lowering"),
            Some("selector_alias_collision"),
            false,
        )
        .unwrap();
        for name in ["/proc/selector_call_first", "/proc/selector_call_second"] {
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(name.as_bytes()))
                    .unwrap()
            };
            // Receiver cache materialization can introduce extra instructions.
            // This regression checks selector identity and argument count,
            // while the separate receiver tests verify cache timing.
            let call = |dmb: &Dmb, id| {
                let instruction = bytecode::decode(dmb.proc_code_words(id).unwrap())
                    .unwrap()
                    .into_iter()
                    .find(|i| matches!(i.opcode, 0x29 | 0x2a))
                    .unwrap();
                let operands = instruction.typed_operands().unwrap();
                let Operand::Variable(mut selector) = operands[0].clone() else {
                    panic!("call selector missing")
                };
                while let Variable::SetCache(_, right) = selector {
                    selector = *right;
                }
                (
                    instruction.opcode,
                    variable(dmb, &selector),
                    operands[1].clone(),
                )
            };
            assert_eq!(
                call(&native, find(&native)),
                call(&emitted.dmb, find(&emitted.dmb)),
                "{name}"
            );
        }
        let find = |name: &[u8]| {
            native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(name))
                .unwrap()
        };
        assert_eq!(
            native.proc_code_words(find(b"/proc/selector_call_first")),
            native.proc_code_words(find(b"/proc/selector_call_second"))
        );
        assert_eq!(
            native.proc_code_words(find(b"/proc/selector_cached_first")),
            native.proc_code_words(find(b"/proc/selector_cached_second"))
        );
    }

    #[test]
    fn global_call_proc_allocations_resolve_without_erasing_argument_counts() {
        let expected = template();
        let mut actual = expected.clone();
        let relocated = actual.procs.len() as u32;
        actual.procs.push(actual.procs[0].clone());
        for (opcode, native, moved) in [
            (0x30, vec![2, 0], vec![2, relocated]),
            (0xcd, vec![0], vec![relocated]),
        ] {
            let ins = |operands| bytecode::Instruction {
                offset: 0,
                opcode,
                name: "call",
                operands,
            };
            assert_eq!(
                instruction(&expected, &ins(native)).unwrap(),
                instruction(&actual, &ins(moved)).unwrap()
            );
        }
        let ins = |count| bytecode::Instruction {
            offset: 0,
            opcode: 0x30,
            name: "call",
            operands: vec![count, 0],
        };
        assert_ne!(
            instruction(&expected, &ins(2)).unwrap(),
            instruction(&expected, &ins(3)).unwrap()
        );
    }

    #[test]
    fn switch_case_string_allocations_do_not_change_semantics() {
        let expected = template();
        let mut actual = expected.clone();
        let relocated = actual.strings.len() as u32;
        actual.strings.push(actual.strings[0].clone());
        let case = |id| Value {
            tag_word: 6,
            data_word: id,
            extra_word: None,
        };
        assert_eq!(
            operand(
                &expected,
                Operand::Switch {
                    cases: vec![(case(0), 9)],
                    default: 11
                }
            ),
            operand(
                &actual,
                Operand::Switch {
                    cases: vec![(case(relocated), 9)],
                    default: 11
                }
            ),
        );
        assert_eq!(
            operand(
                &expected,
                Operand::RangeSwitch {
                    ranges: vec![],
                    exact: vec![(case(0), 9)],
                    default: 11
                }
            ),
            operand(
                &actual,
                Operand::RangeSwitch {
                    ranges: vec![],
                    exact: vec![(case(relocated), 9)],
                    default: 11
                }
            ),
        );
    }

    #[test]
    fn builtin_type_singletons_do_not_resolve_class_zero() {
        let dmb = template();
        for (tag, name) in [
            (40, b"/list".as_slice()),
            (39, b"/file".as_slice()),
            (36, b"/savefile".as_slice()),
        ] {
            assert_eq!(
                value(
                    &dmb,
                    Value {
                        tag_word: tag,
                        data_word: 0,
                        extra_word: None
                    }
                ),
                NormalValue::Type(tag as u8, Some(name.to_vec())),
            );
        }
    }

    #[test]
    fn modified_type_constants_include_override_values() {
        let mut expected = template();
        let code = expected.lists.len() as u32;
        expected
            .lists
            .push(vec![0x50, 1, 0x34, 0xffdc, 0xffce, 0, 0]);
        expected.procs[0].code_locals_args[0] = code;
        let instance = expected.instances.len() as u32;
        expected.instances.push(crate::dmb::Instance {
            kind: 32,
            class: 0,
            initializer: 0,
        });
        let raw = Value {
            tag_word: 41,
            data_word: instance,
            extra_word: None,
        };
        let mut actual = expected.clone();
        assert_eq!(value(&expected, raw), value(&actual, raw));
        actual.lists[code as usize][1] = 2;
        assert_ne!(value(&expected, raw), value(&actual, raw));
        actual.instances[instance as usize].initializer = 0xffff;
        assert_ne!(value(&expected, raw), value(&actual, raw));
    }

    #[test]
    fn unknown_modified_type_initializers_retain_identity_and_avoid_cycles() {
        let mut dmb = template();
        let instance = dmb.instances.len() as u32;
        let code = dmb.lists.len() as u32;
        dmb.lists
            .push(vec![0x60, 41, instance, 0x34, 0xffdc, 0xffce, 0, 0]);
        dmb.procs[0].code_locals_args[0] = code;
        dmb.instances.push(crate::dmb::Instance {
            kind: 32,
            class: 0,
            initializer: 0,
        });
        let raw = Value {
            tag_word: 41,
            data_word: instance,
            extra_word: None,
        };
        let before = value(&dmb, raw);
        assert!(matches!(
            before,
            NormalValue::InstanceType(_, _, InstanceInitializer::Opaque(_, _))
        ));
        let second = dmb.procs.len() as u32;
        dmb.procs.push(dmb.procs[0].clone());
        dmb.instances[instance as usize].initializer = second;
        assert_ne!(before, value(&dmb, raw));
    }

    #[test]
    fn switch_targets_and_case_values_normalize_across_word_widths() {
        for opcode in [0x78, 0x79, 0x7a] {
            let mut expected = template();
            let mut actual = expected.clone();
            let mut left = vec![0x50, 2, opcode];
            let mut right = vec![0x60, 42, 0x4000, 0, opcode];
            let table = match opcode {
                0x78 => vec![1, 42, 0x4000, 0, 0, 0],
                0x79 => vec![1, 32767, 0, 0],
                0x7a => vec![1, 42, 0, 0, 42, 0x4000, 0, 0, 1, 0, 0, 0, 0],
                _ => unreachable!(),
            };
            left.extend(&table);
            right.extend(table);
            let left_end = left.len() as u32;
            let right_end = right.len() as u32;
            let target_positions: &[usize] = match opcode {
                0x78 => &[4, 5],
                0x79 => &[2, 3],
                0x7a => &[7, 11, 12],
                _ => unreachable!(),
            };
            for &position in target_positions {
                left[3 + position] = left_end;
                right[5 + position] = right_end;
            }
            left.push(0x12);
            right.push(0x12);
            expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
            expected.lists.push(left);
            actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
            actual.lists.push(right);
            assert!(compare_proc_code(&expected, 0, &actual, 0, "/switch", 10, true).is_empty());
            // A changed destination must remain a discrepancy after normalization.
            let code_id = actual.procs[0].code_locals_args[0] as usize;
            actual.lists[code_id][5 + target_positions[0]] = 0;
            assert!(!compare_proc_code(&expected, 0, &actual, 0, "/switch", 10, true).is_empty());
        }
    }

    #[test]
    fn identical_dmb_has_no_discrepancies() {
        let dmb = template();
        assert!(compare_dmbs(&dmb, &dmb, &CompareOptions::default()).is_empty());
    }
    #[test]
    fn dedicated_icon_state_is_checked_by_both_metadata_comparers() {
        let expected = template();
        let mut actual = expected.clone();
        let id = expected
            .classes
            .iter()
            .position(|class| expected.string(class.path_string_id()) == Some(b"/obj" as &[u8]))
            .unwrap();
        let mut state = actual.strings[0].clone();
        state.data = b"changed inherited state".to_vec();
        actual.classes[id].initial_ids[5] = actual.strings.len() as u32;
        actual.strings.push(state);
        let full = compare_dmbs(
            &expected,
            &actual,
            &CompareOptions {
                compare_bytecode: false,
                ..Default::default()
            },
        );
        let tables = compare_class_tables(&expected, &actual, 100);
        for differences in [full, tables] {
            assert!(
                differences.iter().any(|difference| {
                    difference.path == "/obj" && difference.field == "class.header.icon_state"
                }),
                "dedicated appearance slots must not disappear behind matching variable lists"
            );
        }
    }
    #[test]
    fn dedicated_header_ids_are_normalized_but_payload_changes_remain_visible() {
        let mut expected = template();
        let id = expected
            .classes
            .iter()
            .position(|class| expected.string(class.path_string_id()) == Some(b"/obj" as &[u8]))
            .unwrap();
        expected.resources.push(crate::dmb::ResourceRef {
            kind: 6,
            id: 0x1234,
        });
        expected.classes[id].initial_ids[4] = 0;
        let mut actual = expected.clone();
        let old_name = actual.classes[id].name_string_id();
        actual.classes[id].initial_ids[2] = actual.strings.len() as u32;
        actual
            .strings
            .push(actual.strings[old_name as usize].clone());
        actual.resources.push(actual.resources[0].clone());
        actual.classes[id].initial_ids[4] = 1;
        assert!(compare_class_tables(&expected, &actual, 100).is_empty());
        assert!(compare_dmbs(
            &expected,
            &actual,
            &CompareOptions {
                compare_bytecode: false,
                ..Default::default()
            }
        )
        .is_empty());
        actual.resources[1].id ^= 1;
        assert!(compare_class_tables(&expected, &actual, 100)
            .iter()
            .any(|d| d.field == "class.header.icon"));
        actual.resources[1].id ^= 1;
        actual.classes[id].direction ^= 1;
        assert!(compare_class_tables(&expected, &actual, 100)
            .iter()
            .any(|d| d.field == "class.header.direction"));
    }
    #[test]
    fn client_path_is_a_singleton_not_class_zero() {
        let dmb = template();
        let singleton = Value {
            tag_word: 59,
            data_word: 0,
            extra_word: None,
        };
        assert_eq!(
            value(&dmb, singleton),
            NormalValue::Type(59, Some(b"/client".to_vec()))
        );
        let invalid = Value {
            data_word: 9,
            ..singleton
        };
        assert_eq!(value(&dmb, invalid), NormalValue::Raw(invalid));
    }

    #[test]
    fn class_parent_change_uses_logical_path() {
        let expected = template();
        let mut actual = expected.clone();
        let class_id = actual
            .classes
            .iter()
            .position(|c| actual.string(c.path_string_id()) == Some(b"/datum" as &[u8]))
            .unwrap();
        actual.classes[class_id].initial_ids[1] = class_id as u32;
        let diff = compare_dmbs(
            &expected,
            &actual,
            &CompareOptions {
                authored_prefixes: vec!["/datum".into()],
                ..Default::default()
            },
        );
        assert!(diff
            .iter()
            .any(|d| d.path == "/datum" && d.field == "class.parent"));
    }

    #[test]
    fn string_id_allocation_does_not_change_semantic_value() {
        let mut dmb = template();
        let original = dmb.classes[0].path_string_id();
        let copy = dmb.strings[original as usize].clone();
        dmb.strings.push(copy);
        let new_id = (dmb.strings.len() - 1) as u32;
        dmb.classes[0].initial_ids[0] = new_id;
        let reference = template();
        let options = CompareOptions {
            compare_bytecode: false,
            ..Default::default()
        };
        assert!(compare_dmbs(&reference, &dmb, &options).is_empty());
    }

    #[test]
    fn equivalent_integer_pushes_normalize_to_same_float() {
        let dmb = template();
        let compact = bytecode::Instruction {
            offset: 0,
            opcode: 0x50,
            name: "PushInt",
            operands: vec![2],
        };
        let float = bytecode::Instruction {
            offset: 0,
            opcode: 0x60,
            name: "PushVal",
            operands: vec![42, 0x4000, 0],
        };
        assert_eq!(
            instruction(&dmb, &compact).unwrap(),
            instruction(&dmb, &float).unwrap()
        );
    }

    #[test]
    fn compact_integer_normalization_uses_native_unsigned_word() {
        let dmb = template();
        for raw in [65535, 65536, (-26i32) as u32] {
            let compact = bytecode::Instruction {
                offset: 0,
                opcode: 0x50,
                name: "PushInt",
                operands: vec![raw],
            };
            assert_eq!(
                instruction(&dmb, &compact).unwrap(),
                NormalInstruction {
                    opcode: 0x60,
                    operands: vec![NormalOperand::Value(NormalValue::Number(
                        (raw as u16 as f32).to_bits()
                    ))],
                }
            );
        }
    }

    #[test]
    fn format_string_ids_are_resolved() {
        let mut dmb = template();
        let first = dmb.strings.len() as u32;
        dmb.strings.push(crate::dmb::DmString {
            data: b"result [x]".to_vec(),
            long_chunks: 0,
        });
        let second = dmb.strings.len() as u32;
        dmb.strings.push(dmb.strings[first as usize].clone());
        let left = bytecode::Instruction {
            offset: 0,
            opcode: 0x4,
            name: "OutputFormat",
            operands: vec![first, 1],
        };
        let right = bytecode::Instruction {
            offset: 0,
            opcode: 0x4,
            name: "OutputFormat",
            operands: vec![second, 1],
        };
        assert_eq!(
            instruction(&dmb, &left).unwrap(),
            instruction(&dmb, &right).unwrap()
        );
    }

    #[test]
    fn debug_file_string_ids_are_resolved() {
        let mut dmb = template();
        let first = dmb.strings.len() as u32;
        dmb.strings.push(crate::dmb::DmString {
            data: b"fixture.dm".to_vec(),
            long_chunks: 0,
        });
        let second = dmb.strings.len() as u32;
        dmb.strings.push(dmb.strings[first as usize].clone());
        let make = |id| bytecode::Instruction {
            offset: 0,
            opcode: 0x84,
            name: "DbgFile",
            operands: vec![id],
        };
        assert_eq!(
            instruction(&dmb, &make(first)).unwrap(),
            instruction(&dmb, &make(second)).unwrap()
        );
    }

    #[test]
    fn class_initializer_is_compared_by_class_path() {
        let mut expected = template();
        let class_id = expected
            .classes
            .iter()
            .position(|class| expected.string(class.path_string_id()) == Some(b"/datum" as &[u8]))
            .unwrap();
        expected.classes[class_id].lists_and_procs[2] = 0;
        let mut actual = expected.clone();
        actual.procs[0].flags ^= 1;
        let options = CompareOptions {
            authored_prefixes: vec!["/datum".into()],
            compare_bytecode: false,
            ..Default::default()
        };
        let differences = compare_dmbs(&expected, &actual, &options);
        assert!(differences
            .iter()
            .any(|item| item.path == "/datum::<init>" && item.field == "proc.flags"));
        let table_differences = compare_proc_tables(&expected, &actual, 100);
        assert!(table_differences
            .iter()
            .any(|item| item.path == "/datum::<init>" && item.field == "proc.flags"));
    }

    #[test]
    fn branch_targets_normalize_across_instruction_widths() {
        let mut expected = template();
        let mut actual = expected.clone();
        expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
        expected.lists.push(vec![0x50, 2, 0xf, 4, 0x12]);
        actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
        actual.lists.push(vec![0x60, 42, 0x4000, 0, 0xf, 6, 0x12]);
        let mut collector = Collector {
            output: Vec::new(),
            limit: 10,
        };
        compare_code(&expected, 0, &actual, 0, "/test", &mut collector);
        assert!(collector.output.is_empty(), "{:?}", collector.output);
    }

    #[test]
    fn spawn_targets_normalize_without_masking_different_destinations() {
        let mut expected = template();
        let mut actual = expected.clone();
        expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
        expected.lists.push(vec![0x50, 2, 0x25, 4, 0x12, 0]);
        actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
        actual
            .lists
            .push(vec![0x60, 42, 0x4000, 0, 0x25, 6, 0x12, 0]);
        assert!(compare_proc_code(&expected, 0, &actual, 0, "/test", 10, false).is_empty());
        let code_id = actual.procs[0].code_locals_args[0] as usize;
        actual.lists[code_id][5] = 7;
        assert!(!compare_proc_code(&expected, 0, &actual, 0, "/test", 10, false).is_empty());
    }

    #[test]
    fn debug_markers_can_be_ignored_without_losing_jump_targets() {
        let mut expected = template();
        let mut actual = expected.clone();
        expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
        expected
            .lists
            .push(vec![0x85, 7, 0x50, 2, 0xf, 6, 0x85, 8, 0x12]);
        actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
        actual.lists.push(vec![0x60, 42, 0x4000, 0, 0xf, 6, 0x12]);
        assert!(compare_proc_code(&expected, 0, &actual, 0, "/test", 10, true).is_empty());
        assert!(!compare_proc_code(&expected, 0, &actual, 0, "/test", 10, false).is_empty());
    }

    #[test]
    fn try_catch_targets_normalize_across_instruction_widths() {
        let mut expected = template();
        let mut actual = expected.clone();
        expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
        expected
            .lists
            .push(vec![0x50, 2, 0x12c, 4, 0x12e, 8, 0x12f, 8, 0x12]);
        actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
        actual.lists.push(vec![
            0x60, 42, 0x4000, 0, 0x12c, 6, 0x12e, 10, 0x12f, 10, 0x12,
        ]);
        let mut collector = Collector {
            output: Vec::new(),
            limit: 10,
        };
        compare_code(&expected, 0, &actual, 0, "/test", &mut collector);
        assert!(collector.output.is_empty(), "{:?}", collector.output);
    }

    #[test]
    fn safe_reference_jump_targets_normalize_across_instruction_widths() {
        let mut expected = template();
        let mut actual = expected.clone();
        expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
        expected.lists.push(vec![0x50, 2, 0x13e, 4, 0x12]);
        actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
        actual.lists.push(vec![0x60, 42, 0x4000, 0, 0x13e, 6, 0x12]);
        let mut collector = Collector {
            output: Vec::new(),
            limit: 10,
        };
        compare_code(&expected, 0, &actual, 0, "/test", &mut collector);
        assert!(collector.output.is_empty(), "{:?}", collector.output);
    }

    #[test]
    fn weighted_pick_targets_normalize_across_instruction_widths() {
        let mut expected = template();
        let mut actual = expected.clone();
        expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
        expected.lists.push(vec![0x50, 10, 0xb1, 2, 6, 7, 0x12, 0]);
        actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
        actual
            .lists
            .push(vec![0x60, 42, 0x4120, 0, 0xb1, 2, 8, 9, 0x12, 0]);
        let mut collector = Collector {
            output: Vec::new(),
            limit: 10,
        };
        compare_code(&expected, 0, &actual, 0, "/test", &mut collector);
        assert!(collector.output.is_empty(), "{:?}", collector.output);
    }

    #[test]
    fn selected_path_count_detects_empty_filter() {
        let dmb = template();
        let missing = CompareOptions {
            authored_prefixes: vec!["does_not_exist".into()],
            ..Default::default()
        };
        assert_eq!(selected_path_count(&dmb, &missing), 0);
        let present = CompareOptions {
            authored_prefixes: vec!["/datum".into()],
            ..Default::default()
        };
        assert!(selected_path_count(&dmb, &present) > 0);
    }

    #[test]
    fn world_settings_are_compared_without_raw_string_ids() {
        let expected = template();
        let mut actual = expected.clone();
        let old_name = actual.world.name_string_id();
        actual
            .strings
            .push(actual.strings[old_name as usize].clone());
        actual.world.ids[6] = (actual.strings.len() - 1) as u32;
        let options = CompareOptions {
            compare_bytecode: false,
            ..Default::default()
        };
        assert!(compare_dmbs(&expected, &actual, &options).is_empty());

        actual.world.tick_lag += 1;
        let differences = compare_dmbs(&expected, &actual, &options);
        assert!(differences
            .iter()
            .any(|item| item.path == "/world" && item.field == "numeric_settings"));
    }

    #[test]
    fn global_declaration_flags_are_compared() {
        let expected = template();
        let mut actual = expected.clone();
        let footer = actual.variable_footer as usize;
        assert!(actual.lists[footer].len() >= 2);
        actual.lists[footer][1] ^= 2;
        let differences = compare_dmbs(
            &expected,
            &actual,
            &CompareOptions {
                compare_bytecode: false,
                ..Default::default()
            },
        );
        assert!(differences
            .iter()
            .any(|item| item.path.starts_with("/globals/") && item.field == "declaration"));
        let class_differences = compare_class_tables(&expected, &actual, 100);
        assert!(class_differences
            .iter()
            .any(|item| item.path.starts_with("/globals/") && item.field == "declaration"));
    }

    #[test]
    fn mob_visibility_records_are_compared() {
        let expected = template();
        let mut actual = expected.clone();
        assert!(!actual.mobs.is_empty());
        actual.mobs[0].sight ^= 1;
        let differences = compare_dmbs(
            &expected,
            &actual,
            &CompareOptions {
                compare_bytecode: false,
                ..Default::default()
            },
        );
        assert!(differences.iter().any(|item| item.field == "mob.record"));
    }

    #[test]
    fn anonymous_argument_source_expression_code_is_compared() {
        let mut expected = template();
        let empty_args = expected.lists.len() as u32;
        expected.lists.push(Vec::new());
        let argument_list = expected.lists.len() as u32;
        expected.lists.push(vec![0, 0x40, 0, 0]);
        expected.procs[0].code_locals_args[2] = argument_list;
        let expression_code = expected.lists.len() as u32;
        expected.lists.push(vec![0x50, 1, 0x12]);
        let mut expression = expected.procs[0].clone();
        expression.strings = [0xffff; 4];
        expression.code_locals_args[0] = expression_code;
        expression.code_locals_args[2] = empty_args;
        let expression_id = expected.procs.len() as u32;
        expected.procs.push(expression);
        expected.proc_references.push(expression_id);
        let mut actual = expected.clone();
        actual.lists[expression_code as usize][1] = 2;

        let differences = compare_dmbs(&expected, &actual, &CompareOptions::default());
        assert!(differences.iter().any(|item| {
            item.path.contains("::<argument 0 source>") && item.field.starts_with("bytecode[")
        }));
    }

    #[test]
    fn decoded_map_cell_instance_changes_are_detected() {
        let mut expected = template();
        expected.dimensions = [1, 1, 1];
        expected.instances.push(crate::dmb::Instance {
            kind: 1,
            class: 0,
            initializer: 0xffff,
        });
        expected.grid.push(crate::dmb::GridRun {
            turf: (expected.instances.len() - 1) as u32,
            area: 0xffff,
            contents: 0xffff,
            copies: 1,
        });
        assert!(compare_maps(&expected, &expected, 10).is_empty());
        let mut actual = expected.clone();
        actual.grid[0].turf = 0xffff;
        let differences = compare_maps(&expected, &actual, 10);
        assert!(differences
            .iter()
            .any(|item| item.path.ends_with("/turf") && item.field == "instance"));
    }

    #[test]
    fn semantic_map_comparison_ignores_object_order_within_a_cell() {
        let mut expected = template();
        expected.dimensions = [1, 1, 1];
        expected.instances.push(crate::dmb::Instance {
            kind: 1,
            class: 0,
            initializer: 0xffff,
        });
        expected.instances.push(crate::dmb::Instance {
            kind: 2,
            class: 0,
            initializer: 0xffff,
        });
        let a = (expected.instances.len() - 2) as u32;
        let b = a + 1;
        expected.map_objects.push(crate::dmb::MapObject {
            offset: 0,
            instance: a,
        });
        expected.map_objects.push(crate::dmb::MapObject {
            offset: 0,
            instance: b,
        });
        let mut actual = expected.clone();
        actual.map_objects[0].instance = b;
        actual.map_objects[1].instance = a;
        assert!(!compare_maps(&expected, &actual, 10).is_empty());
        assert!(compare_maps_semantic(&expected, &actual, 10).is_empty());
    }

    #[test]
    fn mob_map_instance_uses_mob_table_before_class_table() {
        let mut dmb = template();
        assert!(dmb.classes.len() > 1);
        dmb.mobs.push(crate::dmb::MobType {
            class: 1,
            key: 0,
            sight: 0,
            extended_sight: None,
        });
        let mob_id = (dmb.mobs.len() - 1) as u32;
        dmb.instances.push(crate::dmb::Instance {
            kind: 8,
            class: mob_id,
            initializer: 0xffff,
        });
        let instance_id = (dmb.instances.len() - 1) as u32;
        assert_eq!(map_instance(&dmb, instance_id).unwrap().1, path(&dmb, 1));
        assert_eq!(
            value(
                &dmb,
                Value {
                    tag_word: 8,
                    data_word: mob_id,
                    extra_word: None,
                },
            ),
            NormalValue::Type(8, path(&dmb, 1)),
        );
        assert_eq!(
            value(
                &dmb,
                Value {
                    tag_word: 41,
                    data_word: instance_id,
                    extra_word: None,
                },
            ),
            NormalValue::InstanceType(8, path(&dmb, 1), InstanceInitializer::Absent),
        );
    }

    #[test]
    fn anonymous_proc_sentinel_is_not_string_id_65535() {
        let mut dmb = template();
        dmb.strings.resize(
            65_536,
            crate::dmb::DmString {
                data: b"real string".to_vec(),
                long_chunks: 0,
            },
        );
        dmb.procs[0].strings = [0xffff; 4];
        assert_eq!(dmb.string(0xffff), Some(b"real string" as &[u8]));
        assert_eq!(proc_path(&dmb, 0), None);
        assert!(!proc_index(&dmb, &CompareOptions::default())
            .values()
            .any(|ids| ids.contains(&0)));
    }

    #[test]
    fn independent_constant_map_writes_ignore_order_but_detect_values() {
        let mut expected = template();
        let x = expected.strings.len() as u32;
        expected.strings.push(crate::dmb::DmString {
            data: b"x".to_vec(),
            long_chunks: 0,
        });
        let y = expected.strings.len() as u32;
        expected.strings.push(crate::dmb::DmString {
            data: b"y".to_vec(),
            long_chunks: 0,
        });
        let code = expected.lists.len() as u32;
        expected.lists.push(vec![
            0x50, 1, 0x34, 0xffdc, 0xffce, x, 0x50, 2, 0x34, 0xffdc, 0xffce, y, 0,
        ]);
        let mut initializer = expected.procs[0].clone();
        initializer.strings = [0xffff; 4];
        initializer.code_locals_args[0] = code;
        let initializer_id = expected.procs.len() as u32;
        expected.procs.push(initializer);
        let instance_id = expected.instances.len() as u32;
        expected.instances.push(crate::dmb::Instance {
            kind: 1,
            class: 0,
            initializer: initializer_id,
        });
        expected.dimensions = [1, 1, 1];
        expected.grid.push(crate::dmb::GridRun {
            turf: instance_id,
            area: 0xffff,
            contents: 0xffff,
            copies: 1,
        });
        let mut actual = expected.clone();
        actual.lists[code as usize] = (vec![
            0x50, 2, 0x34, 0xffdc, 0xffce, y, 0x50, 1, 0x34, 0xffdc, 0xffce, x, 0,
        ]).into();
        assert!(!compare_maps(&expected, &actual, 10).is_empty());
        assert!(compare_maps_semantic(&expected, &actual, 10).is_empty());
        actual.lists[code as usize] = (vec![
            0x50, 2, 0x34, 0xffdc, 0xffce, 0xffdc, 0xffce, y, 0x50, 1, 0x34, 0xffdc, 0xffce,
            0xffdc, 0xffce, x, 0,
        ]).into();
        assert!(compare_maps_semantic(&expected, &actual, 10).is_empty());
        actual.lists[code as usize][6] = 0xffe5;
        assert!(constant_initializer_signature(&actual, initializer_id).is_none());
        assert!(!compare_maps_semantic(&expected, &actual, 10).is_empty());
        actual.lists[code as usize][6] = 0xffce;
        actual.lists[code as usize][1] = 3;
        assert!(!compare_maps_semantic(&expected, &actual, 10).is_empty());
    }
}
