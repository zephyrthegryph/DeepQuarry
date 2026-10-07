//! Bounded cold procedure driver. ABI interpretation remains an explicit policy.
use crate::debug_sources::{DebugOrigins, FrontendDebugProvider};
use crate::procedure_policy::{AbiContext, PreparedAbi, PreparedUnit};
use dm_codegen_byond::lower_resolver::ResolverProc;
use dm_codegen_byond::{compile_simple_proc_with_resolver_and_debug, ProcedureInputs};
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
    /// Issued production parses retain the existing behavior for custom policies.
    fn prepare_captured(
        &self,
        metadata: &ProcedureMetadata,
        parsed: &dm_tree::frontend::ParsedBody<'_>,
        context: &AbiContext<'_>,
    ) -> Result<PreparedUnit, String> {
        self.prepare(metadata, parsed.item(), context)
    }
    fn inputs(
        &self,
        identity: UnitIdentity,
        metadata: &ProcedureMetadata,
        symbols: &SymbolTable,
        origin: &SourceLocation,
    ) -> Result<ProcedureInputs, String>;
    /// Existing local-only policies are deliberately unauthoritative for DMB output.
    fn prepare(
        &self,
        metadata: &ProcedureMetadata,
        parsed: &dm_syntax::Item,
        context: &AbiContext<'_>,
    ) -> Result<PreparedUnit, String> {
        self.inputs(context.identity, metadata, context.symbols, context.origin)
            .map(|inputs| PreparedUnit::local_only(inputs, parsed))
    }
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
    /// Exact immutable tree selection, independent of encounter order.
    pub effective: bool,
    pub origin: BodyOccurrence,
    pub code: ResolverProc,
    pub metadata: Arc<ProcedureMetadata>,
    pub abi: Option<Arc<PreparedAbi>>,
    pub debug_origins: DebugOrigins,
    pub source_helpers: Vec<crate::argument_sources::LoweredHelper>,
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
    lower_frontend_impl(frontend, host, policy, config, None)
}
/// Startup admission is an exact captured body inventory, never a bypass flag.
pub fn lower_frontend_with_statics<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: &crate::startup::CapturedStartup,
) -> LoweringBatch {
    lower_frontend_impl(frontend, host, policy, config, Some(startup))
}
fn lower_frontend_impl<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: Option<&crate::startup::CapturedStartup>,
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
                            .map(|body| lower_one(frontend, body, host, policy, startup))
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
    startup: Option<&crate::startup::CapturedStartup>,
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
    if let Some(captured) = startup {
        captured
            .validate_for(frontend)
            .map_err(|message| error(None, message))?;
    }
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
    let unsupported = |message| {
        vec![LoweringDiagnostic {
            kind: DiagnosticKind::UnsupportedModel,
            identity: Some(identity),
            origin: body.source.clone(),
            message,
        }]
    };
    let metadata = node
        .metadata
        .procedure
        .as_ref()
        .ok_or_else(|| unsupported("procedure signature metadata unsupported".into()))?;
    let symbols = startup.map_or(tree.symbols(), |captured| captured.plan().symbols.as_ref());
    let parsed = frontend.parse_body(body).map_err(|diagnostic| {
        vec![LoweringDiagnostic {
            kind: diagnostic.kind,
            identity: Some(identity),
            origin: diagnostic.location.unwrap_or_else(|| body.source.clone()),
            message: diagnostic.message,
        }]
    })?;
    let context = AbiContext {
        identity,
        symbols,
        origin: &body.source,
        resolver: host,
    };
    let prepared = policy
        .prepare_captured(metadata, &parsed, &context)
        .map_err(unsupported)?;
    let parsed = parsed.item();
    let procedure_identity = dm_ir::ProcedureIdentity {
        owner: identity.owner,
        name: identity.name,
        verb: identity.namespace == Namespace::Verb,
        occurrence: identity.occurrence,
    };
    let mut inputs = prepared.inputs;
    if inputs.procedure_identity.is_some_and(|supplied| supplied != procedure_identity) {
        return Err(unsupported("procedure ABI identity differs from current body".into()));
    }
    inputs.procedure_identity = Some(procedure_identity);
    let executable_body = if let Some(startup) = startup {
        let captured = startup
            .procedure(body.declaration)
            .ok_or_else(|| unsupported("procedure startup inventory missing".into()))?;
        if captured.procedure != procedure_identity {
            return Err(unsupported(
                "procedure startup inventory differs from current body".into(),
            ));
        }
        if captured.declarations.is_empty()
            && captured.origins.is_empty()
            && !dm_tree::procedure_statics::items_may_contain_stored_declarations(
                &prepared.executable_body,
            )
        {
            prepared.executable_body
        } else {
            let current =
                dm_tree::procedure_statics::capture(procedure_identity, &prepared.executable_body)
                    .map_err(unsupported)?;
            if captured.procedure != current.procedure
                || captured.declarations != current.declarations
                || captured.origins != current.origins
            {
                return Err(unsupported(
                    "procedure startup inventory differs from current body".into(),
                ));
            }
            current.executable_body
        }
    } else {
        if dm_tree::procedure_statics::items_may_contain_stored_declarations(
            &prepared.executable_body,
        ) {
            let static_plan =
                dm_tree::procedure_statics::capture(procedure_identity, &prepared.executable_body)
                    .map_err(unsupported)?;
            if !static_plan.declarations.is_empty() {
                return Err(unsupported(
                    "procedure statics require verified shared-slot/default/startup admission"
                        .into(),
                ));
            }
        }
        prepared.executable_body
    };
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
    let debug = FrontendDebugProvider::new(frontend, parsed.header_span.start);
    let code = compile_simple_proc_with_resolver_and_debug(
        &executable_body,
        &inputs,
        symbols,
        host,
        Some(&debug),
    )
    .map_err(|errors| {
        errors
            .into_iter()
            .map(|e| LoweringDiagnostic {
                kind: match e.kind {
                    dm_codegen_byond::LowerErrorKind::SourceError => DiagnosticKind::SourceError,
                    dm_codegen_byond::LowerErrorKind::UnsupportedModel => {
                        DiagnosticKind::UnsupportedModel
                    }
                    dm_codegen_byond::LowerErrorKind::Internal => DiagnosticKind::Internal,
                },
                identity: Some(identity),
                origin: e
                    .span
                    .and_then(|span| frontend.location(span.start))
                    .unwrap_or_else(|| body.source.clone()),
                message: if e.statement.is_empty() {
                    e.reason
                } else {
                    format!("{}: {}", e.statement, e.reason)
                },
            })
            .collect::<Vec<_>>()
    })?;
    let source_helpers = match prepared.abi.as_ref() {
        Some(abi) => crate::argument_sources::lower_helpers(
            crate::argument_sources::HelperInputs {
                frontend,
                parsed: &parsed,
                metadata,
                owner: identity,
                inputs: &inputs,
                helpers: &abi.source_helpers,
                symbols,
            },
            host,
        )
        .map_err(unsupported)?,
        None => Vec::new(),
    };
    Ok(LoweredUnit {
        identity,
        effective: tree.resolve(node.owner, node.name, node.kind) == Some(body.member),
        origin: body.clone(),
        code,
        metadata: Arc::clone(metadata),
        abi: prepared.abi,
        debug_origins: debug.finish(),
        source_helpers,
    })
}
/// A deterministic identity index for subsequent linking; duplicate structural
/// identities are a driver/model error, never silently overwritten.
impl LoweringBatch {
    /// Symbolic-only lowering may use local policies. Full output must have
    /// authoritative metadata and actual linked argument-source artifacts.
    pub fn require_production_abi(&self) -> Result<(), String> {
        for unit in &self.units {
            let abi = unit.abi.as_ref().ok_or_else(|| {
                format!(
                    "authoritative procedure ABI missing for {:?}",
                    unit.identity
                )
            })?;
            if abi.source_helpers.len() != unit.source_helpers.len()
                || abi
                    .source_helpers
                    .iter()
                    .zip(unit.source_helpers.iter())
                    .any(|(expected, actual)| {
                        actual.owner != unit.identity
                            || usize::try_from(actual.argument).ok() != Some(expected.argument)
                    })
            {
                return Err(format!(
                    "argument-source helper lowering is incomplete for {:?}",
                    unit.identity
                ));
            }
        }
        Ok(())
    }
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
    fn startup_admission_filters_declarations_and_preserves_distinct_static_slots() {
        let frontend = frontend("/proc/first()\n    var/static/counter = 1\n    return counter\n/proc/second()\n    var/static/counter = 2\n    return counter\n");
        let ordinary = lower_frontend(&frontend, &Host, &NoParameters, LoweringConfig::default());
        assert!(ordinary.units.is_empty());
        assert_eq!(ordinary.diagnostics.len(), 2);
        let startup = crate::startup::capture(&frontend).unwrap();
        let host = startup.resolver(&frontend, &Host).unwrap();
        let one = lower_frontend_with_statics(
            &frontend,
            &host,
            &NoParameters,
            LoweringConfig {
                workers: 1,
                max_chunk: 1,
            },
            &startup,
        );
        let two = lower_frontend_with_statics(
            &frontend,
            &host,
            &NoParameters,
            LoweringConfig {
                workers: 2,
                max_chunk: 1,
            },
            &startup,
        );
        assert!(one.diagnostics.is_empty(), "{:?}", one.diagnostics);
        assert!(two.diagnostics.is_empty(), "{:?}", two.diagnostics);
        assert_eq!(one.units.len(), 2);
        for (a, b) in one.units.iter().zip(&two.units) {
            assert_eq!(a.code.procedure, b.code.procedure);
            assert_eq!(a.code.procedure_statics, b.code.procedure_statics);
            assert_eq!(a.code.procedure_statics.len(), 1);
        }
        assert_ne!(
            one.units[0].code.procedure_statics,
            one.units[1].code.procedure_statics
        );
    }
    #[test]
    fn global_units_use_global_storage_against_the_real_tree() {
        let frontend = frontend("var/counter = 1\n/proc/read()\n    return counter\n");
        let batch = lower_frontend(
            &frontend,
            frontend.snapshot.tree.as_ref(),
            &NoParameters,
            LoweringConfig::default(),
        );
        assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
        let body = frontend.body(&frontend.bodies[0]).unwrap();
        let mut bindings = dm_codegen_byond::LowerBindings {
            current_proc_path: Some("/proc/read".into()),
            ..Default::default()
        };
        bindings.globals.insert("counter".into());
        let reference =
            dm_codegen_byond::compile_simple_proc_with_bindings(&body.children, &bindings).unwrap();
        let mut without_debug = batch.units[0].code.procedure.clone();
        without_debug.code.items.retain(|item| !matches!(item, dm_codegen_byond::Item::Instruction(instruction) if matches!(instruction.opcode,0x84|0x85)));
        assert_eq!(without_debug, reference);
        assert!(!batch.units[0].debug_origins.entries.is_empty());
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
        assert!(batch
            .diagnostics
            .iter()
            .all(|error| error.kind == DiagnosticKind::UnsupportedModel));
    }
    #[test]
    fn included_macro_failures_report_statement_lines_in_worker_order() {
        struct Included;
        impl dm_preprocess::SourceProvider for Included {
            fn read(&self, path: &Path) -> Result<String, String> {
                match path.file_name().and_then(|name| name.to_str()) {
                    Some("project.dme") => Ok("#include \"body.dm\"\n".into()),
                    Some("body.dm") => Ok("#define BAD missing_call()\n/proc/first()\n    if(1)\n        return BAD\n/proc/second()\n    return BAD\n".into()),
                    _ => Err("unexpected source".into()),
                }
            }
        }
        let frontend =
            dm_tree::frontend::build(Path::new("project.dme"), &Included, &BTreeMap::new(), 1)
                .unwrap();
        let one = lower_frontend(
            &frontend,
            &Host,
            &NoParameters,
            LoweringConfig {
                workers: 1,
                ..Default::default()
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
        assert!(one.units.is_empty());
        assert_eq!(one.diagnostics.len(), 2);
        assert_eq!(
            one.diagnostics
                .iter()
                .map(|diagnostic| diagnostic.origin.line)
                .collect::<Vec<_>>(),
            vec![4, 6]
        );
        for (left, right) in one.diagnostics.iter().zip(&two.diagnostics) {
            assert!(left.origin.semantic_path.ends_with("body.dm"));
            assert_eq!(left.kind, DiagnosticKind::UnsupportedModel);
            assert_eq!(left.kind, right.kind);
            assert_eq!(left.origin.span, right.origin.span);
            assert_eq!(left.origin.semantic_path, right.origin.semantic_path);
            assert_eq!(left.origin.line, right.origin.line);
            assert_eq!(
                left.origin.encounter_ordinal,
                right.origin.encounter_ordinal
            );
            assert_eq!(left.origin.include_chain, right.origin.include_chain);
            assert_eq!(left.message, right.message);
        }
    }
    #[test]
    fn included_macro_and_loop_bodies_keep_actual_source_debug_origins() {
        struct Included;
        impl dm_preprocess::SourceProvider for Included {
            fn read(&self, path: &Path) -> Result<String, String> {
                match path.file_name().and_then(|name|name.to_str()) {
                    Some("project.dme") => Ok("#include \"body.dm\"\n".into()),
                    Some("body.dm") => Ok("#define VALUE 7\n/proc/p()\n    var/x = 0\n    while(x < 1)\n        x++\n    return VALUE\n".into()),
                    _ => Err("unexpected source".into()),
                }
            }
        }
        let frontend =
            dm_tree::frontend::build(Path::new("project.dme"), &Included, &BTreeMap::new(), 1)
                .unwrap();
        let batch = lower_frontend(&frontend, &Host, &NoParameters, LoweringConfig::default());
        assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
        assert_eq!(batch.units.len(), 1);
        let entries = &batch.units[0].debug_origins.entries;
        assert!(entries
            .iter()
            .any(|origin| origin.semantic_path.ends_with("body.dm") && origin.line == 5));
        assert!(entries
            .iter()
            .any(|origin| origin.semantic_path.ends_with("body.dm") && origin.line == 6));
        assert!(batch.require_production_abi().is_err());
    }
    #[test]
    fn captured_policy_prepares_guarded_settings_and_authoritative_layout() {
        use crate::procedure_policy::{
            CapturedConstantEvaluator, CapturedInheritedFacts, CapturedProcedurePolicy,
            InheritedLayout,
        };
        use dm_codegen_byond::procedure_abi::{AbiError, Category};
        struct Facts;
        impl CapturedInheritedFacts for Facts {
            fn inherited(&self, _: &AbiContext<'_>) -> Result<InheritedLayout, AbiError> {
                Ok(InheritedLayout::Fresh)
            }
        }
        impl CapturedConstantEvaluator for Facts {
            fn evaluate(
                &self,
                expression: &dm_ir::SymbolicExpression,
                context: &AbiContext<'_>,
            ) -> Result<dm_ir::SemanticValue, AbiError> {
                match expression.source_text(context.symbols).as_deref() {
                    Some("0") => Ok(dm_ir::SemanticValue::NumberBits(0f32.to_bits())),
                    Some("1") => Ok(dm_ir::SemanticValue::NumberBits(1f32.to_bits())),
                    Some("null") => Ok(dm_ir::SemanticValue::Null),
                    _ => Err(AbiError("uncaptured constant".into())),
                }
            }
        }
        let frontend=frontend("/proc/p(value as num | null)\n    if(0)\n        set hidden = 1\n    else\n        set category = null\n    return value\n");
        let facts = Facts;
        let policy = CapturedProcedurePolicy {
            evaluator: &facts,
            inherited: &facts,
            resource_search_context: None,
        };
        let batch = lower_frontend(&frontend, &Host, &policy, LoweringConfig::default());
        assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
        batch.require_production_abi().unwrap();
        let abi = batch.units[0].abi.as_ref().unwrap();
        assert_eq!(abi.layout.category, Category::Null);
        assert_eq!(abi.layout.flags, 0x24);
        assert_eq!(batch.units[0].code.procedure.argument_type_flags, [136]);
        let helper_frontend =
            self::frontend("/proc/source(value in list(value))\n    return value\n");
        let helpers = lower_frontend(&helper_frontend, &Host, &policy, LoweringConfig::default());
        assert!(helpers.diagnostics.is_empty(), "{:?}", helpers.diagnostics);
        helpers.require_production_abi().unwrap();
        assert_eq!(helpers.units[0].source_helpers.len(), 1);
        let helper = &helpers.units[0].source_helpers[0];
        assert_eq!(helper.owner, helpers.units[0].identity);
        assert_eq!(helper.argument, 0);
        assert!(helper.code.procedure.argument_names.is_empty());
        assert_eq!(helper.debug_origins.entries[0].line, 1);
        assert!(helper.code.procedure.code.items.iter().any(|item| matches!(item,dm_codegen_byond::Item::Instruction(instruction) if instruction.operands.iter().any(|word|matches!(word,dm_codegen_byond::Word::Variable(dm_codegen_byond::VariableWord::Arg(0)))))));
    }
    #[test]
    fn empty_static_inventory_skips_only_actual_body_without_stored_qualifiers() {
        let frontend = frontend(
            "/proc/p()\n    var/local = 1\n    if(local)\n        local++\n    return local\n",
        );
        let startup = crate::startup::capture(&frontend).unwrap();
        assert!(startup.procedures()[0].1.declarations.is_empty());
        let ordinary = lower_frontend(&frontend, &Host, &NoParameters, LoweringConfig::default());
        let captured = lower_frontend_with_statics(
            &frontend,
            &Host,
            &NoParameters,
            LoweringConfig::default(),
            &startup,
        );
        assert!(ordinary.diagnostics.is_empty());
        assert!(captured.diagnostics.is_empty());
        assert_eq!(
            ordinary.units[0].code.procedure,
            captured.units[0].code.procedure
        );
        struct Injected;
        impl AbiPolicy for Injected {
            fn inputs(
                &self,
                _: UnitIdentity,
                _: &ProcedureMetadata,
                _: &SymbolTable,
                _: &SourceLocation,
            ) -> Result<ProcedureInputs, String> {
                Ok(ProcedureInputs::default())
            }
            fn prepare(
                &self,
                _: &ProcedureMetadata,
                parsed: &dm_syntax::Item,
                _: &AbiContext<'_>,
            ) -> Result<PreparedUnit, String> {
                let mut prepared = PreparedUnit::local_only(ProcedureInputs::default(), parsed);
                let injected =
                    dm_syntax::parse("/proc/injected()\n    if(1)\n        var/static/cache = 1\n");
                prepared
                    .executable_body
                    .insert(0, injected.items[0].children[0].clone());
                Ok(prepared)
            }
        }
        let injected = lower_frontend_with_statics(
            &frontend,
            &Host,
            &Injected,
            LoweringConfig::default(),
            &startup,
        );
        assert!(injected.units.is_empty());
        assert_eq!(injected.diagnostics.len(), 1);
        assert!(injected.diagnostics[0]
            .message
            .contains("startup inventory differs"));
    }
}
