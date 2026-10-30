use super::*;
use std::path::Path;
struct Source(dm_preprocess::AcquiredSource);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("original acquisition required".into())
    }
    fn acquired_source(&self, _: &Path) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        Ok(Some(self.0.clone()))
    }
    fn source_acquisition(
        &self,
        _: &Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.0
            .lease()
            .source_text()
            .same_view(text)
            .then(|| self.0.clone())
    }
}
fn front(source: &str) -> dm_tree::frontend::ColdFrontend {
    let source = Source(dm_preprocess::AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    dm_tree::frontend::build(
        Path::new("original-abi.dme"),
        &source,
        &Default::default(),
        1,
    )
    .unwrap()
}
#[test]
fn original_formal_receipt_requires_exact_current_metadata_occurrence_and_symbol_owner() {
    let frontend = front("/proc/p(x=null as mob in world)\n    return x\n");
    let occurrence = &frontend.bodies[0];
    let metadata = frontend
        .snapshot
        .tree
        .member(occurrence.member)
        .unwrap()
        .metadata
        .procedure
        .as_deref()
        .unwrap();
    let receipt = OriginalFormalTokens::capture(&frontend, occurrence, metadata).unwrap();
    receipt
        .require_for(metadata, frontend.snapshot.tree.symbols())
        .unwrap();
    assert!(OriginalFormalTokens::capture(&frontend, &occurrence.clone(), metadata).is_err());
    assert!(OriginalFormalTokens::capture(&frontend, occurrence, &metadata.clone()).is_err());
    assert!(receipt
        .require_for(&metadata.clone(), frontend.snapshot.tree.symbols())
        .is_err());
    assert!(receipt
        .require_for(metadata, &SymbolTable::default())
        .is_err());
    let foreign = front("/proc/p(x=null as mob in world)\n    return x\n");
    assert!(OriginalFormalTokens::capture(&foreign, occurrence, metadata).is_err());
}
#[test]
fn original_formal_receipts_are_source_neutral_but_reissued_for_each_current_owner() {
    let mut canonical = None;
    for padding in ["", "\n\n"] {
        let frontend = front(&format!(
            "{padding}/proc/p(x=null as mob in world)\n    return x\n"
        ));
        let occurrence = &frontend.bodies[0];
        let metadata = frontend
            .snapshot
            .tree
            .member(occurrence.member)
            .unwrap()
            .metadata
            .procedure
            .as_deref()
            .unwrap();
        let receipt = OriginalFormalTokens::capture(&frontend, occurrence, metadata).unwrap();
        receipt
            .require_for(metadata, frontend.snapshot.tree.symbols())
            .unwrap();
        let prepared = procedure_abi::prepare_verified_procedure_original_tokens(
            metadata,
            frontend.snapshot.tree.symbols(),
            &[],
            ProcedureInputs::default(),
            InheritedAbi::Fresh,
            |_| Err(AbiError::unsupported("unused")),
        )
        .unwrap();
        let abi = PreparedAbi {
            layout: prepared.layout,
            argument_sources: prepared.argument_sources,
            source_helpers: prepared.source_helpers,
        };
        if let Some(old) = canonical.as_ref() {
            assert_eq!(&abi.canonical_bytes(), old);
        } else {
            canonical = Some(abi.canonical_bytes());
        }
    }
}

#[test]
fn original_abi_tokens_do_not_demand_optional_default_roots_or_tighten_body_acceptance() {
    for (default, optional_refused) in [
        (format!("\"{}\"", "a".repeat(4096)), false),
        (format!("\"[{}1]\"", "!".repeat(4000)), true),
        (format!("{}1", "!".repeat(300)), true),
    ] {
        let frontend = front(&format!(
            "/proc/p(x={default} as text in world)\n    return x\n"
        ))
        .with_body_queries(Arc::new(crate::query_db::QueryDb::default()));
        let occurrence = &frontend.bodies[0];
        // This invokes the real BodySyntaxInput::parse gate. The optional
        // resource frontier must neither hide the body nor reject ABI tokens.
        let parsed = frontend.parse_body(occurrence).unwrap();
        assert_eq!(
            parsed.source_header_expressions().is_err(),
            optional_refused
        );
        let metadata = frontend
            .snapshot
            .tree
            .member(occurrence.member)
            .unwrap()
            .metadata
            .procedure
            .as_deref()
            .unwrap();
        let receipt = OriginalFormalTokens::capture(&frontend, occurrence, metadata).unwrap();
        receipt
            .require_for(metadata, frontend.snapshot.tree.symbols())
            .unwrap();
        let old = procedure_abi::prepare_verified_procedure(
            metadata,
            frontend.snapshot.tree.symbols(),
            &[],
            ProcedureInputs::default(),
            InheritedAbi::Fresh,
            |_| Err(AbiError::unsupported("unused")),
        )
        .unwrap();
        let actual = procedure_abi::prepare_verified_procedure_original_tokens(
            metadata,
            frontend.snapshot.tree.symbols(),
            &[],
            ProcedureInputs::default(),
            InheritedAbi::Fresh,
            |_| Err(AbiError::unsupported("unused")),
        )
        .unwrap();
        assert_eq!(
            old.inputs.parameter_defaults,
            actual.inputs.parameter_defaults
        );
        assert_eq!(
            old.inputs.parameter_type_flags,
            actual.inputs.parameter_type_flags
        );
        assert_eq!(old.argument_sources, actual.argument_sources);
        assert_eq!(old.layout, actual.layout);
    }
}
