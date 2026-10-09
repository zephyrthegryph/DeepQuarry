//! Typed host/transport failure contract; displayed diagnostics remain unchanged.
use serde::{Deserialize, Serialize};
use std::{error::Error, fmt};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum FailureKind {
    Source,
    Internal,
    Infrastructure,
    Cancelled,
}
impl FailureKind {
    pub fn exit_code(self) -> i32 {
        match self {
            Self::Source => 2,
            Self::Internal => 70,
            Self::Infrastructure => 1,
            Self::Cancelled => 75,
        }
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RequestFailure {
    pub kind: FailureKind,
    pub message: String,
}
impl RequestFailure {
    pub fn source(message: impl Into<String>) -> Self {
        Self {
            kind: FailureKind::Source,
            message: message.into(),
        }
    }
    pub fn internal(message: impl Into<String>) -> Self {
        Self {
            kind: FailureKind::Internal,
            message: message.into(),
        }
    }
    pub fn infrastructure(message: impl Into<String>) -> Self {
        Self {
            kind: FailureKind::Infrastructure,
            message: message.into(),
        }
    }
    pub fn cancelled(message: impl Into<String>) -> Self {
        Self {
            kind: FailureKind::Cancelled,
            message: message.into(),
        }
    }
    pub fn from_error(error: &(dyn Error + 'static)) -> Self {
        Self {
            kind: classify(error),
            message: error.to_string(),
        }
    }
}
impl fmt::Display for RequestFailure {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.message.fmt(formatter)
    }
}
impl Error for RequestFailure {}
pub fn classify(error: &(dyn Error + 'static)) -> FailureKind {
    let mut current = Some(error);
    while let Some(error) = current {
        if let Some(failure) = error.downcast_ref::<RequestFailure>() {
            return failure.kind;
        }
        if let Some(error) = error.downcast_ref::<std::io::Error>() {
            if error.kind() == std::io::ErrorKind::Interrupted {
                return FailureKind::Cancelled;
            }
            // io::Error::source delegates to the inner error's source and can
            // omit the typed inner error itself. Inspect that owner explicitly.
            if let Some(inner) = error.get_ref() {
                current = Some(inner);
                continue;
            }
        }
        current = error.source();
    }
    FailureKind::Infrastructure
}
pub fn exit_code(error: &(dyn Error + 'static)) -> i32 {
    classify(error).exit_code()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn typed_transport_roundtrip_preserves_diagnostic_and_exit_classification() {
        for (failure, code) in [
            (
                RequestFailure::source("source.dm:9:error: invalid expression"),
                2,
            ),
            (RequestFailure::internal("unsupported lowering"), 70),
            (RequestFailure::infrastructure("output unavailable"), 1),
            (RequestFailure::cancelled("build cancelled"), 75),
        ] {
            let displayed = failure.to_string();
            let wire = serde_json::to_vec(&RequestFailure::from_error(&failure)).unwrap();
            let decoded: RequestFailure = serde_json::from_slice(&wire).unwrap();
            assert_eq!(decoded.to_string(), displayed);
            assert_eq!(exit_code(&decoded), code);
        }
    }
    #[test]
    fn io_wrappers_preserve_typed_source_and_interrupt_is_never_fallback() {
        let wrapped = std::io::Error::other(RequestFailure::source("file.dm:1:error: source"));
        assert_eq!(exit_code(&wrapped), 2);
        assert_eq!(
            exit_code(&std::io::Error::from(std::io::ErrorKind::Interrupted)),
            75
        );
        assert_eq!(exit_code(&std::io::Error::other("unclassified IO")), 1);
    }
}
