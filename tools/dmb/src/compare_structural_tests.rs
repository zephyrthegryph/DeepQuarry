use super::*;

fn template() -> Dmb {
    Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap()
}

#[test]
fn counting_collector_never_stops_at_example_limit() {
    let mut out = Collector {
        output: Vec::new(),
        limit: 1,
        report: Some(StructuralReport::new("snapshot")),
    };
    for index in 0..300 {
        out.check(&format!("/datum/t{index}"), "class.count", 1, 2);
        assert!(!out.full());
    }
    let report = out.report.unwrap();
    assert_eq!(report.total_discrepancies, 300);
    assert_eq!(report.categories["type_set"].discrepancy_count, 300);
    assert_eq!(report.categories["type_set"].examples.len(), EXAMPLES);
}

#[test]
fn physical_proc_namespace_difference_is_not_canonicalized_away() {
    let mut expected = template();
    let mut actual = expected.clone();
    let path = expected.strings.len() as u32;
    expected.strings.push(crate::dmb::DmString {
        data: b"/datum/proc/f".to_vec(),
        long_chunks: 0,
    });
    actual.strings.push(crate::dmb::DmString {
        data: b"/datum/f".to_vec(),
        long_chunks: 0,
    });
    expected.procs[0].strings[0] = path;
    actual.procs[0].strings[0] = path;
    let report = structural_report(&expected, &actual, "captured-snapshot");
    assert!(report.categories["procedure_table"]
        .examples
        .iter()
        .any(|difference| difference.field == "proc.physical_path_count"));
    assert!(report.traversal_complete);
    assert_eq!(report.snapshot_id, "captured-snapshot");
}

#[test]
fn debug_only_changes_do_not_change_normalized_bytecode() {
    let mut expected = template();
    let mut actual = expected.clone();
    expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
    expected.lists.push(vec![0x85, 42, 0xf, 4, 0x12]);
    actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
    actual.lists.push(vec![0xf, 2, 0x12]);
    let mut out = Collector {
        output: Vec::new(),
        limit: 0,
        report: Some(StructuralReport::new("snapshot")),
    };
    compare_code(
        &memo::NormalizationContext::new(&expected),
        0,
        &memo::NormalizationContext::new(&actual),
        0,
        "/test",
        &mut out,
    );
    assert_eq!(out.report.unwrap().total_discrepancies, 0);
}

#[test]
fn opaque_values_cannot_certify_semantic_equality() {
    let mut report = StructuralReport::new("snapshot");
    audit_value(
        &NormalValue::Raw(Value {
            tag_word: 0xff,
            data_word: 12,
            extra_word: None,
        }),
        "/datum/test",
        &mut report,
    );
    assert_eq!(report.uncovered["opaque_value"].occurrence_count, 1);
    assert!(!report.complete);
}

#[test]
fn signatures_capture_full_values_and_allow_old_cases_to_disappear() {
    let mut baseline = StructuralReport::new("snapshot");
    let prefix = "x".repeat(5000);
    baseline.record("/x", "class.count", prefix.clone(), format!("{prefix}old"));
    baseline.record("/y", "class.count", "1".into(), "2".into());
    let mut improved = StructuralReport::new("snapshot");
    improved.record("/y", "class.count", "1".into(), "2".into());
    assert!(improved.category_signatures["type_set"]
        .is_subset(&baseline.category_signatures["type_set"]));
    let mut changed = StructuralReport::new("snapshot");
    changed.record("/x", "class.count", prefix.clone(), format!("{prefix}new"));
    assert_eq!(
        changed.categories["type_set"].examples[0].actual,
        baseline.categories["type_set"].examples[0].actual
    );
    assert!(!changed.category_signatures["type_set"]
        .is_subset(&baseline.category_signatures["type_set"]));
    let json = serde_json::to_value(improved).unwrap();
    assert_eq!(json["signature_algorithm"], "md5-length-framed-v1");
    assert_eq!(
        json["category_signatures"]["bytecode"],
        serde_json::json!([])
    );
    assert_eq!(
        json["category_signatures"]["type_set"][0]
            .as_str()
            .unwrap()
            .len(),
        32
    );
}

#[test]
fn invalid_client_singleton_is_a_known_difference_not_unsupported_coverage() {
    let mut report = StructuralReport::new("snapshot");
    audit_value(
        &NormalValue::Raw(Value {
            tag_word: 59,
            data_word: 9,
            extra_word: None,
        }),
        "/test",
        &mut report,
    );
    assert!(report.uncovered.is_empty());
    assert_eq!(report.total_discrepancies, 1);
    assert_eq!(
        report.categories["other"].examples[0].field,
        "invalid.client_singleton_payload"
    );
}

#[test]
fn anonymous_modified_type_initializers_pair_by_use_across_table_renumbering() {
    let mut expected = template();
    let name = expected.strings.len() as u32;
    expected.strings.push(crate::dmb::DmString {
        data: b"/proc/anchor".to_vec(),
        long_chunks: 0,
    });
    expected.procs[0].strings[0] = name;
    let class = expected
        .classes
        .iter()
        .position(|class| expected.string(class.path_string_id()) == Some(b"/datum".as_slice()))
        .unwrap() as u32;
    let init = expected.procs.len() as u32;
    let mut proc_ = expected.procs[0].clone();
    proc_.strings[0] = 0xffff;
    proc_.code_locals_args[0] = expected.lists.len() as u32;
    expected.lists.push(vec![0x50, 1, 0x12]);
    expected.procs.push(proc_);
    let instance = expected.instances.len() as u32;
    expected.instances.push(crate::dmb::Instance {
        kind: 32,
        class,
        initializer: init,
    });
    expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
    expected.lists.push(vec![0x60, 41, instance, 0x12]);
    let mut actual = expected.clone();
    let actual_init = actual.procs.len() as u32;
    actual.procs.push(actual.procs[init as usize].clone());
    let actual_instance = actual.instances.len() as u32;
    actual
        .instances
        .push(actual.instances[instance as usize].clone());
    actual.instances[actual_instance as usize].initializer = actual_init;
    actual.lists[actual.procs[0].code_locals_args[0] as usize][2] = actual_instance;
    let left = anonymous::procedure_ownership(&memo::NormalizationContext::new(&expected));
    let right = anonymous::procedure_ownership(&memo::NormalizationContext::new(&actual));
    let site = "/proc/anchor#0::<modified-type use 0>::<instance /datum init>";
    assert_eq!(left.get(site), Some(&init));
    assert_eq!(right.get(site), Some(&actual_init));
    let mut out = Collector {
        output: Vec::new(),
        limit: 0,
        report: Some(StructuralReport::new("snapshot")),
    };
    anonymous::compare_anonymous(
        &memo::NormalizationContext::new(&expected),
        &memo::NormalizationContext::new(&actual),
        &mut out,
        &left,
        &right,
    );
    assert_eq!(out.report.unwrap().total_discrepancies, 0);
}

#[test]
fn local_unknown_semantics_do_not_hide_missing_required_tool_coverage() {
    let mut report = StructuralReport::new("snapshot");
    report.missing_with_evidence(
        "unclassified_fixed_word_semantics",
        "actual:/proc/p#0:opcode Input occurrence 0:operand 1".into(),
        "opcode=193;operands=[0, 0, 0]".into(),
    );
    report.finalize_coverage();
    assert!(report.traversal_complete);
    assert!(report.tool_complete);
    assert!(!report.complete);
    assert_eq!(report.semantic_coverage, "incomplete");
    report.missing(
        "unpaired_anonymous_procedure",
        "actual:<unowned-anonymous>".into(),
    );
    report.finalize_coverage();
    assert!(!report.tool_complete);
}

#[test]
fn equal_unknown_counts_do_not_admit_changed_wire_evidence() {
    let site = "actual:/proc/p#0:opcode Input occurrence 0:operand 1";
    let mut baseline = StructuralReport::new("snapshot");
    baseline.missing_with_evidence(
        "unclassified_fixed_word_semantics",
        site.into(),
        "opcode=193;operands=[0, 0, 0]".into(),
    );
    let mut candidate = StructuralReport::new("snapshot");
    candidate.missing_with_evidence(
        "unclassified_fixed_word_semantics",
        site.into(),
        "opcode=193;operands=[0, 1, 0]".into(),
    );
    assert_eq!(
        candidate.uncovered["unclassified_fixed_word_semantics"].occurrence_count,
        baseline.uncovered["unclassified_fixed_word_semantics"].occurrence_count
    );
    assert!(
        !candidate.uncovered_signatures["unclassified_fixed_word_semantics"]
            .is_subset(&baseline.uncovered_signatures["unclassified_fixed_word_semantics"])
    );
    let json = serde_json::to_value(candidate).unwrap();
    assert_eq!(
        json["uncovered_signatures"]["unclassified_fixed_word_semantics"][0]
            .as_str()
            .unwrap()
            .len(),
        32
    );
}

#[test]
fn supported_body_change_in_unmatched_named_proc_changes_case_signature() {
    let expected = template();
    let mut baseline = expected.clone();
    let name = baseline.strings.len() as u32;
    baseline.strings.push(crate::dmb::DmString {
        data: b"/proc/unmatched".to_vec(),
        long_chunks: 0,
    });
    let id = baseline.procs.len();
    let mut proc_ = baseline.procs[0].clone();
    proc_.strings[0] = name;
    proc_.code_locals_args[0] = baseline.lists.len() as u32;
    baseline.lists.push(vec![0x50, 1, 0x12]);
    baseline.procs.push(proc_);
    let mut candidate = baseline.clone();
    candidate.lists[candidate.procs[id].code_locals_args[0] as usize][1] = 2;
    let left = anonymous::procedure_ownership(&memo::NormalizationContext::new(&expected));
    let compare = |dmb: &Dmb| {
        let mut out = Collector {
            output: Vec::new(),
            limit: 0,
            report: Some(StructuralReport::new("snapshot")),
        };
        missing::compare_missing_procedures(
            &memo::NormalizationContext::new(&expected),
            &memo::NormalizationContext::new(dmb),
            &mut out,
            &left,
            &anonymous::procedure_ownership(&memo::NormalizationContext::new(dmb)),
        );
        out.report.unwrap()
    };
    let old = compare(&baseline);
    let new = compare(&candidate);
    assert_eq!(
        old.categories["procedure_table"].discrepancy_count,
        new.categories["procedure_table"].discrepancy_count
    );
    assert!(!new.category_signatures["procedure_table"]
        .is_subset(&old.category_signatures["procedure_table"]));
    assert!(old.categories["procedure_table"]
        .examples
        .iter()
        .any(|example| example.field == "proc.unmatched_payload"));
    let mut debug_only = baseline.clone();
    debug_only.lists[debug_only.procs[id].code_locals_args[0] as usize] =
        vec![0x85, 77, 0x50, 1, 0x12];
    assert_eq!(
        compare(&debug_only).category_signatures,
        old.category_signatures
    );
}

#[test]
fn unknown_switch_case_multiplicity_changes_cannot_hide_behind_total_count() {
    let raw = |id| {
        NormalValue::Raw(Value {
            tag_word: 240,
            data_word: id,
            extra_word: None,
        })
    };
    let baseline = NormalOperand::Switch(
        vec![
            (raw(1), NormalTarget::Instruction(0)),
            (raw(1), NormalTarget::Instruction(0)),
            (raw(2), NormalTarget::Instruction(0)),
        ],
        NormalTarget::Instruction(0),
    );
    let candidate = NormalOperand::Switch(
        vec![
            (raw(1), NormalTarget::Instruction(0)),
            (raw(2), NormalTarget::Instruction(0)),
            (raw(2), NormalTarget::Instruction(0)),
        ],
        NormalTarget::Instruction(0),
    );
    let mut old = StructuralReport::new("snapshot");
    let mut new = StructuralReport::new("snapshot");
    audit_operand(
        &baseline,
        "actual:/proc/p#0:opcode Switch occurrence 0:operand 0",
        0x78,
        0,
        &[],
        &mut old,
    );
    audit_operand(
        &candidate,
        "actual:/proc/p#0:opcode Switch occurrence 0:operand 0",
        0x78,
        0,
        &[],
        &mut new,
    );
    assert_eq!(
        old.uncovered["opaque_value"].occurrence_count,
        new.uncovered["opaque_value"].occurrence_count
    );
    assert_eq!(old.uncovered_signatures["opaque_value"].len(), 3);
    assert!(!new.uncovered_signatures["opaque_value"]
        .is_subset(&old.uncovered_signatures["opaque_value"]));
}

#[test]
fn malformed_argument_metadata_cannot_become_an_empty_valid_payload() {
    let mut dmb = template();
    dmb.procs[0].code_locals_args[2] = dmb.lists.len() as u32;
    dmb.lists.push(vec![42]);
    let mut report = StructuralReport::new("snapshot");
    audit_coverage(
        &memo::NormalizationContext::new(&dmb),
        "actual",
        &mut report,
        &anonymous::procedure_ownership(&memo::NormalizationContext::new(&dmb)),
    );
    report.finalize_coverage();
    assert!(report.uncovered.contains_key("procedure_argument_list"));
    assert!(!report.tool_complete);
}

#[test]
fn supported_unmatched_payload_is_invariant_under_reference_renumbering() {
    let expected = template();
    let mut baseline = expected.clone();
    let name = baseline.strings.len() as u32;
    baseline.strings.push(crate::dmb::DmString {
        data: b"/proc/unmatched".to_vec(),
        long_chunks: 0,
    });
    let callee = baseline.strings.len() as u32;
    baseline.strings.push(crate::dmb::DmString {
        data: b"/proc/callee".to_vec(),
        long_chunks: 0,
    });
    baseline.procs[0].strings[0] = callee;
    let mut proc_ = baseline.procs[0].clone();
    proc_.strings[0] = name;
    proc_.code_locals_args[0] = baseline.lists.len() as u32;
    baseline.lists.push(vec![0x30, 0, 0, 0x12]);
    let baseline_id = baseline.procs.len() as u32;
    baseline.procs.push(proc_);
    let mut candidate = baseline.clone();
    let new_callee_id = candidate.procs.len() as u32;
    candidate.procs.push(candidate.procs[0].clone());
    let new_name = candidate.strings.len() as u32;
    candidate
        .strings
        .push(candidate.strings[name as usize].clone());
    let mut moved = candidate.procs[baseline_id as usize].clone();
    moved.strings[0] = new_name;
    moved.code_locals_args[0] = candidate.lists.len() as u32;
    candidate.lists.push(vec![0x30, 0, new_callee_id, 0x12]);
    if moved.code_locals_args[1] != 0xffff {
        let locals = candidate.lists[moved.code_locals_args[1] as usize].clone();
        moved.code_locals_args[1] = candidate.lists.len() as u32;
        candidate.lists.push(locals);
    }
    let candidate_id = candidate.procs.len() as u32;
    candidate.procs.push(moved);
    let compare = |dmb: &Dmb, id| {
        let mut out = Collector {
            output: Vec::new(),
            limit: 0,
            report: Some(StructuralReport::new("snapshot")),
        };
        missing::compare_missing_procedures(
            &memo::NormalizationContext::new(&expected),
            &memo::NormalizationContext::new(dmb),
            &mut out,
            &BTreeMap::new(),
            &BTreeMap::from([("/proc/unmatched#0".into(), id)]),
        );
        out.report.unwrap().category_signatures
    };
    assert_eq!(
        compare(&baseline, baseline_id),
        compare(&candidate, candidate_id)
    );
}

#[test]
fn unresolved_certified_proc_operand_blocks_tool_completeness() {
    let mut report = StructuralReport::new("snapshot");
    audit_operand(
        &NormalOperand::Word(123),
        "actual:/proc/p#0:opcode CallGlob occurrence 0:operand 1",
        0x30,
        1,
        &[0, 123],
        &mut report,
    );
    report.finalize_coverage();
    assert!(!report.tool_complete);
    assert!(report
        .uncovered
        .contains_key("unresolved_required_operand_reference"));
}

#[test]
fn summary_bounds_examples_without_copying_exact_signatures() {
    let mut report = StructuralReport::new("summary-fixture");
    for index in 0..300 {
        report.record(
            "/datum/example",
            "proc.flags",
            "0".into(),
            index.to_string(),
        );
    }
    report.observe_bytecode("/datum/example/proc/check", 3, 4);
    let summary = report.summary();
    let flags = &summary.categories["procedure_flags"];
    assert_eq!(flags.discrepancy_count, 300);
    assert_eq!(flags.unique_case_count, 300);
    assert_eq!(flags.examples.len(), EXAMPLES);
    assert!(std::ptr::eq(
        flags.examples.as_ptr(),
        report.categories["procedure_flags"].examples.as_ptr()
    ));
    let json = serde_json::to_value(summary).unwrap();
    assert!(json.get("category_signatures").is_none());
    assert!(json.get("bytecode_procedures").is_none());
    assert_eq!(
        json["bytecode_shape_counts"]
            ["different_instruction_count_positional_alignment_provisional"],
        1
    );
    assert_eq!(
        json["opcode_equivalence"],
        "not_asserted_by_difference_counts_or_instruction_shapes"
    );
}
