//! Typed producer errors shared by preparation and host diagnostics.
use std::{fmt, io};
#[path = "../../../shared/operational_error.rs"]
mod operational_transport;
use operational_transport::OperationalError;
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AbiErrorKind {
    Source,
    Unsupported,
    Invariant,
    Operational(io::ErrorKind),
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AbiError {
    pub kind: AbiErrorKind,
    pub message: String,
    // Actual operation-local exception transport. Never a semantic identity,
    // ABI receipt, artifact key or source-quota reservation.
    operational: Option<OperationalError>,
}
impl AbiError {
    pub fn operational(error: io::Error) -> Self {
        Self {
            kind: AbiErrorKind::Operational(error.kind()),
            message: error.to_string(),
            operational: Some(OperationalError::new(error)),
        }
    }
    pub fn operational_error(&self) -> Option<&io::Error> {
        self.operational.as_ref().map(OperationalError::error)
    }
    pub fn into_operational(mut self) -> Result<io::Error, Self> {
        match self.operational.take() {
            Some(error) => Ok(error.into_io()),
            None => Err(self),
        }
    }
    /// Add existing predecessor context without discarding its typed cause.
    pub fn with_context(mut self, message: impl Into<String>) -> Self {
        self.message = message.into();
        self
    }
    pub fn source(message: impl Into<String>) -> Self {
        Self {
            kind: AbiErrorKind::Source,
            message: message.into(),
            operational: None,
        }
    }
    pub fn unsupported(message: impl Into<String>) -> Self {
        Self {
            kind: AbiErrorKind::Unsupported,
            message: message.into(),
            operational: None,
        }
    }
    pub fn invariant(message: impl Into<String>) -> Self {
        Self {
            kind: AbiErrorKind::Invariant,
            message: message.into(),
            operational: None,
        }
    }
}
impl fmt::Display for AbiError {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.message.fmt(out)
    }
}
impl std::error::Error for AbiError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.operational_error()
            .map(|e| e as &dyn std::error::Error)
    }
}
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
    #[test]
    fn actual_operational_cause_survives_transport_clones_and_context() {
        let error = AbiError::operational(io::Error::from_raw_os_error(1450));
        let kind = error.operational_error().unwrap().kind();
        let alias = error.clone().with_context("predecessor ABI unavailable");
        assert_eq!(alias.kind, AbiErrorKind::Operational(kind));
        assert_eq!(
            alias.operational_error().unwrap().raw_os_error(),
            Some(1450)
        );
        assert_ne!(
            error,
            AbiError::operational(io::Error::from_raw_os_error(1450)),
            "transport owners are not semantic error equality"
        );
        let lifted = alias.into_operational().unwrap();
        assert_eq!(lifted.kind(), kind);
        assert_eq!(
            error.operational_error().unwrap().raw_os_error(),
            Some(1450)
        );
        drop(lifted);
        let original = error.into_operational().unwrap();
        assert_eq!(original.raw_os_error(), Some(1450));
        let syntax = AbiError::source("ordinary source diagnostic");
        assert_eq!(syntax.clone().into_operational().unwrap_err(), syntax);
    }
}
