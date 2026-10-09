use super::*;
use std::sync::atomic::{AtomicBool, Ordering};

struct BorrowedPolicy(AtomicBool);
impl AbiPolicy for BorrowedPolicy {
    fn inputs(
        &self,
        _: UnitIdentity,
        _: &ProcedureMetadata,
        _: &SymbolTable,
        _: &SourceLocation,
    ) -> Result<ProcedureInputs, String> {
        Ok(ProcedureInputs::default())
    }
    fn prepare_captured(
        &self,
        metadata: &ProcedureMetadata,
        parsed: &dm_tree::frontend::ParsedBody<'_>,
        context: &AbiContext<'_>,
    ) -> Result<PreparedUnit, String> {
        assert!(!parsed.item().children.is_empty());
        self.0.store(true, Ordering::Relaxed);
        self.prepare(metadata, parsed.item(), context)
    }
}

#[test]
fn owned_preparation_preserves_borrowed_custom_policy_and_exact_header() {
    let frontend = frontend("/proc/p()\n    return 7\n");
    let body = &frontend.bodies[0];
    let identity = crate::lowering::source_unit_identity(&frontend, body)
        .unwrap()
        .identity;
    let tree = frontend.snapshot.tree.as_ref();
    let member = tree.member(body.member).unwrap();
    let metadata = member.metadata.procedure.as_ref().unwrap();
    let parsed = frontend.parse_body(body).unwrap();
    let header = parsed.item().header.clone();
    let span = parsed.item().header_span;
    let policy = BorrowedPolicy(AtomicBool::new(false));
    let context = AbiContext {
        identity,
        symbols: tree.symbols(),
        origin: &body.source,
        resolver: &Host,
    };
    let (prepared, retained_header) = policy
        .prepare_owned_captured(metadata, parsed, &context)
        .unwrap();
    assert!(policy.0.load(Ordering::Relaxed));
    assert!(!prepared.executable_body.is_empty());
    assert_eq!(retained_header.header, header);
    assert_eq!(retained_header.header_span, span);
    assert!(retained_header.children.is_empty());
}
