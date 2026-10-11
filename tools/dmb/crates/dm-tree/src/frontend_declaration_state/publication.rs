//! Request ownership of the existing declaration cores, independent of the
//! current semantic/query tree. Every mutable operation runs under the pending
//! guard; failed requests cannot replace published claims or bookkeeping.
use super::*;
use std::sync::Mutex;
type Attempt = dm_session::ArtifactAttempt<DeclarationClaims>;
struct Owner {
    seed: DeclarationClaims,
    published: Arc<dm_session::ArtifactPublication<DeclarationClaims>>,
}
struct Access {
    owner: Arc<Owner>,
    current: Mutex<Arc<Attempt>>,
    external_guard: Mutex<std::sync::Weak<()>>,
}
pub(in crate::frontend) struct RetainedDeclarations {
    pub(in crate::frontend) grammar: GrammarAccess,
    access: Arc<Access>,
}
pub(in crate::frontend) struct GrammarAccess {
    access: Arc<Access>,
}
/// Owned request guard: it neither borrows nor retains a semantic tree.
pub struct DeclarationRequest {
    attempt: Arc<Attempt>,
    _lifetime: Arc<()>,
}
impl DeclarationRequest {
    pub fn publish_successful(&self) -> bool {
        self.attempt.publish_successful()
    }
}
impl Drop for DeclarationRequest {
    fn drop(&mut self) {
        self.attempt.abort();
    }
}
impl DeclarationClaims {
    fn fork(&self, previous: Option<&Self>) -> Self {
        let authored_current = previous.and_then(|old| {
            old.authored_current
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .clone()
        });
        let symbols = previous
            .map(|old| Arc::clone(&old.symbols.lock().unwrap_or_else(|e| e.into_inner())))
            .unwrap_or_default();
        Self {
            grammar: self.grammar.fork(),
            values: self.values.fork(),
            authored: self.authored.as_ref().map(|lease| lease.fork()),
            authored_current: Arc::new(Mutex::new(authored_current)),
            symbols: Mutex::new(symbols),
            keys: AtomicUsize::new(0),
            hits: AtomicUsize::new(0),
        }
    }
}
impl Default for RetainedDeclarations {
    fn default() -> Self {
        Self::from_seed(DeclarationClaims::default())
    }
}
impl Access {
    fn current(&self) -> Arc<Attempt> {
        Arc::clone(&self.current.lock().unwrap_or_else(|e| e.into_inner()))
    }
    fn with_pending<T>(&self, operation: impl FnOnce(&DeclarationClaims) -> T) -> Option<T> {
        self.current().with_pending(operation)
    }
}
impl RetainedDeclarations {
    fn from_seed(seed: DeclarationClaims) -> Self {
        let published = Arc::new(dm_session::ArtifactPublication::default());
        let attempt = Arc::new(published.begin(seed.fork(None)));
        let access = Arc::new(Access {
            owner: Arc::new(Owner { seed, published }),
            current: Mutex::new(attempt),
            external_guard: Mutex::new(std::sync::Weak::new()),
        });
        Self {
            grammar: GrammarAccess {
                access: Arc::clone(&access),
            },
            access,
        }
    }
    pub(crate) fn with_shared_authored(owner: Arc<crate::SharedNormalizedDeclarations>) -> Self {
        Self::from_seed(DeclarationClaims::with_shared_authored(owner))
    }
    pub(in crate::frontend) fn begin_request(&self, publishable: bool) -> DeclarationRequest {
        let owner = &self.access.owner;
        let claims = owner
            .published
            .with_published(|previous| owner.seed.fork(Some(previous)))
            .unwrap_or_else(|| owner.seed.fork(None));
        let attempt = Arc::new(if publishable {
            owner.published.begin(claims)
        } else {
            owner.published.begin_ephemeral(claims)
        });
        *self
            .access
            .current
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Arc::clone(&attempt);
        let lifetime = Arc::new(());
        *self
            .access
            .external_guard
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Arc::downgrade(&lifetime);
        DeclarationRequest {
            attempt,
            _lifetime: lifetime,
        }
    }
    pub(in crate::frontend) fn key(text: &str) -> Vec<u8> {
        DeclarationClaims::key(text)
    }
    pub(in crate::frontend) fn compatibility_request(&self) -> Option<DeclarationRequest> {
        let external = self
            .access
            .external_guard
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .upgrade()
            .is_some();
        (!external).then(|| self.begin_request(true))
    }
    pub(in crate::frontend) fn retain(&self, keys: &[Vec<u8>]) {
        self.access.with_pending(|claims| claims.retain(keys));
    }
    pub(in crate::frontend) fn clear(&self) {
        self.access.current().abort();
        let empty = Arc::new(
            self.access
                .owner
                .published
                .begin(self.access.owner.seed.fork(None)),
        );
        empty.publish_successful();
        *self
            .access
            .current
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Arc::new(
            self.access
                .owner
                .published
                .begin(self.access.owner.seed.fork(None)),
        );
    }
    pub(in crate::frontend) fn get_shared(
        &self,
        key: &[u8],
        text: &str,
        offset: usize,
    ) -> Option<CurrentContribution> {
        self.access
            .with_pending(|claims| claims.get_shared(key, text, offset))
            .flatten()
    }
    pub(in crate::frontend) fn capture(
        &self,
        key: &[u8],
        text: &str,
        offset: usize,
        items: Vec<Item>,
        facts: crate::AdaptedDeclarations,
        ledger: AllocationLedger,
    ) -> Option<CurrentContribution> {
        self.access
            .with_pending(|claims| claims.capture(key, text, offset, items, facts, ledger))
            .flatten()
    }
    pub(in crate::frontend) fn current_catalog(
        &self,
        current: &[Arc<Contribution>],
        engine: Option<&SymbolTable>,
    ) -> Result<Arc<super::super::symbol_catalog::SymbolCatalog>, dm_ir::SymbolCollision> {
        // Calls belong to active frontend requests. After sealing, standalone
        // compatibility obtains a fresh catalog without mutating retained data.
        self.access
            .with_pending(|claims| claims.current_catalog(current, engine))
            .unwrap_or_else(|| DeclarationClaims::default().current_catalog(current, engine))
    }
    pub(crate) fn take_authored_index(
        &self,
        skeletons: crate::skeleton_roster::SkeletonView<'_>,
    ) -> Option<crate::declaration_contributions::KeyedDeclarations> {
        self.access
            .with_pending(|claims| claims.take_authored_index(skeletons))
            .flatten()
    }
    pub(crate) fn adopt_authored<'a>(
        &self,
        currents: impl IntoIterator<Item = &'a mut CurrentContribution>,
    ) -> Option<()> {
        self.access
            .with_pending(|claims| claims.adopt_authored(currents))
            .flatten()
    }
    pub(in crate::frontend) fn stats(&self) -> DeclarationRetentionStats {
        self.access
            .with_pending(|claims| claims.stats())
            .or_else(|| {
                self.access
                    .owner
                    .published
                    .with_published(|claims| claims.stats())
            })
            .unwrap_or_default()
    }
    pub(in crate::frontend) fn visit_storage(
        &self,
        mut visit: impl FnMut(DeclarationStorageView<'_>),
    ) {
        // Visit each generic core once; current/published bookkeeping leaves
        // share the caller's pointer ledger rather than summing reports.
        self.access.owner.seed.values.visit_storage(&mut visit);
        let mut bookkeeping = |claims: &DeclarationClaims| {
            claims.visit_bookkeeping(|view| {
                if matches!(
                    view,
                    DeclarationStorageView::AuthoredLeafRoster { .. }
                        | DeclarationStorageView::SymbolCatalog { .. }
                ) {
                    visit(view);
                }
            });
        };
        self.access.with_pending(&mut bookkeeping);
        self.access.owner.published.with_published(&mut bookkeeping);
    }
    pub(crate) fn visit_authored_storage(
        &self,
        visit: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                crate::declaration_contributions::TypeContribution,
                dm_ir::SymbolId,
                Option<Arc<[crate::declaration_contributions::DeclarationRow]>>,
                (),
            >,
        ),
    ) {
        self.access.owner.seed.visit_authored_storage(visit);
    }
    #[cfg(test)]
    pub(in crate::frontend) fn authored_current(
        &self,
    ) -> Arc<Mutex<Option<Arc<authored::AdmittedAuthored>>>> {
        self.access
            .with_pending(|claims| Arc::clone(&claims.authored_current))
            .expect("active test frontend")
    }
    #[cfg(test)]
    pub(in crate::frontend) fn current_symbols(
        &self,
        current: &[Arc<Contribution>],
    ) -> Result<SymbolTable, dm_ir::SymbolCollision> {
        self.access
            .with_pending(|claims| claims.current_symbols(current))
            .unwrap_or_else(|| DeclarationClaims::default().current_symbols(current))
    }
    #[cfg(test)]
    pub(in crate::frontend) fn get(
        &self,
        key: &[u8],
        text: &str,
        offset: usize,
    ) -> Option<(Vec<Item>, crate::AdaptedDeclarations, AllocationLedger)> {
        self.access
            .with_pending(|claims| claims.get(key, text, offset))
            .flatten()
    }
    #[cfg(test)]
    pub(in crate::frontend) fn insert(
        &self,
        key: &[u8],
        text: &str,
        offset: usize,
        items: &[Item],
        facts: &crate::AdaptedDeclarations,
        ledger: &AllocationLedger,
    ) {
        self.access
            .with_pending(|claims| claims.insert(key, text, offset, items, facts, ledger));
    }
}
impl GrammarAccess {
    pub(in crate::frontend) fn discover(
        &self,
        expanded: &ExpandedRegions,
    ) -> Result<Arc<super::super::grammar_roster::GrammarDescriptors>, &'static str> {
        self.access
            .with_pending(|claims| claims.grammar.discover(expanded))
            .unwrap_or_else(|| self.access.owner.seed.grammar.fork().discover(expanded))
    }
    pub(in crate::frontend) fn hits(&self) -> usize {
        self.access
            .with_pending(|claims| claims.grammar.hits())
            .or_else(|| {
                self.access
                    .owner
                    .published
                    .with_published(|claims| claims.grammar.hits())
            })
            .unwrap_or(0)
    }
    pub(in crate::frontend) fn visit_storage(
        &self,
        visit: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                super::super::grammar_roster::GrammarDescriptors,
                super::super::grammar_roster::GrammarQuery,
                super::super::grammar_roster::GrammarAnswer,
                (),
            >,
        ),
    ) {
        self.access.owner.seed.grammar.visit_storage(visit);
    }
}

#[cfg(test)]
mod request_tests {
    use super::*;
    fn capture(state: &RetainedDeclarations, text: &str) -> CurrentContribution {
        let parsed = dm_syntax::parse_declaration_skeleton(text);
        assert!(parsed.diagnostics.is_empty());
        let ast = AstFile {
            items: parsed.items,
            diagnostics: parsed.diagnostics,
            tokens: Vec::new(),
        };
        let mut facts = crate::from_ast(&ast, SymbolTable::default(), FileId(0), 0, 0).unwrap();
        let ledger =
            crate::allocation_ledger::capture(&ast.items, "/", &mut facts.symbols).unwrap();
        let mut current = state
            .capture(
                &RetainedDeclarations::key(text),
                text,
                0,
                ast.items,
                facts,
                ledger,
            )
            .unwrap();
        state.adopt_authored(std::iter::once(&mut current)).unwrap();
        current
    }
    fn entries(state: &RetainedDeclarations) -> usize {
        let mut count = 0;
        state.visit_storage(|view| {
            if let DeclarationStorageView::Store { entries, .. } = view {
                count = entries;
            }
        });
        count
    }
    fn state() -> RetainedDeclarations {
        RetainedDeclarations::with_shared_authored(Arc::new(
            crate::SharedNormalizedDeclarations::default(),
        ))
    }
    #[test]
    fn aborted_declaration_request_preserves_published_and_releases_partial_claims() {
        let state = state();
        let original = "/obj/base\n    var/count=1\n";
        let changed = "/obj/new_owner\n    var/count=2\n";
        let first = state.begin_request(true);
        let owner = capture(&state, original).value;
        assert!(first.publish_successful());
        drop(first);
        assert_eq!(entries(&state), 1);
        let failed = state.begin_request(true);
        let partial_owner = capture(&state, changed).value;
        let partial = Arc::downgrade(&partial_owner);
        drop(partial_owner);
        assert_eq!(entries(&state), 2);
        drop(failed);
        assert!(partial.upgrade().is_none());
        assert_eq!(entries(&state), 1);
        let next = state.begin_request(true);
        let mut current = state
            .get_shared(&RetainedDeclarations::key(original), original, 70)
            .unwrap();
        assert!(Arc::ptr_eq(&owner, &current.value));
        state.adopt_authored(std::iter::once(&mut current)).unwrap();
        assert!(next.publish_successful());
    }
    #[test]
    fn ephemeral_declaration_request_cannot_supersede_compile_publication() {
        let state = state();
        let build = state.begin_request(true);
        let owner = capture(&state, "/obj/base\n    var/count=1\n").value;
        let analysis = state.begin_request(false);
        capture(&state, "/obj/analysis\n    var/other=2\n");
        assert!(!analysis.publish_successful());
        drop(analysis);
        assert!(build.publish_successful());
        drop(build);
        let next = state.begin_request(true);
        let current = state
            .get_shared(
                &RetainedDeclarations::key("/obj/base\n    var/count=1\n"),
                "/obj/base\n    var/count=1\n",
                0,
            )
            .unwrap();
        assert!(Arc::ptr_eq(&owner, &current.value));
        drop(next);
    }
    #[test]
    fn frontend_compatibility_boundary_respects_external_guard_and_clear() {
        let state = state();
        let text = "/obj/base\n    var/count=1\n";
        let external = state.begin_request(true);
        assert!(state.compatibility_request().is_none());
        capture(&state, text);
        drop(external);
        assert_eq!(entries(&state), 0);
        let direct = state.compatibility_request().unwrap();
        capture(&state, text);
        assert!(direct.publish_successful());
        drop(direct);
        assert_eq!(entries(&state), 1);
        state.clear();
        assert_eq!(entries(&state), 0);
        let direct = state.compatibility_request().unwrap();
        capture(&state, text);
        assert!(direct.publish_successful());
    }
}
