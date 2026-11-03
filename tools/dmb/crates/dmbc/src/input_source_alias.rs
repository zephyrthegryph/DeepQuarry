//! Optional acquired-file alias contract. No payload read and no generic key fold.
use super::*;
use std::sync::Arc;
#[derive(Clone, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
pub(crate) struct SourceAliasRecord {
    primary: FileInput,
    alias: FileInput,
}
struct Challenge {
    primary: FileInput,
    lease: Option<dm_preprocess::SourceAcquisitionLease>,
}
/// Only RecordingInputs can issue this from a genuine current positive file
/// observation. Acquired-source use additionally carries its actual lease.
#[derive(Clone)]
pub struct SourceAliasChallenge(Arc<Challenge>);
impl SourceAliasChallenge {
    pub fn primary(&self) -> &FileInput {
        &self.0.primary
    }
}
/// Opaque producer response bound to the exact private issued challenge.
#[derive(Clone)]
pub struct SourceAliasProof {
    challenge: SourceAliasChallenge,
    alias: FileInput,
}
impl SourceAliasProof {
    pub(crate) fn primary(&self) -> &FileInput {
        self.challenge.primary()
    }
    pub(crate) fn alias(&self) -> &FileInput {
        &self.alias
    }
    pub(crate) fn record(&self) -> SourceAliasRecord {
        SourceAliasRecord {
            primary: self.primary().clone(),
            alias: self.alias.clone(),
        }
    }
}
fn safe_drive_alias(left: &Path, right: &Path) -> bool {
    #[cfg(windows)]
    {
        left != right
            && dm_preprocess::regions::relative_filesystem_path(left, right)
                .is_some_and(|path| path.as_os_str().is_empty())
    }
    #[cfg(not(windows))]
    {
        let _ = (left, right);
        false
    }
}
impl SourceAliasRecord {
    pub(crate) fn replay(
        &self,
        requested: &Path,
        challenge: &SourceAliasChallenge,
    ) -> io::Result<SourceAliasProof> {
        let primary = challenge.primary();
        if &self.primary != primary
            || self.alias.path != requested
            || !safe_drive_alias(requested, &primary.path)
            || primary.stamp.file_id.is_none()
            || self.alias.stamp != primary.stamp
            || self.alias.content != primary.content
        {
            return Err(invalid("recorded acquired-source alias proof differs"));
        }
        Ok(SourceAliasProof {
            challenge: challenge.clone(),
            alias: self.alias.clone(),
        })
    }
}
pub(super) fn filesystem_source_alias(
    requested: &Path,
    challenge: &SourceAliasChallenge,
) -> io::Result<Option<SourceAliasProof>> {
    let primary = challenge.primary();
    if !safe_drive_alias(requested, &primary.path) || primary.stamp.file_id.is_none() {
        return Ok(None);
    }
    // Actual filesystem contract plus current stable file identity, not equal
    // bytes/hash as identity. Ordinary publication still validates both paths.
    if FileSystemInputs.stamp(requested)? != primary.stamp {
        return Err(invalid("source alias file identity/stamp changed"));
    }
    Ok(Some(SourceAliasProof {
        challenge: challenge.clone(),
        alias: FileInput {
            path: requested.to_path_buf(),
            ..primary.clone()
        },
    }))
}
/// Current-capture binding; retains only a light genuine primary lease.
pub(crate) struct AcquiredSourceAlias {
    proof: SourceAliasProof,
}
impl AcquiredSourceAlias {
    pub(crate) fn metadata_charge(&self) -> usize {
        std::mem::size_of::<Self>()
            .saturating_add(2 * std::mem::size_of::<usize>())
            .saturating_add(std::mem::size_of::<Challenge>())
            .saturating_add(2 * std::mem::size_of::<usize>())
            .saturating_add(self.proof.primary().path.capacity())
            .saturating_add(self.proof.alias().path.capacity())
    }
    pub(crate) fn primary_path(&self) -> &Path {
        &self.proof.primary().path
    }
    pub(crate) fn requested_path(&self) -> &Path {
        &self.proof.alias().path
    }
    pub(crate) fn visit_metadata(&self, mut visit: impl FnMut(&PathBuf)) {
        visit(&self.proof.primary().path);
        visit(&self.proof.alias().path);
    }
    pub(crate) fn visit_challenge(&self, visit: impl FnOnce(usize, usize)) {
        visit(
            Arc::as_ptr(&self.proof.challenge.0) as usize,
            std::mem::size_of::<Challenge>(),
        );
    }
    pub(crate) fn lease(&self) -> &dm_preprocess::SourceAcquisitionLease {
        self.proof.challenge.0.lease.as_ref().expect("acquired alias constructor requires an actual source lease")
    }
}
impl<P: SnapshotProvider> RecordingInputs<P> {
    /// Record a supported provider-certified alias of an actual positive file
    /// observation. This creates no source acquisition, decoded view or role.
    pub(super) fn record_observed_file_alias(&self,requested:&Path,primary:&Path)->io::Result<()>{
        let requested=canonical_path(requested);let primary=canonical_path(primary);
        if requested==primary{return Ok(())}
        let fact=self.recorded_file_fact(&primary)?;
        let challenge=SourceAliasChallenge(Arc::new(Challenge{primary:fact.clone(),lease:None}));
        let proof=self.provider.source_alias(&requested,&challenge)?.ok_or_else(||invalid("provider cannot certify actual observed file alias"))?;
        if !Arc::ptr_eq(&proof.challenge.0,&challenge.0)||proof.primary()!=&fact||proof.alias().path!=requested||proof.alias().stamp!=fact.stamp||proof.alias().content!=fact.content{return Err(invalid("observed file alias proof differs"))}
        let mut current=self.snapshot.lock().map_err(|_|invalid("input mutex poisoned"))?;
        if current.files.get(&primary)!=Some(&fact){return Err(invalid("observed alias primary changed"))}
        current.record_verified_digest(&requested,proof.alias().stamp.clone(),proof.alias().content)
    }

    pub(crate) fn acquire_source_alias(
        &self,
        requested: &Path,
        primary: &Path,
        text: &dm_preprocess::SourceText,
    ) -> io::Result<Option<Arc<AcquiredSourceAlias>>> {
        let requested = canonical_path(requested);
        let primary = canonical_path(primary);
        let Some(acquired) = self.current_source_acquisition(&primary, text) else {
            return Ok(None);
        };
        let fact = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input mutex poisoned"))?
            .files
            .get(&primary)
            .cloned()
            .ok_or_else(|| invalid("acquired alias primary fact unavailable"))?;
        let challenge = SourceAliasChallenge(Arc::new(Challenge {
            primary: fact.clone(),
            lease: Some(acquired.lease().clone()),
        }));
        let Some(proof) = self.provider.source_alias(&requested, &challenge)? else {
            return Ok(None);
        };
        if !Arc::ptr_eq(&proof.challenge.0, &challenge.0)
            || proof.primary() != &fact
            || proof.alias().path != requested
            || proof.alias().stamp != fact.stamp
            || proof.alias().content != fact.content
            || !self.validate_source_acquisition(&primary, &acquired)
        {
            return Err(invalid("foreign acquired-source alias proof"));
        }
        self.snapshot
            .lock()
            .map_err(|_| invalid("input mutex poisoned"))?
            .record_verified_digest(
                &requested,
                proof.alias().stamp.clone(),
                proof.alias().content,
            )?;
        Ok(Some(Arc::new(AcquiredSourceAlias { proof })))
    }
}

#[cfg(test)]
#[path = "input_source_alias_tests.rs"]
mod tests;
