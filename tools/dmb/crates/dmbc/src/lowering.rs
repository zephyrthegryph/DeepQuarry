//! Bounded cold procedure driver. ABI interpretation remains an explicit policy.
use dm_codegen_byond::lower_resolver::ResolverProc;
use dm_codegen_byond::{compile_simple_proc_with_resolver, ProcedureInputs};
use dm_ir::{ProcedureMetadata, Resolver, SymbolId, SymbolTable};
use dm_tree::{
    frontend::{BodyOccurrence, ColdFrontend, DiagnosticKind, SourceLocation},
    MemberKind,
};
use std::{collections::BTreeMap, sync::Arc, thread};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Namespace {
    Proc,
    Verb,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct UnitIdentity {
    pub owner: SymbolId,
    pub name: SymbolId,
    pub namespace: Namespace,
    pub occurrence: u32,
}
/// Converts signature/default/annotation semantics using one pinned compiler ABI.
/// Reject unsupported flags/value-source/default decoding rather than guessing.
pub trait AbiPolicy: Sync {
    fn inputs(
        &self,
        identity: UnitIdentity,
        metadata: &ProcedureMetadata,
        symbols: &SymbolTable,
        origin: &SourceLocation,
    ) -> Result<ProcedureInputs, String>;
}
#[derive(Clone, Copy, Debug)]
pub struct LoweringConfig {
    pub workers: usize,
    pub max_chunk: usize,
}
impl Default for LoweringConfig {
    fn default() -> Self {
        Self {
            workers: 1,
            max_chunk: 32,
        }
    }
}
pub struct LoweredUnit {
    pub identity: UnitIdentity,
    pub origin: BodyOccurrence,
    pub code: ResolverProc,
    pub metadata: Arc<ProcedureMetadata>,
}
#[derive(Clone, Debug)]
pub struct LoweringDiagnostic {
    pub kind: DiagnosticKind,
    pub identity: Option<UnitIdentity>,
    pub origin: SourceLocation,
    pub message: String,
}
#[derive(Default)]
pub struct LoweringBatch {
    pub units: Vec<LoweredUnit>,
    pub diagnostics: Vec<LoweringDiagnostic>,
}
pub fn lower_frontend<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
) -> LoweringBatch {
    // At most eight workers and bounded chunks, independent of machine core count.
    let workers = config.workers.clamp(1, 8);
    let chunk = config.max_chunk.clamp(1, 256);
    let mut bodies: Vec<_> = frontend.bodies.iter().collect();
    bodies.sort_by_key(|body| {
        (
            body.source.encounter_ordinal,
            body.expanded_span.start,
            body.declaration.0,
        )
    });
    let mut batch = LoweringBatch::default();
    for wave in bodies.chunks(workers * chunk) {
        let outcomes = thread::scope(|scope| {
            let mut handles = Vec::new();
            for slice in wave.chunks(chunk) {
                handles.push((
                    slice,
                    scope.spawn(move || {
                        slice
                            .iter()
                            .map(|body| lower_one(frontend, body, host, policy))
                            .collect::<Vec<_>>()
                    }),
                ));
            }
            handles
                .into_iter()
                .flat_map(|(slice, handle)| {
                    handle.join().unwrap_or_else(|_| {
                        slice
                            .iter()
                            .map(|body| {
                                Err(vec![LoweringDiagnostic {
                                    kind: DiagnosticKind::Internal,
                                    identity: None,
                                    origin: body.source.clone(),
                                    message: "procedure lowering worker panicked".into(),
                                }])
                            })
                            .collect()
                    })
                })
                .collect::<Vec<_>>()
        });
        for outcome in outcomes {
            match outcome {
                Ok(unit) => batch.units.push(unit),
                Err(errors) => batch.diagnostics.extend(errors),
            }
        }
    }
    batch
}
fn lower_one<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    host: &R,
    policy: &P,
) -> Result<LoweredUnit, Vec<LoweringDiagnostic>> {
    let tree = &frontend.snapshot.tree;
    let error = |identity, message| {
        vec![LoweringDiagnostic {
            kind: DiagnosticKind::Internal,
            identity,
            origin: body.source.clone(),
            message,
        }]
    };
    let node = tree
        .member(body.member)
        .ok_or_else(|| error(None, "body member missing from immutable tree".into()))?;
    let owner = tree
        .type_node(node.owner)
        .ok_or_else(|| error(None, "body owner missing from immutable tree".into()))?
        .path;
    let namespace = match node.kind {
        MemberKind::Proc => Namespace::Proc,
        MemberKind::Verb => Namespace::Verb,
        MemberKind::Var => return Err(error(None, "variable cannot own a procedure body".into())),
    };
    let occurrence = tree
        .override_chain(body.member)
        .iter()
        .filter(|id| {
            tree.member(**id).is_some_and(|previous| {
                previous.owner == node.owner
                    && previous.kind == node.kind
                    && previous.name == node.name
            })
        })
        .count()
        - 1;
    let occurrence = u32::try_from(occurrence)
        .map_err(|_| error(None, "procedure occurrence exceeds u32".into()))?;
    let identity = UnitIdentity {
        owner,
        name: node.name,
        namespace,
        occurrence,
    };
    let unsupported = |message| vec![LoweringDiagnostic {
        kind: DiagnosticKind::UnsupportedModel,
        identity: Some(identity),
        origin: body.source.clone(),
        message,
    }];
    let metadata = node.metadata.procedure.as_ref().ok_or_else(|| {
        unsupported("procedure signature metadata unsupported".into())
    })?;
    let symbols = tree.symbols();
    let mut inputs = policy
        .inputs(identity, metadata, symbols, &body.source)
        .map_err(unsupported)?;
    let owner_text = symbols
        .text(owner)
        .ok_or_else(|| error(Some(identity), "owner spelling missing".into()))?;
    let name = symbols
        .text(node.name)
        .ok_or_else(|| error(Some(identity), "procedure spelling missing".into()))?;
    inputs.current_type_path = (owner_text != "/").then(|| owner_text.into());
    inputs.current_proc_path = Some(format!(
        "{}/{}/{}",
        owner_text.trim_end_matches('/'),
        if namespace == Namespace::Verb {
            "verb"
        } else {
            "proc"
        },
        name
    ));
    let parsed = frontend
        .body(body)
        .map_err(|diagnostic| vec![LoweringDiagnostic {
            kind: diagnostic.kind,
            identity: Some(identity),
            origin: diagnostic.location.unwrap_or_else(|| body.source.clone()),
            message: diagnostic.message,
        }])?;
    let code = compile_simple_proc_with_resolver(&parsed.children, &inputs, symbols, host)
        .map_err(|errors| {
            errors
                .into_iter()
                .map(|e| LoweringDiagnostic {
                    // Legacy lower errors do not yet carry a typed source/model
                    // distinction. Do not misreport an unimplemented opcode or
                    // resolver meaning as an invalid user program.
                    kind: DiagnosticKind::UnsupportedModel,
                    identity: Some(identity),
                    origin: body.source.clone(),
                    message: if e.statement.is_empty() {
                        e.reason
                    } else {
                        format!("{}: {}", e.statement, e.reason)
                    },
                })
                .collect::<Vec<_>>()
        })?;
    Ok(LoweredUnit {
        identity,
        origin: body.clone(),
        code,
        metadata: Arc::clone(metadata),
    })
}
/// A deterministic identity index for subsequent linking; duplicate structural
/// identities are a driver/model error, never silently overwritten.
impl LoweringBatch {
    pub fn identity_index(&self) -> Result<BTreeMap<UnitIdentity, usize>, UnitIdentity> {
        let mut index = BTreeMap::new();
        for (position, unit) in self.units.iter().enumerate() {
            if index.insert(unit.identity, position).is_some() {
                return Err(unit.identity);
            }
        }
        Ok(index)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{ResolveQuery, ResolvedMeaning};
    use std::{collections::BTreeMap, path::Path};
    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    struct Host;
    impl Resolver for Host {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            ResolvedMeaning::Unsupported(query)
        }
    }
    struct NoParameters;
    impl AbiPolicy for NoParameters {
        fn inputs(
            &self,
            _: UnitIdentity,
            metadata: &ProcedureMetadata,
            _: &SymbolTable,
            _: &SourceLocation,
        ) -> Result<ProcedureInputs, String> {
            if !metadata.signature.parameters.is_empty() || metadata.signature.variadic {
                return Err("no-parameter policy does not know parameter ABI".into());
            }
            Ok(ProcedureInputs::default())
        }
    }
    fn frontend(source: &'static str) -> ColdFrontend {
        dm_tree::frontend::build(
            Path::new("project.dme"),
            &Source(source),
            &BTreeMap::new(),
            1,
        )
        .unwrap()
    }
    #[test]
    fn actual_lazy_frontend_units_are_equal_with_one_or_two_workers() {
        let frontend = frontend("/proc/first()\n    return 1\n/proc/second()\n    return 2\n");
        let one = lower_frontend(
            &frontend,
            &Host,
            &NoParameters,
            LoweringConfig {
                workers: 1,
                max_chunk: 1,
            },
        );
        let two = lower_frontend(
            &frontend,
            &Host,
            &NoParameters,
            LoweringConfig {
                workers: 2,
                max_chunk: 1,
            },
        );
        assert!(one.diagnostics.is_empty(), "{:?}", one.diagnostics);
        assert!(two.diagnostics.is_empty(), "{:?}", two.diagnostics);
        assert_eq!(one.units.len(), 2);
        assert_eq!(one.identity_index(), two.identity_index());
        for (a, b) in one.units.iter().zip(&two.units) {
            assert_eq!(a.identity, b.identity);
            assert_eq!(a.origin.source.span, b.origin.source.span);
            assert_eq!(a.code.procedure, b.code.procedure);
        }
    }
    #[test]
    fn global_units_use_global_storage_against_the_real_tree() {
        let frontend = frontend("var/counter = 1\n/proc/read()\n    return counter\n");
        let batch = lower_frontend(&frontend, frontend.snapshot.tree.as_ref(),
            &NoParameters, LoweringConfig::default());
        assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
        let body = frontend.body(&frontend.bodies[0]).unwrap();
        let mut bindings = dm_codegen_byond::LowerBindings {
            current_proc_path: Some("/proc/read".into()),
            ..Default::default()
        };
        bindings.globals.insert("counter".into());
        let reference = dm_codegen_byond::compile_simple_proc_with_bindings(
            &body.children, &bindings).unwrap();
        assert_eq!(batch.units[0].code.procedure, reference);
    }
    #[test]
    fn unsupported_parameter_policy_reports_ordered_source_diagnostics() {
        let frontend=frontend("/proc/first(value as num)\n    return value\n/proc/second(value as text)\n    return value\n");
        let batch = lower_frontend(
            &frontend,
            &Host,
            &NoParameters,
            LoweringConfig {
                workers: 2,
                max_chunk: 1,
            },
        );
        assert!(batch.units.is_empty());
        assert_eq!(batch.diagnostics.len(), 2);
        assert!(batch.diagnostics[0].origin.line < batch.diagnostics[1].origin.line);
        assert!(batch
            .diagnostics
            .iter()
            .all(|error| error.message.contains("parameter ABI")));
        assert!(batch.diagnostics.iter().all(|error|
            error.kind == DiagnosticKind::UnsupportedModel));
    }
}
