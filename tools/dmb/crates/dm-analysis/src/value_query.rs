//! Query-host admission for whole-program source-semantic value proofs.
//! The existing compiler query graph owns reuse and invalidation. These issued
//! parameters/artifacts contain no sibling cache and no copied model or AST.
use crate::{
    untyped::Unsupported,
    value_program::{ValueProof, Values},
};
use dm_tree::frontend::{BodyArchive, BodySyntaxFailure, CurrentArchivedBody, Diagnostic};
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc, Weak,
};

/// Checked native value-query transport. Genuine semantic refusals and syntax
/// anchors stay distinct from actual operation failures; no IO is a proof.
#[derive(Debug)]
pub enum ValueQueryFailure {
    Unsupported(Unsupported),
    Syntax(Diagnostic),
    Operational(std::io::Error),
}
impl From<String> for ValueQueryFailure {
    fn from(e: String) -> Self {
        Self::Unsupported(Unsupported(e))
    }
}
impl From<&str> for ValueQueryFailure {
    fn from(e: &str) -> Self {
        Self::Unsupported(Unsupported(e.into()))
    }
}
impl From<Unsupported> for ValueQueryFailure {
    fn from(e: Unsupported) -> Self {
        Self::Unsupported(e)
    }
}
impl From<BodySyntaxFailure> for ValueQueryFailure {
    fn from(e: BodySyntaxFailure) -> Self {
        match e {
            BodySyntaxFailure::Syntax(d) => Self::Syntax(d),
            BodySyntaxFailure::Operational(e) => Self::Operational(e),
        }
    }
}
impl std::fmt::Display for ValueQueryFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Unsupported(e) => e.0.fmt(f),
            Self::Syntax(e) => e.message.fmt(f),
            Self::Operational(e) => e.fmt(f),
        }
    }
}
impl std::error::Error for ValueQueryFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Operational(e) => Some(e),
            _ => None,
        }
    }
}
/// A host loan of the actual current canonical BODY query result. The
/// scoped callback cannot retain the body's syntax or projected ledgers.
pub trait CanonicalValueBodies {
    fn with_current_body<T>(
        &self,
        archive: &BodyArchive,
        ordinal: usize,
        consume: impl FnOnce(CurrentArchivedBody<'_, '_>, &dm_syntax::SettingAdmission<'_>) -> Result<T, BodySyntaxFailure>,
    ) -> Result<T, BodySyntaxFailure>;
}

/// One retained archive plus canonical exemption policy. Only this constructor
/// issues keys; equal source bytes are never a proof's authority. The resolver
/// is always this archive's semantic tree, not a caller-supplied host.
pub struct ArchiveValueInput {
    key: u64,
    archive: Arc<BodyArchive>,
    exempt_types: Box<[String]>,
    canonical_bodies: bool,
}
impl ArchiveValueInput {
    pub fn new(archive: Arc<BodyArchive>, exempt_types: &[String]) -> Arc<Self> {
        Self::issue(archive, exempt_types, false)
    }
    /// Explicit opt-in, with a distinct proof issuance key. A proof from the
    /// existing compatibility entry cannot certify this body's provenance.
    pub fn new_canonical(archive: Arc<BodyArchive>, exempt_types: &[String]) -> Arc<Self> {
        Self::issue(archive, exempt_types, true)
    }
    fn issue(archive: Arc<BodyArchive>, exempt_types: &[String], canonical_bodies: bool) -> Arc<Self> {
        static NEXT: AtomicU64 = AtomicU64::new(1);
        let mut exempt_types = exempt_types.to_vec();
        exempt_types.sort();
        exempt_types.dedup();
        let key = NEXT
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |key| {
                key.checked_add(1)
            })
            .expect("native value input issuance exhausted");
        Arc::new(Self {
            key,
            archive,
            exempt_types: exempt_types.into(),
            canonical_bodies,
        })
    }
    pub fn key(&self) -> u64 {
        self.key
    }
    pub fn archive(&self) -> &Arc<BodyArchive> {
        &self.archive
    }
    pub fn exempt_types(&self) -> &[String] {
        &self.exempt_types
    }

    pub fn requires_canonical_bodies(&self) -> bool { self.canonical_bodies }

    /// Compute once inside the host query, after recording its parser-query
    /// edges. This module deliberately knows nothing about the graph engine.
    pub fn compute(self: &Arc<Self>) -> Result<Arc<ArchiveValueProof>, Unsupported> {
        if self.canonical_bodies { return Err(Unsupported("canonical value input requires its current BODY provider".into())); }
        let values =
            Values::build_archive(self.archive(), self.archive.tree(), &self.exempt_types)?;
        Ok(Arc::new(ArchiveValueProof {
            input: Arc::downgrade(self),
            summary: values.into_summary(),
        }))
    }
    pub fn compute_checked(self: &Arc<Self>) -> Result<Arc<ArchiveValueProof>, ValueQueryFailure> {
        if self.canonical_bodies { return Err("canonical value input requires its current BODY provider".into()); }
        let values =
            Values::build_archive_checked(self.archive(), self.archive.tree(), &self.exempt_types)?;
        Ok(Arc::new(ArchiveValueProof {
            input: Arc::downgrade(self),
            summary: values.into_summary(),
        }))
    }
    pub fn compute_canonical_checked(
        self: &Arc<Self>,
        provider: &impl CanonicalValueBodies,
    ) -> Result<Arc<ArchiveValueProof>, ValueQueryFailure> {
        if !self.canonical_bodies { return Err("compatibility value input cannot certify canonical BODY loans".into()); }
        if self.archive.source_mapping().initial_environment() != dm_preprocess::InitialEnvironment::OriginalChecker0290 {
            return Err("canonical value proof requires the actual Original initial environment".into());
        }
        let values = Values::build_archive_canonical_checked(self.archive(), &self.exempt_types, provider)?;
        Ok(Arc::new(ArchiveValueProof { input: Arc::downgrade(self), summary: values.into_summary() }))
    }
    pub fn obtain_checked(
        self: &Arc<Self>,
        host: &dyn ArchiveValueQueries,
    ) -> Result<Arc<ArchiveValueProof>, ValueQueryFailure> {
        let proof = host.value_proof_checked(self)?;
        proof.validate_for(self)?;
        Ok(proof)
    }
    pub fn obtain(
        self: &Arc<Self>,
        host: &dyn ArchiveValueQueries,
    ) -> Result<Arc<ArchiveValueProof>, Unsupported> {
        let proof = host.value_proof(self)?;
        proof.validate_for(self)?;
        Ok(proof)
    }
}
impl std::fmt::Debug for ArchiveValueInput {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ArchiveValueInput")
            .field("key", &self.key)
            .field("bodies", &self.archive.len())
            .field("exempt_types", &self.exempt_types)
            .finish()
    }
}

/// Immutable equations/solution/origin summaries. Weak issuance evidence does
/// not retain obsolete archives or form a cycle with the daemon's query graph.
pub struct ArchiveValueProof {
    input: Weak<ArchiveValueInput>,
    summary: Arc<ValueProof>,
}
impl ArchiveValueProof {
    pub fn validate_for(&self, input: &Arc<ArchiveValueInput>) -> Result<(), Unsupported> {
        if !self.input.ptr_eq(&Arc::downgrade(input)) {
            return Err(Unsupported(
                "value proof belongs to another archive/config issuance".into(),
            ));
        }
        Ok(())
    }
    pub fn budget_charge(&self) -> usize {
        self.summary.budget_charge()
    }
    pub(crate) fn summary(&self) -> Arc<ValueProof> {
        Arc::clone(&self.summary)
    }
}
impl std::fmt::Debug for ArchiveValueProof {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ArchiveValueProof")
            .field("budget_charge", &self.budget_charge())
            .finish_non_exhaustive()
    }
}

pub trait ArchiveValueQueries: std::fmt::Debug + Send + Sync {
    /// Compatibility-only hosts keep their independent contract. Native hosts
    /// override this to preserve actual operational failures from the SAME Db.
    fn value_proof_checked(
        &self,
        input: &Arc<ArchiveValueInput>,
    ) -> Result<Arc<ArchiveValueProof>, ValueQueryFailure> {
        self.value_proof(input)
            .map_err(ValueQueryFailure::Unsupported)
    }
    fn value_proof(
        &self,
        input: &Arc<ArchiveValueInput>,
    ) -> Result<Arc<ArchiveValueProof>, Unsupported>;
}

#[cfg(test)]
#[path = "value_query_tests.rs"]
mod tests;
