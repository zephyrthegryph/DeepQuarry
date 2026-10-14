//! A confirmed source error must not become an infrastructure fallback merely
//! because another procedure also uses unsupported native semantics.
use crate::request_failure::FailureKind;
use dm_tree::frontend::DiagnosticKind;

pub fn failure_kind(kinds: impl IntoIterator<Item = DiagnosticKind>) -> FailureKind {
    let mut source = false;
    for kind in kinds {
        match kind {
            DiagnosticKind::Internal => return FailureKind::Internal,
            DiagnosticKind::SourceError => source = true,
            DiagnosticKind::UnsupportedModel => {}
        }
    }
    if source {
        FailureKind::Source
    } else {
        FailureKind::Internal
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn confirmed_source_errors_remain_nonfallback_in_mixed_batches() {
        for kinds in [
            vec![DiagnosticKind::SourceError],
            vec![
                DiagnosticKind::UnsupportedModel,
                DiagnosticKind::SourceError,
            ],
        ] {
            assert_eq!(failure_kind(kinds).exit_code(), 2);
        }
        for kinds in [
            vec![],
            vec![DiagnosticKind::UnsupportedModel],
            vec![DiagnosticKind::Internal],
        ] {
            assert_eq!(failure_kind(kinds).exit_code(), 70);
        }
    }

    #[test]
    fn actual_compiler_fault_dominates_source_errors_in_either_order() {
        for kinds in [
            [DiagnosticKind::SourceError, DiagnosticKind::Internal],
            [DiagnosticKind::Internal, DiagnosticKind::SourceError],
        ] {
            assert_eq!(failure_kind(kinds).exit_code(), 70);
        }
    }
}
