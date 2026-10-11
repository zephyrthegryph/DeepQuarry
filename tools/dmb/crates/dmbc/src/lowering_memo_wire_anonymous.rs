//! Existing anonymous typed-candidate loop; optional original receipt for verification.
use super::*;
#[derive(Default)]
pub(crate) struct AnonymousLookup {
    pub code: Option<ResolverProc>,
    pub errors: Option<Vec<dm_codegen_byond::LowerError>>,
    pub verification_reads: Option<Vec<(ResolveQuery, Vec<u8>)>>,
}
impl Candidates<'_> {
    pub(crate) fn anonymous_verified<R: Resolver>(
        self,
        key: &[u8],
        host: &R,
        debug_count: usize,
        verify: bool,
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
                        let verification_reads = verify.then(|| {
                            value
                                .reads
                                .iter()
                                .map(|read| (read.query(), read.answer().to_vec()))
                                .collect()
                        });
                        return AnonymousLookup {
                            verification_reads,
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
            let verification_reads = verify.then(|| {
                value
                    .reads
                    .iter()
                    .map(|read| (read.query(), read.answer().to_vec()))
                    .collect()
            });
            if let Some(code) = value.body.rehydrate(host, debug_count) {
                return AnonymousLookup {
                    verification_reads,
                    code: Some(code),
                    errors: None,
                };
            }
        }
        AnonymousLookup::default()
    }
}
