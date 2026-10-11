//! Modified assignment continuation reuse on the existing fragment store.
//! Current origins never enter retained input or program ownership.
use super::*;
pub(super) struct Lowered {
    pub code: crate::InitializerCode,
    pub encoding: Option<Arc<crate::symbolic::InitializerEncoding>>,
}

pub(super) fn lower<R: Resolver>(
    symbol: SymRef,
    descriptor: &dm_ir::ModifiedInstance,
    source: &Origins,
    symbols: &SymbolTable,
    host: &R,
    calls: Option<&dyn dm_tree::constants::PureCalls>,
    fragments: Option<&crate::initializer_lowering::InitializerFragments>,
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
    let fields = descriptor
        .fields()
        .iter()
        .map(|(name, value)| Ok((name.clone(), prepare_value(value, calls)?)))
        .collect::<Result<Vec<_>, String>>()?;
    if let (Some(store), Some(binding)) = (fragments, &binding) {
        current_keys.push(Arc::clone(&binding.key));
        if let Some((code, encoding)) = store.modified(binding, &fields, symbols, &proof_host) {
            return Ok(Lowered {
                code,
                encoding: Some(encoding),
            });
        }
    }
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
