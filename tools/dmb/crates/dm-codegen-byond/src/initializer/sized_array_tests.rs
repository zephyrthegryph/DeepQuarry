//! Complete words from pinned516.1687 sized-array capture receipt beside fixtures.
use super::*;
use dm_ir::SymbolId;
struct Host;
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        let owner = SymbolId::of("/datum/probe");
        let name = SymbolId::of("value");
        match query {
            ResolveQuery::VarStorage {
                owner: actual,
                name: actual_name,
            } if actual == owner => ResolvedMeaning::InstanceField {
                declaring_owner: owner,
                name: actual_name,
            },
            ResolveQuery::HasMemberVar { owner: actual, .. } if actual == owner => {
                ResolvedMeaning::Presence(true)
            }
            ResolveQuery::DeclaredVarType { .. } => ResolvedMeaning::DeclaredType(None),
            ResolveQuery::VarStorage { owner: actual, .. } if actual == SymbolId::of("/") => {
                ResolvedMeaning::Slot {
                    symbol: name,
                    owner: actual,
                    name,
                }
            }
            ResolveQuery::GlobalVar(actual) if actual == name => ResolvedMeaning::Slot {
                symbol: name,
                owner: SymbolId::of("/"),
                name,
            },
            ResolveQuery::RuntimeType(path) if path == SymbolId::of("/list") => {
                ResolvedMeaning::Symbol(path)
            }
            ResolveQuery::GlobalVar(_) => ResolvedMeaning::Missing,
            _ => ResolvedMeaning::Unsupported(query),
        }
    }
}
#[test]
fn explicit_sized_values_match_authenticated_complete_words_and_fragment_assembly() {
    let cases: &[(bool, bool, &[u8])] = &[
        (
            true,
            true,
            include_bytes!(
                "../../../../fixtures/native/sized_array_initializers/instance_list.native.bin"
            ),
        ),
        (
            true,
            false,
            include_bytes!(
                "../../../../fixtures/native/sized_array_initializers/instance_null.native.bin"
            ),
        ),
        (
            false,
            true,
            include_bytes!(
                "../../../../fixtures/native/sized_array_initializers/global_list.native.bin"
            ),
        ),
        (
            false,
            false,
            include_bytes!(
                "../../../../fixtures/native/sized_array_initializers/global_null.native.bin"
            ),
        ),
    ];
    let extra_cases: &[(bool, bool, &[u8])] = &[
        (
            false,
            true,
            include_bytes!(
                "../../../../fixtures/native/sized_array_initializers/static_list.native.bin"
            ),
        ),
        (
            false,
            false,
            include_bytes!(
                "../../../../fixtures/native/sized_array_initializers/static_null.native.bin"
            ),
        ),
        (
            true,
            true,
            include_bytes!(
                "../../../../fixtures/native/sized_array_initializers/multidim_list.native.bin"
            ),
        ),
    ];
    for &(instance, assigned, bytes) in cases.iter().chain(extra_cases) {
        let native = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
        let mut symbols = SymbolTable::default();
        let owner = symbols
            .intern(if instance { "/datum/probe" } else { "/" })
            .unwrap();
        let name = symbols.intern("value").unwrap();
        symbols.intern("/list").unwrap();
        let target = if instance {
            InitializerTarget::Instance {
                declaring_owner: owner,
                receiver_owner: owner,
                name,
            }
        } else {
            InitializerTarget::Shared {
                slot: name,
                owner,
                name,
            }
        };
        let value = dm_syntax::parse_expression(if assigned { "list(1,2)" } else { "null" })
            .expr
            .unwrap();
        let assignments = [AssignmentView {
            source_site: dm_ir::InitializerSite::Declaration,
            target: &target,
            lexical_owner: owner,
            value: &value,
            occurrence: dm_syntax::Span::new(0, 0),
        }];
        let continuation = Some(ValueContinuation {
            dimensions: if bytes == extra_cases[2].2 {
                &[2, 3]
            } else {
                &[2]
            },
            before_assignment: !instance,
            emit_assignment: assigned,
            assignment_is_allocation: false,
        });
        let context = || InitializerContext {
            symbols: &symbols,
            resource_search_context: None,
            debug: None,
        };
        let whole =
            lower_with_value_continuations(&assignments, context(), &Host, vec![continuation])
                .unwrap();
        let prepared = prepare_assignment_group(&assignments, context(), &Host)
            .unwrap()
            .with_value_continuations(vec![continuation])
            .unwrap();
        let fragment = prepared.lower_fragment(0, &Host).unwrap();
        let assembled = prepared.assemble(vec![fragment]).unwrap();
        let mut ledger = crate::Ledger::default();
        for payload in &whole.procedure.strings {
            let id = (0..native.strings.len())
                .find(|&id| native.string(id as u32) == Some(payload.bytes.as_ref()))
                .unwrap();
            ledger.bind(SymRef::String(payload.id), id as u32).unwrap();
        }
        ledger.bind(SymRef::VariableSlot(name), 67).unwrap();
        ledger.bind(SymRef::Type(SymbolId::of("/list")), 0).unwrap();
        let expected = native.proc_code_words(native.procs.len() - 1).unwrap();
        assert_eq!(
            crate::link_proc(&whole.procedure.code, &ledger)
                .unwrap()
                .words,
            expected
        );
        assert_eq!(
            crate::link_proc(&assembled.procedure.code, &ledger)
                .unwrap()
                .words,
            expected
        );
    }
}

#[test]
fn implicit_allocation_and_inherited_override_match_authenticated_words() {
    let cases: &[(&[u8], usize, &[u16], bool)] = &[
        (
            include_bytes!(
                "../../../../fixtures/native/sized_array_initializers/inherited_list.native.bin"
            ),
            68,
            &[2],
            true,
        ),
        (
            include_bytes!(
                "../../../../fixtures/native/sized_array_initializers/multidim_implicit.native.bin"
            ),
            67,
            &[2, 3],
            true,
        ),
        (
            include_bytes!(
                "../../../../fixtures/native/sized_array_initializers/inherited_list.native.bin"
            ),
            67,
            &[],
            false,
        ),
    ];
    for &(bytes, id, dimensions, allocation) in cases {
        let native = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
        let mut symbols = SymbolTable::default();
        let owner = symbols.intern("/datum/probe").unwrap();
        let name = symbols.intern("value").unwrap();
        symbols.intern("/list").unwrap();
        let target = InitializerTarget::Instance {
            declaring_owner: owner,
            receiver_owner: owner,
            name,
        };
        let value = dm_syntax::parse_expression(if allocation { "null" } else { "list(1,2)" })
            .expr
            .unwrap();
        let views = [AssignmentView {
            source_site: if allocation {
                dm_ir::InitializerSite::Declaration
            } else {
                dm_ir::InitializerSite::Assignment
            },
            target: &target,
            lexical_owner: owner,
            value: &value,
            occurrence: dm_syntax::Span::new(0, 0),
        }];
        let continuations = vec![allocation.then_some(ValueContinuation {
            dimensions,
            before_assignment: false,
            emit_assignment: true,
            assignment_is_allocation: true,
        })];
        let context = || InitializerContext {
            symbols: &symbols,
            resource_search_context: None,
            debug: None,
        };
        let whole = lower_with_value_continuations(&views, context(), &Host, continuations.clone())
            .unwrap();
        let group = prepare_assignment_group(&views, context(), &Host)
            .unwrap()
            .with_value_continuations(continuations)
            .unwrap();
        let fragment = group.lower_fragment(0, &Host).unwrap();
        let assembled = group.assemble(vec![fragment]).unwrap();
        let mut ledger = crate::Ledger::default();
        for payload in &whole.procedure.strings {
            let id = (0..native.strings.len())
                .find(|&id| native.string(id as u32) == Some(payload.bytes.as_ref()))
                .unwrap();
            ledger.bind(SymRef::String(payload.id), id as u32).unwrap();
        }
        ledger.bind(SymRef::Type(SymbolId::of("/list")), 0).unwrap();
        let expected = native.proc_code_words(id).unwrap();
        assert_eq!(
            crate::link_proc(&whole.procedure.code, &ledger)
                .unwrap()
                .words,
            expected
        );
        assert_eq!(
            crate::link_proc(&assembled.procedure.code, &ledger)
                .unwrap()
                .words,
            expected
        );
    }
}
