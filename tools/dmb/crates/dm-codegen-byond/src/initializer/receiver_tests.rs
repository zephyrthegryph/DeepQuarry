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
