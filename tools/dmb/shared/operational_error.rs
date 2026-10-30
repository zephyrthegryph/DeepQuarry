//! Actual operation-local IO transport, not a semantic value or budget lease.
//! Arc/error metadata is the explicitly bounded framework exception baseline.
use std::{fmt, io, sync::Arc};
#[derive(Clone, Debug)]
pub struct OperationalError {
    source: Arc<io::Error>,
}
impl OperationalError {
    pub fn new(error: io::Error) -> Self {
        Self {
            source: Arc::new(error),
        }
    }
    pub fn kind(&self) -> io::ErrorKind {
        self.source.kind()
    }
    pub fn error(&self) -> &io::Error {
        &self.source
    }
    pub fn into_io(self) -> io::Error {
        match Arc::try_unwrap(self.source) {
            Ok(error) => error,
            Err(source) => {
                let kind = source.kind();
                io::Error::new(kind, Self { source })
            }
        }
    }
}
impl fmt::Display for OperationalError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.source.fmt(f)
    }
}
impl std::error::Error for OperationalError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(self.source.as_ref())
    }
}
impl PartialEq for OperationalError {
    fn eq(&self, other: &Self) -> bool {
        // ONLY exception-transport clone identity. Never a semantic equivalence,
        // question/cache key, source receipt or admission proof.
        Arc::ptr_eq(&self.source, &other.source)
    }
}
impl Eq for OperationalError {}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn clone_transport_preserves_kind_and_source_without_semantic_equality() {
        let original = OperationalError::new(io::Error::from_raw_os_error(1450));
        let alias = original.clone();
        assert_eq!(original, alias);
        let kind = original.kind();
        let lifted = original.into_io();
        assert_eq!(lifted.kind(), kind);
        let mut source: Option<&(dyn std::error::Error + 'static)> = Some(&lifted);
        let mut found = false;
        while let Some(error) = source {
            if error
                .downcast_ref::<io::Error>()
                .is_some_and(|e| e.raw_os_error() == Some(1450))
            {
                found = true;
            }
            source = error.source();
        }
        assert!(found, "actual original OS error survives alias transport");
        assert_ne!(
            alias,
            OperationalError::new(io::Error::from_raw_os_error(1450)),
            "distinct operations have no semantic-equality claim"
        );
        drop(lifted);
        let unshared = alias.into_io();
        assert_eq!(unshared.raw_os_error(), Some(1450));
    }
}
