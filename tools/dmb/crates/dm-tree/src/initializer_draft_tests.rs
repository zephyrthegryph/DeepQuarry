use super::*;
use dm_ir::{FileId, ProcedureIdentity, SymbolId, SymbolTable};

fn fixture() -> (
    TreeSnapshot,
    Vec<OccurrenceId>,
    OccurrenceId,
    crate::procedure_statics::StaticPlan,
) {
    let text = "var/a = mark(1)\n/proc/work()\n    var/static/local = mark(2)\n    return local\nvar/b = mark(3)\n";
    let ast = dm_syntax::parse(text);
    let snapshot = crate::from_ast(&ast, SymbolTable::default(), FileId(0), 0, 0)
        .unwrap()
        .finish()
        .unwrap();
    let order: Vec<_> = (0..snapshot.occurrences.source_order().len())
        .map(|index| OccurrenceId(index as u32))
        .collect();
    let occurrence = order.iter().copied().find(|id| snapshot.occurrences.get(*id).is_some_and(|row| matches!(row.target, Target::Member(member) if snapshot.tree.member(member).is_some_and(|node| node.kind == MemberKind::Proc)))).unwrap();
    let procedure = ast
        .items
        .iter()
        .find(|item| item.header.contains("work("))
        .unwrap();
    let identity = ProcedureIdentity {
        owner: SymbolId::of("/"),
        name: SymbolId::of("work"),
        verb: false,
        occurrence: 0,
    };
    let capture = crate::procedure_statics::capture(identity, &procedure.children).unwrap();
    (snapshot, order, occurrence, capture)
}
#[test]
fn owned_rows_and_analysis_plan_preserve_exact_interleaving_and_legacy_hash() {
    let (snapshot, order, occurrence, capture) = fixture();
    let draft = capture_declaration_draft(&snapshot, &order).unwrap();
    let base = plan(&snapshot, &order).unwrap();
    let borrowed = with_procedure_statics(&base, &order, &[]).unwrap();
    assert_eq!(borrowed.origins, base.origins);
    let issued = capture_declaration_plan(&snapshot, &order).unwrap();
    let expected =
        with_captured_procedure_statics_borrowed(&issued, [(occurrence, &capture)]).unwrap();
    let owned = finish_declaration_draft(draft, [(occurrence, &capture)]).unwrap();
    assert_eq!(owned.writes.as_ref(), expected.writes.as_ref());
    assert_eq!(owned.origins.as_ref(), expected.origins.as_ref());
    assert_eq!(owned.identity, expected.identity);
    let targets: Vec<_> = owned.writes.iter().map(|write| &write.target).collect();
    assert!(
        matches!(targets[0], InitializerTarget::Shared { name, .. } if *name == SymbolId::of("a"))
    );
    assert!(
        matches!(targets[1], InitializerTarget::ProcedureStatic(identity) if identity.name == SymbolId::of("local"))
    );
    assert!(
        matches!(targets[2], InitializerTarget::Shared { name, .. } if *name == SymbolId::of("b"))
    );
    let mut legacy = b"dm-authored-startup-plan-v2\0".to_vec();
    for (actual, expected) in owned.writes.iter().zip(expected.writes.iter()) {
        let bytes = expected.canonical_bytes();
        assert_eq!(actual.canonical_bytes(), bytes);
        legacy.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
        legacy.extend_from_slice(&bytes);
    }
    assert_eq!(owned.identity, xxhash_rust::xxh3::xxh3_128(&legacy));
}
#[test]
fn owned_rows_preserve_capture_validation_and_declaration_error_order() {
    let (snapshot, order, occurrence, capture) = fixture();
    let issued = capture_declaration_plan(&snapshot, &order).unwrap();
    let captures = [(occurrence, &capture), (occurrence, &capture)];
    let borrowed = with_captured_procedure_statics_borrowed(&issued, captures).unwrap_err();
    let owned = finish_declaration_draft(
        capture_declaration_draft(&snapshot, &order).unwrap(),
        captures,
    )
    .unwrap_err();
    assert_eq!(owned, "duplicate or incomplete procedure static capture");
    assert_eq!(borrowed, owned);
    let mut duplicate = order.clone();
    duplicate[1] = duplicate[0];
    let expected = plan(&snapshot, &duplicate).unwrap_err();
    let actual = match capture_declaration_draft(&snapshot, &duplicate) {
        Err(error) => error,
        Ok(_) => panic!("duplicate order accepted"),
    };
    assert_eq!(actual, expected);
    assert_eq!(actual, vec![PlanError::DuplicateOccurrence(duplicate[0])]);
}
