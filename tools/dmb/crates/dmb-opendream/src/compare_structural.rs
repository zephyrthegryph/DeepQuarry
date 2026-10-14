//! Uncapped comparison receipts. Example storage is bounded; traversal is not.
use super::*;
use serde::Serialize;

const EXAMPLES: usize = 5;
const CATEGORIES: &[&str] = &[
    "type_set",
    "type_headers",
    "variable_defaults",
    "procedure_table",
    "procedure_flags",
    "globals",
    "strings_by_use",
    "bytecode",
    "other",
];

#[derive(Default, Serialize)]
pub struct CategoryReport {
    pub discrepancy_count: u64,
    pub examples: Vec<Discrepancy>,
}

#[derive(Default, Serialize)]
pub struct CoverageReport {
    pub occurrence_count: u64,
    pub examples: Vec<String>,
}

#[derive(Default, Serialize)]
pub struct BytecodeProcedureReport {
    pub expected_instruction_count: Option<usize>,
    pub actual_instruction_count: Option<usize>,
    pub positionally_compared_instructions: usize,
    pub expected_unmatched_tail: usize,
    pub actual_unmatched_tail: usize,
    pub differing_fields: u64,
    pub shape_classification: &'static str,
}

#[derive(Serialize)]
pub struct StructuralReport {
    #[serde(skip)]
    debug_scratch: (String, String),
    pub schema_version: u32,
    pub snapshot_id: String,
    /// Exhaustive traversal finished, independent of semantic coverage.
    pub traversal_complete: bool,
    /// Required categories and procedure ownership were traversed/decoded.
    pub tool_complete: bool,
    pub semantic_coverage: &'static str,
    /// False when some encountered representation lacks semantic resolution.
    pub complete: bool,
    pub total_discrepancies: u64,
    pub unexplained_discrepancies: u64,
    pub categories: BTreeMap<String, CategoryReport>,
    pub signature_algorithm: &'static str,
    #[serde(serialize_with = "serialize_signatures")]
    pub category_signatures: BTreeMap<String, BTreeSet<[u8; 16]>>,
    pub bytecode_procedures: BTreeMap<String, BytecodeProcedureReport>,
    pub uncovered: BTreeMap<String, CoverageReport>,
    #[serde(serialize_with = "serialize_signatures")]
    pub uncovered_signatures: BTreeMap<String, BTreeSet<[u8; 16]>>,
    /// Exact admitted discrepancies only; currently no admissions.
    pub explained_divergences: Vec<String>,
    pub normalization: Vec<&'static str>,
}

/// Bounded diagnostic view. Exact-case signatures remain exclusively in the raw report.
#[derive(Serialize)]
pub struct StructuralSummary<'a> {
    pub schema_version: u32,
    pub snapshot_id: &'a str,
    pub scope: &'static str,
    pub opcode_equivalence: &'static str,
    pub traversal_complete: bool,
    pub tool_complete: bool,
    pub semantic_coverage: &'a str,
    pub complete: bool,
    pub total_discrepancies: u64,
    pub unexplained_discrepancies: u64,
    pub categories: BTreeMap<&'a str, CategorySummary<'a>>,
    pub uncovered: BTreeMap<&'a str, CoverageSummary<'a>>,
    pub bytecode_shape_counts: BTreeMap<&'a str, usize>,
}

#[derive(Serialize)]
pub struct CategorySummary<'a> {
    pub discrepancy_count: u64,
    pub unique_case_count: usize,
    pub examples: &'a [Discrepancy],
}

#[derive(Serialize)]
pub struct CoverageSummary<'a> {
    pub occurrence_count: u64,
    pub unique_case_count: usize,
    pub examples: &'a [String],
}

impl StructuralReport {
    /// Borrow capped examples; never copy or serialize the full signature roster.
    pub fn summary(&self) -> StructuralSummary<'_> {
        let mut shapes = BTreeMap::new();
        for procedure in self.bytecode_procedures.values() {
            *shapes.entry(procedure.shape_classification).or_insert(0) += 1;
        }
        StructuralSummary {
            schema_version: 1,
            snapshot_id: &self.snapshot_id,
            scope: "unscoped_diagnostic_only_requires_authenticated_source_and_configuration",
            opcode_equivalence: "not_asserted_by_difference_counts_or_instruction_shapes",
            traversal_complete: self.traversal_complete,
            tool_complete: self.tool_complete,
            semantic_coverage: self.semantic_coverage,
            complete: self.complete,
            total_discrepancies: self.total_discrepancies,
            unexplained_discrepancies: self.unexplained_discrepancies,
            categories: self
                .categories
                .iter()
                .map(|(name, entry)| {
                    (
                        name.as_str(),
                        CategorySummary {
                            discrepancy_count: entry.discrepancy_count,
                            unique_case_count: self
                                .category_signatures
                                .get(name)
                                .map_or(0, BTreeSet::len),
                            examples: &entry.examples[..entry.examples.len().min(EXAMPLES)],
                        },
                    )
                })
                .collect(),
            uncovered: self
                .uncovered
                .iter()
                .map(|(name, entry)| {
                    (
                        name.as_str(),
                        CoverageSummary {
                            occurrence_count: entry.occurrence_count,
                            unique_case_count: self
                                .uncovered_signatures
                                .get(name)
                                .map_or(0, BTreeSet::len),
                            examples: &entry.examples[..entry.examples.len().min(EXAMPLES)],
                        },
                    )
                })
                .collect(),
            bytecode_shape_counts: shapes,
        }
    }
    fn new(snapshot_id: &str) -> Self {
        Self {
            debug_scratch: Default::default(),
            schema_version: 1, snapshot_id: snapshot_id.into(),
            traversal_complete: false, complete: false,
            tool_complete: false, semantic_coverage: "incomplete",
            total_discrepancies: 0, unexplained_discrepancies: 0,
            categories: CATEGORIES.iter().map(|name| ((*name).into(), CategoryReport::default())).collect(),
            signature_algorithm: "md5-length-framed-v1",
            category_signatures: CATEGORIES.iter().map(|name| ((*name).into(), BTreeSet::new())).collect(),
            bytecode_procedures: BTreeMap::new(),
            uncovered: BTreeMap::new(), explained_divergences: Vec::new(),
            uncovered_signatures: BTreeMap::new(),
            normalization: vec!["debug file/line opcodes excluded; branch targets use normalized instruction indices", "typed table references resolve to names; PushInt normalizes to numeric PushVal", "runtime hidden-initializer markers use established comparator semantics", "global-reference-normalization-v3: Global operands resolve direct VarIDs; footer ordinals are declaration metadata"],
        }
    }
    pub(super) fn record(&mut self, path: &str, field: &str, expected: String, actual: String) {
        self.record_text(path, field, &expected, &actual);
    }
    pub(super) fn record_debug(
        &mut self,
        path: &str,
        field: &str,
        expected: impl std::fmt::Debug,
        actual: impl std::fmt::Debug,
    ) {
        use std::fmt::Write;
        let (mut left, mut right) = std::mem::take(&mut self.debug_scratch);
        left.clear();
        right.clear();
        write!(&mut left, "{expected:?}").expect("String formatting");
        write!(&mut right, "{actual:?}").expect("String formatting");
        self.record_text(path, field, &left, &right);
        self.debug_scratch = (left, right);
    }
    fn record_text(&mut self, path: &str, field: &str, expected: &str, actual: &str) {
        let category = if field == "string.use" {
            "strings_by_use"
        } else if field == "class.count" {
            "type_set"
        } else if field.starts_with("bytecode") {
            "bytecode"
        } else if path.starts_with("/globals") {
            "globals"
        } else if field == "proc.flags" {
            "procedure_flags"
        } else if field.starts_with("proc.")
            || field.starts_with("class.proc")
            || field.starts_with("class.verb")
        {
            "procedure_table"
        } else if field.starts_with("class.default") || field.starts_with("class.declaration") {
            "variable_defaults"
        } else if field.starts_with("class.") {
            "type_headers"
        } else {
            "other"
        };
        self.total_discrepancies += 1;
        self.unexplained_discrepancies += 1;
        let mut digest = md5::Context::new();
        for value in [path, field, expected, actual] {
            digest.consume((value.len() as u64).to_le_bytes());
            digest.consume(value.as_bytes());
        }
        self.category_signatures
            .entry(category.into())
            .or_default()
            .insert(digest.compute().0);
        if category == "bytecode" {
            let entry = self.bytecode_procedures.entry(path.into()).or_default();
            entry.differing_fields += 1;
            if entry.shape_classification.is_empty() {
                entry.shape_classification = "decode_or_normalization_unavailable";
            }
        }
        let entry = self.categories.entry(category.into()).or_default();
        entry.discrepancy_count += 1;
        if entry.examples.len() < EXAMPLES {
            entry.examples.push(Discrepancy {
                path: path.into(),
                field: field.into(),
                expected: excerpt(expected.to_owned()),
                actual: excerpt(actual.to_owned()),
            });
        }
    }
    pub(super) fn observe_bytecode(&mut self, path: &str, expected: usize, actual: usize) {
        let entry = self.bytecode_procedures.entry(path.into()).or_default();
        entry.expected_instruction_count = Some(expected);
        entry.actual_instruction_count = Some(actual);
        entry.positionally_compared_instructions = expected.min(actual);
        entry.expected_unmatched_tail = expected.saturating_sub(actual);
        entry.actual_unmatched_tail = actual.saturating_sub(expected);
        entry.shape_classification = if expected == actual {
            "same_instruction_count_not_semantic_equivalence"
        } else {
            "different_instruction_count_positional_alignment_provisional"
        };
    }
    fn missing(&mut self, kind: &str, site: String) {
        self.missing_with_evidence(kind, site, String::new());
    }
    fn missing_with_evidence(&mut self, kind: &str, site: String, evidence: String) {
        let mut digest = md5::Context::new();
        for value in [kind, site.as_str(), evidence.as_str()] {
            digest.consume((value.len() as u64).to_le_bytes());
            digest.consume(value.as_bytes());
        }
        self.uncovered_signatures
            .entry(kind.into())
            .or_default()
            .insert(digest.compute().0);
        let entry = self.uncovered.entry(kind.into()).or_default();
        entry.occurrence_count += 1;
        if entry.examples.len() < EXAMPLES {
            entry.examples.push(excerpt(if evidence.is_empty() {
                site
            } else {
                format!("{site}: wire={evidence}")
            }));
        }
    }
    fn finalize_coverage(&mut self) {
        self.traversal_complete = true;
        self.complete = self.uncovered.is_empty();
        self.semantic_coverage = if self.complete {
            "complete"
        } else {
            "incomplete"
        };
        self.tool_complete = self.uncovered.keys().all(|kind| {
            matches!(
                kind.as_str(),
                "opaque_value"
                    | "opaque_instance_initializer"
                    | "unclassified_fixed_word_semantics"
            )
        });
    }
}

fn serialize_signatures<S: serde::Serializer>(
    signatures: &BTreeMap<String, BTreeSet<[u8; 16]>>,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    use serde::ser::{SerializeMap, SerializeSeq};
    struct Cases<'a>(&'a BTreeSet<[u8; 16]>);
    impl Serialize for Cases<'_> {
        fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
            let mut seq = serializer.serialize_seq(Some(self.0.len()))?;
            for digest in self.0 {
                let hex = signature_hex(digest);
                seq.serialize_element(std::str::from_utf8(&hex).expect("ASCII hex"))?;
            }
            seq.end()
        }
    }
    let mut map = serializer.serialize_map(Some(signatures.len()))?;
    for (category, cases) in signatures {
        map.serialize_entry(category, &Cases(cases))?;
    }
    map.end()
}

fn signature_hex(digest: &[u8; 16]) -> [u8; 32] {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut result = [0; 32];
    for (index, byte) in digest.iter().copied().enumerate() {
        result[index * 2] = DIGITS[(byte >> 4) as usize];
        result[index * 2 + 1] = DIGITS[(byte & 15) as usize];
    }
    result
}

#[cfg(test)]
mod exact_reporting_tests {
    use super::*;
    #[test]
    fn stack_hex_matches_legacy_format_for_every_byte() {
        for byte in 0..=u8::MAX {
            let digest = [byte; 16];
            assert_eq!(
                std::str::from_utf8(&signature_hex(&digest)).unwrap(),
                format!("{:x}", md5::Digest(digest))
            );
        }
    }
    #[test]
    fn reused_debug_buffers_preserve_full_fingerprints_and_capped_examples() {
        let mut actual = StructuralReport::new("exact");
        let mut expected = StructuralReport::new("exact");
        for index in 0..EXAMPLES + 10 {
            let left = (index, "λ".repeat(5000), vec![0u8, 15, 255]);
            let right = (index + 1, "different", Some(-17));
            actual.record_debug("/datum/a", "class.default.value", &left, &right);
            expected.record(
                "/datum/a",
                "class.default.value",
                format!("{left:?}"),
                format!("{right:?}"),
            );
        }
        assert_eq!(
            serde_json::to_value(&actual).unwrap(),
            serde_json::to_value(&expected).unwrap()
        );
        assert_eq!(
            actual.categories["variable_defaults"].examples.len(),
            EXAMPLES
        );
        assert_eq!(
            actual.category_signatures["variable_defaults"].len(),
            EXAMPLES + 10
        );
    }
}

/// Whole-program comparison with no discrepancy cap and no path filter.
/// `snapshot_id` is a caller's independently authenticated shared-input receipt,
/// not proof inferred from either DMB. The caller must verify that receipt.
pub fn structural_report(expected: &Dmb, actual: &Dmb, snapshot_id: &str) -> StructuralReport {
    let expected = &memo::NormalizationContext::new(expected);
    let actual = &memo::NormalizationContext::new(actual);

    let mut out = Collector {
        output: Vec::new(),
        limit: usize::MAX,
        report: Some(StructuralReport::new(snapshot_id)),
    };
    let expected_ownership = anonymous::procedure_ownership(expected);
    let actual_ownership = anonymous::procedure_ownership(actual);
    collect_dmbs(expected, actual, &CompareOptions::default(), &mut out);
    // Physical /proc and override paths are semantically distinct for typesof.
    // The older comparator canonicalizes those paths for pairing only.
    let left = physical_paths(expected);
    let right = physical_paths(actual);
    for name in left.keys().chain(right.keys()).collect::<BTreeSet<_>>() {
        out.check(
            &label(name),
            "proc.physical_path_count",
            left.get(name),
            right.get(name),
        );
    }
    compare_members(expected, actual, &mut out);
    anonymous::compare_anonymous(
        expected,
        actual,
        &mut out,
        &expected_ownership,
        &actual_ownership,
    );
    missing::compare_missing_procedures(
        expected,
        actual,
        &mut out,
        &expected_ownership,
        &actual_ownership,
    );
    let left_strings = string_uses(expected);
    let right_strings = string_uses(actual);
    for site in left_strings
        .keys()
        .chain(right_strings.keys())
        .collect::<BTreeSet<_>>()
    {
        out.check(
            site,
            "string.use",
            left_strings.get(site),
            right_strings.get(site),
        );
    }
    let report = out.report.as_mut().expect("structural collector");
    audit_coverage(expected, "expected", report, &expected_ownership);
    audit_coverage(actual, "actual", report, &actual_ownership);
    report.finalize_coverage();
    out.report.expect("structural collector")
}

fn excerpt(mut text: String) -> String {
    if text.len() > 4096 {
        let mut end = 4096;
        while !text.is_char_boundary(end) {
            end -= 1;
        }
        text.truncate(end);
        text.push_str("… [example truncated; count is uncapped]");
    }
    text
}

fn physical_paths(dmb: &memo::NormalizationContext<'_>) -> BTreeMap<Vec<u8>, usize> {
    let mut paths = BTreeMap::new();
    for proc_ in &dmb.procs {
        if let Some(path) = optional_proc_string(dmb, proc_.strings[0]) {
            *paths.entry(path).or_default() += 1;
        }
    }
    paths
}

fn compare_members(
    expected: &memo::NormalizationContext<'_>,
    actual: &memo::NormalizationContext<'_>,
    out: &mut Collector,
) {
    let options = CompareOptions::default();
    let left = class_index(expected, &options);
    let right = class_index(actual, &options);
    for name in left.keys().chain(right.keys()).collect::<BTreeSet<_>>() {
        for (&a, &b) in left
            .get(name)
            .into_iter()
            .flatten()
            .zip(right.get(name).into_iter().flatten())
        {
            for (field, x, y) in [
                (
                    "class.procs",
                    expected.classes[a].proc_list_id(),
                    actual.classes[b].proc_list_id(),
                ),
                (
                    "class.verbs",
                    expected.classes[a].verb_list_id(),
                    actual.classes[b].verb_list_id(),
                ),
            ] {
                let resolve = |dmb: &memo::NormalizationContext<'_>, id| {
                    if id == 0xffff {
                        return Some(Vec::new());
                    }
                    dmb.lists.get(id as usize).map(|list| {
                        list.iter()
                            .map(|id| proc_path(dmb, *id))
                            .collect::<Vec<_>>()
                    })
                };
                // Preserve ordering: dispatch/override order is observable.
                out.check(
                    &label(name),
                    field,
                    resolve(expected, x),
                    resolve(actual, y),
                );
            }
        }
    }
}

fn audit_value(value: &NormalValue, site: &str, report: &mut StructuralReport) {
    match value {
        NormalValue::InstanceType(_, None, _) => {
            report.missing("unresolved_typed_reference", site.into())
        }
        NormalValue::Raw(raw) if raw.kind() == ValueKind::ClientPath && raw.id() != 0 => {
            report.record(
                site,
                "invalid.client_singleton_payload",
                "ClientPath payload 0 (pinned BYOND 516.1687)".into(),
                format!("{raw:?}"),
            );
        }
        NormalValue::Raw(raw) => {
            report.missing_with_evidence("opaque_value", site.into(), format!("{:?}", raw.encode()))
        }
        NormalValue::InstanceType(kind, class, InstanceInitializer::Opaque(_, Some(words))) => {
            report.missing_with_evidence(
                "opaque_instance_initializer",
                site.into(),
                format!("kind={kind};class={class:?};initializer_words={words:?}"),
            )
        }
        NormalValue::InstanceType(_, _, InstanceInitializer::Opaque(_, None)) => {
            report.missing("instance_initializer_code", site.into())
        }
        NormalValue::String(None)
        | NormalValue::Type(_, None)
        | NormalValue::Proc(None)
        | NormalValue::Resource(None) => report.missing("unresolved_typed_reference", site.into()),
        _ => {}
    }
}

fn audit_coverage(
    dmb: &memo::NormalizationContext<'_>,
    side: &str,
    report: &mut StructuralReport,
    ownership: &BTreeMap<String, u32>,
) {
    let paired_unnamed: BTreeSet<_> = ownership.values().copied().collect();
    let mut owner_names = BTreeMap::new();
    for (name, id) in ownership {
        owner_names.entry(*id).or_insert(name);
    }
    for (id, class) in dmb.classes.iter().enumerate() {
        let site = format!(
            "{side}:class:{}",
            label(
                dmb.string(class.path_string_id())
                    .unwrap_or(b"<unresolved-class-path>")
            )
        );
        for (kind, list_id, decoded) in [
            (
                "declaration_list",
                class.defining_variable_list_id(),
                dmb.class_variable_declarations(id).is_some(),
            ),
            (
                "initial_value_list",
                class.initialized_variable_list_id(),
                dmb.class_initial_values(id).is_some(),
            ),
            (
                "builtin_override_list",
                class.overriding_variable_list_id(),
                dmb.class_builtin_overrides(id).is_some(),
            ),
        ] {
            if list_id != 0xffff && !decoded {
                report.missing(kind, site.clone());
            }
        }
        for list_id in [class.proc_list_id(), class.verb_list_id()] {
            if list_id != 0xffff {
                match dmb.lists.get(list_id as usize) {
                    Some(list) => {
                        for proc_id in list {
                            if proc_path(dmb, *proc_id).is_none() {
                                report.missing("class_procedure_binding", site.clone());
                            }
                        }
                    }
                    None => report.missing("class_procedure_list", site.clone()),
                }
            }
        }
        if bytes(dmb, class.path_string_id()).is_none() {
            report.missing("class_path", site.clone());
        }
        for (kind, values) in [
            ("defaults", defaults(dmb, id)),
            (
                "declarations",
                declaration(dmb, id).map(|values| {
                    values
                        .into_iter()
                        .map(|(name, (_, value))| (name, value))
                        .collect()
                }),
            ),
        ] {
            if let Some(values) = values {
                for (name, value) in values {
                    audit_value(&value, &format!("{site}:{kind}:{}", label(&name)), report);
                }
            } else {
                report.missing(kind, site.clone());
            }
        }
    }
    if let Some(globals) = global_declarations(dmb) {
        for (name, values) in globals {
            for (rank, (_, value)) in values.into_iter().enumerate() {
                audit_value(
                    &value,
                    &format!("{side}:global:{}#{rank}", label(&name)),
                    report,
                );
            }
        }
    } else {
        report.missing("global_table", side.into());
    }
    for (id, _) in dmb.procs.iter().enumerate() {
        let site = format!(
            "{side}:proc:{}",
            owner_names
                .get(&(id as u32))
                .map_or("<unowned-anonymous>", |name| name.as_str())
        );
        let code_id = dmb.procs[id].code_locals_args[0];
        if code_id != 0xffff && dmb.lists.get(code_id as usize).is_none() {
            report.missing("procedure_code_list", site.clone());
        }
        let locals_id = dmb.procs[id].code_locals_args[1];
        if locals_id != 0xffff {
            match dmb.lists.get(locals_id as usize) {
                Some(locals) => {
                    for variable_id in locals {
                        if dmb
                            .variables
                            .get(*variable_id as usize)
                            .and_then(|variable| dmb.string(variable.name))
                            .is_none()
                        {
                            report.missing("unresolved_local_name", site.clone());
                        }
                    }
                }
                None => report.missing("procedure_local_list", site.clone()),
            }
        }
        let args_id = dmb.procs[id].code_locals_args[2];
        match dmb.proc_arguments(id) {
            Some(arguments) => {
                for argument in arguments {
                    if dmb
                        .variables
                        .get(argument.variable_id as usize)
                        .and_then(|variable| dmb.string(variable.name))
                        .is_none()
                    {
                        report.missing("unresolved_argument_name", site.clone());
                    }
                }
            }
            None if args_id != 0xffff => report.missing("procedure_argument_list", site.clone()),
            None => {}
        }
        if proc_path(dmb, id as u32).is_none() && !paired_unnamed.contains(&(id as u32)) {
            report.missing("unpaired_anonymous_procedure", site.clone());
        }
        let code = dmb.proc_code_words(id).unwrap_or_default();
        match bytecode::decode(code) {
            Err(error) => report.missing("bytecode_decode", format!("{site}:{error:?}")),
            Ok(instructions) => {
                let mut opcode_occurrences = BTreeMap::<u32, usize>::new();
                let mut boundaries: BTreeSet<_> =
                    instructions.iter().map(|item| item.offset).collect();
                boundaries.insert(code.len());
                for item in instructions {
                    if matches!(item.opcode, 0x84 | 0x85) {
                        continue;
                    }
                    let occurrence = opcode_occurrences.entry(item.opcode).or_default();
                    let instruction_site =
                        format!("{site}:opcode {} occurrence {}", item.name, *occurrence);
                    *occurrence += 1;
                    match item.branch_targets() {
                        Ok(targets) => {
                            for target in targets {
                                if !boundaries.contains(&(target as usize)) {
                                    report.missing(
                                        "invalid_branch_target",
                                        format!("{site}:{}@{}->{target}", item.name, item.offset),
                                    );
                                }
                            }
                        }
                        Err(error) => {
                            report.missing("branch_operand_decode", format!("{site}:{error:?}"))
                        }
                    }
                    match instruction(dmb, &item) {
                        Err(error) => report.missing("operand_decode", format!("{site}:{error:?}")),
                        Ok(normal) => {
                            for (index, operand) in normal.operands.into_iter().enumerate() {
                                audit_operand(
                                    &operand,
                                    &format!("{instruction_site}:operand {index}"),
                                    item.opcode,
                                    index,
                                    &item.operands,
                                    report,
                                );
                            }
                        }
                    }
                }
            }
        }
    }
    // No strings-table positional diff: every established string reference is
    // compared at its semantic use site. Unknown operands cannot certify this.
}

fn audit_operand(
    operand: &NormalOperand,
    site: &str,
    opcode: u32,
    index: usize,
    raw_words: &[u32],
    report: &mut StructuralReport,
) {
    match operand {
        NormalOperand::Value(value) => audit_value(value, site, report),
        NormalOperand::String(None) | NormalOperand::Proc(None) => {
            report.missing("unresolved_typed_reference", site.into())
        }
        NormalOperand::Variable(value) => audit_variable(value, site, report),
        NormalOperand::Word(_)
            if matches!(
                super::operand_roles::fixed_word_role(opcode, index),
                super::operand_roles::FixedWordRole::ProcedureId
                    | super::operand_roles::FixedWordRole::StringId
            ) =>
        {
            report.missing_with_evidence(
                "unresolved_required_operand_reference",
                site.into(),
                format!("opcode={opcode};operands={raw_words:?}"),
            )
        }
        NormalOperand::Word(_)
            if !super::operand_roles::contextual_fixed_word_is_scalar(opcode, index, raw_words)
                && super::operand_roles::fixed_word_role(opcode, index)
                    != super::operand_roles::FixedWordRole::BranchTarget =>
        {
            report.missing_with_evidence(
                "unclassified_fixed_word_semantics",
                site.into(),
                format!("opcode={opcode};operands={raw_words:?}"),
            )
        }
        NormalOperand::Switch(cases, _) => {
            for (index, (value, _)) in cases.iter().enumerate() {
                audit_value(value, &format!("{site}:case {index}"), report);
            }
        }
        NormalOperand::RangeSwitch(ranges, exact, _) => {
            for (index, (a, b, _)) in ranges.iter().enumerate() {
                audit_value(a, &format!("{site}:range {index}:lower"), report);
                audit_value(b, &format!("{site}:range {index}:upper"), report);
            }
            for (index, (value, _)) in exact.iter().enumerate() {
                audit_value(value, &format!("{site}:exact case {index}"), report);
            }
        }
        _ => {}
    }
}

fn audit_variable(variable: &NormalVariable, site: &str, report: &mut StructuralReport) {
    match variable {
        NormalVariable::Field(None)
        | NormalVariable::Global(None)
        | NormalVariable::InvalidGlobal(..)
        | NormalVariable::DynamicProc(None)
        | NormalVariable::DynamicVerb(None)
        | NormalVariable::StaticProc(None)
        | NormalVariable::StaticVerb(None) => {
            report.missing("unresolved_variable_reference", site.into())
        }
        NormalVariable::Nested(_, left, right) => {
            audit_variable(left, site, report);
            if let Some(right) = right {
                audit_variable(right, site, report);
            }
        }
        _ => {}
    }
}

fn string_uses(dmb: &memo::NormalizationContext<'_>) -> BTreeMap<String, Vec<Vec<u8>>> {
    let mut uses = BTreeMap::new();
    for (name, ids) in class_index(dmb, &CompareOptions::default()) {
        for (rank, id) in ids.into_iter().enumerate() {
            let class = &dmb.classes[id];
            for (kind, string_id) in [
                ("name", class.name_string_id()),
                ("description", class.description_string_id()),
                ("icon_state", class.icon_state_string_id()),
                ("text", class.text),
                ("maptext", class.maptext),
                ("suffix", class.suffix),
            ] {
                if let Some(text) = bytes(dmb, string_id) {
                    uses.insert(format!("{}#{rank}:header:{kind}", label(&name)), vec![text]);
                }
            }
            for (field, value) in defaults(dmb, id).unwrap_or_default() {
                if let NormalValue::String(Some(text)) = value {
                    uses.insert(
                        format!("{}#{rank}:default:{}", label(&name), label(&field)),
                        vec![text],
                    );
                }
            }
        }
    }
    for (name, ids) in proc_index(dmb, &CompareOptions::default()) {
        for (rank, id) in ids.into_iter().enumerate() {
            let proc_ = &dmb.procs[id];
            for (slot, kind) in [(1, "display"), (2, "description"), (3, "category")] {
                if let Some(text) = optional_proc_string(dmb, proc_.strings[slot]) {
                    uses.insert(format!("{}#{rank}:{kind}", label(&name)), vec![text]);
                }
            }
            if let Ok(code) = bytecode::decode(dmb.proc_code_words(id).unwrap_or_default()) {
                for (index, item) in code
                    .iter()
                    .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                    .enumerate()
                {
                    if let Ok(normal) = instruction(dmb, item) {
                        let mut strings = Vec::new();
                        for operand in &normal.operands {
                            operand_strings(operand, &mut strings);
                        }
                        if !strings.is_empty() {
                            uses.insert(
                                format!("{}#{rank}:instruction[{index}]", label(&name)),
                                strings,
                            );
                        }
                    }
                }
            }
        }
    }
    for (name, values) in global_declarations(dmb).unwrap_or_default() {
        for (rank, (_, value)) in values.into_iter().enumerate() {
            if let NormalValue::String(Some(text)) = value {
                uses.insert(format!("/globals/{}#{rank}", label(&name)), vec![text]);
            }
        }
    }
    uses
}

fn operand_strings(operand: &NormalOperand, output: &mut Vec<Vec<u8>>) {
    let value_string = |value: &NormalValue, output: &mut Vec<Vec<u8>>| {
        if let NormalValue::String(Some(text)) = value {
            output.push(text.clone());
        }
    };
    match operand {
        NormalOperand::String(Some(text)) => output.push(text.clone()),
        NormalOperand::Value(value) => value_string(value, output),
        NormalOperand::Switch(cases, _) => {
            for (value, _) in cases {
                value_string(value, output);
            }
        }
        NormalOperand::RangeSwitch(ranges, exact, _) => {
            for (a, b, _) in ranges {
                value_string(a, output);
                value_string(b, output);
            }
            for (value, _) in exact {
                value_string(value, output);
            }
        }
        _ => {}
    }
}

#[cfg(test)]
#[path = "compare_structural_tests.rs"]
mod tests;
