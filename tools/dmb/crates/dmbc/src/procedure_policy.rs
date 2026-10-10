//! Immutable, request-local procedure ABI preparation. This adapter owns no
//! project bindings: evaluators and inherited facts are borrowed captured hosts.
//! The driver must distinguish local-only lowering from authoritative output.
use crate::lowering::UnitIdentity;
use dm_codegen_byond::{
    lower_resolver::ProcedureInputs,
    procedure_abi::{
        self, AbiError, ArgumentSource, ArgumentSourceHelper, InheritedAbi, ProcLayout,
    },
};
use dm_ir::{ProcedureMetadata, Resolver, SemanticValue, SymbolTable, SymbolicExpression};
use dm_syntax::Item;
use dm_tree::frontend::SourceLocation;
use std::sync::Arc;

pub struct AbiContext<'a> {
    pub identity: UnitIdentity,
    pub symbols: &'a SymbolTable,
    pub origin: &'a SourceLocation,
    pub resolver: &'a dyn Resolver,
}
/// Evaluate using captured source/constant meanings. Errors distinguish unsupported
/// meanings from values; no filesystem or compiler-global snapshot is supplied.
pub trait CapturedConstantEvaluator: Sync {
    fn evaluate(
        &self,
        expression: &SymbolicExpression,
        context: &AbiContext<'_>,
    ) -> Result<SemanticValue, AbiError>;
}
/// Fresh is an explicit proof that there is no inherited ABI. An unresolved engine
/// ancestor is Unsupported, never an inferred default layout.
pub enum InheritedLayout {
    Fresh,
    Known(ProcLayout),
    Unsupported,
}
pub trait CapturedInheritedFacts: Sync {
    fn inherited(&self, context: &AbiContext<'_>) -> Result<InheritedLayout, AbiError>;
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PreparedAbi {
    pub layout: ProcLayout,
    pub argument_sources: Vec<ArgumentSource>,
    pub source_helpers: Vec<ArgumentSourceHelper>,
}
#[path = "procedure_canonical.rs"]
mod canonical;
pub(crate) use canonical::PreparedCanonical;

pub struct PreparedUnit {
    pub(crate) canonical: Option<Arc<PreparedCanonical>>,
    pub inputs: ProcedureInputs,
    pub executable_body: Vec<Item>,
    /// None supports existing local-only lowering tests, not a production DMB.
    pub abi: Option<Arc<PreparedAbi>>,
}
/// Privately issued production preparation for an exact captured body. Its
/// executable transform is fixed, not supplied by a custom ABI policy. The
/// body's complete authored bytes remain in the memo key. On a miss the real
/// parser and setting-strip transform still run before lowering.
pub struct PreparedReplay {
    inputs: ProcedureInputs,
    abi: Arc<PreparedAbi>,
    canonical: Option<Arc<PreparedCanonical>>,
}
impl PreparedReplay {
    /// Only the frozen captured policy may issue this after validating its
    /// current body, metadata, symbol lineage and source occurrence.
    pub(crate) fn from_unit(unit: &PreparedUnit) -> Option<Self> {
        Some(Self {
            inputs: unit.inputs.clone(),
            abi: Arc::clone(unit.abi.as_ref()?),
            canonical: unit.canonical.clone(),
        })
    }
    pub(crate) fn into_view(self) -> PreparedUnit {
        PreparedUnit {
            canonical: self.canonical,
            inputs: self.inputs,
            executable_body: Vec::new(),
            abi: Some(self.abi),
        }
    }
    pub(crate) const TRANSFORM: &'static [u8] = b"captured-setting-strip-v1";
}
impl PreparedUnit {
    pub(crate) fn canonical_metadata(&self) -> Option<Arc<[u8]>> {
        if let Some(canonical) = &self.canonical {
            if canonical.matches(&self.inputs, self.abi.as_ref()) {
                return Some(Arc::clone(&canonical.bytes));
            }
        }
        canonical::encode(&self.inputs, self.abi.as_deref()).map(Arc::from)
    }
    pub(crate) fn issue_canonical(&mut self) {
        self.canonical = PreparedCanonical::capture(&self.inputs, self.abi.as_ref()).map(Arc::new);
    }
    pub fn local_only(inputs: ProcedureInputs, parsed: &Item) -> Self {
        Self {
            canonical: None,
            inputs,
            executable_body: parsed.children.clone(),
            abi: None,
        }
    }
    pub fn require_production_abi(&self) -> Result<&PreparedAbi, AbiError> {
        self.abi.as_deref().ok_or_else(|| {
            AbiError::invariant("authoritative procedure ABI is required for full output")
        })
    }
}
pub struct CapturedProcedurePolicy<'a> {
    pub evaluator: &'a dyn CapturedConstantEvaluator,
    pub inherited: &'a dyn CapturedInheritedFacts,
    /// Explicit terminal FILE_DIR discovery identity, not derived from filenames.
    pub resource_search_context: Option<u128>,
}
impl CapturedProcedurePolicy<'_> {
    /// ABI interpretation reads semantic settings and local layout only. Current
    /// provenance is supplied by AbiContext; the borrowed relative node avoids
    /// cloning a shifted header/body merely to perform the same interpretation.
    pub fn prepare_view(
        &self,
        metadata: &ProcedureMetadata,
        parsed: dm_tree::frontend::ItemView<'_>,
        context: &AbiContext<'_>,
    ) -> Result<PreparedUnit, AbiError> {
        self.prepare_parts(
            metadata,
            context,
            |symbols| dm_tree::settings::extract_settings_view(parsed, symbols),
            || {
                parsed
                    .children()
                    .map(|child| child.materialize_relative())
                    .collect()
            },
        )
    }
    pub fn prepare(
        &self,
        metadata: &ProcedureMetadata,
        parsed: &Item,
        context: &AbiContext<'_>,
    ) -> Result<PreparedUnit, AbiError> {
        self.prepare_parts(
            metadata,
            context,
            |symbols| dm_tree::settings::extract_settings(&parsed.children, symbols),
            || parsed.children.clone(),
        )
    }
    fn prepare_parts(
        &self,
        metadata: &ProcedureMetadata,
        context: &AbiContext<'_>,
        settings: impl FnOnce(&mut SymbolTable) -> Result<Arc<[dm_ir::ProcedureSettingNode]>, String>,
        body: impl FnOnce() -> Vec<Item>,
    ) -> Result<PreparedUnit, AbiError> {
        let inherited = self.inherited.inherited(context)?;
        let inherited = match &inherited {
            InheritedLayout::Fresh => InheritedAbi::Fresh,
            InheritedLayout::Known(layout) => InheritedAbi::Known(layout),
            InheritedLayout::Unsupported => InheritedAbi::Unsupported,
        };
        // Parse only this unit's setting context into a fresh token symbol table.
        // No complete project symbol table or binding map is cloned.
        let mut setting_symbols = SymbolTable::default();
        let actual = settings(&mut setting_symbols).map_err(AbiError::unsupported)?;
        if actual.as_ref() != metadata.settings.as_ref() {
            return Err(AbiError::unsupported(
                "captured procedure setting tree differs from actual body",
            ));
        }
        let executable = dm_tree::settings::strip_setting_items(body());
        let prepared = procedure_abi::prepare_verified_procedure(
            metadata,
            context.symbols,
            &executable,
            ProcedureInputs {
                resource_search_context: self.resource_search_context,
                ..ProcedureInputs::default()
            },
            inherited,
            |expression| self.evaluator.evaluate(expression, context),
        )?;
        Ok(PreparedUnit {
            canonical: None,
            inputs: prepared.inputs,
            executable_body: prepared.executable_body,
            abi: Some(Arc::new(PreparedAbi {
                layout: prepared.layout,
                argument_sources: prepared.argument_sources,
                source_helpers: prepared.source_helpers,
            })),
        })
    }
}
impl PreparedAbi {
    /// Symbolic output contract framing. Physical string/helper/argument IDs and
    /// source positions are deliberately excluded; every effective ABI value is
    /// included. Helper code must also be frozen with the shared encoder before
    /// its explicit semantic artifact is eligible for final publication.
    pub fn canonical_bytes(&self) -> Vec<u8> {
        fn bytes(out: &mut Vec<u8>, value: &[u8]) {
            out.extend_from_slice(&(value.len() as u64).to_le_bytes());
            out.extend_from_slice(value);
        }
        fn optional(out: &mut Vec<u8>, value: Option<&[u8]>) {
            out.push(u8::from(value.is_some()));
            if let Some(value) = value {
                bytes(out, value);
            }
        }
        let mut out = b"dm-prepared-procedure-abi-v1\0".to_vec();
        optional(&mut out, self.layout.display_name.as_deref());
        optional(&mut out, self.layout.description.as_deref());
        match &self.layout.category {
            procedure_abi::Category::Default => out.push(0),
            procedure_abi::Category::Null => out.push(1),
            procedure_abi::Category::Text(value) => {
                out.push(2);
                bytes(&mut out, value);
            }
        }
        out.extend_from_slice(&[self.layout.source_kind, self.layout.source_parameter]);
        out.extend_from_slice(&self.layout.flags.to_le_bytes());
        out.push(u8::from(self.layout.invisibility.is_some()));
        if let Some(value) = self.layout.invisibility {
            out.push(value);
        }
        out.extend_from_slice(&(self.argument_sources.len() as u64).to_le_bytes());
        for source in &self.argument_sources {
            match source {
                ArgumentSource::Builtin { kind, parameter } => {
                    out.extend_from_slice(&[0, *kind, *parameter])
                }
                ArgumentSource::Helper { argument } => {
                    out.push(1);
                    out.extend_from_slice(&(*argument as u64).to_le_bytes());
                }
            }
        }
        out.extend_from_slice(&(self.source_helpers.len() as u64).to_le_bytes());
        for helper in &self.source_helpers {
            out.extend_from_slice(&(helper.argument as u64).to_le_bytes());
            bytes(&mut out, &helper.expression.canonical_bytes());
            out.extend_from_slice(&(helper.frame_parameters.len() as u64).to_le_bytes());
            for parameter in &helper.frame_parameters {
                bytes(&mut out, parameter.as_bytes());
            }
        }
        out
    }
}
impl crate::lowering::AbiPolicy for CapturedProcedurePolicy<'_> {
    fn inputs(
        &self,
        _identity: UnitIdentity,
        _metadata: &ProcedureMetadata,
        _symbols: &SymbolTable,
        _origin: &SourceLocation,
    ) -> Result<ProcedureInputs, String> {
        Err("captured procedure ABI requires the actual parsed body through prepare".into())
    }
    fn prepare(
        &self,
        metadata: &ProcedureMetadata,
        parsed: &Item,
        context: &AbiContext<'_>,
    ) -> Result<PreparedUnit, String> {
        CapturedProcedurePolicy::prepare(self, metadata, parsed, context)
            .map_err(|error| error.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn local_only_preparation_is_not_authoritative() {
        let parsed = dm_syntax::parse("/proc/p()\n    return 1\n");
        let prepared = PreparedUnit::local_only(ProcedureInputs::default(), &parsed.items[0]);
        assert!(prepared.require_production_abi().is_err());
    }
    #[test]
    fn effective_category_and_helper_source_have_distinct_canonical_content() {
        let mut abi = PreparedAbi {
            layout: ProcLayout::default(),
            argument_sources: Vec::new(),
            source_helpers: Vec::new(),
        };
        let default = abi.canonical_bytes();
        abi.layout.category = procedure_abi::Category::Null;
        abi.layout.flags |= 0x20;
        assert_ne!(default, abi.canonical_bytes());
        let null = abi.canonical_bytes();
        abi.argument_sources
            .push(ArgumentSource::Helper { argument: 0 });
        assert_ne!(null, abi.canonical_bytes());
    }
}
