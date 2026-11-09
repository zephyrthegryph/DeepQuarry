use super::*;
use crate::{
    query_db::{NativeQueryOwnerIdentity, QueryDb},
    runner_host::workspace_discovery::DiscoveryReceipt,
    selected_report_spool::{Sealed, Stage},
};
use dq_analyze::{
    captured_reactive_reads::Failure,
    lints::check_grep::native as grep,
};
use std::{io::{Read, Write}, ops::Range};

struct Observed {
    stamp: Stamp,
    content: u128,
}
impl Observed {
    fn require(&self, fact: &FileInput) -> io::Result<()> {
        if self.stamp != fact.stamp || self.content != fact.content {
            return Err(invalid("staged DMM file observation changed"));
        }
        Ok(())
    }
}
enum Outcome<E> {
    Unselected,
    Ready(Range<u64>),
    Failed(E),
    Consumed,
}
struct FactRow {
    ordinal: usize,
    fact: Observed,
}

pub(crate) struct PairedDmmFacts {
    discovery: Arc<DiscoveryReceipt>,
    rows: Vec<FactRow>,
}

impl PairedDmmFacts {
    fn slot(&self, ordinal: usize) -> io::Result<usize> {
        self.rows.binary_search_by_key(&ordinal, |row| row.ordinal)
            .map_err(|_| invalid("paired DMM omitted expected capture slot"))
    }

    pub(crate) fn path(&self, ordinal: usize) -> io::Result<&Path> {
        self.slot(ordinal)?;
        self.discovery.files().get(ordinal).map(PathBuf::as_path)
            .ok_or_else(|| invalid("paired DMM path absent from its discovery ordinal"))
    }

    pub(crate) fn require(&self, ordinal: usize, fact: &FileInput) -> io::Result<()> {
        let slot = self.slot(ordinal)?;
        if self.discovery.files().get(ordinal) != Some(&fact.path) {
            return Err(invalid("paired DMM fact path differs from its discovery ordinal"));
        }
        self.rows[slot].fact.require(fact)
    }

    pub(crate) fn facts_in(&self, current: &InputSnapshot) -> bool {
        self.rows.iter().all(|row| {
            self.discovery.files().get(row.ordinal)
                .and_then(|path| current.recorded_canonical_file(path))
                .is_some_and(|fact| self.discovery.files().get(row.ordinal) == Some(&fact.path)
                    && row.fact.require(fact).is_ok())
        })
    }
}

struct Entry {
    map: Outcome<io::Error>,
    grep: Outcome<Failure>,
}
pub(crate) struct PairedDmmStage {
    facts: Arc<PairedDmmFacts>,
    recorder: Arc<()>,
    queries: NativeQueryOwnerIdentity,
    entries: Vec<Entry>,
    map_order: Vec<usize>,
    read_failure: Option<(usize, io::Error)>,
    spool: Sealed,
}

impl PairedDmmStage {
    /// The caller holds the actual source-family gate and records any
    /// escaping stage control in that family before releasing the budget.
    pub(crate) fn stage<P: SnapshotProvider>(
        inputs: &RecordingInputs<P>,
        derived: &Arc<DerivedPreflight>,
        queries: &QueryDb,
        budget: &Arc<Budget>,
        lender: &mut dyn RecordedPolicySourceLender,
        cache: &Path,
    ) -> io::Result<Self> {
        derived.require_recording(inputs)?;
        {
            let current = inputs.snapshot.lock().map_err(|_| invalid("paired DMM recorder poisoned"))?;
            if !derived.handler_prefix_donor(inputs, queries, &current) {
                return Err(invalid("paired DMM requires the actual joined Derived query owner"));
            }
        }
        let discovery = Arc::clone(derived.discovery());
        discovery.check_grep_names()?;
        let root = &discovery.contract().root;
        let is_dmm = |path: &Path| path.strip_prefix(root).is_ok_and(|relative|
            relative.starts_with("maps") && relative.extension().is_some_and(|ext| ext == "dmm"));
        let count = discovery.files().iter().filter(|path| is_dmm(path)).count();
        let fixed = count.checked_mul(std::mem::size_of::<Entry>() + std::mem::size_of::<FactRow>()
                + std::mem::size_of::<usize>())
            .and_then(|n| n.checked_add(std::mem::size_of::<Self>() + NativeQueryOwnerIdentity::retained_charge()
                + std::mem::size_of::<PairedDmmFacts>() + 2 * std::mem::size_of::<usize>()))
            .ok_or(io::ErrorKind::OutOfMemory)?;
        budget.charge(fixed).map_err(quota)?;
        let mut entries = exact_vec(count)?;
        let mut fact_rows = exact_vec(count)?;
        let mut map_order = exact_vec(count)?;
        inputs.fold_observed_map_edits_inputs(&discovery, budget, lender, |path, _| {
            let ordinal = discovery.files().iter().position(|candidate| candidate == path && is_dmm(candidate))
                .ok_or_else(|| invalid("MapEdits path lacks its joined CheckGrep DMM membership"))?;
            if map_order.len() == count || map_order.contains(&ordinal) {
                return Err(invalid("joined MapEdits DMM membership repeats"));
            }
            map_order.push(ordinal);
            Ok(())
        })?;

        let config = derived.joined_configuration(inputs, queries)?;
        let scope = config.check_grep_scope().map_err(|message| io::Error::new(io::ErrorKind::InvalidData, message))?;
        budget.charge(scope.budget_charge()).map_err(quota)?;
        let mut spool = Stage::new(cache)?;
        spool.write_all(b"DQ-DMM-PAIR\x01")?;

        let before = inputs.snapshot.lock().map_err(|_| invalid("paired DMM recorder poisoned"))?
            .policy_closure_charge()?;
        let metadata_owner = inputs.policy_metadata_owner(Some(budget))?;
        lender.prepare_directory_metadata(&metadata_owner, before)?;
        let mut read_failure = None;
        let read_result = (|| -> io::Result<()> {
            for (ordinal, path) in discovery.files().iter().enumerate().filter(|(_, path)| is_dmm(path)) {
                crate::daemon::control::checkpoint()?;
                budget.charge(path_charge(path, 32, 8192)?).map_err(quota)?;
                let raw_scope = Budget::scoped_temporaries(budget).map_err(quota)?;
                raw_scope.charge(path_charge(path, 4, 512)?).map_err(quota)?;
                // This is the only actual provider read for this DMM. Both
                // source-neutral producers run below on this exact allocation.
                let raw = match inputs.read_policy_payload_admitted(path, budget.remaining(),
                    &mut |size| raw_scope.charge(size).map_err(quota)) {
                    Ok(Some(raw)) => raw,
                    Ok(None) => {
                        read_failure = Some((ordinal, io::Error::new(io::ErrorKind::Interrupted,
                            "discovered paired DMM disappeared before bounded read")));
                        break;
                    }
                    Err(actual) => { read_failure = Some((ordinal, actual)); break; }
                };
                let fact = inputs.recorded_file_fact(path)?;
                raw_scope.charge(256).map_err(quota)?;
                let raw: dm_resources::SharedBytes = raw.into();
                let relative = dq_analyze::util::rel_slash(path, root);
                let map = if map_order.contains(&ordinal) {
                    isolated(budget, |local| match map_edits_policy::ParsedMap::parse(
                        raw.as_slice(), local, &crate::daemon::control::checkpoint,
                    ) {
                        Ok(data) => Ok(Outcome::Ready(write_map(&mut spool, &data)?)),
                        Err(failure) => Ok(Outcome::Failed(map_failure(failure))),
                    })?
                } else { Outcome::Unselected };
                let grep = if !config.policy_path_exempt("check_grep", "", &relative) {
                    isolated(budget, |local| {
                        let mut outcome = None;
                        let mut encode_error = None;
                        let scan = dq_analyze::captured_raw_file::with_original_policy_file_prepared(
                            root, path, 0, local,
                            |scratch| {
                                let width = dq_analyze::captured_raw_file::analyze_raw_len(raw.as_slice())
                                    .map_err(|message| Failure::Operational(io::Error::other(message)))?
                                    .checked_mul(4).and_then(|n| n.checked_add(8192))
                                    .ok_or_else(|| Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
                                scratch.charge(width).map_err(|message| Failure::Operational(quota(message)))?;
                                Ok(crate::input_snapshot::normalize_recorded_policy_original(
                                    &RecordedSourceOriginal::Bytes(&raw)))
                            },
                            &mut |actual, views| {
                                if actual != relative { return Err("paired DMM relative spelling differs".into()); }
                                grep::with_source_file(views, &mut |source| {
                                    let data = grep::scan_static_file(scope.report_scope(), local,
                                        &crate::daemon::control::checkpoint, source)?;
                                    let start = spool.length();
                                    if let Err(first) = data.write_dmm_fragment(actual, &mut spool) {
                                        encode_error = Some(first);
                                        return Err(Failure::Operational(io::ErrorKind::Interrupted.into()));
                                    }
                                    outcome = Some(start..spool.length());
                                    Ok(())
                                })?;
                                Ok(true)
                            },
                        );
                        if let Some(first) = encode_error { return Err(first); }
                        Ok(match scan {
                            Ok(true) => Outcome::Ready(outcome.ok_or_else(|| invalid("paired DMM grep omitted file"))?),
                            Ok(false) => return Err(invalid("paired DMM grep file stopped")),
                            Err(first) => Outcome::Failed(first),
                        })
                    })?
                } else { Outcome::Unselected };
                fact_rows.push(FactRow { ordinal, fact: Observed { stamp: fact.stamp, content: fact.content } });
                entries.push(Entry { map, grep });
                drop((raw, raw_scope));
            }
            Ok(())
        })();
        let settled = inputs.snapshot.lock().map_err(|_| invalid("paired DMM recorder poisoned"))
            .and_then(|snapshot| snapshot.policy_closure_charge())
            .and_then(|bytes| lender.directory_metadata_settled(&metadata_owner, bytes));
        read_result?;
        if let Err(later) = settled {
            return Err(read_failure.map_or(later, |(_, first)| first));
        }
        let spool = match spool.seal() {
            Ok(spool) => spool,
            Err(later) => return Err(read_failure.map_or(later, |(_, first)| first)),
        };
        let facts = Arc::new(PairedDmmFacts { discovery, rows: fact_rows });
        Ok(Self { facts, recorder: Arc::clone(&inputs.source_issuer),
            queries: queries.native_query_owner_identity(), entries, map_order, read_failure, spool })
    }

    /// Run before attaching the attempt-local spool to the actual workspace.
    /// The ordinary full closure and subsequent live restat remain mandatory.
    pub(crate) fn require_recording<P: SnapshotProvider>(
        &self, inputs: &RecordingInputs<P>, discovery: &Arc<DiscoveryReceipt>, queries: &QueryDb,
    ) -> io::Result<()> {
        if !Arc::ptr_eq(&self.facts.discovery, discovery) || !Arc::ptr_eq(&self.recorder, &inputs.source_issuer)
            || !self.queries.matches(queries) {
            return Err(invalid("paired DMM belongs to another recorder, discovery or QueryDb"));
        }
        discovery.validate_recording(inputs)
    }

    pub(crate) fn retained_fixed_bytes(&self) -> usize {
        std::mem::size_of::<Self>()
            + self.entries.capacity() * std::mem::size_of::<Entry>()
            + std::mem::size_of::<PairedDmmFacts>() + 2 * std::mem::size_of::<usize>()
            + self.facts.rows.capacity() * std::mem::size_of::<FactRow>()
            + self.map_order.capacity() * std::mem::size_of::<usize>()
    }

    pub(crate) fn facts(&self) -> &Arc<PairedDmmFacts> { &self.facts }

    pub(crate) fn map_order(&self) -> &[usize] { &self.map_order }

    /// At the old main file-capture position only.
    pub(crate) fn require_capture_slot(&mut self, ordinal: usize, fact: Option<&FileInput>) -> io::Result<()> {
        if self.read_failure.as_ref().is_some_and(|(at, _)| *at == ordinal) {
            return Err(self.read_failure.take().unwrap().1);
        }
        let fact = fact.ok_or_else(|| invalid("paired DMM missing its actual recorded file fact"))?;
        self.facts.require(ordinal, fact)
    }

    fn entry(&mut self, ordinal: usize) -> io::Result<&mut Entry> {
        let slot = self.facts.slot(ordinal)?;
        self.entries.get_mut(slot).ok_or_else(|| invalid("paired DMM outcome slot differs"))
    }

    pub(crate) fn take_grep(
        &mut self, ordinal: usize, relative: &str, budget: &Budget,
    ) -> Result<grep::StaticFileData, Failure> {
        let path = self.facts.path(ordinal)?;
        budget.charge(path_charge(path, 4, 512)?).map_err(quota)?;
        let expected = dq_analyze::util::rel_slash(path, &self.facts.discovery.contract().root);
        if relative != expected { return Err("paired DMM grep relative path differs".into()); }
        let slot = &mut self.entry(ordinal)?.grep;
        let range = match slot {
            Outcome::Ready(range) => range.clone(),
            Outcome::Failed(_) => {
                let Outcome::Failed(first) = std::mem::replace(slot, Outcome::Consumed) else { unreachable!() };
                return Err(first);
            }
            _ => return Err("paired DMM grep frame not issued or already refused".into()),
        };
        Ok(self.spool.with_private_frame(range.start, range.end, |input|
            grep::StaticFileData::read_dmm_fragment(relative, input, budget, &crate::daemon::control::checkpoint))?)
    }

    pub(crate) fn replay_capture_error(&mut self, ordinal: usize) -> io::Result<()> {
        if self.read_failure.as_ref().is_some_and(|(at, _)| *at == ordinal) {
            return Err(self.read_failure.take().expect("matching recorded DMM failure").1);
        }
        Ok(())
    }

    pub(crate) fn require_map_outcome(&mut self, ordinal: usize, fact: &FileInput) -> io::Result<()> {
        self.facts.require(ordinal, fact)?;
        let slot = &mut self.entry(ordinal)?.map;
        match slot {
            Outcome::Ready(_) => Ok(()),
            Outcome::Failed(_) => {
                let Outcome::Failed(first) = std::mem::replace(slot, Outcome::Consumed) else { unreachable!() };
                Err(first)
            }
            _ => Err(invalid("paired MapEdits frame not issued")),
        }
    }

    pub(crate) fn take_map(
        &mut self, ordinal: usize, budget: &Arc<Budget>,
        mut visit: impl FnMut(&str, &str, usize) -> io::Result<()>,
    ) -> io::Result<()> {
        let slot = &mut self.entry(ordinal)?.map;
        let range = match slot {
            Outcome::Ready(range) => range.clone(),
            Outcome::Failed(_) => {
                let Outcome::Failed(first) = std::mem::replace(slot, Outcome::Consumed) else { unreachable!() };
                return Err(first);
            }
            _ => return Err(invalid("paired MapEdits frame not issued or already refused")),
        };
        self.spool.with_private_frame(range.start, range.end, |input| {
                let rows = u32::from_le_bytes(take(input)?) as usize;
                for _ in 0..rows {
                    crate::daemon::control::checkpoint()?;
                    let scratch = Budget::scoped_temporaries(budget).map_err(quota)?;
                    let ty = read_text(input, &scratch)?;
                    let field = read_text(input, &scratch)?;
                    let line = usize::try_from(u64::from_le_bytes(take(input)?))
                        .ok().filter(|line| *line != 0).ok_or_else(|| invalid("paired DMM line differs"))?;
                    visit(&ty, &field, line)?;
                }
                Ok(())
            })
    }
}

fn isolated<T>(budget: &Arc<Budget>, work: impl FnOnce(&Arc<Budget>) -> io::Result<T>) -> io::Result<T> {
    let window = Budget::reserve_window(budget, budget.remaining()).map_err(quota)?;
    let local = Budget::new(window.capacity()).map_err(quota)?;
    work(&local)
}
fn exact_vec<T>(n: usize) -> io::Result<Vec<T>> {
    if n == 0 { return Ok(Vec::new()); }
    let layout = std::alloc::Layout::array::<T>(n).map_err(|_| io::ErrorKind::OutOfMemory)?;
    assert_ne!(layout.size(), 0);
    // SAFETY: exact pre-funded Global layout, empty until caller initializes.
    let ptr = std::ptr::NonNull::new(unsafe { std::alloc::alloc(layout) }.cast::<T>())
        .ok_or(io::ErrorKind::OutOfMemory)?;
    Ok(unsafe { Vec::from_raw_parts(ptr.as_ptr(), 0, n) })
}
fn take<const N: usize>(input: &mut dyn Read) -> io::Result<[u8; N]> {
    let mut bytes = [0; N];
    input.read_exact(&mut bytes)?;
    Ok(bytes)
}
fn text(out: &mut Stage, value: &str) -> io::Result<()> {
    out.write_all(&u32::try_from(value.len()).map_err(|_| invalid("paired DMM string exceeds width"))?.to_le_bytes())?;
    out.write_all(value.as_bytes())
}
fn read_text(input: &mut dyn Read, budget: &Budget) -> io::Result<String> {
    let n = u32::from_le_bytes(take(input)?) as usize;
    budget.charge(n).map_err(quota)?;
    let mut bytes = exact_vec(n)?;
    bytes.resize(n, 0);
    input.read_exact(&mut bytes)?;
    String::from_utf8(bytes).map_err(|_| invalid("paired DMM spelling is not UTF-8"))
}
fn write_map(out: &mut Stage, data: &map_edits_policy::ParsedMap) -> io::Result<Range<u64>> {
    let start = out.length();
    out.write_all(&u32::try_from(data.edits().count()).map_err(|_| invalid("paired DMM row count exceeds width"))?.to_le_bytes())?;
    for (ty, field, line) in data.edits() {
        text(out, ty)?;
        text(out, field)?;
        out.write_all(&u64::try_from(line).map_err(|_| invalid("paired DMM line exceeds width"))?.to_le_bytes())?;
    }
    Ok(start..out.length())
}


#[cfg(test)]
mod tests {
    use super::*;
    use crate::policy_request::{AnalysisContext, PolicyInputRequest, WorkspaceAuxiliaryQuestion as Q, WorkspacePolicyRequest};
    use std::sync::Mutex;

    #[derive(Default)]
    struct CountingFiles {
        dmm_reads: Mutex<BTreeMap<PathBuf, usize>>,
    }

    impl CountingFiles {
        fn count(&self, path: &Path) {
            if path.extension().is_some_and(|ext| ext == "dmm") {
                *self.dmm_reads.lock().unwrap().entry(path.to_owned()).or_default() += 1;
            }
        }
    }

    impl SnapshotProvider for CountingFiles {
        fn stamp(&self, path: &Path) -> io::Result<Stamp> { FileSystemInputs.stamp(path) }
        fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
            self.count(path);
            FileSystemInputs.read(path)
        }
        fn list(&self, folder: &Path) -> io::Result<FolderListing> { FileSystemInputs.list(folder) }
        fn read_policy_bounded(&self, path: &Path, limit: usize) -> io::Result<Option<CapturedInputRead>> {
            self.count(path);
            FileSystemInputs.read_policy_bounded(path, limit)
        }
        fn read_policy_bounded_admitted(
            &self, path: &Path, limit: usize, before: &mut dyn FnMut(usize) -> io::Result<()>,
        ) -> io::Result<Option<CapturedInputRead>> {
            self.count(path);
            FileSystemInputs.read_policy_bounded_admitted(path, limit, before)
        }
        fn read_original_open_admitted(
            &self, path: &Path, limit: usize, work: &dyn dm_preprocess::source_arena_credit::SourceArenaWork,
            after_open: &mut dyn FnMut() -> io::Result<dm_preprocess::OriginalRawOpenDecision>,
            before: &mut dyn FnMut(usize) -> io::Result<()>,
        ) -> io::Result<OriginalOpenedRead> {
            self.count(path);
            FileSystemInputs.read_original_open_admitted(path, limit, work, after_open, before)
        }
        fn policy_directory(&self, path: &Path, follow: bool, limit: usize)
            -> io::Result<Option<PolicyDirectoryListing>> {
            FileSystemInputs.policy_directory(path, follow, limit)
        }
    }

    #[derive(Default)]
    struct StageLender {
        before: Option<usize>,
        after: Option<usize>,
    }
    impl RecordedPolicySourceLender for StageLender {
        fn prepare_source(&mut self) -> io::Result<()> { panic!("paired DMM must use the ordinary bounded reader") }
        fn acquired(&mut self, _: &dm_preprocess::SourceAcquisitionLease) -> io::Result<()> {
            panic!("paired DMM must not issue compiled source")
        }
        fn prepare_directory_metadata(&mut self, _: &Arc<()>, bytes: usize) -> io::Result<()> {
            assert!(self.before.replace(bytes).is_none());
            Ok(())
        }
        fn directory_window_started(&mut self, _: &Arc<()>, _: usize) -> io::Result<()> {
            panic!("paired DMM must reuse the existing discovery")
        }
        fn directory_metadata_settled(&mut self, _: &Arc<()>, bytes: usize) -> io::Result<()> {
            assert!(self.after.replace(bytes).is_none());
            Ok(())
        }
    }

    #[test]
    fn paired_dmm_reads_once_for_actual_map_edits_and_check_grep() {
        let root = crate::test_scratch::dir("paired-actual-dmm");
        for folder in ["code", "maps/palettes", "interface", "modular_chomp", "doc/rewrite", "tgui", "tools/ci"] {
            std::fs::create_dir_all(root.join(folder)).unwrap();
        }
        std::fs::write(root.join("code/probe.dm"), "/datum/probe\n    var/value\n").unwrap();
        std::fs::write(root.join("tools/ci/lint_scopes.toml"), "").unwrap();
        let map = root.join("maps/active.dmm");
        let palette = root.join("maps/palettes/ignored-by-map-edits.dmm");
        std::fs::write(&map, "/obj/probe{\nstep_x = 2\n}\n/obj/probe{step_x = 3}\n").unwrap();
        std::fs::write(&palette, "/obj/probe{\nstep_y = 1\n}\n").unwrap();
        let request = PolicyInputRequest {
            analysis_context: Some(AnalysisContext::OriginalAnalyze0290),
            workspace: Some(WorkspacePolicyRequest {
                root: root.clone(),
                recursive_roots: Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY).unwrap()
                    .iter().map(|name| root.join(name)).collect(),
                configuration: root.join("tools/ci/lint_scopes.toml"),
            }),
            workspace_auxiliary: Q::PRIVATE_FULL_REGISTRY.to_vec(),
            ..Default::default()
        }.admit_private_authored_doc_ui().unwrap();
        let provider = CountingFiles::default();
        let inputs = RecordingInputs::new(&provider, 0)
            .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
        let queries = Arc::new(QueryDb::default());
        let derived = queries.prepare_derived_preflight(&inputs, &request).unwrap();
        assert!(provider.dmm_reads.lock().unwrap().is_empty());
        let discovery = derived.discovery();
        let budget = Budget::new(8 << 20).unwrap();
        let mut lender = StageLender::default();
        let mut staged = PairedDmmStage::stage(&inputs, &derived, &queries, &budget, &mut lender, &crate::test_scratch::dir("paired-dmm-spool")).unwrap();
        let map_fact = inputs.recorded_file_fact(&map).unwrap();
        let palette_fact = inputs.recorded_file_fact(&palette).unwrap();
        let ordinal = |fact: &FileInput| discovery.files().iter().position(|path| path == &fact.path).unwrap();
        let map_index = ordinal(&map_fact);
        let palette_index = ordinal(&palette_fact);
        assert!(lender.after.unwrap() >= lender.before.unwrap());
        staged.require_recording(&inputs, discovery, &queries).unwrap();
        let foreign = RecordingInputs::new(&provider, 0)
            .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
        assert_eq!(staged.require_recording(&foreign, discovery, &queries).unwrap_err().kind(),
            io::ErrorKind::InvalidData);
        staged.require_capture_slot(map_index, Some(&map_fact)).unwrap();
        staged.require_capture_slot(palette_index, Some(&palette_fact)).unwrap();
        assert_eq!(staged.map_order(), &[map_index]);
        let donor = Arc::clone(staged.facts());
        let original = inputs.snapshot().unwrap();
        assert!(donor.facts_in(&original));
        let mut changed_recording = original.clone();
        changed_recording.files.get_mut(&map_fact.path).unwrap().content ^= 1;
        assert!(!donor.facts_in(&changed_recording));
        changed_recording.files.remove(&map_fact.path);
        assert!(!donor.facts_in(&changed_recording));
        let mut rows = Vec::new();
        staged.take_map(map_index, &budget, |ty, field, line| {
            rows.push((ty.to_owned(), field.to_owned(), line));
            Ok(())
        }).unwrap();
        assert_eq!(rows, [("/obj/probe".to_owned(), "step_x".to_owned(), 2)]);
        for (index, fact) in [(map_index, &map_fact), (palette_index, &palette_fact)] {
            let relative = dq_analyze::util::rel_slash(&fact.path, &discovery.contract().root);
            let grep = staged.take_grep(index, &relative, &budget).unwrap();
            assert!(grep.run.sites.iter().any(|site| site.rule == "step_xy" && site.rel == relative));
            let warm = staged.take_grep(index, &relative, &budget).unwrap();
            assert_eq!(warm.run.sites, grep.run.sites);
            assert_eq!(warm.allow_used, grep.allow_used);
            assert!(warm.source_lines().eq(grep.source_lines()));
        }
        let counts = provider.dmm_reads.lock().unwrap();
        assert_eq!(counts.get(&map_fact.path), Some(&1));
        assert_eq!(counts.get(&palette_fact.path), Some(&1));
        assert_eq!(counts.len(), 2);
        drop(counts);

        std::fs::write(&map, "/obj/probe{\nstep_x = 9\n}\n/obj/probe{step_x = 3}\n").unwrap();
        let actual = FileSystemInputs.read_verified(&map).unwrap();
        let changed = FileInput { path: map_fact.path.clone(), stamp: actual.stamp().clone(), content: actual.content() };
        assert_ne!(changed.content, map_fact.content);
        assert_eq!(staged.require_capture_slot(map_index, Some(&changed)).unwrap_err().kind(),
            io::ErrorKind::InvalidData);
        drop(staged);
        assert!(donor.facts_in(&original));
    }
}
