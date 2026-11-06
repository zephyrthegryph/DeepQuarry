//! Whole-program inference is a derived family of the compiler's existing DB.
//! Parameters retain input owners weakly; proof values retain no AST/model.
use super::*;
use dm_analysis::{
    untyped::Unsupported,
    value_query::{ArchiveValueInput, ArchiveValueProof, ArchiveValueQueries, CanonicalValueBodies, ValueQueryFailure},
};
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Weak,
};

pub(super) const VALUE_PROOFS: Kind = Kind(5);
const BUDGET: usize = 64 * 1024 * 1024;
struct Params {
    input: Weak<ArchiveValueInput>,
    key: Key,
}
// Non-IO graph failures are also operational. Keep the original exception,
// not only its Debug rendering, while retaining the prior public message.
#[derive(Debug)]
struct ValueQueryGraphFailure(QueryError);
impl std::fmt::Display for ValueQueryGraphFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "native value proof query failed: {:?}", self.0)
    }
}
impl std::error::Error for ValueQueryGraphFailure {}
// Only genuine semantic rejection data is cloneable/cacheable. IO never enters
// this enum or an Outcome. Original syntax anchors remain original owners.
#[derive(Clone, Debug)]
enum SemanticRejection {
    Unsupported(Unsupported),
    Syntax(dm_tree::frontend::Diagnostic),
}
type ProofResult = Result<Arc<ArchiveValueProof>, SemanticRejection>;
impl SemanticRejection {
    fn compatibility(&self) -> Unsupported {
        match self {
            Self::Unsupported(e) => e.clone(),
            Self::Syntax(e) => Unsupported(e.message.clone()),
        }
    }
    fn into_checked(self) -> ValueQueryFailure {
        match self {
            Self::Unsupported(e) => ValueQueryFailure::Unsupported(e),
            Self::Syntax(e) => ValueQueryFailure::Syntax(e),
        }
    }
    fn charge(&self) -> usize {
        match self {
            Self::Unsupported(e) => e.0.capacity(),
            Self::Syntax(e) => diagnostic_storage_bound(e),
        }
    }
}
// Conservative alias-overcount of accessible retained buffers, not RSS or an
// exact std Arc allocator-layout claim. Inline payload is charged by envelope.
fn diagnostic_storage_bound(e: &dm_tree::frontend::Diagnostic) -> usize {
    let mut n = e.message.capacity();
    if let Some(p) = &e.location {
        n = n
            .saturating_add(std::mem::size_of_val(p.path.as_ref()))
            .saturating_add(p.path.capacity())
            .saturating_add(p.semantic_path.len())
            .saturating_add(std::mem::size_of_val(p.include_chain.as_ref()));
        for (_, bytes) in p.macro_expansions.view().buffers() {
            n = n.saturating_add(bytes);
        }
        for (at, m) in p.macro_expansions.iter().enumerate() {
            if let Some(buffers) = p.macro_expansions.view().author_buffers(at) {
                for (_, bytes) in buffers {
                    n = n.saturating_add(bytes);
                }
            } else {
                n = n.saturating_add(m.name.len());
            }
            if let Some(chain) = m.replacement_chain.native_owner() {
                n = n.saturating_add(std::mem::size_of_val(chain.as_ref()));
                for name in chain.iter() {
                    n = n.saturating_add(name.len());
                }
            }
            if let Some(d) = &m.definition {
                n = n
                    .saturating_add(std::mem::size_of_val(d.path.as_ref()))
                    .saturating_add(d.path.capacity());
            }
        }
    }
    n
}
/// Reborrow the active graph context sequentially for each canonical child
/// query. The callback must finish before the equation builder requests another.
struct CanonicalBodies<'a, 'db> {
    context: std::cell::RefCell<&'a mut dm_query::Ctx<'db>>,
    archive: &'a dm_tree::frontend::BodyArchive,
    body_charge: &'a Arc<AtomicUsize>,
}
impl CanonicalValueBodies for CanonicalBodies<'_, '_> {
    fn with_current_body<T>(
        &self,
        archive: &dm_tree::frontend::BodyArchive,
        ordinal: usize,
        consume: impl FnOnce(dm_tree::frontend::CurrentArchivedBody<'_, '_>, &dm_syntax::SettingAdmission<'_>) -> Result<T, dm_tree::frontend::BodySyntaxFailure>,
    ) -> Result<T, dm_tree::frontend::BodySyntaxFailure> {
        use dm_tree::frontend::BodySyntaxFailure;
        if !std::ptr::eq(archive, self.archive) {
            return Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData, "value proof requested a foreign canonical archive")));
        }
        let mut context = self.context.try_borrow_mut().map_err(|_| BodySyntaxFailure::Operational(std::io::Error::other("canonical value BODY context is already borrowed")))?;
        super::setting_syntax::with_setting_admission(self.body_charge, |admission| {
            archive.with_current_body_checked_in(ordinal, admission, &mut **context,
                |ctx, syntax| body_syntax::obtain_product(ctx, syntax),
                |_, body| consume(body, admission),
            )
        })
    }
}

pub(super) fn register(db: &Db, charged: Arc<AtomicUsize>, body_charge: Arc<AtomicUsize>) {
    db.define(VALUE_PROOFS, "native-value-proofs", move |ctx, params| {
        let params = params
            .downcast_ref::<Params>()
            .expect("value proof parameter type");
        let input = params
            .input
            .upgrade()
            .ok_or(QueryError::Missing(params.key))?;
        let computed = if input.requires_canonical_bodies() {
            input.compute_canonical_checked(&CanonicalBodies {
                context: std::cell::RefCell::new(ctx),
                archive: input.archive(),
                body_charge: &body_charge,
            })
        } else {
            for syntax in input.archive().syntax_inputs().ok_or(QueryError::Missing(params.key))? {
                body_syntax::observe(ctx, syntax)?;
            }
            input.compute_checked()
        };
        let result: ProofResult = match computed {
            Ok(proof) => Ok(proof),
            Err(ValueQueryFailure::Unsupported(e)) => Err(SemanticRejection::Unsupported(e)),
            Err(ValueQueryFailure::Syntax(e)) => Err(SemanticRejection::Syntax(e)),
            Err(ValueQueryFailure::Operational(e)) => {
                return Err(QueryError::operational(params.key, e))
            }
        };
        let envelope = std::mem::size_of::<ProofResult>() + 2 * std::mem::size_of::<usize>();
        let bytes = result.as_ref().map_or_else(
            |e| e.charge().saturating_add(envelope),
            |proof| proof.budget_charge().saturating_add(envelope),
        );
        // Failed inference is not a nominal1024-byte loophole. No publication
        // (including a cached error) may exceed this existing derived family cap.
        if charged
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |old| {
                old.checked_add(bytes).filter(|n| *n <= BUDGET)
            })
            .is_err()
        {
            return Err(QueryError::operational(
                params.key,
                std::io::Error::new(
                    std::io::ErrorKind::OutOfMemory,
                    "native value proof result admission denied",
                ),
            ));
        }
        Ok(Outcome::new(result, params.key.id, bytes))
    });
}
impl QueryDb {
    pub(super) fn prepare_value_input(
        &self,
        input: &Arc<ArchiveValueInput>,
    ) -> Result<(), Unsupported> {
        self.prepare_value_input_checked(input)
            .map_err(|failure| match failure {
                ValueQueryFailure::Unsupported(e) => e,
                ValueQueryFailure::Syntax(e) => Unsupported(e.message),
                ValueQueryFailure::Operational(e) => Unsupported(e.to_string()), // independent legacy adapter only
            })
    }
    fn prepare_value_input_checked(
        &self,
        input: &Arc<ArchiveValueInput>,
    ) -> Result<(), ValueQueryFailure> {
        self.prune_value_proofs();
        if !input.archive().uses_body_queries(self) {
            return Err(Unsupported(
                "value proofs require the compiler's existing syntax graph".into(),
            )
            .into());
        }
        let syntax_inputs = input
            .archive()
            .syntax_inputs()
            .ok_or_else(|| Unsupported("issued syntax inputs absent".into()))?;
        // Kind5 observes all parser dependencies before inference. Reject an
        // oversized cohort before that loop can populate the syntax family.
        // This migration admission estimate is not a full-host/RSS guarantee.
        admit_syntax_cohort(syntax_inputs.iter().map(|input| input.budget_charge())).map_err(
            |e| {
                ValueQueryFailure::Operational(std::io::Error::new(
                    std::io::ErrorKind::OutOfMemory,
                    e.0,
                ))
            },
        )?;
        if !input.requires_canonical_bodies() {
            let mut inputs = self.body_inputs.lock().unwrap_or_else(|e| e.into_inner());
            for syntax in syntax_inputs {
                inputs
                    .entry(Key::new(body_syntax::BODY_SYNTAX, syntax.key().into()))
                    .or_insert_with(|| Arc::downgrade(syntax));
            }
        }
        let key = Key::new(VALUE_PROOFS, input.key().into());
        self.value_inputs
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .entry(key)
            .or_insert_with(|| Arc::downgrade(input));
        if self.value_charge.load(Ordering::Relaxed) > BUDGET {
            let freed = self.db.evict_values(&[VALUE_PROOFS]);
            let _ = self
                .value_charge
                .try_update(Ordering::Relaxed, Ordering::Relaxed, |bytes| {
                    Some(bytes.saturating_sub(freed))
                });
        }
        Ok(())
    }
    pub(super) fn prune_value_proofs(&self) {
        self.value_inputs
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .retain(|key, input| {
                if input.strong_count() > 0 {
                    return true;
                }
                let freed = self.db.value_bytes_at(*key);
                self.db.remove(*key);
                let _ =
                    self.value_charge
                        .try_update(Ordering::Relaxed, Ordering::Relaxed, |bytes| {
                            Some(bytes.saturating_sub(freed))
                        });
                false
            });
    }
}
impl ArchiveValueQueries for QueryDb {
    fn value_proof_checked(
        &self,
        input: &Arc<ArchiveValueInput>,
    ) -> Result<Arc<ArchiveValueProof>, ValueQueryFailure> {
        self.prepare_value_input_checked(input)?;
        let key = Key::new(VALUE_PROOFS, input.key().into());
        let answer = self
            .db
            .get::<ProofResult>(
                key,
                Arc::new(Params {
                    input: Arc::downgrade(input),
                    key,
                }),
            )
            .map_err(|e| {
                ValueQueryFailure::Operational(match e.into_operational() {
                    Ok(actual) => actual.into_io(),
                    Err(other) => std::io::Error::other(ValueQueryGraphFailure(other)),
                })
            })?;
        let proof = answer
            .as_ref()
            .as_ref()
            .map(Arc::clone)
            .map_err(|e| e.clone().into_checked())?;
        proof.validate_for(input)?;
        Ok(proof)
    }
    fn value_proof(
        &self,
        input: &Arc<ArchiveValueInput>,
    ) -> Result<Arc<ArchiveValueProof>, Unsupported> {
        self.prepare_value_input(input)?;
        let key = Key::new(VALUE_PROOFS, input.key().into());
        let answer = self
            .db
            .get::<ProofResult>(
                key,
                Arc::new(Params {
                    input: Arc::downgrade(input),
                    key,
                }),
            )
            .map_err(|e| Unsupported(format!("native value proof query failed: {e:?}")))?;
        let proof = answer
            .as_ref()
            .as_ref()
            .map(Arc::clone)
            .map_err(SemanticRejection::compatibility)?;
        proof.validate_for(input)?;
        Ok(proof)
    }
}

/// Pure preflight: arithmetic overflow is refusal, never a truncated cohort.
fn admit_syntax_cohort(charges: impl IntoIterator<Item = usize>) -> Result<usize, Unsupported> {
    charges.into_iter().try_fold(0usize, |total, charge| {
        total
            .checked_add(charge)
            .filter(|&bytes| bytes <= body_syntax::BUDGET)
            .ok_or_else(|| {
                Unsupported(format!(
                    "native value proof syntax cohort exceeds {}-byte migration admission budget",
                    body_syntax::BUDGET,
                ))
            })
    })
}

#[cfg(test)]
mod budget_tests {
    use super::*;

    #[test]
    fn value_syntax_cohort_accepts_empty_and_exact_budget() {
        assert_eq!(admit_syntax_cohort([]).unwrap(), 0);
        assert_eq!(
            admit_syntax_cohort([body_syntax::BUDGET]).unwrap(),
            body_syntax::BUDGET
        );
        assert_eq!(
            admit_syntax_cohort([body_syntax::BUDGET - 1, 1]).unwrap(),
            body_syntax::BUDGET
        );
    }
    #[test]
    fn value_syntax_cohort_rejects_over_budget_and_overflow_without_parsing() {
        assert!(admit_syntax_cohort([body_syntax::BUDGET, 1]).is_err());
        assert!(admit_syntax_cohort([usize::MAX]).is_err());
        assert!(admit_syntax_cohort([1, usize::MAX]).is_err());
    }
}

/// A real Kind10 -> Kind5 edge. This reuses the registered body syntax graph;
/// it never computes a parallel value model from the policy wrapper.
pub(super) fn observe(
    ctx: &mut dm_query::Ctx<'_>,
    input: &Arc<ArchiveValueInput>,
) -> Result<Result<Arc<ArchiveValueProof>, String>, QueryError> {
    let key = Key::new(VALUE_PROOFS, input.key().into());
    let answer = ctx.get::<ProofResult>(
        key,
        Arc::new(Params {
            input: Arc::downgrade(input),
            key,
        }),
    )?;
    Ok((|| {
        let proof = answer
            .as_ref()
            .as_ref()
            .map(Arc::clone)
            .map_err(|e| e.compatibility().0)?;
        proof.validate_for(input).map_err(|e| e.0)?;
        Ok(proof)
    })())
}

impl QueryDb {
    pub(crate) fn value_rejection_census(&self, c: &mut crate::heap_census::HeapCensus) {
        let inputs = self.value_inputs.lock().unwrap_or_else(|e| e.into_inner());
        for key in inputs.keys() {
            let Some(result) = self.db.retained_value::<ProofResult>(*key) else {
                continue;
            };
            if c.arc_object("native_value_result", &result) {
                match result.as_ref(){
                    Err(SemanticRejection::Unsupported(e))=>c.string("native_value_rejection",&e.0),
                    Err(SemanticRejection::Syntax(e))=>c.body_syntax_diagnostic("native_value_rejection",e),
                    Ok(_)=>c.unknown("native_value_result","existing value proof equation/solution storage is not enumerated by this rejection-only hook"),
                }
            }
        }
        c.unknown("native_value_rejection","original shared source Arc control blocks/allocator metadata and existing Db/index internals are not exact RSS accounting");
    }
}

#[cfg(test)]
mod rejection_storage_tests {
    use super::*;
    #[test]
    fn syntax_rejection_charge_includes_spare_message_and_path_and_exact_macro_rows() {
        let path = Arc::new({
            let mut p = PathBuf::from("code/probe.dm");
            p.reserve(4096);
            p
        });
        let macros = Arc::new({
            let mut v = Vec::with_capacity(16);
            v.push(dm_preprocess::regions::MacroExpansion {
                name: Arc::from("M"),
                invocation_span: dm_syntax::Span { start: 0, end: 1 },
                replacement_chain: Arc::from([Arc::<str>::from("M")]),
                definition: Some(dm_preprocess::regions::DefinitionOrigin {
                    path: path.clone(),
                    source_span: dm_syntax::Span { start: 0, end: 1 },
                    source_line: 1,
                }),
            });
            v.into_boxed_slice()
        });
        let location = dm_tree::frontend::SourceLocation {
            span: dm_ir::Span {
                file: Default::default(),
                start: 0,
                end: 1,
            },
            path: path.clone(),
            semantic_path: Arc::from("code/probe.dm"),
            line: 7,
            encounter_ordinal: 0,
            include_occurrence: 0,
            include_chain: Arc::from([0usize, 1]),
            macro_expansions: macros.clone().into(),
        };
        let mut message = String::from("actual original syntax error");
        message.reserve_exact(8192);
        let expected = message
            .capacity()
            .saturating_add(path.capacity() * 2)
            .saturating_add(
                macros.len() * std::mem::size_of::<dm_preprocess::regions::MacroExpansion>(),
            );
        let error = dm_tree::frontend::Diagnostic {
            kind: dm_tree::frontend::DiagnosticKind::SourceError,
            stage: dm_tree::frontend::DiagnosticStage::Syntax,
            message,
            location: Some(location),
        };
        let rejected = SemanticRejection::Syntax(error);
        assert!(rejected.charge() >= expected);
        let checked = rejected.clone().into_checked();
        match checked {
            ValueQueryFailure::Syntax(d) => {
                assert_eq!(d.location.as_ref().unwrap().line, 7);
                assert!(Arc::ptr_eq(&d.location.as_ref().unwrap().path, &path));
            }
            other => panic!("syntax became another failure: {other:?}"),
        }
        let mut census = crate::heap_census::HeapCensus::new("value-rejection-test");
        if let SemanticRejection::Syntax(d) = &rejected {
            census.body_syntax_diagnostic("value_rejection_test", d);
        }
        let report = census.finish();
        let minimum = path
            .capacity()
            .saturating_add(
                macros.len() * std::mem::size_of::<dm_preprocess::regions::MacroExpansion>(),
            )
            .saturating_add(8192);
        assert!(
            report.unique_known_capacity_bytes >= minimum as u64,
            "actual source/message/macro owners are visited, shared path deduplicated"
        );
    }
}
