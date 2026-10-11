//! Test-only identity-less transport adapter for canonical receipt fixtures.
use super::*;
#[derive(Default)]
pub(crate) struct AnonymousLookup {
    pub code: Option<ResolverProc>,
    pub errors: Option<Vec<dm_codegen_byond::LowerError>>,
}
impl Candidates<'_> {
    #[cfg(test)]
    pub(crate) fn anonymous<R: Resolver>(
        self,
        key: &[u8],
        host: &R,
        debug_count: usize,
    ) -> AnonymousLookup {
        // Preserve the existing failure-first semantics across variants. Typed
        // payload admission happens once before either outcome is inspected.
        let mut executables = Vec::new();
        for candidate in self.0.into_iter().rev() {
            match candidate {
                Candidate::Failure(value) => {
                    if value.identity.is_none()
                        && value.key.as_ref() == key
                        && read_mismatch(&value.reads, &value.versions, host).is_none()
                    {
                        return AnonymousLookup {
                            errors: Some(
                                value.errors.into_iter().map(ErrorWire::rehydrate).collect(),
                            ),
                            code: None,
                        };
                    }
                }
                Candidate::Executable(value) => executables.push(value),
                Candidate::Compact(_) | Candidate::Selections(_) => (),
            }
        }
        for value in executables {
            if value.identity.is_some()
                || value.abi.is_some()
                || !value.helpers.is_empty()
                || value.key != key
                || read_mismatch(&value.reads, &value.versions, host).is_some()
            {
                continue;
            }
            if let Some(code) = value.body.rehydrate(host, debug_count) {
                return AnonymousLookup {
                    code: Some(code),
                    errors: None,
                };
            }
        }
        AnonymousLookup::default()
    }
}
