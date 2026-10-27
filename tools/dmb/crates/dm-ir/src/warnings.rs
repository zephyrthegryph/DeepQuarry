//! Shared successful compiler diagnostic codes.
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum WarningCode {
    ListDoubleInit,
    ListWithoutFilter,
    ObjectFilterRightmost,
    AnythingFilterRightmost,
    AnythingWithoutList,
    NoParent,
    OverrideBeforeDefinition,
    DefinitionAfterOverride,
    // Append new codes: persisted serde enum indices must remain stable.
    UnusedVar,
    AccidentalAssign,
    /// `#warn text`: printed as `warning: #warn text` without a code.
    WarnDirective,
    /// A procedure-local's name used before its `var/` line in a block that encloses the use:
    /// printed as `NAME: use of NAME precedes its definition`.
    VarBeforeDef,
    /// The `var/` line a `VarBeforeDef` use precedes.
    VarBeforeDefDefinition,
}
impl WarningCode {
    pub fn name(self) -> &'static str {
        match self {
            Self::ListDoubleInit => "list_double_init",
            Self::ListWithoutFilter => "list_without_filter",
            Self::ObjectFilterRightmost | Self::AnythingFilterRightmost => "filter_rightmost",
            Self::AnythingWithoutList => "anything_no_list",
            Self::NoParent => "no_parent",
            Self::OverrideBeforeDefinition | Self::DefinitionAfterOverride => "override_before_def",
            Self::UnusedVar => "unused_var",
            Self::AccidentalAssign => "accidental_assign",
            Self::WarnDirective => "warn",
            Self::VarBeforeDef | Self::VarBeforeDefDefinition => "var_before_def",
        }
    }
}

impl WarningCode {
    pub fn requires_name(self) -> bool {
        matches!(
            self,
            Self::ListDoubleInit
                | Self::OverrideBeforeDefinition
                | Self::DefinitionAfterOverride
                | Self::UnusedVar
                | Self::WarnDirective
                | Self::VarBeforeDef
                | Self::VarBeforeDefDefinition
        )
    }
    pub fn message(self) -> &'static str {
        match self {
            Self::ListDoubleInit => "list doubly initialized",
            Self::ObjectFilterRightmost => "object type filter should be right-most",
            Self::AnythingFilterRightmost => "'anything' should be right-most",
            Self::AnythingWithoutList => "'anything' has no meaning without a list",
            Self::NoParent => "..: ..() has no parent proc to call",
            Self::OverrideBeforeDefinition => "procedure override precedes definition",
            Self::DefinitionAfterOverride => "definition is here",
            Self::UnusedVar => "variable defined but not used",
            Self::AccidentalAssign => {
                "assignment in condition, may have intended == operator instead"
            }
            Self::WarnDirective => "",
            Self::VarBeforeDef => "precedes its definition",
            Self::VarBeforeDefDefinition => "definition is here",
            Self::ListWithoutFilter => "it is recommended that you use an object filter or 'anything' when combining constant input types with lists",
        }
    }
}
