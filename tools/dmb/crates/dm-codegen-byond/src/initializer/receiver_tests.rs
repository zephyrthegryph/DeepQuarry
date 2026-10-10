//! Exact native initializer receiver golden; table IDs bind to native spellings.
use super::*;
use dm_ir::SymbolId;

struct Fields;
impl Resolver for Fields {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        let owner = SymbolId::of("/datum/probe");
        match query {
            ResolveQuery::VarStorage {
                owner: actual,
                name,
            } if actual == owner => ResolvedMeaning::InstanceField {
                declaring_owner: owner,
                name,
            },
            ResolveQuery::HasMemberVar { owner: actual, .. } if actual == owner => {
                ResolvedMeaning::Presence(true)
            }
            ResolveQuery::DeclaredVarType { owner: actual, .. } if actual == owner => {
                ResolvedMeaning::DeclaredType(None)
            }
            ResolveQuery::GlobalVar(_) => ResolvedMeaning::Missing,
            _ => ResolvedMeaning::Unsupported(query),
        }
    }
}

#[test]
fn instance_list_initializers_match_native_complete_words() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/initializer_receiver/initializer_receiver.native.bin"
    ))
    .unwrap();
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/datum/probe").unwrap();
    let assignments: Vec<_> = [
        ("empty", "list()"),
        ("numbers", "list(1,2)"),
        ("assoc", "list(\"x\"=3)"),
    ]
    .into_iter()
    .map(|(name, source)| {
        let name = symbols.intern(name).unwrap();
        (
            InitializerTarget::Instance {
                declaring_owner: owner,
                receiver_owner: owner,
                name,
            },
            owner,
            dm_syntax::parse_expression(source).expr.unwrap(),
        )
    })
    .collect();
    let compiled = lower_assignments(
        &assignments,
        owner,
        InitializerContext {
            symbols: &symbols,
            resource_search_context: None,
            debug: None,
        },
        &Fields,
    )
    .unwrap();
    let mut ledger = crate::Ledger::default();
    for payload in &compiled.procedure.strings {
        let id = (0..native.strings.len())
            .find(|&id| native.string(id as u32) == Some(payload.bytes.as_ref()))
            .unwrap();
        ledger.bind(SymRef::String(payload.id), id as u32).unwrap();
    }
    let linked = crate::link_proc(&compiled.procedure.code, &ledger).unwrap();
    let class = native
        .classes
        .iter()
        .find(|class| native.string(class.path_string_id()) == Some(b"/datum/probe"))
        .unwrap();
    assert_eq!(
        linked.words,
        native
            .proc_code_words(class.initializer_proc_id() as usize)
            .unwrap()
    );
}

#[test]
fn declaration_and_override_receivers_match_authenticated_complete_words() {
    use dm_ir::InitializerSite::{Assignment, Declaration};
    let cases: &[(dm_ir::InitializerSite, &[u8])] = &[
        (Declaration, include_bytes!("../../../../fixtures/translation/initializer_receiver_contexts/declared.native.bin")),
        (Assignment, include_bytes!("../../../../fixtures/translation/initializer_receiver_contexts/reopened.native.bin")),
        (Assignment, include_bytes!("../../../../fixtures/translation/initializer_receiver_contexts/inherited.native.bin")),
    ];
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/datum/probe").unwrap();
    let name = symbols.intern("values").unwrap();
    let target = InitializerTarget::Instance {
        declaring_owner: owner,
        receiver_owner: owner,
        name,
    };
    let value = dm_syntax::parse_expression("list(1,2)").expr.unwrap();
    let views = [
        AssignmentView {
            source_site: Declaration,
            target: &target,
            lexical_owner: owner,
            value: &value,
            occurrence: value.span,
        },
        AssignmentView {
            source_site: Assignment,
            target: &target,
            lexical_owner: owner,
            value: &value,
            occurrence: value.span,
        },
    ];
    let mut expected_mixed = Vec::new();
    let mut mixed_ledger = crate::Ledger::default();
    for (index, (site, bytes)) in cases.iter().enumerate() {
        let native = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
        let view = [AssignmentView {
            source_site: *site,
            ..views[0]
        }];
        let code = lower_assignment_views(
            &view,
            InitializerContext {
                symbols: &symbols,
                resource_search_context: None,
                debug: None,
            },
            &Fields,
        )
        .unwrap();
        let mut ledger = crate::Ledger::default();
        for payload in &code.procedure.strings {
            let id = (0..native.strings.len())
                .find(|&id| native.string(id as u32) == Some(payload.bytes.as_ref()))
                .unwrap();
            ledger.bind(SymRef::String(payload.id), id as u32).unwrap();
        }
        let class = native
            .classes
            .iter()
            .find(|class| native.string(class.path_string_id()) == Some(b"/datum/probe"))
            .unwrap();
        let expected = native
            .proc_code_words(class.initializer_proc_id() as usize)
            .unwrap();
        assert_eq!(
            crate::link_proc(&code.procedure.code, &ledger)
                .unwrap()
                .words,
            expected
        );
        if index == 0 {
            mixed_ledger = ledger;
        }
        if index < 2 {
            expected_mixed.extend_from_slice(&expected[..expected.len() - 1]);
        }
    }
    expected_mixed.push(opcode::END);
    let context = || InitializerContext {
        symbols: &symbols,
        resource_search_context: None,
        debug: None,
    };
    let whole = lower_assignment_views(&views, context(), &Fields).unwrap();
    let group = prepare_assignment_group(&views, context(), &Fields).unwrap();
    let fragments = (0..views.len())
        .map(|index| group.lower_fragment(index, &Fields).unwrap())
        .collect();
    let assembled = group.assemble(fragments).unwrap();
    assert_eq!(
        crate::link_proc(&whole.procedure.code, &mixed_ledger)
            .unwrap()
            .words,
        expected_mixed
    );
    assert_eq!(
        crate::link_proc(&assembled.procedure.code, &mixed_ledger)
            .unwrap()
            .words,
        expected_mixed
    );
    let empty = byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/translation/initializer_receiver_contexts/uninitialized_typed_list.native.bin")).unwrap();
    let class = empty
        .classes
        .iter()
        .find(|class| empty.string(class.path_string_id()) == Some(b"/datum/probe"))
        .unwrap();
    assert_eq!(class.initializer_proc_id(), 65535);
}
