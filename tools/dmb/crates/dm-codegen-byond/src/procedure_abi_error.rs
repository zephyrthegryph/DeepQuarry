//! Typed producer errors shared by preparation and host diagnostics.
use std::fmt;
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AbiErrorKind {
    Source,
    Unsupported,
    Invariant,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AbiError {
    pub kind: AbiErrorKind,
    pub message: String,
}
impl AbiError {
    pub fn source(message: impl Into<String>) -> Self {
        Self {
            kind: AbiErrorKind::Source,
            message: message.into(),
        }
    }
    pub fn unsupported(message: impl Into<String>) -> Self {
        Self {
            kind: AbiErrorKind::Unsupported,
            message: message.into(),
        }
    }
    pub fn invariant(message: impl Into<String>) -> Self {
        Self {
            kind: AbiErrorKind::Invariant,
            message: message.into(),
        }
    }
}
impl fmt::Display for AbiError {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.message.fmt(out)
    }
}
impl std::error::Error for AbiError {}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn producer_classification_is_explicit_and_never_inferred_from_message() {
        let source = AbiError::source("invisibility exceeds 127");
        assert_eq!(source.kind, AbiErrorKind::Source);
        assert_eq!(source.to_string(), "invisibility exceeds 127");
        let unsupported = AbiError::unsupported("invisibility exceeds 127");
        assert_eq!(unsupported.kind, AbiErrorKind::Unsupported);
        let invariant = AbiError::invariant("captured metadata changed");
        assert_eq!(invariant.kind, AbiErrorKind::Invariant);
    }
}
