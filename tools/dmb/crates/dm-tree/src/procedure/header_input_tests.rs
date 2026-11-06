use super::*;
use crate::frontend::{
    build_with_executor_and_semantic_state, FrontendConfig, RetainedSemanticTree,
};
use dm_ir::{FileId, SymbolTable};
use dm_syntax::AstFile;
use std::path::Path;
fn original(source: &str) -> (AstFile, Arc<OriginalProcedureHeaders>) {
    let parsed = dm_syntax::parse_declaration_skeleton(source);
    assert!(parsed.diagnostics.is_empty());
    let owner: SourceText = source.to_owned().into();
    let headers =
        OriginalProcedureHeaders::from_primary(owner, &parsed.items, 0, parsed.tokens).unwrap();
    (
        AstFile {
            items: parsed.items,
            ..Default::default()
        },
        headers,
    )
}
#[test]
fn original_tokens_remove_runtime_and_ledger_duplicate_signature_lexing() {
    for source in [
        "/proc/check(obj/item/x = list(1, 2) as obj | null in choices(x), /datum/header_decl, ...) as num\n    return x\n",
        "/datum/holder\n    proc\n        check(datum/x, list/datum/L[], value=1)\n            return x\n",
    ] {
        let (ast,headers)=original(source);
        let before_lex=super::super::header::lexical_header_calls();
        let before_parse=super::super::signature_interpretations();
        let (mut facts,receipt)=crate::adapter::from_ast_with_source_headers(&ast,SymbolTable::default(),FileId(0),0,0,source,&headers,0).unwrap();
        let after=super::super::signature_interpretations();
        assert_eq!(after-before_parse,1,"one runtime interpretation per original proc");
        assert_eq!(super::super::header::lexical_header_calls(),before_lex,"native signature must not call LexedHeader");
        let native=crate::allocation_ledger::capture_with_header_receipt(&ast.items,"/",&mut facts.symbols,&receipt).unwrap();
        assert_eq!(super::super::signature_interpretations(),after,"ledger must consume moved signature allocation results");
        assert_eq!(super::super::header::lexical_header_calls(),before_lex,"ledger must not lex arguments");
        let mut compatibility=crate::from_ast(&ast,SymbolTable::default(),FileId(0),0,0).unwrap();
        let old=crate::allocation_ledger::capture(&ast.items,"/",&mut compatibility.symbols).unwrap();
        assert_eq!(facts.skeletons,compatibility.skeletons);
        assert_eq!(native.events.iter().collect::<Vec<_>>(),old.events.iter().collect::<Vec<_>>());
        let foreign=ast.items.clone();
        assert!(crate::allocation_ledger::capture_with_header_receipt(&foreign,"/",&mut facts.symbols,&receipt).unwrap_err().message.contains("another original declaration owner"));
    }
}
#[test]
fn original_body_and_header_tokens_share_one_owner_and_foreign_equal_source_is_not_an_owner() {
    let source = "/proc/check(datum/x)\n    x = list(1,2,3,4,5)\n    return x\n";
    let lexed = dm_syntax::parse_declaration_skeleton(source);
    let original_tokens = lexed.tokens.len();
    let (ast, headers) = original(source);
    assert_eq!(headers.tokens.window().len(), original_tokens);
    assert!(
        headers
            .tokens
            .window()
            .iter()
            .any(|t| t.span.start >= ast.items[0].header_span.end),
        "original body tokens must survive for the one shared parser input"
    );
    let mut nodes = 0;
    let mut bytes = 0;
    headers.visit_storage(|_, _, capacity| {
        nodes += 1;
        bytes += capacity
    });
    assert_eq!(nodes, 3);
    assert!(bytes > headers.tokens.window().len() * std::mem::size_of::<SpanToken>());
    let copy: SourceText = source.to_owned().into();
    assert!(!headers.same_source(&copy));
    assert!(
        crate::frontend::RelativeSyntax::capture_with_settings_headers(
            ast.items,
            copy,
            &Default::default(),
            Some(headers)
        )
        .is_err()
    );
}
#[test]
fn portable_header_reissue_preserves_source_native_signature_not_serialized_authority() {
    let source =
        "/proc/check(value=length(list(1,2)) as num in world.contents)\n    return value\n";
    let (ast, cold) = original(source);
    let current: SourceText = source.to_owned().into();
    let reissued = OriginalProcedureHeaders::reissue(current, &ast.items, 0).unwrap();
    let a = cold
        .parts(ast.items[0].header_span, 0, &ast.items[0].header)
        .unwrap()
        .parse(&mut SymbolTable::default())
        .unwrap();
    let b = reissued
        .parts(ast.items[0].header_span, 0, &ast.items[0].header)
        .unwrap()
        .parse(&mut SymbolTable::default())
        .unwrap();
    assert_eq!(a.signature, b.signature);
    assert!(!Arc::ptr_eq(&cold, &reissued));
}
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
        text: &SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.0
            .lease()
            .source_text()
            .same_view(text)
            .then(|| self.0.clone())
    }
}
#[test]
fn cold_warm_and_body_only_edit_keep_one_original_header_owner_per_current_chunk() {
    fn build(state: &mut RetainedSemanticTree, source: &str) -> crate::frontend::ColdFrontend {
        let provider = Source(dm_preprocess::AcquiredSource::from_original_bytes(
            source.as_bytes().to_vec(),
            (),
        ));
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        build_with_executor_and_semantic_state(
            Path::new("headers.dme"),
            &provider,
            &Default::default(),
            FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
            None,
            &executor,
            Some(state),
        )
        .unwrap()
    }
    fn owners(front: &crate::frontend::ColdFrontend) -> Vec<(usize, usize)> {
        let mut values = Vec::new();
        front
            .body_archive()
            .unwrap()
            .visit_original_header_storage(|address, _, capacity| values.push((address, capacity)));
        values
    }
    let mut state = RetainedSemanticTree::default();
    let first = build(&mut state, "/proc/check(datum/x)\n    return 1\n");
    let warm = build(&mut state, "/proc/check(datum/x)\n    return 1\n");
    assert_eq!(
        owners(&first),
        owners(&warm),
        "unchanged in-memory contribution shares exact owners"
    );
    assert!(Arc::ptr_eq(&first.snapshot.tree, &warm.snapshot.tree));
    let edit = build(&mut state, "/proc/check(datum/x)\n    return 12345\n");
    assert!(Arc::ptr_eq(&first.snapshot.tree, &edit.snapshot.tree));
    assert_ne!(
        owners(&first),
        owners(&edit),
        "fresh source occurrence cannot inherit an old header input"
    );
    let current = edit.body_archive().unwrap();
    let old = first.body_archive().unwrap();
    let a = old.parse(0).unwrap();
    let b = current.parse(0).unwrap();
    let view = a.source_parameters().unwrap();
    assert!(view.require_for(current.tree(), b.occurrence()).is_err());
}

#[test]
fn current_body_code_authenticates_shared_token_ranges_for_live_and_archived_parse() {
    let source = "/proc/a(x)\n    return x\n/proc/b(y)\n    return y\n";
    let acquired =
        dm_preprocess::AcquiredSource::from_original_bytes(source.as_bytes().to_vec(), ());
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let front = build_with_executor_and_semantic_state(
        Path::new("body-token-authority.dme"),
        &Source(acquired),
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        None,
    )
    .unwrap();
    let a = &front.bodies[0];
    let b = &front.bodies[1];
    assert!(front
        .syntax
        .parse_original_procedure(a.expanded_span, front.body_code(a).unwrap().identity())
        .is_ok());
    assert!(
        front
            .syntax
            .parse_original_procedure(a.expanded_span, front.body_code(b).unwrap().identity())
            .is_err(),
        "another real original body code cannot authorize this range"
    );
    let archive = front.body_archive().unwrap();
    assert_eq!(
        front.parse_body(a).unwrap().item().header,
        archive.parse(0).unwrap().header().header
    );
    let forged = Span::new(a.expanded_span.start, a.expanded_span.end + 1);
    assert!(
        front
            .syntax
            .parse_original_procedure(forged, front.body_code(a).unwrap().identity())
            .is_err(),
        "nearby equal-prefix span must not bypass exact original envelope"
    );
}
