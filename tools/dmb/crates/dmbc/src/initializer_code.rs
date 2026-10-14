//! Current immutable code paired with a source-neutral ordered reachability receipt.
use dm_codegen_byond::lower_resolver::ResolverProc;
use dm_ir::{SymbolId, SymbolTable};
use std::sync::Arc;

pub(crate) struct TypeRequests {
    ordered: Vec<SymbolId>,
    reference_count: usize,
}
impl TypeRequests {
    pub(crate) fn capture(code: &ResolverProc) -> Arc<Self> {
        let mut ordered = Vec::new();
        let mut reference_count = 0;
        visit(code, |id, reference| {
            ordered.push(id);
            if reference {
                reference_count += 1;
            }
        });
        Arc::new(Self {
            ordered,
            reference_count,
        })
    }
    pub(crate) fn append(
        &self,
        output: &mut Vec<SymbolId>,
        symbols: &SymbolTable,
    ) -> Result<(), String> {
        // Preserve the legacy producer's last missing-reference error and append
        // order. Descriptor runtime classes did not receive this spelling check.
        let mut failure = None;
        for &id in &self.ordered[..self.reference_count] {
            if symbols.text(id).is_none() {
                failure = Some(format!(
                    "referenced type spelling not collision checked: {id:?}"
                ));
            }
        }
        output.extend_from_slice(&self.ordered);
        failure.map_or(Ok(()), Err)
    }
    pub(crate) fn ordered(&self) -> &Vec<SymbolId> {
        &self.ordered
    }
}

/// Replacing code constructs a new receipt. There is deliberately no mutable
/// access to the paired code, or constructor accepting a caller-issued receipt.
#[derive(Clone)]
pub struct InitializerCode {
    code: Arc<ResolverProc>,
    requests: Arc<TypeRequests>,
}
impl From<ResolverProc> for InitializerCode {
    fn from(code: ResolverProc) -> Self {
        let requests = TypeRequests::capture(&code);
        Self {
            code: Arc::new(code),
            requests,
        }
    }
}
impl From<Arc<ResolverProc>> for InitializerCode {
    fn from(code: Arc<ResolverProc>) -> Self {
        let requests = TypeRequests::capture(&code);
        Self { code, requests }
    }
}
impl InitializerCode {
    pub(crate) fn from_admitted(code: ResolverProc, requests: Arc<TypeRequests>) -> Self {
        Self {
            code: Arc::new(code),
            requests,
        }
    }
    pub(crate) fn from_admitted_owner(
        code: Arc<ResolverProc>,
        requests: Arc<TypeRequests>,
    ) -> Self {
        Self { code, requests }
    }
    pub(crate) fn requests(&self) -> &Arc<TypeRequests> {
        &self.requests
    }
    pub(crate) fn code_owner(&self) -> &Arc<ResolverProc> {
        &self.code
    }
}
impl std::ops::Deref for InitializerCode {
    type Target = ResolverProc;
    fn deref(&self) -> &Self::Target {
        &self.code
    }
}
impl AsRef<ResolverProc> for InitializerCode {
    fn as_ref(&self) -> &ResolverProc {
        &self.code
    }
}

fn visit(code: &ResolverProc, mut emit: impl FnMut(SymbolId, bool)) {
    code.procedure.code.for_each_reference(|reference| {
        if let dm_ir::SymRef::Type(id) = reference {
            emit(id, true);
        }
    });
    for instance in code.instances.values() {
        emit(instance.runtime_type, false);
    }
    for instance in code.modified_instances.values() {
        emit(instance.descriptor.runtime_type(), false);
    }
}
pub(crate) fn append_fresh(
    code: &ResolverProc,
    output: &mut Vec<SymbolId>,
    symbols: &SymbolTable,
) -> Result<(), String> {
    let mut failure = None;
    visit(code, |id, reference| {
        if reference && symbols.text(id).is_none() {
            failure = Some(format!(
                "referenced type spelling not collision checked: {id:?}"
            ));
        }
        output.push(id);
    });
    failure.map_or(Ok(()), Err)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn code() -> ResolverProc {
        ResolverProc {
            procedure: Default::default(),
            modified_instances: Default::default(),
            procedure_values: Default::default(),
            procedure_statics: Default::default(),
            slots: Default::default(),
            resources: Default::default(),
            instances: Default::default(),
        }
    }
    fn operand(code: &mut ResolverProc, id: SymbolId) {
        code.procedure
            .code
            .items
            .push(dm_codegen_byond::Item::Instruction(
                dm_codegen_byond::Instruction {
                    opcode: 0,
                    operands: vec![dm_codegen_byond::Word::Reference(dm_ir::SymRef::Type(id))],
                },
            ));
    }
    #[test]
    fn current_receipt_matches_fresh_order_errors_and_replacement() {
        let mut current = code();
        operand(&mut current, SymbolId::of("/missing_first"));
        operand(&mut current, SymbolId::of("/missing_last"));
        let symbols = SymbolTable::default();
        let receipt = InitializerCode::from(current.clone());
        let mut fresh = Vec::new();
        let mut retained = Vec::new();
        assert_eq!(
            append_fresh(&current, &mut fresh, &symbols),
            receipt.requests.append(&mut retained, &symbols)
        );
        assert_eq!(fresh, retained);
        assert_eq!(
            retained,
            vec![
                SymbolId::of("/missing_first"),
                SymbolId::of("/missing_last")
            ]
        );
        let shared = InitializerCode::from_admitted(current, Arc::clone(receipt.requests()));
        assert!(Arc::ptr_eq(receipt.requests(), shared.requests()));
        let replacement = InitializerCode::from(code());
        assert!(replacement.requests.ordered.is_empty());
        assert!(!Arc::ptr_eq(receipt.requests(), replacement.requests()));
    }
}
