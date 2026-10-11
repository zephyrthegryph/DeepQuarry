//! Demand-driven anonymous descriptor graph over already lowered operand sites.
//! No source corpus scan, generated class, filesystem read or copied bindings.
use crate::debug_sources::DebugOriginProvider;
use crate::{
    debug_sources::{DebugOrigin, DebugOrigins},
    initialization_artifact::{InitializationArtifact, InitializationCoverage},
};
use dm_codegen_byond::lower_resolver::{CapturedModifiedInstance, ResolverProc};
use dm_ir::{Resolver, SymRef, SymbolId, SymbolTable};
use std::{
    collections::{HashMap, VecDeque},
    sync::Arc,
};

mod source_recipe;
pub(crate) use source_recipe::{RecipeWire, SourceRecipe};
mod descriptor_recipe;
mod expression_recipe;
mod retained;
#[cfg(test)]
mod retained_tests;
pub(crate) use expression_recipe::ExpressionRecipe;

pub struct Collected {
    pub descriptors: Vec<(SymRef, CapturedModifiedInstance)>,
    pub artifacts: Vec<InitializationArtifact>,
}
struct Origins {
    entries: Vec<DebugOrigin>,
}
/// Exact operand seed whose source ordinals were resolved before rich IR was released.
#[derive(Clone)]
pub struct PreparedSeed {
    reference: SymRef,
    captured: CapturedModifiedInstance,
    origins: DebugOrigins,
}
impl PreparedSeed {
    /// Consume a seed already authenticated by the existing current recipe issuer.
    pub(crate) fn into_current_capture(self) -> (SymRef, CapturedModifiedInstance) {
        (self.reference, self.captured)
    }
    pub(crate) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        census.prepared_modified(&self.captured, &self.origins);
    }
}
pub(crate) fn prepare_seed(
    reference: SymRef,
    captured: &CapturedModifiedInstance,
    debug: &DebugOrigins,
) -> Result<PreparedSeed, String> {
    if reference != SymRef::Instance(SymbolId::of(&captured.descriptor.alias())) {
        return Err("modified symbol differs from issued descriptor".into());
    }
    Ok(PreparedSeed {
        reference,
        captured: captured.clone(),
        origins: DebugOrigins {
            entries: origins(captured, debug)?.entries,
        },
    })
}
/// Resource facts were captured before descriptor identity was issued. Repeated
/// lowering may verify them, but cannot silently substitute a changed payload.
struct ResourceProofHost<'a, R> {
    host: &'a R,
    descriptor: &'a dm_ir::ModifiedInstance,
}
impl<R: Resolver> Resolver for ResourceProofHost<'_, R> {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M};
        let path = match query {
            Q::Resource(path) => Some(path),
            Q::ResourceIn {
                path,
                search_context,
            } if self.descriptor.resource_context() == Some(search_context) => Some(path),
            Q::ResourceIn { .. } => return M::Unsupported(query),
            _ => None,
        };
        let Some(path) = path else {
            return self.host.resolve(query);
        };
        let expected = self.descriptor.resources().iter().find_map(|(raw, proof)| {
            let literal = raw.strip_prefix('\'')?.strip_suffix('\'')?;
            (SymbolId::of(literal) == path).then_some(*proof)
        });
        let Some(expected) = expected else {
            return M::Unsupported(query);
        };
        match self.host.resolve(query) {
            M::Resource { path, content }
                if path == expected.path && content == expected.content =>
            {
                M::Resource { path, content }
            }
            _ => M::Unsupported(query),
        }
    }
}
impl dm_codegen_byond::DebugSourceProvider for Origins {
    fn entry_ordinal(&self) -> Result<u32, String> {
        Ok(0)
    }
    fn ordinal(&self, index: usize) -> Result<u32, String> {
        if index + 1 >= self.entries.len() {
            return Err("modified field debug origin missing".into());
        }
        u32::try_from(index + 1).map_err(|_| "modified field debug ordinal overflow".into())
    }
}
fn origins(captured: &CapturedModifiedInstance, parent: &DebugOrigins) -> Result<Origins, String> {
    if captured.field_origins.len() != captured.descriptor.fields().len() {
        return Err("modified field origin cardinality mismatch".into());
    }
    let get = |ordinal: Option<u32>| {
        parent
            .entries
            .get(ordinal.ok_or("modified source ordinal unavailable")? as usize)
            .cloned()
            .ok_or_else(|| "modified source ordinal outside captured ledger".to_owned())
    };
    let mut entries = vec![get(captured.origin)?];
    for ordinal in &captured.field_origins {
        entries.push(get(*ordinal)?);
    }
    Ok(Origins { entries })
}
fn enqueue(
    code: &ResolverProc,
    debug: &DebugOrigins,
    seen: &mut HashMap<SymRef, Arc<[u8]>>,
    pending: &mut VecDeque<(SymRef, CapturedModifiedInstance, Origins)>,
) -> Result<(), String> {
    let mut ordered = Vec::new();
    code.procedure.code.for_each_reference(|reference| {
        if matches!(reference, SymRef::Instance(_)) {
            ordered.push(reference);
        }
    });
    for symbol in ordered {
        let Some(captured) = code.modified_instances.get(&symbol) else {
            continue;
        };
        if symbol != SymRef::Instance(SymbolId::of(&captured.descriptor.alias())) {
            return Err("modified symbol differs from issued descriptor".into());
        }
        let bytes = captured.descriptor.canonical_bytes();
        if let Some(previous) = seen.get(&symbol) {
            if previous.as_ref() != bytes {
                return Err("modified alias collision".into());
            }
            continue;
        }
        let source = origins(captured, debug)?;
        seen.insert(symbol, Arc::from(bytes));
        pending.push_back((symbol, captured.clone(), source));
    }
    Ok(())
}
fn enqueue_defaults(
    defaults: &[(SymRef, CapturedModifiedInstance, DebugOrigins)],
    seen: &mut HashMap<SymRef, Arc<[u8]>>,
    pending: &mut VecDeque<(SymRef, CapturedModifiedInstance, Origins)>,
) -> Result<(), String> {
    for (symbol, captured, debug) in defaults {
        if *symbol != SymRef::Instance(SymbolId::of(&captured.descriptor.alias())) {
            return Err("modified default alias differs from issued descriptor".into());
        }
        let bytes: Arc<[u8]> = Arc::from(captured.descriptor.canonical_bytes());
        if let Some(old) = seen.get(symbol) {
            if old != &bytes {
                return Err("modified default identity collision".into());
            }
            continue;
        }
        seen.insert(*symbol, bytes);
        pending.push_back((*symbol, captured.clone(), origins(captured, debug)?));
    }
    Ok(())
}
/// Operand first-use order is explicit. Each new descriptor is lowered once;
/// nested sidecars append to the same FIFO until the exact graph is closed.
pub fn collect<'a, R: Resolver>(
    seeds: impl IntoIterator<Item = (&'a ResolverProc, &'a DebugOrigins)>,
    symbols: &SymbolTable,
    host: &R,
    calls: Option<&dyn dm_tree::constants::PureCalls>,
) -> Result<Collected, String> {
    collect_with_defaults(seeds, &[], symbols, host, calls)
}
pub fn collect_with_defaults<'a, R: Resolver>(
    seeds: impl IntoIterator<Item = (&'a ResolverProc, &'a DebugOrigins)>,
    defaults: &[(SymRef, CapturedModifiedInstance, DebugOrigins)],
    symbols: &SymbolTable,
    host: &R,
    calls: Option<&dyn dm_tree::constants::PureCalls>,
) -> Result<Collected, String> {
    let mut seen = HashMap::new();
    let mut pending = VecDeque::new();
    enqueue_defaults(defaults, &mut seen, &mut pending)?;
    for (code, debug) in seeds {
        enqueue(code, debug, &mut seen, &mut pending)?;
    }
    finish_collection(seen, pending, symbols, host, calls, None, None)
}
/// Consume compact body seeds before initializer/map seeds in their original order.
pub fn collect_prepared_with_defaults<'a, R: Resolver>(
    prepared: impl IntoIterator<Item = &'a PreparedSeed>,
    trailing: impl IntoIterator<Item = (&'a ResolverProc, &'a DebugOrigins)>,
    defaults: &[(SymRef, CapturedModifiedInstance, DebugOrigins)],
    symbols: &SymbolTable,
    host: &R,
    calls: Option<&dyn dm_tree::constants::PureCalls>,
) -> Result<Collected, String> {
    collect_owned_prepared_with_defaults(
        prepared.into_iter().cloned(),
        trailing,
        defaults,
        symbols,
        host,
        calls,
    )
}
/// Move request-local captured sidecars into the same FIFO without copying their origins.
pub fn collect_owned_prepared_with_defaults<'a, R: Resolver>(
    prepared: impl IntoIterator<Item = PreparedSeed>,
    trailing: impl IntoIterator<Item = (&'a ResolverProc, &'a DebugOrigins)>,
    defaults: &[(SymRef, CapturedModifiedInstance, DebugOrigins)],
    symbols: &SymbolTable,
    host: &R,
    calls: Option<&dyn dm_tree::constants::PureCalls>,
) -> Result<Collected, String> {
    collect_owned_prepared_retained(prepared, trailing, defaults, symbols, host, calls, None)
}
pub(crate) fn collect_owned_prepared_retained<'a, R: Resolver>(
    prepared: impl IntoIterator<Item = PreparedSeed>,
    trailing: impl IntoIterator<Item = (&'a ResolverProc, &'a DebugOrigins)>,
    defaults: &[(SymRef, CapturedModifiedInstance, DebugOrigins)],
    symbols: &SymbolTable,
    host: &R,
    calls: Option<&dyn dm_tree::constants::PureCalls>,
    fragments: Option<&crate::initializer_lowering::InitializerFragments>,
) -> Result<Collected, String> {
    collect_owned_prepared_retained_verified(
        prepared, trailing, defaults, symbols, host, calls, fragments, None,
    )
}
#[allow(clippy::too_many_arguments)]
pub(crate) fn collect_owned_prepared_retained_verified<'a, R: Resolver>(
    prepared: impl IntoIterator<Item = PreparedSeed>,
    trailing: impl IntoIterator<Item = (&'a ResolverProc, &'a DebugOrigins)>,
    defaults: &[(SymRef, CapturedModifiedInstance, DebugOrigins)],
    symbols: &SymbolTable,
    host: &R,
    calls: Option<&dyn dm_tree::constants::PureCalls>,
    fragments: Option<&crate::initializer_lowering::InitializerFragments>,
    verification: Option<&crate::lowering_memo::VerifyPolicy>,
) -> Result<Collected, String> {
    let mut seen = HashMap::new();
    let mut pending = VecDeque::new();
    enqueue_defaults(defaults, &mut seen, &mut pending)?;
    for seed in prepared {
        let bytes = seed.captured.descriptor.canonical_bytes();
        if let Some(previous) = seen.get(&seed.reference) {
            if previous.as_ref() != bytes {
                return Err("modified alias collision".into());
            }
            continue;
        }
        seen.insert(seed.reference, Arc::from(bytes));
        pending.push_back((
            seed.reference,
            seed.captured,
            Origins {
                entries: seed.origins.entries,
            },
        ));
    }
    for (code, debug) in trailing {
        enqueue(code, debug, &mut seen, &mut pending)?;
    }
    finish_collection(seen, pending, symbols, host, calls, fragments, verification)
}
fn finish_collection<R: Resolver>(
    mut seen: HashMap<SymRef, Arc<[u8]>>,
    mut pending: VecDeque<(SymRef, CapturedModifiedInstance, Origins)>,
    symbols: &SymbolTable,
    host: &R,
    calls: Option<&dyn dm_tree::constants::PureCalls>,
    fragments: Option<&crate::initializer_lowering::InitializerFragments>,
    verification: Option<&crate::lowering_memo::VerifyPolicy>,
) -> Result<Collected, String> {
    let mut current_keys = Vec::new();
    let mut result = Collected {
        descriptors: Vec::new(),
        artifacts: Vec::new(),
    };
    while let Some((symbol, captured, source)) = pending.pop_front() {
        let descriptor = &captured.descriptor;
        let lowered = retained::lower(
            symbol,
            descriptor,
            &source,
            symbols,
            host,
            calls,
            fragments,
            verification,
            &mut current_keys,
        )?;
        let debug_origins = DebugOrigins {
            entries: source.entries,
        };
        enqueue(&lowered.code, &debug_origins, &mut seen, &mut pending)?;
        let artifact = InitializationArtifact {
            encoding: lowered.encoding,
            identity: dm_link::InitializerIdentity::Modified(SymbolId::of(
                &captured.descriptor.alias(),
            )),
            code: lowered.code,
            debug_origins: Arc::new(debug_origins),
            coverage: InitializationCoverage::ModifiedAssignments {
                count: u32::try_from(descriptor.fields().len())
                    .map_err(|_| "modified field count exceeds u32")?,
                canonical_body: Arc::from(descriptor.canonical_bytes()),
            },
        };
        artifact.validate()?;
        result.descriptors.push((symbol, captured));
        result.artifacts.push(artifact);
    }
    if let Some(fragments) = fragments {
        fragments.retain_modified_keys(current_keys);
    }
    Ok(result)
}
/// Seed stored defaults from the exact classified source occurrence ledger.
pub fn default_seeds(
    frontend: &dm_tree::frontend::ColdFrontend,
    plan: &dm_tree::initializers::InitializerPlan,
    classified: &crate::initializer_policy::ClassifiedInitializers,
) -> Result<Vec<(SymRef, CapturedModifiedInstance, DebugOrigins)>, String> {
    fn append(
        value: &dm_ir::SemanticValue,
        origin: &DebugOrigin,
        output: &mut Vec<(SymRef, CapturedModifiedInstance, DebugOrigins)>,
    ) {
        match value {
            dm_ir::SemanticValue::ModifiedInstance(descriptor) => output.push((
                SymRef::Instance(SymbolId::of(&descriptor.alias())),
                CapturedModifiedInstance {
                    descriptor: descriptor.as_ref().clone(),
                    source_span: None,
                    field_origins: vec![Some(0); descriptor.fields().len()],
                    origin: Some(0),
                },
                DebugOrigins {
                    entries: vec![origin.clone()],
                },
            )),
            dm_ir::SemanticValue::List(values) => {
                for (key, value) in values.iter() {
                    if let Some(key) = key {
                        append(key, origin, output);
                    }
                    append(value, origin, output);
                }
            }
            _ => (),
        }
    }
    let mut output = Vec::new();
    for write in &classified.writes {
        let crate::initializer_policy::DefaultValue::Scalar(value) = &write.default else {
            continue;
        };
        let source = plan
            .origins
            .get(write.source_ordinal)
            .ok_or("modified default source ordinal missing")?;
        let origin = if let dm_tree::initializers::InitializerOriginKind::ProcedureStatic {
            expanded_span,
            ..
        } = &source.kind
        {
            frontend.origin(expanded_span.start)?
        } else {
            let occurrence = frontend
                .plan
                .occurrences
                .get(source.provenance.include_occurrence as usize)
                .ok_or("modified default include missing")?;
            let file = frontend
                .files
                .get(source.provenance.span.file.index())
                .ok_or("modified default source file missing")?;
            let offset = source.provenance.span.start as usize;
            if !file.captured
                || file.path.as_ref() != occurrence.path.as_ref()
                || offset > file.text.len()
            {
                return Err("modified default source provenance mismatch".into());
            }
            DebugOrigin {
                semantic_path: occurrence.semantic_path.clone(),
                line: u32::try_from(file.line_starts.partition_point(|start| *start <= offset))
                    .map_err(|_| "modified default line overflow")?,
            }
        };
        append(value, &origin, &mut output);
    }
    Ok(output)
}
fn prepare_value(
    value: &dm_syntax::Expr,
    calls: Option<&dyn dm_tree::constants::PureCalls>,
) -> Result<dm_syntax::Expr, String> {
    use dm_syntax::ExprKind;
    let mut result = value.clone();
    match &mut result.kind {
        ExprKind::Group(value) | ExprKind::Unary { value, .. } => {
            **value = prepare_value(value, calls)?
        }
        ExprKind::Binary { lhs, rhs, .. } => {
            **lhs = prepare_value(lhs, calls)?;
            **rhs = prepare_value(rhs, calls)?;
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            **condition = prepare_value(condition, calls)?;
            **then_value = prepare_value(then_value, calls)?;
            **else_value = prepare_value(else_value, calls)?;
        }
        ExprKind::Call { callee, .. } if matches!(&callee.kind,ExprKind::Ident(name) if calls.is_some_and(|calls|calls.accepts(name))) =>
        {
            let scalar = dm_tree::constants::evaluate_expr_with_resources_and_calls(
                value,
                |_| None,
                |raw| {
                    dm_codegen_byond::decode_constant_string_literal(raw)
                        .ok()
                        .flatten()
                },
                |expr| dm_codegen_byond::nameof_reference(expr).map(str::to_owned),
                |_| None,
                calls,
            )
            .map_err(|error| format!("modified pure call {}: {}", error.name, error.reason))?
            .ok_or("modified pure call has no certified scalar value")?;
            result.kind = match scalar {
                dm_tree::constants::Constant::Number(number) if number.is_finite() => {
                    ExprKind::Literal(number.to_string())
                }
                dm_tree::constants::Constant::Text(text) => ExprKind::Literal(
                    serde_json::to_string(&text).map_err(|error| error.to_string())?,
                ),
                dm_tree::constants::Constant::Null => ExprKind::Ident("null".into()),
                _ => return Err("modified pure call result representation is unsupported".into()),
            };
        }
        ExprKind::Call { callee, args } if matches!(&callee.kind,ExprKind::Ident(name) if name=="list" || name=="newlist") => {
            for value in args {
                if let ExprKind::Binary { op, lhs, rhs } = &mut value.kind {
                    if op == "=" {
                        if !matches!(&lhs.kind, ExprKind::Ident(_)) {
                            **lhs = prepare_value(lhs, calls)?;
                        }
                        **rhs = prepare_value(rhs, calls)?;
                        continue;
                    }
                }
                *value = prepare_value(value, calls)?;
            }
        }
        ExprKind::ObjectInitializer { object, fields } => {
            **object = prepare_value(object, calls)?;
            for (_, value) in fields {
                *value = prepare_value(value, calls)?;
            }
        }
        _ => (),
    }
    Ok(result)
}
/// Descriptor records are installed before the captured map/skin stage, sharing
/// the same frozen instance/procedure tables and exact coverage validation.
pub struct Stage<'a> {
    pub descriptors: &'a [(SymRef, CapturedModifiedInstance)],
    pub types: &'a dyn crate::class_projection::TypeValuePolicy,
    pub next: Option<&'a dyn crate::composition::NonTextOutputStage>,
}
impl crate::composition::NonTextOutputStage for Stage<'_> {
    fn required_types(&self) -> Vec<SymbolId> {
        let mut result = self
            .next
            .map(|stage| stage.required_types())
            .unwrap_or_default();
        result.extend(
            self.descriptors
                .iter()
                .map(|(_, value)| value.descriptor.runtime_type()),
        );
        result
    }
    fn validate_source(&self, frontend: &dm_tree::frontend::ColdFrontend) -> Result<(), String> {
        self.next
            .map_or(Ok(()), |stage| stage.validate_source(frontend))
    }
    fn apply(
        &self,
        dmb: &mut byond_dmb::dmb::Dmb,
        batch: &crate::symbolic::FrozenBatch,
    ) -> Result<std::collections::BTreeSet<dm_link::Key>, String> {
        let mut covered = crate::modified_output::attach(dmb, self.descriptors, batch, self.types)?;
        if let Some(stage) = self.next {
            covered.extend(stage.apply(dmb, batch)?);
        }
        Ok(covered)
    }
}

#[cfg(test)]
mod resource_tests {
    use super::*;
    use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M};
    struct Host {
        content: u128,
    }
    impl Resolver for Host {
        fn resolve(&self, query: Q) -> M {
            match query {
                Q::HasMemberVar { owner, name }
                    if owner == SymbolId::of("/obj/base") && name == SymbolId::of("asset") =>
                {
                    M::Presence(true)
                }
                Q::ResourceIn {
                    path,
                    search_context: 7,
                } if path == SymbolId::of("asset.txt") => M::Resource {
                    path,
                    content: self.content,
                },
                other => M::Unsupported(other),
            }
        }
    }
    #[test]
    fn captured_default_seed_shares_descriptor_backing_after_runtime_ledger_drop() {
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &std::path::Path) -> Result<String, String> {
                Ok("/var/value = 1\n".into())
            }
        }
        let frontend = dm_tree::frontend::build(
            std::path::Path::new("defaults.dme"),
            &Source,
            &Default::default(),
            1,
        )
        .unwrap();
        let startup = crate::startup::capture(&frontend).unwrap();
        let ast = dm_syntax::parse_expression("/obj/base{asset='asset.txt'}")
            .expr
            .unwrap();
        let dm_syntax::ExprKind::ObjectInitializer { fields, .. } = ast.kind else {
            panic!("descriptor")
        };
        let descriptor = Arc::new(
            dm_ir::ModifiedInstance::capture_with_resources(
                SymbolId::of("/obj/base"),
                SymbolId::of("/"),
                Some(7),
                &fields,
                |_| None,
                None,
                |path| {
                    Ok(dm_ir::CapturedModifiedResource {
                        path: SymbolId::of(path),
                        content: 99,
                    })
                },
            )
            .unwrap(),
        );
        let classified = crate::initializer_policy::ClassifiedInitializers {
            accepted: Vec::new(),
            writes: vec![crate::initializer_policy::ClassifiedWrite {
                source_ordinal: 0,
                write: startup.plan().writes[0].clone(),
                default: crate::initializer_policy::DefaultValue::Scalar(
                    dm_ir::SemanticValue::ModifiedInstance(Arc::clone(&descriptor)),
                ),
                phase: Some(crate::initializer_policy::Phase::Runtime),
                runtime_value: Some(crate::initializer_policy::RuntimeValue::Expression(
                    Arc::new(dm_syntax::parse_expression("list(1,2,3)").expr.unwrap()),
                )),
            }],
            groups: vec![crate::initializer_policy::RuntimeGroup {
                declaration_presence: None,
                receiver: None,
                writes: vec![0],
            }],
        };
        let seeds = default_seeds(&frontend, startup.plan(), &classified).unwrap();
        assert_eq!(seeds.len(), 1);
        assert_eq!(
            seeds[0].0,
            SymRef::Instance(SymbolId::of(&descriptor.alias()))
        );
        assert_eq!(seeds[0].1.descriptor, *descriptor);
        assert_eq!(
            seeds[0].1.descriptor.fields().as_ptr(),
            descriptor.fields().as_ptr()
        );
        assert_eq!(
            seeds[0].1.descriptor.canonical_bytes().as_ptr(),
            descriptor.canonical_bytes().as_ptr()
        );
        drop(classified);
        assert_eq!(seeds[0].2.entries[0].semantic_path.as_ref(), "defaults.dme");
        assert_eq!(seeds[0].2.entries[0].line, 1);
        assert_eq!(seeds[0].1.field_origins, [Some(0)]);
        assert_eq!(seeds[0].1.descriptor.resources()["'asset.txt'"].content, 99);
    }
    #[test]
    fn modified_resource_initializer_emits_the_captured_payload_and_rejects_changed_proof() {
        let ast = dm_syntax::parse_expression("/obj/base{asset='asset.txt'}")
            .expr
            .unwrap();
        let dm_syntax::ExprKind::ObjectInitializer { fields, .. } = ast.kind else {
            panic!("descriptor")
        };
        let descriptor = dm_ir::ModifiedInstance::capture_with_resources(
            SymbolId::of("/obj/base"),
            SymbolId::of("/"),
            Some(7),
            &fields,
            |_| None,
            None,
            |path| {
                Ok(dm_ir::CapturedModifiedResource {
                    path: SymbolId::of(path),
                    content: 99,
                })
            },
        )
        .unwrap();
        let captured = CapturedModifiedInstance {
            descriptor,
            source_span: None,
            field_origins: vec![Some(0)],
            origin: Some(0),
        };
        let symbol = SymRef::Instance(SymbolId::of(&captured.descriptor.alias()));
        let debug = DebugOrigins {
            entries: vec![DebugOrigin {
                semantic_path: "body.dm".into(),
                line: 3,
            }],
        };
        let mut symbols = SymbolTable::default();
        for spelling in ["/", "/obj/base", "asset", "asset.txt"] {
            symbols.intern(spelling).unwrap();
        }
        let defaults = [(symbol, captured, debug)];
        let retained = crate::initializer_lowering::InitializerFragments::default();
        let first = collect_owned_prepared_retained(
            std::iter::empty(),
            std::iter::empty(),
            &defaults,
            &symbols,
            &Host { content: 99 },
            None,
            Some(&retained),
        )
        .unwrap();
        // Ordinary fragment pruning must not evict the previous modified roster.
        retained.retain_keys(&Default::default());
        let mut shifted = defaults.clone();
        shifted[0].2.entries[0].semantic_path = "included/current.dm".into();
        shifted[0].2.entries[0].line = 41;
        let second = collect_owned_prepared_retained(
            std::iter::empty(),
            std::iter::empty(),
            &shifted,
            &symbols,
            &Host { content: 99 },
            None,
            Some(&retained),
        )
        .unwrap();
        assert_eq!(retained.hits.load(std::sync::atomic::Ordering::Relaxed), 1);
        assert!(Arc::ptr_eq(
            first.artifacts[0].code.code_owner(),
            second.artifacts[0].code.code_owner()
        ));
        let fresh_current = collect_with_defaults(
            std::iter::empty(),
            &shifted,
            &symbols,
            &Host { content: 99 },
            None,
        )
        .unwrap();
        assert_eq!(
            second.artifacts[0].debug_origins,
            fresh_current.artifacts[0].debug_origins
        );
        assert!(second.artifacts[0]
            .debug_origins
            .entries
            .iter()
            .all(
                |origin| origin.semantic_path.as_ref() == "included/current.dm"
                    && origin.line == 41
            ));
        assert_eq!(
            dm_codegen_byond::encoder::freeze_proc(&second.artifacts[0].code.procedure.code)
                .unwrap()
                .code()
                .canonical_bytes(),
            dm_codegen_byond::encoder::freeze_proc(&fresh_current.artifacts[0].code.procedure.code)
                .unwrap()
                .code()
                .canonical_bytes()
        );
        assert_eq!(
            dm_codegen_byond::encoder::freeze_proc(&first.artifacts[0].code.procedure.code)
                .unwrap()
                .code()
                .canonical_bytes(),
            dm_codegen_byond::encoder::freeze_proc(&second.artifacts[0].code.procedure.code)
                .unwrap()
                .code()
                .canonical_bytes()
        );
        assert!(collect_owned_prepared_retained(
            std::iter::empty(),
            std::iter::empty(),
            &shifted,
            &symbols,
            &Host { content: 100 },
            None,
            Some(&retained)
        )
        .is_err());
        assert_eq!(retained.hits.load(std::sync::atomic::Ordering::Relaxed), 1);
        let mut changed_input = crate::initializer_lowering::receipts::Binding::modified(
            symbol,
            &defaults[0].1.descriptor,
            None,
        );
        changed_input.inputs = Arc::new(crate::initializer_lowering::receipts::Inputs::Modified {
            canonical: Arc::from(defaults[0].1.descriptor.canonical_bytes()),
            policy: Some(17),
            lexical_owner: SymbolId::of("/"),
            resource_context: Some(7),
        });
        assert!(retained
            .modified(&changed_input, &symbols, &Host { content: 99 }, |_| panic!(
                "rejected input must not prepare fields"
            ),)
            .is_none());
        let leaf_input = crate::initializer_lowering::receipts::Binding::modified(
            symbol,
            &defaults[0].1.descriptor,
            None,
        );
        assert!(retained
            .modified(&leaf_input, &symbols, &Host { content: 99 }, |_| panic!(
                "leaf hit must not prepare fields"
            ))
            .is_some());
        let output = collect_with_defaults(
            std::iter::empty(),
            &defaults,
            &symbols,
            &Host { content: 99 },
            None,
        )
        .unwrap();
        assert_eq!(output.artifacts.len(), 1);
        let prepared = prepare_seed(defaults[0].0, &defaults[0].1, &defaults[0].2).unwrap();
        let prepared_output = collect_prepared_with_defaults(
            [&prepared, &prepared],
            std::iter::empty(),
            &[],
            &symbols,
            &Host { content: 99 },
            None,
        )
        .unwrap();
        assert_eq!(prepared_output.artifacts.len(), 1);
        assert_eq!(
            prepared_output.artifacts[0].debug_origins,
            output.artifacts[0].debug_origins
        );
        assert_eq!(
            dm_codegen_byond::encoder::freeze_proc(
                &prepared_output.artifacts[0].code.procedure.code
            )
            .unwrap()
            .code()
            .canonical_bytes(),
            dm_codegen_byond::encoder::freeze_proc(&output.artifacts[0].code.procedure.code)
                .unwrap()
                .code()
                .canonical_bytes(),
        );
        assert_eq!(
            output.artifacts[0]
                .code
                .resources
                .get(&SymbolId::of("asset.txt")),
            Some(&99)
        );
        assert!(output.artifacts[0].code.procedure.code.items.iter().any(|item| matches!(item,
            dm_codegen_byond::Item::Instruction(instruction) if instruction.operands.iter().any(|word|
                matches!(word,dm_codegen_byond::Word::Value(dm_codegen_byond::ValueWord::Resource(content)) if *content == 99)))));
        assert!(collect_with_defaults(
            std::iter::empty(),
            &defaults,
            &symbols,
            &Host { content: 100 },
            None
        )
        .is_err());
    }
}
