use super::*;
use std::sync::Mutex;
struct Host {
    parent: Option<bool>,
    reads: Mutex<Vec<Q>>,
}
impl Resolver for Host {
    fn resolve(&self, query: Q) -> M {
        self.reads.lock().unwrap().push(query);
        let owner = SymbolId::of("/datum/probe");
        let name = SymbolId::of("f");
        match query {
            Q::DeclarationChain { .. } => M::Members(
                vec![M::Declaration {
                    identity: dm_ir::ProcedureIdentity {
                        owner,
                        name,
                        verb: false,
                        occurrence: 0,
                    },
                    definition: dm_ir::ProcedureDefinition::Declare,
                    previous: None,
                    data: Arc::new(Default::default()),
                }]
                .into(),
            ),
            Q::Ancestry(_) => M::Symbols(vec![owner, SymbolId::of("/datum")].into()),
            Q::Proc { .. } => match self.parent {
                Some(false) => M::Missing,
                Some(true) => M::Member {
                    owner: SymbolId::of("/datum"),
                    name,
                    data: Arc::new(Default::default()),
                    fingerprint: 2,
                },
                None => M::Unsupported(query),
            },
            _ => M::Unsupported(query),
        }
    }
}
#[test]
fn parent_diagnostic_requires_exact_negative_reads_and_current_occurrence() {
    let symbols = SymbolTable::default();
    for parent in [Some(false), Some(true), None] {
        let host = Host {
            parent,
            reads: Mutex::new(vec![]),
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
        let identity = dm_ir::ProcedureIdentity {
            owner: SymbolId::of("/datum/probe"),
            name: SymbolId::of("f"),
            verb: false,
            occurrence: 0,
        };
        assert_eq!(lookup.parent_presence(identity), parent);
        struct Debug;
        impl crate::DebugSourceProvider for Debug {
            fn entry_ordinal(&self) -> Result<u32, String> {
                Ok(0)
            }
            fn ordinal(&self, _: usize) -> Result<u32, String> {
                Ok(1)
            }
        }
        let ast = dm_syntax::parse("/datum/probe/proc/f()\n    return ..()\n");
        let compiled = crate::compile_simple_proc_with_resolver_and_debug(
            &ast.items[0].children,
            &ProcedureInputs {
                procedure_identity: Some(identity),
                ..Default::default()
            },
            &symbols,
            &host,
            Some(&Debug),
        )
        .unwrap();
        assert_eq!(
            compiled.procedure.warnings.len(),
            usize::from(parent == Some(false))
        );
        if let Some(warning) = compiled.procedure.warnings.first() {
            assert_eq!(warning.code, dm_ir::WarningCode::NoParent);
            assert_eq!(warning.name, None);
            assert_eq!(warning.source_ordinal, Some(1));
        }
        assert!(host
            .reads
            .lock()
            .unwrap()
            .iter()
            .any(|q| matches!(q, Q::Proc { .. })));
        assert_eq!(
            lookup.parent_presence(dm_ir::ProcedureIdentity {
                occurrence: 1,
                ..identity
            }),
            None
        );
    }
}

fn view<'a>(resolver: &'a dyn Resolver, symbols: &'a SymbolTable) -> ProjectResolver<'a> {
    ProjectResolver {
        modified_instances: RefCell::new(Default::default()),
        procedure_values: RefCell::new(Default::default()),
        procedure_statics: RefCell::new(Default::default()),
        resolver,
        symbols,
        slots: RefCell::new(Default::default()),
        resources: RefCell::new(Default::default()),
        instances: RefCell::new(Default::default()),
        runtime_types: RefCell::new(Default::default()),
        resource_search_context: None,
    }
}
fn identity(owner: &str, occurrence: u32) -> dm_ir::ProcedureIdentity {
    dm_ir::ProcedureIdentity {
        owner: SymbolId::of(owner),
        name: SymbolId::of("f"),
        verb: false,
        occurrence,
    }
}
fn declaration(
    identity: dm_ir::ProcedureIdentity,
    previous: Option<dm_ir::ProcedureIdentity>,
) -> M {
    M::Declaration {
        identity,
        previous,
        definition: dm_ir::ProcedureDefinition::Implicit,
        data: Arc::new(Default::default()),
    }
}
struct ChainHost {
    chain: Arc<[M]>,
    parent: M,
    reads: Mutex<Vec<Q>>,
}
impl Resolver for ChainHost {
    fn resolve(&self, query: Q) -> M {
        self.reads.lock().unwrap().push(query);
        match query {
            Q::DeclarationChain { .. } => M::Members(Arc::clone(&self.chain)),
            Q::Ancestry(owner) => M::Symbols(vec![owner, SymbolId::of("/datum")].into()),
            Q::Proc { .. } => self.parent.clone(),
            _ => M::Unsupported(query),
        }
    }
}
#[test]
fn reopened_parent_proof_selects_exact_current_occurrence_not_later_head() {
    let first = identity("/datum/probe", 0);
    let later = identity("/datum/probe", 1);
    let host = ChainHost {
        chain: vec![declaration(later, Some(first)), declaration(first, None)].into(),
        parent: M::Missing,
        reads: Mutex::new(vec![]),
    };
    let symbols = SymbolTable::default();
    let lookup = view(&host, &symbols);
    assert_eq!(lookup.parent_presence(first), Some(false));
    assert!(host
        .reads
        .lock()
        .unwrap()
        .iter()
        .any(|query| matches!(query, Q::Proc { .. })));
    host.reads.lock().unwrap().clear();
    assert_eq!(lookup.parent_presence(later), Some(true));
    assert!(!host
        .reads
        .lock()
        .unwrap()
        .iter()
        .any(|query| matches!(query, Q::Proc { .. })));
    assert_eq!(lookup.parent_presence(identity("/datum/probe", 2)), None);
    let broken = ChainHost {
        chain: vec![declaration(later, None), declaration(first, None)].into(),
        parent: M::Missing,
        reads: Mutex::new(vec![]),
    };
    assert_eq!(view(&broken, &symbols).parent_presence(later), None);
    let wrong_namespace = dm_ir::ProcedureIdentity {
        verb: true,
        ..first
    };
    let broken = ChainHost {
        chain: vec![
            declaration(first, Some(wrong_namespace)),
            declaration(wrong_namespace, None),
        ]
        .into(),
        parent: M::Missing,
        reads: Mutex::new(vec![]),
    };
    assert_eq!(view(&broken, &symbols).parent_presence(first), None);
}
#[test]
fn source_and_engine_parent_proofs_keep_incomplete_negatives_unknown() {
    let own = identity("/datum/probe", 0);
    let ancestor = identity("/datum", 0);
    let symbols = SymbolTable::default();
    let source = ChainHost {
        chain: vec![
            declaration(own, Some(ancestor)),
            declaration(ancestor, None),
        ]
        .into(),
        parent: M::Unsupported(Q::Proc {
            owner: ancestor.owner,
            name: ancestor.name,
            verb: false,
        }),
        reads: Mutex::new(vec![]),
    };
    assert_eq!(view(&source, &symbols).parent_presence(own), Some(true));
    assert!(!source
        .reads
        .lock()
        .unwrap()
        .iter()
        .any(|query| matches!(query, Q::Proc { .. })));
    // A source-only chain cannot fabricate metadata for an intrinsic parent.
    for parent in [
        M::IntrinsicProc {
            declaring_owner: ancestor.owner,
            name: ancestor.name,
        },
        M::RetainedProc {
            declaring_owner: ancestor.owner,
            name: ancestor.name,
            verb: false,
            engine_identity: 17,
            wire_proc: 9,
        },
    ] {
        let engine = ChainHost {
            chain: vec![declaration(own, None)].into(),
            parent,
            reads: Mutex::new(vec![]),
        };
        assert_eq!(view(&engine, &symbols).parent_presence(own), Some(true));
        assert!(engine
            .reads
            .lock()
            .unwrap()
            .iter()
            .any(|query| matches!(query, Q::Proc { .. })));
    }
    let unknown = ChainHost {
        chain: vec![declaration(own, None)].into(),
        parent: M::Unsupported(Q::Proc {
            owner: ancestor.owner,
            name: ancestor.name,
            verb: false,
        }),
        reads: Mutex::new(vec![]),
    };
    assert_eq!(view(&unknown, &symbols).parent_presence(own), None);
}
