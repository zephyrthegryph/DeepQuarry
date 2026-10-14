//! Compiler-selected bindings, separate from resolver probes and source authority.
use crate::{SymRef, SymbolId};
use dm_syntax::NodeStep;
/// Semantic capture coverage identity used by every retained/disk request key.
pub const SELECTED_REFERENCES_POLICY: &[u8] = b"selected-reference-coverage-v3";

#[derive(Clone, Copy, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum SelectedBuiltin {
    Src,
    Usr,
    World,
    Args,
    Caller,
    Callee,
    ReturnValue,
}
#[derive(Clone, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum SelectedMeaning {
    Local(u32),
    Argument(u32),
    SharedStorage(SymRef),
    InstanceField {
        owner: Option<SymbolId>,
        name: SymbolId,
    },
    Builtin(SelectedBuiltin),
    Literal,
    NumericConstant(u32),
    StringConstant(SymbolId),
    ProcedureValue(SymRef),
    TypeValue(Option<SymbolId>),
    /// Runtime property selection by name; no declared receiver type is inferred.
    RuntimeProperty {
        name: SymbolId,
        static_property: bool,
        safe: bool,
    },
    ProcedureCall {
        reference: SymRef,
        safe: bool,
    },
    DynamicProcedure {
        selector: SymbolId,
        safe: bool,
    },
    DynamicCall {
        dispatcher: SymbolId,
        target_count: u8,
    },
    IntrinsicCall(SymbolId),
}
impl SelectedMeaning {
    /// Structural validity only; resolver freshness still requires artifact admission.
    pub fn structurally_valid(&self) -> bool {
        match self {
            Self::SharedStorage(reference) => reference.kind() == crate::RelocationKind::Variable,
            Self::ProcedureValue(reference) | Self::ProcedureCall { reference, .. } => {
                reference.kind() == crate::RelocationKind::Procedure
            }
            Self::DynamicCall {
                dispatcher,
                target_count,
            } => {
                (1..=2).contains(target_count)
                    && (*dispatcher == SymbolId::of("call")
                        || *dispatcher == SymbolId::of("call_ext"))
            }
            _ => true,
        }
    }
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SelectedReference {
    /// Coordinates in the exact current typed model supplied to the compiler.
    pub path: Vec<NodeStep>,
    pub name: SymbolId,
    pub meaning: SelectedMeaning,
    /// Checked coordinates relative to the exact admitted procedure source.
    /// None is an explicit location gap, never permission to infer a span.
    pub relative_span: Option<(usize, usize)>,
}
/// Partial selection evidence. Absence is never an unresolved-name conclusion.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct SelectedReferences {
    pub references: Vec<SelectedReference>,
    /// Current implementation does not capture every call/selector selection.
    pub complete: bool,
    /// Compiler-generated nodes do not acquire an authored node coordinate.
    pub unbound_selections: usize,
}
