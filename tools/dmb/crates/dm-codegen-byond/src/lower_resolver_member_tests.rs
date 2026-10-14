use super::tests::{lower, Host};
use super::*;
use std::sync::Mutex;
#[test]
fn positive_member_proc_does_not_require_opposite_namespace_absence() {
    let mut symbols = SymbolTable::default();
    symbols.intern("/datum/probe").unwrap();
    symbols.intern("/datum/base").unwrap();
    for name in ["authored", "intrinsic", "verb_only", "unknown"] {
        symbols.intern(name).unwrap();
    }
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::Proc {
                owner,
                name,
                verb: false,
            } if name == SymbolId::of("authored") => M::Member {
                owner,
                name,
                fingerprint: 1,
                data: std::sync::Arc::new(Default::default()),
            },
            Q::Proc {
                owner,
                name,
                verb: false,
            } if name == SymbolId::of("intrinsic") => M::IntrinsicProc {
                declaring_owner: owner,
                name,
            },
            Q::Proc {
                name, verb: false, ..
            } if name == SymbolId::of("verb_only") => M::Missing,
            Q::Proc {
                owner,
                name,
                verb: true,
            } if name == SymbolId::of("verb_only") => M::Member {
                owner,
                name,
                fingerprint: 2,
                data: std::sync::Arc::new(Default::default()),
            },
            Q::MethodProcedureValue { owner, name, verb }
                if owner == SymbolId::of("/datum/probe")
                    && (name == SymbolId::of("authored") || name == SymbolId::of("verb_only")) =>
            {
                M::Value(dm_ir::SemanticValue::Procedure(dm_ir::ProcedureIdentity {
                    owner: SymbolId::of("/datum/base"),
                    name,
                    verb,
                    occurrence: 7,
                }))
            }
            _ => M::Unsupported(query),
        },
    };
    let lookup = ProjectResolver {
        modified_instances: RefCell::new(Default::default()),
        procedure_values: RefCell::new(Default::default()),
        procedure_statics: RefCell::new(Default::default()),
        resolver: &host,
        symbols: &symbols,
        slots: RefCell::new(Default::default()),
        resources: RefCell::new(Default::default()),
        instances: RefCell::new(Default::default()),
        runtime_types: RefCell::new(Default::default()),
        resource_search_context: None,
    };
    assert_eq!(
        lookup.member_proc("/datum/probe", "authored").unwrap(),
        Some(dm_ir::SymRef::Proc {
            owner: SymbolId::of("/datum/base"),
            name: SymbolId::of("authored"),
            occurrence: 7
        })
    );
    assert_eq!(
        lookup.member_proc("/datum/probe", "intrinsic").unwrap(),
        None
    );
    assert_eq!(host.reads.lock().unwrap().len(), 3);
    assert!(host.reads.lock().unwrap().iter().all(|query| matches!(
        query,
        Q::Proc { verb: false, .. } | Q::MethodProcedureValue { verb: false, .. }
    )));
    assert_eq!(
        lookup.member_proc("/datum/probe", "verb_only").unwrap(),
        Some(dm_ir::SymRef::Verb {
            owner: SymbolId::of("/datum/base"),
            name: SymbolId::of("verb_only"),
            occurrence: 7
        })
    );
    assert!(lookup.member_proc("/datum/probe", "unknown").is_err());
}
#[test]
fn procedure_literal_lowering_keeps_exact_formal_identity_sidecar() {
    let owner = SymbolId::of("/datum/base");
    let name = SymbolId::of("callback");
    let identity = dm_ir::ProcedureIdentity {
        owner,
        name,
        verb: false,
        occurrence: 0,
    };
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::ProcedureValue {
                owner: found,
                name: found_name,
                verb: false,
                formal: true,
            } if found == SymbolId::of("/datum/base") && found_name == SymbolId::of("callback") => {
                M::Value(SemanticValue::Procedure(dm_ir::ProcedureIdentity {
                    owner: found,
                    name: found_name,
                    verb: false,
                    occurrence: 0,
                }))
            }
            _ => M::Unsupported(query),
        },
    };
    let parsed = dm_syntax::parse("/proc/p()\n    return list(/datum/base/proc/callback)\n");
    let code = crate::compile_simple_proc_with_resolver(
        &parsed.items[0].children,
        &ProcedureInputs::default(),
        &SymbolTable::default(),
        &host,
    )
    .unwrap();
    assert_eq!(code.procedure_values.len(), 1);
    assert_eq!(code.procedure_values.values().next(), Some(&identity));
    assert_eq!(
        host.reads.lock().unwrap().as_slice(),
        &[Q::ProcedureValue {
            owner,
            name,
            verb: false,
            formal: true
        }]
    );
}
