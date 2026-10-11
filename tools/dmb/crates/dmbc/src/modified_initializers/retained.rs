//! Modified assignment continuation reuse on the existing fragment store.
//! Current origins never enter retained input or program ownership.
use super::*;
pub(super) struct Lowered {
    pub code: crate::InitializerCode,
    pub encoding: Option<Arc<crate::symbolic::InitializerEncoding>>,
}
/// Ephemeral current roots; never retained by the fragment owner.
pub(super) struct CurrentFields<'a> {
    fields: &'a [(String, dm_syntax::Expr)],
    calls: Option<&'a dyn dm_tree::constants::PureCalls>,
    roots: HashMap<usize, Arc<dm_syntax::Expr>>,
}
impl<'a> CurrentFields<'a> {
    pub(super) fn new(
        fields: &'a [(String, dm_syntax::Expr)],
        calls: Option<&'a dyn dm_tree::constants::PureCalls>,
    ) -> Self {
        Self {
            fields,
            calls,
            roots: HashMap::new(),
        }
    }
    pub(super) fn root(&mut self, index: usize) -> Option<Arc<dm_syntax::Expr>> {
        if let Some(root) = self.roots.get(&index) {
            return Some(Arc::clone(root));
        }
        let field = self.fields.get(index)?;
        let root = Arc::new(prepare_value(&field.1, self.calls).ok()?);
        self.roots.insert(index, Arc::clone(&root));
        Some(root)
    }
    #[cfg(test)]
    pub(super) fn prepared_indexes(&self) -> impl Iterator<Item = usize> + '_ {
        self.roots.keys().copied()
    }
}

pub(super) fn lower<R: Resolver>(
    symbol: SymRef,
    descriptor: &dm_ir::ModifiedInstance,
    source: &Origins,
    symbols: &SymbolTable,
    host: &R,
    calls: Option<&dyn dm_tree::constants::PureCalls>,
    fragments: Option<&crate::initializer_lowering::InitializerFragments>,
    verification: Option<&crate::lowering_memo::VerifyPolicy>,
    current_keys: &mut Vec<Arc<[u8]>>,
) -> Result<Lowered, String> {
    // External pure-call providers cannot license reuse of their evaluations.
    let policy = match calls {
        None => Some(None),
        Some(calls) => calls.immutable_policy_identity().map(Some),
    };
    let binding = policy.map(|policy| {
        crate::initializer_lowering::receipts::Binding::modified(symbol, descriptor, policy)
    });
    let proof_host = ResourceProofHost { host, descriptor };
    if let (Some(store), Some(binding)) = (fragments, &binding) {
        current_keys.push(Arc::clone(&binding.key));
        // This request-local root memo is populated only after exact admission,
        // and only for field indexes named by nested expression recipes.
        let mut roots = CurrentFields::new(descriptor.fields(), calls);
        let selected = verification.is_some_and(|policy| policy.select());
        let verify = |old_reads: &crate::initializer_lowering::verification::Receipt,
                      old: &crate::InitializerCode| {
            // Fresh evaluator values and reads do not come from the replay recorder/root memo.
            let fields = descriptor
                .fields()
                .iter()
                .map(|(name, value)| Ok((name.clone(), prepare_value(value, calls)?)))
                .collect::<Result<Vec<_>, String>>()?;
            let recorder = crate::lowering_memo::RecordingResolver::new(&proof_host);
            let fresh = dm_codegen_byond::initializer::lower_modified_assignments(
                &fields,
                descriptor.runtime_type(),
                dm_codegen_byond::initializer::InitializerContext {
                    symbols,
                    resource_search_context: descriptor.resource_context(),
                    debug: Some(source),
                },
                &recorder,
            );
            crate::initializer_lowering::verification::code(
                binding,
                old_reads,
                old,
                fresh,
                crate::initializer_lowering::receipts::reads(binding, recorder.reads()),
                "modified fragment",
            )
            .map_err(|error| format!("{error:?}"))
        };
        let mut verifier = |reads: &crate::initializer_lowering::verification::Receipt,
                            code: &crate::InitializerCode| {
            verify(reads, code).map_err(dm_codegen_byond::initializer::InitializerError::Invalid)
        };
        if let Some((code, encoding)) = store
            .modified_verified(
                binding,
                symbols,
                &proof_host,
                |index| roots.root(index),
                if selected { Some(&mut verifier) } else { None },
            )
            .map_err(|error| format!("modified initializer {symbol:?}: {error:?}"))?
        {
            return Ok(Lowered {
                code,
                encoding: Some(encoding),
            });
        }
    }
    let fields = descriptor
        .fields()
        .iter()
        .map(|(name, value)| Ok((name.clone(), prepare_value(value, calls)?)))
        .collect::<Result<Vec<_>, String>>()?;
    let recorder = crate::lowering_memo::RecordingResolver::new(&proof_host);
    let code = Arc::new(
        dm_codegen_byond::initializer::lower_modified_assignments(
            &fields,
            descriptor.runtime_type(),
            dm_codegen_byond::initializer::InitializerContext {
                symbols,
                resource_search_context: descriptor.resource_context(),
                debug: Some(source),
            },
            &recorder,
        )
        .map_err(|error| format!("modified initializer {symbol:?}: {error:?}"))?,
    );
    let encoding = if let (Some(store), Some(binding)) = (fragments, &binding) {
        store.remember_modified(binding, &recorder, &code, &fields)
    } else {
        None
    };
    let code = match &encoding {
        Some(encoding) => {
            crate::InitializerCode::from_admitted_owner(code, encoding.type_requests())
        }
        None => code.into(),
    };
    Ok(Lowered { code, encoding })
}
