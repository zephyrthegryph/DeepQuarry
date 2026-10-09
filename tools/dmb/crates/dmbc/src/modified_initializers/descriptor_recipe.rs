//! Exact semantic descriptor evidence, separate from current expression authority.
use super::*;
use dm_syntax::{Expr, ExprKind};

#[derive(Clone)]
pub(crate) struct DescriptorRecipe {
    reference: SymRef,
    canonical: Arc<[u8]>,
    runtime_type: SymbolId,
    lexical_owner: SymbolId,
    resource_context: Option<u128>,
    origin: Option<u32>,
}
impl DescriptorRecipe {
    pub(super) fn from_capture(
        reference: SymRef,
        captured: &CapturedModifiedInstance,
    ) -> Option<Self> {
        let origin = captured.origin;
        if reference != SymRef::Instance(SymbolId::of(&captured.descriptor.alias()))
            || captured.field_origins.iter().any(|field| *field != origin)
        {
            return None;
        }
        Some(Self {
            reference,
            canonical: captured.descriptor.canonical_bytes().into(),
            runtime_type: captured.descriptor.runtime_type(),
            lexical_owner: captured.descriptor.lexical_owner(),
            resource_context: captured.descriptor.resource_context(),
            origin,
        })
    }
    pub(super) fn capture_current(
        &self,
        expression: &Expr,
        resolver: &dyn Resolver,
        symbols: &SymbolTable,
    ) -> Option<CapturedModifiedInstance> {
        let ExprKind::ObjectInitializer { object, fields } = &expression.kind else {
            return None;
        };
        let ExprKind::TypePath(path) = &object.kind else {
            return None;
        };
        let path = path.trim_end_matches('/');
        if SymbolId::of(path) != self.runtime_type {
            return None;
        }
        let owner = symbols.text(self.lexical_owner)?;
        let captured = dm_codegen_byond::lower_resolver::ModifiedCaptureContext {
            resolver,
            symbols,
            resource_search_context: self.resource_context,
        }
        .capture(path, owner, fields, self.origin, expression.span)
        .ok()?;
        if captured.descriptor.canonical_bytes() != self.canonical.as_ref()
            || SymRef::Instance(SymbolId::of(&captured.descriptor.alias())) != self.reference
        {
            return None;
        }
        Some(captured)
    }
    pub(super) fn reference(&self) -> SymRef {
        self.reference
    }
    pub(super) fn canonical(&self) -> &Arc<[u8]> {
        &self.canonical
    }
    pub(super) fn retained_census(&self, census: &mut crate::heap_census::HeapCensus) {
        census.slice("session_symbolic.modified_canonical", &self.canonical, true);
    }
}
