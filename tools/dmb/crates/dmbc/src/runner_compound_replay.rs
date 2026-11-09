//! Optional one-entry replay of exact verified joined output. No model or pair.
use std::{io,path::{Path,PathBuf},sync::atomic::{AtomicBool,Ordering}};
use dm_preprocess::source_arena_credit::{SourceArenaControlCredit,SourceArenaCredit,SourceArenaWork};
use crate::{
    daemon::selected_report_wire::{CompiledSelectedReports,CompoundRoster,CompoundSendScratch,Frame},
    request::{BuildOutcome,BuildRequest},
    request_runner::JoinedSelectedInputs,
    selected_report_spool::Verified,
};
use dq_analyze::selected_exclusions_wire::Frame as CheckerFrame;

#[derive(Eq, PartialEq)]
pub(super) struct Candidate {
    root: PathBuf,
    physical_cache: PathBuf,
    roster: CompoundRoster,
    compact_checker: bool,
    workers: usize,
    progress_enabled: bool,
    timeout_seconds: Option<u16>,
    no_cache: bool,
}

pub(super) struct Key {
    candidate: Candidate,
    exclusions: Vec<String>,
    _credit: SourceArenaCredit,
}

impl Candidate {
    pub(super) fn closed(
        prepare: &BuildRequest, root: PathBuf, physical_cache: PathBuf,
        roster: CompoundRoster, compact_checker: bool,
    ) -> Option<Self> {
        use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
        // The caller already validated the exact closed authored shape. Check
        // its lexical source/role paths as well, so alternate spellings simply
        // decline rather than relying on equivalence through canonicalization.
        let workspace = prepare.policy_inputs.as_ref()?.workspace.as_ref()?;
        let expected_roots = match roster {
            CompoundRoster::Selected(roster) => roster.workspace_roots(),
            _ => Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY)?,
        };
        if prepare.warnings != crate::diagnostics::WarningPolicy::default()
            || workspace.root != root
            || prepare.project.strip_prefix(&root).ok() != Some(Path::new("deepquarry.dme"))
            || workspace.configuration.strip_prefix(&root).ok() != Some(Path::new("tools/ci/lint_scopes.toml"))
            || !workspace.recursive_roots.iter().zip(expected_roots).all(|(actual, expected)|
                actual.strip_prefix(&root).ok() == Some(Path::new(expected)))
        {
            return None;
        }
        Some(Self {
            root, physical_cache, roster, compact_checker, workers: prepare.workers,
            progress_enabled: prepare.progress_enabled, timeout_seconds: prepare.timeout_seconds,
            no_cache: prepare.no_cache,
        })
    }

    /// Pay optional key storage only after the real cold publication. A
    /// failure here cannot undo the normal delivery of that current outcome.
    pub(super) fn try_retain(self, exclusions: &[String], work: &dyn SourceArenaWork) -> Option<Key> {
        let text = exclusions.iter().try_fold(0usize, |total, text| {
            total.checked_add(text.capacity())?.checked_add(std::mem::size_of::<String>())
        })?;
        let bytes = self.root.capacity().checked_add(self.physical_cache.capacity())?
            .checked_add(text.checked_mul(4)?)?.checked_add(std::mem::size_of::<Key>())?;
        if bytes > 64*1024 { return None; }
        let credit = work.reserve(bytes).ok()?;
        Some(Key { candidate: self, exclusions: exclusions.to_vec(), _credit: credit })
    }
}

pub(super) struct Reports {
    pub(super) frame: Frame,
    pub(super) clean: bool,
    pub(super) diagnostics: Option<Verified>,
    pub(super) checker: (CheckerFrame,Verified),
    pub(super) report: Verified,
    pub(super) credit: SourceArenaControlCredit,
}

impl Reports {
    pub(super) fn with_publication(
        self, compiled: BuildOutcome, roster: CompoundRoster, send_scratch: Option<CompoundSendScratch>,
    ) -> CompiledSelectedReports {
        CompiledSelectedReports {
            compiled, roster, frame: self.frame, clean: self.clean, diagnostics: self.diagnostics,
            checker: self.checker, report: self.report, _credit: self.credit, send_scratch,
        }
    }

    pub(super) fn try_retain(mut self, key: Key, work: &dyn SourceArenaWork) -> (Self,Option<(Key,Self)>) {
        // Bound the additional disk lifetime per host and never duplicate a file.
        let length = self.report.length().checked_add(self.checker.1.length())
            .and_then(|n|n.checked_add(self.diagnostics.as_ref().map_or(0, Verified::length)));
        if length.is_none_or(|length|length > dq_analyze::selected_exclusions_wire::MAX_STREAM) {
            return (self,None);
        }
        let mut denied = false;
        let mut share = |spool: Verified| match spool.into_replayable(work) {
            Ok(ready) => ready,
            Err((original,_)) => {
                // Optional retention cannot change a freshly published outcome.
                // Normal output still observes current cancellation and IO.
                denied = true;
                original
            }
        };
        self.diagnostics = self.diagnostics.map(&mut share);
        self.checker.1 = share(self.checker.1);
        self.report = share(self.report);
        if denied { return (self,None); }
        let alias = self.replay_alias();
        (self,alias.map(|alias|(key,alias)))
    }

    fn replay_alias(&self) -> Option<Self> {
        let diagnostics = match &self.diagnostics {
            Some(spool) => Some(spool.replay_alias()?),
            None => None,
        };
        Some(Self {
            frame: self.frame, clean: self.clean, diagnostics,
            checker: (self.checker.0,self.checker.1.replay_alias()?),
            report: self.report.replay_alias()?, credit: self.credit.clone(),
        })
    }
}

// This limits retained disk handles independently of host/variant count.
static RETAINED_COMPOUND_SLOT: AtomicBool = AtomicBool::new(false);

pub(super) struct RetainedSlot(&'static AtomicBool);

impl RetainedSlot {
    pub(super) fn acquire() -> Option<Self> {
        Self::claim(&RETAINED_COMPOUND_SLOT)
    }

    fn claim(slot: &'static AtomicBool) -> Option<Self> {
        slot.compare_exchange(false,true,Ordering::AcqRel,Ordering::Acquire)
            .ok().map(|_|Self(slot))
    }
}

impl Drop for RetainedSlot {
    fn drop(&mut self) {
        self.0.store(false,Ordering::Release);
    }
}

pub(super) struct Entry {
    pub(super) key: Key,
    pub(super) reports: Reports,
    pub(super) joined: JoinedSelectedInputs,
    // Release the sole process claim only after retained owners drop.
    pub(super) _slot: RetainedSlot,
}

impl Entry {
    pub(super) fn matches(&self, candidate: &Candidate, exclusions: &[String]) -> bool {
        self.key.candidate == *candidate && self.key.exclusions.as_slice() == exclusions
    }

    pub(super) fn output_for_replay(&self) -> io::Result<Option<Reports>> {
        if let Some(notices) = &self.reports.diagnostics {
            if !notices.check_replay()? { return Ok(None); }
        }
        if !self.reports.checker.1.check_replay()? || !self.reports.report.check_replay()? {
            return Ok(None);
        }
        self.reports.replay_alias().map(Some)
            .ok_or_else(||io::Error::other("joined report replay lost its verified backing"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn retained_compound_slot_is_exclusive_and_refundable() {
        static SLOT: AtomicBool = AtomicBool::new(false);
        let held = RetainedSlot::claim(&SLOT).unwrap();
        std::thread::scope(|scope| {
            assert!(scope.spawn(||RetainedSlot::claim(&SLOT).is_none()).join().unwrap());
        });
        drop(held);
        assert!(RetainedSlot::claim(&SLOT).is_some());
    }
}
