//! Shared successful compiler diagnostic codes.
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum WarningCode {
    ListDoubleInit,
    ListWithoutFilter,
}
impl WarningCode {
    pub fn name(self) -> &'static str {
        match self {
            Self::ListDoubleInit => "list_double_init",
            Self::ListWithoutFilter => "list_without_filter",
        }
    }
}

impl WarningCode {
    pub fn requires_name(self) -> bool {
        matches!(self, Self::ListDoubleInit)
    }
    pub fn message(self) -> &'static str {
        match self {
            Self::ListDoubleInit => "list doubly initialized",
            Self::ListWithoutFilter => "it is recommended that you use an object filter or 'anything' when combining constant input types with lists",
        }
    }
}
