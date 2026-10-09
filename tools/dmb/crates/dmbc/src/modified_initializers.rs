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

pub struct Collected {
    pub descriptors: Vec<(SymRef, CapturedModifiedInstance)>,
    pub artifacts: Vec<InitializationArtifact>,
}
struct Origins {
    entries: Vec<DebugOrigin>,
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
    for (code, debug) in seeds {
        enqueue(code, debug, &mut seen, &mut pending)?;
    }
    let mut result = Collected {
        descriptors: Vec::new(),
        artifacts: Vec::new(),
    };
    while let Some((symbol, captured, source)) = pending.pop_front() {
        let descriptor = &captured.descriptor;
        let fields = descriptor
            .fields()
            .iter()
            .map(|(name, value)| Ok((name.clone(), prepare_value(value, calls)?)))
            .collect::<Result<Vec<_>, String>>()?;
        let code = dm_codegen_byond::initializer::lower_modified_assignments(
            &fields,
            descriptor.runtime_type(),
            dm_codegen_byond::initializer::InitializerContext {
                symbols,
                resource_search_context: descriptor.resource_context(),
                debug: Some(&source),
            },
            &ResourceProofHost { host, descriptor },
        )
        .map_err(|error| format!("modified initializer {symbol:?}: {error:?}"))?;
        let debug_origins = DebugOrigins {
            entries: source.entries,
        };
        enqueue(&code, &debug_origins, &mut seen, &mut pending)?;
        let artifact = InitializationArtifact {
            identity: dm_link::InitializerIdentity::Modified(SymbolId::of(
                &captured.descriptor.alias(),
            )),
            code,
            debug_origins,
            coverage: InitializationCoverage::ModifiedAssignments {
                count: u32::try_from(fields.len())
                    .map_err(|_| "modified field count exceeds u32")?,
                canonical_body: Arc::from(descriptor.canonical_bytes()),
            },
        };
        artifact.validate()?;
        result.descriptors.push((symbol, captured));
        result.artifacts.push(artifact);
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
                semantic_path: occurrence.semantic_path.to_string(),
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
        let output = collect_with_defaults(
            std::iter::empty(),
            &defaults,
            &symbols,
            &Host { content: 99 },
            None,
        )
        .unwrap();
        assert_eq!(output.artifacts.len(), 1);
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
