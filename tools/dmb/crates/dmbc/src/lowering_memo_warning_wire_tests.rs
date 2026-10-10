//! Rich replay uses the same warning receipt admission as compact replay.
use super::*;
struct Host;
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> dm_ir::ResolvedMeaning {
        match query {
            ResolveQuery::RuntimeType(id) => dm_ir::ResolvedMeaning::Symbol(id),
            _ => dm_ir::ResolvedMeaning::Missing,
        }
    }
}
struct Origin;
impl dm_codegen_byond::DebugSourceProvider for Origin {
    fn entry_ordinal(&self) -> Result<u32, String> {
        Ok(0)
    }
    fn ordinal(&self, _: usize) -> Result<u32, String> {
        Ok(0)
    }
}
#[test]
fn rich_warning_replay_rejects_invalid_receipts_and_binds_current_coordinates() {
    let ast = dm_syntax::parse("/proc/p()\n    var/list/value[2] = null\n    return value\n");
    let code = dm_codegen_byond::compile_simple_proc_with_resolver_and_debug(
        &ast.items[0].children,
        &Default::default(),
        &Default::default(),
        &Host,
        Some(&Origin),
    )
    .unwrap();
    assert_eq!(code.procedure.warnings.len(), 1);
    let key = b"exact source/configuration";
    let bytes = encode_executable(key, &[], &[], &code).unwrap();
    let restored = decode_executable(&bytes, key, &Host, 1).unwrap();
    assert_eq!(restored.procedure.warnings, code.procedure.warnings);
    assert!(decode_executable(&bytes, key, &Host, 0).is_none());
    for (path, line) in [("original.dm", 2), ("current.dm", 12)] {
        let origins: crate::debug_sources::FrozenDebugOrigins =
            crate::debug_sources::DebugOrigins {
                entries: vec![crate::debug_sources::DebugOrigin {
                    semantic_path: path.into(),
                    line,
                }],
            }
            .into();
        let symbols = dm_ir::SymbolTable::default();
        let bind = |warnings: &[dm_codegen_byond::ProcedureWarning]| {
            crate::initializer_policy::warnings::render(
                &crate::procedure_warnings::bind(
                    warnings,
                    &origins,
                    &symbols,
                    &restored.procedure.local_names,
                )
                .unwrap(),
            )
            .unwrap()
        };
        assert_eq!(
            bind(&restored.procedure.warnings),
            bind(&code.procedure.warnings)
        );
        assert_eq!(
            bind(&restored.procedure.warnings),
            [format!(
                "{path}:{line}:warning (list_double_init): value: list doubly initialized\n"
            )]
        );
    }
    for mode in 0..5 {
        let mut bad = payload(&bytes).unwrap();
        let warning = &mut bad.body.code.warnings[0];
        match mode {
            0 => warning.source_ordinal = None,
            1 => warning.source_ordinal = Some(u32::MAX),
            2 => warning.name = None,
            3 => warning.name = Some(SymbolId::of("absent")),
            _ => warning.code = dm_ir::WarningCode::ListWithoutFilter,
        }
        let bytes = dm_wire::encode(EXECUTABLE_SCHEMA, &bad).unwrap();
        assert!(decode_executable(&bytes, key, &Host, 1).is_none());
        let framed = dm_cache::encode_variants(&[bytes]).unwrap();
        assert!(candidates(&framed)
            .unwrap()
            .anonymous(key, &Host, 1)
            .code
            .is_none());
    }
    // The same CodeWire validator is used for every cached companion.
    let mut helper = CodeWire::capture(&code);
    helper.code.warnings[0].source_ordinal = Some(1);
    assert!(helper.rehydrate(&Host, 1).is_none());
}
