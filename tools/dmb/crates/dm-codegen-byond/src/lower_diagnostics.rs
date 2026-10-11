use serde::{Deserialize, Serialize};
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub enum LowerErrorKind {
    SourceError,
    #[default]
    UnsupportedModel,
    Internal,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LowerSpan {
    pub start: usize,
    pub end: usize,
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct LowerError {
    pub statement: String,
    pub reason: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub span: Option<LowerSpan>,
    /// Current-source primary cursor; memo storage rebases offsets relative to the body.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub primary_anchor: Option<crate::DiagnosticAnchor>,
    #[serde(default)]
    pub kind: LowerErrorKind,
    #[serde(default)]
    pub related: Vec<LowerRelated>,
}

impl LowerError {
    pub(crate) fn at(mut self, span: Option<LowerSpan>) -> Self {
        if self.span.is_none() {
            self.span = span;
        }
        self
    }
}

/// Secondary current-source diagnostic; never carries an absolute file origin.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LowerRelated {
    pub span: LowerSpan,
    pub message: String,
}

#[path = "undefined_variable_diagnostic.rs"]
mod undefined_variable;
pub(crate) use undefined_variable::undefined_type_message;
pub(crate) use undefined_variable::undefined_variable_message;
