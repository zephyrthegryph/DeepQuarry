//! Source syntax is not operation cancellation, quota or provider failure.
use super::Diagnostic;
use std::{fmt, io};
#[derive(Debug)]
pub enum BodySyntaxFailure {
    Syntax(Diagnostic),
    Operational(io::Error),
}
impl From<Diagnostic> for BodySyntaxFailure {
    fn from(d: Diagnostic) -> Self {
        Self::Syntax(d)
    }
}
impl BodySyntaxFailure {
    pub fn into_io(self) -> io::Error {
        match self {
            Self::Operational(error) => error,
            syntax => io::Error::new(io::ErrorKind::InvalidData, syntax),
        }
    }
    pub fn syntax(&self) -> Option<&Diagnostic> {
        match self {
            Self::Syntax(d) => Some(d),
            Self::Operational(_) => None,
        }
    }
}
impl fmt::Display for BodySyntaxFailure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Syntax(d) => d.message.fmt(f),
            Self::Operational(e) => e.fmt(f),
        }
    }
}
impl std::error::Error for BodySyntaxFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Operational(e) => Some(e),
            Self::Syntax(_) => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn syntax_failure_keeps_original_anchor_and_operational_keeps_real_error() {
        let location = super::super::SourceLocation {
            span: dm_ir::Span {
                file: Default::default(),
                start: 7,
                end: 11,
            },
            path: std::sync::Arc::new("code/probe.dm".into()),
            semantic_path: std::sync::Arc::from("code/probe.dm"),
            line: 3,
            encounter_ordinal: 2,
            include_occurrence: 0,
            include_chain: std::sync::Arc::from([]),
            macro_expansions: Default::default(),
        };
        let failure = BodySyntaxFailure::Syntax(Diagnostic {
            kind: super::super::DiagnosticKind::SourceError,
            stage: super::super::DiagnosticStage::Syntax,
            message: "unchanged syntax refusal".into(),
            location: Some(location.clone()),
        });
        assert_eq!(failure.syntax().unwrap().location.as_ref(), Some(&location));
        assert_eq!(failure.to_string(), "unchanged syntax refusal");
        let wrapped = failure.into_io();
        let syntax = wrapped
            .get_ref()
            .unwrap()
            .downcast_ref::<BodySyntaxFailure>()
            .unwrap();
        assert_eq!(syntax.syntax().unwrap().location.as_ref(), Some(&location));
        let actual = io::Error::new(io::ErrorKind::Interrupted, "actual parser cancellation");
        let failure = BodySyntaxFailure::Operational(actual);
        assert!(failure.syntax().is_none());
        let actual = failure.into_io();
        assert_eq!(actual.kind(), io::ErrorKind::Interrupted);
        assert_eq!(actual.to_string(), "actual parser cancellation");
    }
}
