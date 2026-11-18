//! Immutable aggregate in the SAME Db; no row-payload cache or public Arc escape.
use super::*;
use serde::ser::{SerializeMap, SerializeSeq};
use serde::{Deserialize, Serialize};
const ROOT_INPUT: Kind = Kind(15);
const ROOT_RESULT: Kind = Kind(16);
// Public request may retain the complete outer512KiB wire buffer plus its
// fixed-schema parsed representation. This is accounting, not an RSS claim.
pub(super) const REPORT_RESERVE: usize = 4 * 1024 * 1024;
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WorkspaceCursor {
    aggregate_id: String,
    offset: usize,
}
impl WorkspaceCursor {
    pub fn offset(&self) -> usize {
        self.offset
    }
    pub fn aggregate_id(&self) -> String {
        self.aggregate_id.clone()
    }
}
struct Manifest {
    graph: u64,
    capture: Weak<WorkspaceCapture>,
    names: Vec<&'static str>,
    pages: Vec<Weak<PageResult>>,
    scopes: Vec<Weak<Scope>>,
    id: u128,
    metadata_budget: usize,
}
#[derive(Clone)]
struct RootParams {
    input: Key,
}
struct Segment {
    page: usize,
    file: usize,
    lint: usize,
    kind: u8,
    first: usize,
    len: usize,
}
pub(super) struct Aggregate {
    graph: u64,
    capture: Weak<WorkspaceCapture>,
    names: Vec<&'static str>,
    pages: Vec<Arc<PageResult>>,
    scopes: Vec<Arc<Scope>>,
    segments: Vec<Segment>,
    total: usize,
    id: u128,
}
impl Aggregate {
    fn metadata(&self) -> usize {
        std::mem::size_of::<Self>()
            + 2 * std::mem::size_of::<usize>()
            + self.names.capacity() * std::mem::size_of::<&str>()
            + self.pages.capacity() * std::mem::size_of::<Arc<PageResult>>()
            + self.scopes.capacity() * std::mem::size_of::<Arc<Scope>>()
            + self.segments.capacity() * std::mem::size_of::<Segment>()
    }
    pub(super) fn visit(&self, owners: &mut Owners) {
        if owners.keys.contains_key(&(3, self as *const _ as usize)) {
            return;
        }
        owners.add(3, self as *const _ as usize, self.metadata());
        for scope in &self.scopes {owners.scope(scope);}
        for page in &self.pages {
            owners.page(page);
        }
    }
    fn same(&self, graph: u64, capture: &Arc<WorkspaceCapture>, names: &[&'static str]) -> bool {
        self.graph == graph
            && self.names == names
            && self.capture.strong_count() != 0
            && Weak::ptr_eq(&self.capture, &Arc::downgrade(capture))
    }
}
#[cfg(test)]
fn register(db: &Db) {
    register_with_admission(db, Arc::new(super::super::Admission::default()));
}
pub(super) fn register_with_admission(db: &Db, admission: Arc<super::super::Admission>) {
    db.define_input(ROOT_INPUT, "native-workspace-raw-aggregate-manifest");
    db.define(
        ROOT_RESULT,
        "native-workspace-raw-aggregate",
        move |ctx, params| {
            let params = params
                .downcast_ref::<RootParams>()
                .expect("workspace aggregate params");
            admission.abort.before_outcome(params.input)?;
            let manifest = ctx.input::<Manifest>(params.input)?;
            let result = aggregate_with_admission(&manifest, &admission).map(Arc::new);
            let bytes = result.as_ref().map_or_else(
                |e| super::super::result_error_charge::<Arc<Aggregate>>(e),
                |a| {
                    a.metadata()
                        + std::mem::size_of::<Result<Arc<Aggregate>, String>>()
                        + 2 * std::mem::size_of::<usize>()
                },
            );
            if bytes > manifest.metadata_budget {
                admission.denied.store(true, Ordering::Relaxed);
                return Err(QueryError::Missing(params.input));
            }
            let hash = result
                .as_ref()
                .map_or_else(|e| dm_query::hash_bytes(e.as_bytes()), |a| a.id);
            admission.abort.before_outcome(params.input)?;
            Ok(Outcome::new(result, hash, bytes))
        },
    );
}
#[cfg(test)]
fn aggregate(m: &Manifest) -> Result<Aggregate, String> {
    aggregate_with_admission(m, &super::super::Admission::default())
}
fn aggregate_with_admission(
    m: &Manifest,
    admission: &super::super::Admission,
) -> Result<Aggregate, String> {
    admission.abort.scan_checkpoint()?;
    let mut count = 0usize;
    for page in &m.pages {
        let page = page.upgrade().ok_or("aggregate page owner expired")?;
        for file in &page.files {
            for rows in &file.findings {
                count = count
                    .checked_add(usize::from(!rows.run.sites.is_empty()))
                    .and_then(|n| n.checked_add(usize::from(!rows.allow_used.is_empty())))
                    .and_then(|n| n.checked_add(usize::from(!rows.run.notes.is_empty())))
                    .ok_or("aggregate segment overflow")?;
            }
        }
    }
    let metadata = std::mem::size_of::<Aggregate>()
        + std::mem::size_of::<Result<Arc<Aggregate>, String>>()
        + 2 * std::mem::size_of::<usize>()
        + 2 * std::mem::size_of::<usize>()
        + m.pages.len() * std::mem::size_of::<Arc<PageResult>>()
        + m.names.len() * std::mem::size_of::<&str>()
        + m.scopes.len() * std::mem::size_of::<Arc<Scope>>()
        + count
            .checked_mul(std::mem::size_of::<Segment>())
            .ok_or("segment size overflow")?;
    if metadata > m.metadata_budget {
        return Err("aggregate metadata exceeds shared result headroom".into());
    }
    let mut pages = Vec::with_capacity(m.pages.len());
    for page in &m.pages {
        pages.push(page.upgrade().ok_or("aggregate page owner expired")?);
    }
    let mut scopes=Vec::with_capacity(m.scopes.len());
    for scope in &m.scopes {scopes.push(scope.upgrade().ok_or("captured report scope owner expired")?); }
    let mut segments = Vec::with_capacity(count);
    let mut total = 0usize;
    // Lint-major order, file order, then site/allow/note. Borrowing avoids
    // duplicating the complete result payload just to serialize one page.
    for lint in 0..m.names.len() {
        for (p, page) in pages.iter().enumerate() {
            for (f, file) in page.files.iter().enumerate() {
                let rows = &file.findings[lint];
                for (kind, len) in [
                    (0, rows.run.sites.len()),
                    (1, rows.allow_used.len()),
                    (2, rows.run.notes.len()),
                ] {
                    if len == 0 {
                        continue;
                    }
                    segments.push(Segment {
                        page: p,
                        file: f,
                        lint,
                        kind,
                        first: total,
                        len,
                    });
                    total = total.checked_add(len).ok_or("aggregate row overflow")?;
                }
            }
        }
    }
    admission.abort.scan_checkpoint()?;
    Ok(Aggregate {
        graph: m.graph,
        capture: m.capture.clone(),
        names: m.names.clone(),
        scopes,
        pages,
        segments,
        total,
        id: m.id,
    })
}
/// The reader and its views borrow an aggregate while the family gate is held.
/// Neither aggregate/page Arcs nor row payloads escape to unaccounted callers.
pub struct WorkspacePageReader<'a> {
    db: &'a QueryDb,
    inventory: Option<&'a ResourceInventory>,
    aggregate: &'a Aggregate,
    offset: usize,
    max: usize,
}
impl WorkspacePageReader<'_> {
    pub fn aggregate_id(&self) -> String {
        format!("{:032x}", self.aggregate.id)
    }
    pub fn total_items(&self) -> usize {
        self.aggregate.total
    }
    pub fn max_items(&self) -> usize {
        self.max
    }
    pub fn page(&self, count: usize) -> io::Result<WorkspacePageView<'_>> {
        if count > self.max || (count == 0 && self.offset < self.aggregate.total) {
            return Err(invalid("invalid workspace page item count"));
        }
        Ok(WorkspacePageView {
            aggregate: self.aggregate,
            offset: self.offset,
            count,
        })
    }
    pub fn require_output_admission(
        &self,
        encoded_bytes: usize,
        metadata_bound: usize,
    ) -> io::Result<()> {
        crate::daemon::control::checkpoint()?;
        let retained = match self.inventory {
            Some(inventory) => inventory.bytes(),
            None => self.db.workspace_owners_locked(&[])?.bytes,
        };
        let requested = encoded_bytes
            .checked_add(metadata_bound)
            .ok_or_else(|| invalid("wire admission overflow"))?;
        if requested > REPORT_RESERVE
            || retained
                .checked_add(requested)
                .and_then(|n| n.checked_add(self.db.raw_policy.charge.load(Ordering::Relaxed)))
                .is_none_or(|n| n > RESULT_BOUND)
        {
            return Err(invalid(
                "workspace wire result exceeds shared result-family headroom",
            ));
        }
        Ok(())
    }
}
pub struct WorkspacePageView<'a> {
    aggregate: &'a Aggregate,
    offset: usize,
    count: usize,
}
impl Serialize for WorkspacePageView<'_> {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut map = serializer.serialize_map(Some(7))?;
        let id = format!("{:032x}", self.aggregate.id);
        let next = self.offset + self.count;
        let cursor = (next < self.aggregate.total).then(|| WorkspaceCursor {
            aggregate_id: id.clone(),
            offset: next,
        });
        map.serialize_entry("aggregate_id", &id)?;
        map.serialize_entry("offset", &self.offset)?;
        map.serialize_entry("count", &self.count)?;
        map.serialize_entry("total_items", &self.aggregate.total)?;
        map.serialize_entry("next_cursor", &cursor)?;
        map.serialize_entry("items", &Items(self))?;
        map.serialize_entry("policy_scopes", &ScopeReports(self.aggregate))?;
        map.end()
    }
}
/// Borrowed exact interpreted projections from the captured policy, not hashes
/// or a reopen of mutable lint_scopes.toml at report time.
struct ScopeReports<'a>(&'a Aggregate);
impl Serialize for ScopeReports<'_>{
 fn serialize<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{
  let mut seq=serializer.serialize_seq(Some(self.0.names.len()))?;
  if self.0.scopes.len()!=self.0.names.len(){return Err(<S::Error as serde::ser::Error>::custom("captured configuration scope count mismatch"))}
  for(name,scope)in self.0.names.iter().zip(&self.0.scopes){
   let json=scope.report_scope_json().map_err(<S::Error as serde::ser::Error>::custom)?;
   seq.serialize_element(&(name,json))?;
  }
  seq.end()
 }
}
struct DigestHex<'a>(&'a [u8;20]);
impl Serialize for DigestHex<'_>{
 fn serialize<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{
  let mut hex=[0u8;40];const DIGITS:&[u8;16]=b"0123456789abcdef";
  for(i,byte)in self.0.iter().copied().enumerate(){hex[i*2]=DIGITS[(byte>>4)as usize];hex[i*2+1]=DIGITS[(byte&15)as usize];}
  let text=std::str::from_utf8(&hex).map_err(<S::Error as serde::ser::Error>::custom)?;
  serializer.serialize_str(text)
 }
}
struct Items<'a, 'b>(&'a WorkspacePageView<'b>);
impl Serialize for Items<'_, '_> {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let p = self.0;
        let a = p.aggregate;
        let mut seq = serializer.serialize_seq(Some(p.count))?;
        let mut position = p.offset;
        let mut segment = a.segments.partition_point(|s| s.first + s.len <= position);
        for _ in 0..p.count {
            let s = &a.segments[segment];
            seq.serialize_element(&Item {
                segment: s,
                aggregate: a,
                index: position - s.first,
            })?;
            position += 1;
            if position == s.first + s.len {
                segment += 1;
            }
        }
        seq.end()
    }
}
struct Item<'a> {
    segment: &'a Segment,
    aggregate: &'a Aggregate,
    index: usize,
}
impl Serialize for Item<'_> {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let s = self.segment;
        let rows = &self.aggregate.pages[s.page].files[s.file].findings[s.lint];
        let mut map = serializer.serialize_map(Some(if s.kind == 0 || s.kind == 1 { 4 } else { 3 }))?;
        map.serialize_entry("lint", self.aggregate.names[s.lint])?;
        match s.kind {
            0 => {
                map.serialize_entry("kind", "site")?;
                map.serialize_entry("site", &rows.run.sites[self.index])?;
                let text = rows.site_text(self.index).ok_or_else(||
                    <S::Error as serde::ser::Error>::custom("missing authenticated as-of report evidence"))?;
                map.serialize_entry("source_text", text)?;
            }
            1 => {
                map.serialize_entry("kind", "allow")?;
                map.serialize_entry("allow", &rows.allow_used[self.index])?;
                let digest=rows.allow_source_digest().ok_or_else(||<S::Error as serde::ser::Error>::custom("missing captured whole-file ALLOW digest"))?;
                map.serialize_entry("source_digest",&DigestHex(digest))?;
            }
            _ => {
                map.serialize_entry("kind", "note")?;
                map.serialize_entry("text", &rows.run.notes[self.index])?;
            }
        }
        map.end()
    }
}
impl QueryDb {
    /// Census includes aggregate-transitive page owners even if their page nodes
    /// were evicted. Conservative map-node metadata is preflighted in the shared
    /// input family before this census grows; address dedup is resource-only.
    pub(super) fn workspace_owners_locked(&self, held: &[Arc<PageResult>]) -> io::Result<Owners> {
        self.workspace_owners_with_fixed_locked(held, 0)
    }
    pub(super) fn workspace_owners_with_fixed_locked(
        &self,
        held: &[Arc<PageResult>],
        fixed: usize,
    ) -> io::Result<Owners> {
        let census_headroom = self.workspace_input_headroom_locked(fixed)?;
        let pages = self
            .raw_policy
            .workspace
            .pages
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let roots = self
            .raw_policy
            .workspace
            .roots
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let terminal = self.db.retained_value::<RawTerminalBody>(RAW_TERMINAL_KEY);
        let mut entries = usize::from(terminal.is_some());
        let page_entries = |p: &PageResult| {
            1 + p.scopes.len() + p.files.iter().map(|f| f.findings.len()).sum::<usize>()
        };
        for key in pages.keys() {
            if let Some(value) = self
                .db
                .retained_value::<Result<Arc<PageResult>, String>>(*key)
            {
                entries = entries.saturating_add(1);
                if let Ok(p) = value.as_ref() {
                    entries = entries.saturating_add(page_entries(p));
                }
            }
        }
        for key in roots.keys() {
            if let Some(value) = self
                .db
                .retained_value::<Result<Arc<Aggregate>, String>>(*key)
            {
                entries = entries.saturating_add(1);
                if let Ok(a) = value.as_ref() {
                    entries = entries.saturating_add(1+a.scopes.len());
                    for p in &a.pages {
                        entries = entries.saturating_add(page_entries(p));
                    }
                }
            }
        }
        for p in held {
            entries = entries.saturating_add(page_entries(p));
        }
        if entries
            .checked_mul(256)
            .and_then(|n| n.checked_add(4096))
            .is_none_or(|n| n > census_headroom)
        {
            return Err(invalid("census metadata exceeds shared input headroom"));
        }
        let mut owners = Owners::default();
        if let Some(terminal) = &terminal {
            owners.add(7, Arc::as_ptr(terminal) as usize, terminal.retained_bytes());
        }
        for key in pages.keys() {
            if let Some(value) = self
                .db
                .retained_value::<Result<Arc<PageResult>, String>>(*key)
            {
                owners.outcome(4, &value);
                if let Ok(p) = value.as_ref() {
                    owners.page(p);
                }
            }
        }
        for key in roots.keys() {
            if let Some(value) = self
                .db
                .retained_value::<Result<Arc<Aggregate>, String>>(*key)
            {
                owners.outcome(5, &value);
                if let Ok(a) = value.as_ref() {
                    a.visit(&mut owners);
                }
            }
        }
        for page in held {
            owners.page(page);
        }
        Ok(owners)
    }
    pub(crate) fn with_workspace_raw_page<R>(
        &self,
        capture: &Arc<WorkspaceCapture>,
        scope: &NativeReadGuard<'_>,
        names: &[String],
        cursor: Option<&WorkspaceCursor>,
        limit: usize,
        scans: Arc<AtomicUsize>,
        visitor: impl FnOnce(WorkspacePageReader<'_>) -> io::Result<R>,
    ) -> io::Result<R> {
        crate::daemon::control::checkpoint()?;
        capture.require_scope(scope)?;
        if !scope.uses_queries(self) {
            return Err(invalid("workspace pages require current compiler QueryDb"));
        }
        let ordered = captured_raw_file::ordered_names(names).map_err(invalid)?;
        if !(1..=512).contains(&limit) {
            return Err(invalid("workspace page limit must be1..512"));
        }
        let _gate = self
            .raw_policy
            .gate
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        self.raw_prune_locked(std::time::Instant::now());
        self.raw_policy.admission.abort.begin();
        self.raw_policy
            .admission
            .denied
            .store(false, Ordering::Relaxed);
        // A content hash is an index only. Exact capture/graph/names checked
        // below before exposing even an already-retained aggregate.
        let id = dm_query::hash_bytes(
            &serde_json::to_vec(&(self.id, capture.issuance(), &ordered)).map_err(invalid)?,
        );
        if cursor.is_some_and(|c| c.aggregate_id != format!("{:032x}", id)) {
            return Err(invalid("stale or foreign workspace cursor"));
        }
        let input = Key::new(ROOT_INPUT, id);
        let key = Key::new(ROOT_RESULT, id);
        let cached = self
            .db
            .retained_value::<Result<Arc<Aggregate>, String>>(key)
            .filter(|v| {
                v.as_ref()
                    .as_ref()
                    .is_ok_and(|a| a.same(self.id, capture, &ordered))
            });
        // Reclaim dead/incompatible cohorts BEFORE pinning the initial owners.
        // Otherwise a failed earlier cohort would consume the retry's budget.
        if cached.is_none() {
            self.workspace_prepare_query_locked(
                capture.root(),
                capture.configuration().0,
                &ordered,
            );
        }
        let inventory = self.workspace_resource_inventory_locked()?;
        let result = if let Some(cached) = cached {
            cached
        } else {
            let (pages,scopes) =
                self.build_workspace_pages_locked(capture, scope, names, scans, &inventory, false, None)?;
            let remaining = RESULT_BOUND
                .checked_sub(inventory.bytes())
                .and_then(|n| n.checked_sub(self.raw_policy.charge.load(Ordering::Relaxed)))
                .and_then(|n| n.checked_sub(REPORT_RESERVE))
                .ok_or_else(|| invalid("aggregate headroom exhausted"))?;
            self.workspace_input_headroom_locked(
                inventory.coordination_charge(2)?
                    + pages
                        .len()
                        .saturating_mul(std::mem::size_of::<Weak<PageResult>>())
                    + scopes.len().saturating_mul(std::mem::size_of::<Weak<Scope>>())
                    + scopes.len().saturating_mul(std::mem::size_of::<Scope>()+2*std::mem::size_of::<usize>())
                    + 4096,
            )?;
            inventory.require_pin_room()?;
            self.workspace_admit_root(input, key)?;
            static NEXT_ROOT: AtomicU64 = AtomicU64::new(1);
            let epoch = NEXT_ROOT
                .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_add(1))
                .map_err(|_| invalid("workspace aggregate issuance exhausted"))?;
            self.db.set_input(
                input,
                Manifest {
                    graph: self.id,
                    capture: Arc::downgrade(capture),
                    names: ordered.clone(),
                    pages: pages.iter().map(Arc::downgrade).collect(),
                    scopes: scopes.iter().map(Arc::downgrade).collect(),
                    id,
                    metadata_budget: remaining,
                },
                u128::from(epoch),
            );
            self.raw_policy
                .workspace
                .roots
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .insert(key, (input, std::time::Instant::now()));
            self.db
                .get::<Result<Arc<Aggregate>, String>>(key, Arc::new(RootParams { input }))
                .map_err(|e| self.derived_query_error("workspace aggregate query", e))?
        };
        let aggregate = match result.as_ref().as_ref() {
            Ok(a) => a,
            Err(e) => {
                self.raw_policy
                    .workspace
                    .roots
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .remove(&key);
                self.db.remove(input);
                self.db.remove(key);
                return Err(invalid(e.clone()));
            }
        };
        inventory.add_aggregate(&result)?;
        capture.require_scope(scope)?;
        if !aggregate.same(self.id, capture, &ordered) {
            return Err(invalid("workspace aggregate capture identity mismatch"));
        }
        let offset = match cursor {
            Some(c)
                if c.aggregate_id == format!("{:032x}", aggregate.id)
                    && c.offset <= aggregate.total =>
            {
                c.offset
            }
            Some(_) => return Err(invalid("stale or foreign workspace cursor")),
            None => 0,
        };
        let value = visitor(WorkspacePageReader {
            db: self,
            inventory: Some(&inventory),
            aggregate,
            offset,
            max: limit.min(aggregate.total - offset),
        })?;
        crate::daemon::control::checkpoint()?;
        capture.require_scope(scope)?;
        Ok(value)
    }
    fn workspace_admit_root(&self, input: Key, result: Key) -> io::Result<()> {
        let raw = self
            .raw_policy
            .admission.leases
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .len();
        let pages = self
            .raw_policy
            .workspace
            .pages
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .len()
            * 2;
        let mut roots = self
            .raw_policy
            .workspace
            .roots
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        while raw
            .saturating_add(pages)
            .saturating_add(self.bulk_raw_terminal_nodes_locked())
            .saturating_add(roots.len() * 2)
            .saturating_add(if roots.contains_key(&result) { 0 } else { 2 })
            > NODE_BOUND
        {
            let old = roots
                .iter()
                .filter(|(k, _)| **k != result)
                .min_by_key(|(_, (_, t))| *t)
                .map(|(k, _)| *k)
                .ok_or_else(|| invalid("workspace aggregate exceeds shared node bound"))?;
            if let Some((input, _)) = roots.remove(&old) {
                self.db.remove(input);
                self.db.remove(old);
            }
        }
        roots.insert(result, (input, std::time::Instant::now()));
        Ok(())
    }
    pub(super) fn workspace_manifest_charge_locked(&self) -> usize {
        let roots = self
            .raw_policy
            .workspace
            .roots
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        roots.values().fold(0usize, |n, (key, _)| {
            n.saturating_add(self.db.input::<Manifest>(*key).map_or(0, |m| {
                std::mem::size_of::<Manifest>()
                    + m.pages.capacity() * std::mem::size_of::<Weak<PageResult>>()
                    + m.scopes.capacity() * std::mem::size_of::<Weak<Scope>>()
                    // Fixed worst-case backing retained by initialized Weak
                    // entries, even after their strong payload was evicted.
                    // Deliberately conservative alongside live-owner census.
                    + m.scopes.len() * (std::mem::size_of::<Scope>()+2*std::mem::size_of::<usize>())
                    + m.names.capacity() * std::mem::size_of::<&str>()
                    + 128
            }))
        })
    }
    /// Called only on a public aggregate miss, before any current page borrow.
    /// Old aggregates can retain evicted page values transitively. Drop those
    /// roots, but preserve page contributions with the exact reusable policy
    /// coordinates. Incompatible partial queries cannot poison a split-lint
    /// retry's shared budget, and compatible source/scope reuse still works.
    pub(super) fn workspace_prepare_query_locked(
        &self,
        root: &std::path::Path,
        configuration: &std::path::Path,
        names: &[&'static str],
    ) {
        self.workspace_roots_clear_locked();
        let mut pages = self
            .raw_policy
            .workspace
            .pages
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        pages.retain(|result, (input, _, _)| {
            let reusable = self
                .db
                .retained_value::<Result<Arc<PageResult>, String>>(*result)
                .is_some_and(|value| {
                    value.as_ref().as_ref().is_ok_and(|p| {
                        p.graph == self.id
                            && p.root == root
                            && p.configuration == configuration
                            && p.names == names
                    })
                });
            if reusable {
                return true;
            }
            self.db.remove(*input);
            self.db.remove(*result);
            false
        });
    }
    pub(super) fn workspace_roots_clear_locked(&self) {
        let mut roots = self
            .raw_policy
            .workspace
            .roots
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        for (result, (input, _)) in roots.iter() {
            self.db.remove(*result);
            self.db.remove(*input);
        }
        roots.clear();
    }
    pub(super) fn workspace_roots_prune_locked(&self, now: std::time::Instant) {
        let mut roots = self
            .raw_policy
            .workspace
            .roots
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        roots.retain(|result, (input, time)| {
            let dead = self
                .db
                .input::<Manifest>(*input)
                .map(|m| m.capture.strong_count() == 0)
                .unwrap_or_else(|| {
                    self.db
                        .retained_value::<Result<Arc<Aggregate>, String>>(*result)
                        .is_none_or(|v| {
                            v.as_ref()
                                .as_ref()
                                .map_or(true, |a| a.capture.strong_count() == 0)
                        })
                });
            if !dead && now.saturating_duration_since(*time) <= std::time::Duration::from_secs(300)
            {
                return true;
            }
            self.db.remove(*input);
            self.db.remove(*result);
            false
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture() -> Arc<PageResult> {
        let root = std::env::current_dir().unwrap().join("aggregate-fixture");
        let scope = Arc::new(
            Config::capture(Configuration::ProvenMissing)
                .unwrap()
                .scope("scheduler")
                .unwrap(),
        );
        let findings = Arc::new(
            File::capture(
                &root,
                &root.join("code/a.dm"),
                "/proc/p()\n    sleep(1)\n    sleep(2)\n".to_owned().into(),
            )
            .unwrap()
            .scan(&scope)
            .unwrap(),
        );
        assert_eq!(findings.run.sites.len(), 2);
        Arc::new(PageResult { scoped_patterns:false,
            graph: 1,
            root: root.clone(),
            configuration: root.join("scopes.toml"),
            names: vec!["scheduler"],
            scopes: vec![scope],
            files: vec![Contribution {
                path: root.join("code/a.dm"),
                proof: SourceProof::Owned(dm_resources::WeakSharedBytes::default()),
                findings: vec![findings],
            }],
            charge: 4096,
        })
    }
    fn manifest(page: &Arc<PageResult>) -> Manifest {
        Manifest {
            graph: 1,
            capture: Weak::new(),
            names: vec!["scheduler"],
            pages: vec![Arc::downgrade(page)],
            scopes: page.scopes.iter().map(Arc::downgrade).collect(),
            id: 7,
            metadata_budget: RESULT_BOUND,
        }
    }

mod empty_scope_report_tests{
 use super::*;
 #[test]fn zero_file_aggregate_retains_actual_captured_scope_and_counts_it_once_until_drop(){
  let config=Config::capture(Configuration::Captured(b"[lint.scheduler.ceilings]\nscheduler=7\n[lint.scheduler.lists]\nextra=['first','second']\n")).unwrap();
  let scope=Arc::new(config.scope("scheduler").unwrap());let weak=Arc::downgrade(&scope);
  let manifest=Manifest{graph:1,capture:Weak::new(),names:vec!["scheduler"],pages:vec![],scopes:vec![weak.clone()],id:9,metadata_budget:RESULT_BOUND};
  let aggregate=aggregate(&manifest).unwrap();drop(scope);drop(config);assert!(weak.upgrade().is_some());
  let view=WorkspacePageView{aggregate:&aggregate,offset:0,count:0};let wire=serde_json::to_value(&view).unwrap();
  assert_eq!(wire["count"],0);assert_eq!(wire["items"],serde_json::json!([]));assert_eq!(wire["policy_scopes"][0][0],"scheduler");
  let interpreted:serde_json::Value=serde_json::from_str(wire["policy_scopes"][0][1].as_str().unwrap()).unwrap();assert_eq!(interpreted[5]["scheduler"],7);assert_eq!(interpreted[3]["extra"],serde_json::json!(["first","second"]));
  let mut owners=Owners::default();aggregate.visit(&mut owners);let first=owners.bytes;assert!(first>=aggregate.metadata()+aggregate.scopes[0].budget_charge());aggregate.visit(&mut owners);assert_eq!(owners.bytes,first);
  drop(aggregate);assert!(weak.upgrade().is_none());assert!(aggregate_with_admission(&manifest,&crate::query_db::raw_policy::Admission::default()).is_err());
 }
 #[test]fn scope_report_budget_and_digest_encoding_never_require_a_source_reopen(){
  let page=fixture();let mut manifest=manifest(&page);manifest.metadata_budget=0;assert!(aggregate(&manifest).is_err());
  let bytes:[u8;20]=[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,255];assert_eq!(serde_json::to_string(&DigestHex(&bytes)).unwrap(),"\"000102030405060708090a0b0c0d0e0f101112ff\"");
 }
}

    #[test]fn root_params_keep_exact_scope_vector_and_conservative_weak_backing_charge_after_eviction(){
        let queries=QueryDb::default();let input=Key::new(ROOT_INPUT,1007);let result=Key::new(ROOT_RESULT,1007);
        let scope=Arc::new(Config::capture(Configuration::ProvenMissing).unwrap().scope("scheduler").unwrap());
        let observed=Arc::downgrade(&scope);
        let manifest=Manifest{graph:queries.id,capture:Weak::new(),names:vec!["scheduler"],pages:Vec::new(),scopes:vec![observed.clone()],id:1007,metadata_budget:RESULT_BOUND};
        let expected=std::mem::size_of::<Manifest>()+manifest.pages.capacity()*std::mem::size_of::<Weak<PageResult>>()+manifest.names.capacity()*std::mem::size_of::<&str>()+manifest.scopes.capacity()*std::mem::size_of::<Weak<Scope>>()+manifest.scopes.len()*(std::mem::size_of::<Scope>()+2*std::mem::size_of::<usize>())+128;
        queries.db.set_input(input,manifest,1);queries.raw_policy.workspace.roots.lock().unwrap().insert(result,(input,std::time::Instant::now()));
        assert_eq!(queries.workspace_manifest_charge_locked(),expected);drop(scope);assert!(observed.upgrade().is_none());
        assert_eq!(queries.workspace_manifest_charge_locked(),expected,"fixed reservation must not disappear while the manifest retains an expired Weak backing");
        drop(observed);queries.workspace_roots_clear_locked();assert_eq!(queries.workspace_manifest_charge_locked(),0);assert!(queries.db.input::<Manifest>(input).is_none());
    }
    #[test]
    fn borrowed_pages_serialize_exact_rows_without_cloning_payload() {
        let page = fixture();
        let a = aggregate(&manifest(&page)).unwrap();
        assert!(Arc::ptr_eq(&a.pages[0], &page));
        let db = QueryDb::default();
        let reader = WorkspacePageReader {
            db: &db,
            inventory: None,
            aggregate: &a,
            offset: 0,
            max: 1,
        };
        let first = serde_json::to_value(reader.page(1).unwrap()).unwrap();
        assert_eq!(first["offset"], 0);
        assert_eq!(first["count"], 1);
        assert_eq!(first["total_items"], 2);
        assert_eq!(first["items"][0]["lint"], "scheduler");
        assert_eq!(first["items"][0]["kind"], "site");
        assert_eq!(first["items"][0]["source_text"], "sleep(1)");
        assert_eq!(
            first["items"][0]["site"],
            serde_json::to_value(&page.files[0].findings[0].run.sites[0]).unwrap()
        );
        let cursor: WorkspaceCursor = serde_json::from_value(first["next_cursor"].clone()).unwrap();
        assert_eq!(cursor.offset(), 1);
        assert_eq!(cursor.aggregate_id(), "00000000000000000000000000000007");
        let last = WorkspacePageReader {
            db: &db,
            inventory: None,
            aggregate: &a,
            offset: cursor.offset(),
            max: 1,
        };
        let last = serde_json::to_value(last.page(1).unwrap()).unwrap();
        assert!(last["next_cursor"].is_null());
        assert_eq!(
            last["items"][0]["site"],
            serde_json::to_value(&page.files[0].findings[0].run.sites[1]).unwrap()
        );
        assert!(reader.page(0).is_err());
        assert!(reader.page(2).is_err());
    }
    #[test]
    fn aggregate_metadata_and_expired_weak_manifest_fail_before_payload_publication() {
        let page = fixture();
        let mut m = manifest(&page);
        m.metadata_budget = 1;
        assert!(aggregate(&m).is_err());
        m.metadata_budget = RESULT_BOUND;
        drop(page);
        assert!(aggregate(&m).is_err());
    }
    #[test]
    fn resource_census_deduplicates_scope_rows_pages_and_transitive_aggregate_owners() {
        let page = fixture();
        let mut a = aggregate(&manifest(&page)).unwrap();
        let mut owners = Owners::default();
        owners.page(&page);
        let single = owners.bytes;
        owners.page(&page);
        assert_eq!(owners.bytes, single);
        a.visit(&mut owners);
        let both = owners.bytes;
        assert_eq!(both, single + a.metadata());
        a.visit(&mut owners);
        assert_eq!(owners.bytes, both);
        // Aggregate alone continues charging the exact page/Scope/Findings
        // owners after the caller or a page-node value stops retaining them.
        drop(page);
        let mut retained = Owners::default();
        a.visit(&mut retained);
        assert_eq!(retained.bytes, both);
        a.pages.clear();
        let mut cleared = Owners::default();
        a.visit(&mut cleared);
        assert!(cleared.bytes < both);
    }
    #[test]
    fn same_db_aggregate_query_reuses_exact_page_owner_without_scans() {
        let db = Db::new();
        register(&db);
        let page = fixture();
        let input = Key::new(ROOT_INPUT, 17);
        let result = Key::new(ROOT_RESULT, 17);
        db.set_input(input, manifest(&page), 1);
        let one = db
            .get::<Result<Arc<Aggregate>, String>>(result, Arc::new(RootParams { input }))
            .unwrap();
        let two = db
            .get::<Result<Arc<Aggregate>, String>>(result, Arc::new(RootParams { input }))
            .unwrap();
        let one = one.as_ref().as_ref().unwrap();
        let two = two.as_ref().as_ref().unwrap();
        assert!(Arc::ptr_eq(one, two));
        assert!(Arc::ptr_eq(&one.pages[0], &page));
    }
    #[test]
    fn output_admission_rejects_oversized_single_record_budget_without_clean_page() {
        let page = fixture();
        let a = aggregate(&manifest(&page)).unwrap();
        let db = QueryDb::default();
        let reader = WorkspacePageReader {
            db: &db,
            inventory: None,
            aggregate: &a,
            offset: 0,
            max: 1,
        };
        assert!(reader.require_output_admission(1, REPORT_RESERVE).is_err());
        assert!(reader.require_output_admission(1, 512 * 1024).is_ok());
    }
    #[test]
    fn dead_capture_root_is_evicted_immediately_not_after_age_timeout() {
        let q = QueryDb::default();
        let page = fixture();
        let input = Key::new(ROOT_INPUT, 901);
        let result = Key::new(ROOT_RESULT, 901);
        q.db.set_input(input, manifest(&page), 1);
        let value =
            q.db.get::<Result<Arc<Aggregate>, String>>(result, Arc::new(RootParams { input }))
                .unwrap();
        assert!(value.is_ok());
        drop(value);
        q.raw_policy
            .workspace
            .roots
            .lock()
            .unwrap()
            .insert(result, (input, std::time::Instant::now()));
        q.workspace_roots_prune_locked(std::time::Instant::now());
        assert!(!q
            .raw_policy
            .workspace
            .roots
            .lock()
            .unwrap()
            .contains_key(&result));
        assert!(q.db.input::<Manifest>(input).is_none());
        assert!(q
            .db
            .retained_value::<Result<Arc<Aggregate>, String>>(result)
            .is_none());
    }
    #[test]
    fn cached_aggregate_error_has_actual_result_arc_and_string_capacity_charge() {
        let q = QueryDb::default();
        let input = Key::new(ROOT_INPUT, 996);
        let result = Key::new(ROOT_RESULT, 996);
        let mut m = Manifest {
            graph: q.id,
            capture: Weak::new(),
            names: vec!["scheduler"],
            pages: vec![Weak::new()],
            scopes: Vec::new(),
            id: 996,
            metadata_budget: RESULT_BOUND,
        };
        q.db.set_input(input, m, 1);
        let value =
            q.db.get::<Result<Arc<Aggregate>, String>>(result, Arc::new(RootParams { input }))
                .unwrap();
        let error = value.as_ref().as_ref().err().unwrap();
        let expected = super::super::super::result_error_charge::<Arc<Aggregate>>(error);
        q.raw_policy
            .workspace
            .roots
            .lock()
            .unwrap()
            .insert(result, (input, std::time::Instant::now()));
        assert_eq!(q.workspace_owners_locked(&[]).unwrap().bytes, expected);
        assert_eq!(q.db.value_bytes_at(result), expected);
        assert_eq!(
            q.raw_policy.charge.load(Ordering::Relaxed),
            0,
            "workspace must not also enter regular raw global counter"
        );
        drop(value);
        q.workspace_roots_clear_locked();
        m = Manifest {
            graph: q.id,
            capture: Weak::new(),
            names: vec!["scheduler"],
            pages: vec![Weak::new()],
            scopes: Vec::new(),
            id: 996,
            metadata_budget: 0,
        };
        q.db.set_input(input, m, 2);
        assert!(q
            .db
            .get::<Result<Arc<Aggregate>, String>>(result, Arc::new(RootParams { input }))
            .is_err());
        assert!(q
            .db
            .retained_value::<Result<Arc<Aggregate>, String>>(result)
            .is_none());
    }
    #[test]
    fn aggregate_cancellation_after_segment_build_retries_unchanged_manifest() {
        let q = QueryDb::default();
        let page = fixture();
        let m = manifest(&page);
        let input = Key::new(ROOT_INPUT, 1189);
        let result = Key::new(ROOT_RESULT, 1189);
        q.db.set_input(input, m, 1);
        let revision = q.db.revision();
        let token = crate::daemon::control::Cancellation::default();
        q.raw_policy.admission.abort.begin();
        q.raw_policy
            .admission
            .abort
            .cancel_on_poll(3, token.clone());
        let binding = crate::daemon::control::bind_with_deadline(
            token,
            std::time::Instant::now() + std::time::Duration::from_secs(60),
        );
        let failure =
            q.db.get::<Result<Arc<Aggregate>, String>>(result, Arc::new(RootParams { input }))
                .err()
                .expect("mid-aggregate cancellation");
        let error = q.derived_query_error("workspace aggregate", failure);
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
        assert!(q
            .db
            .retained_value::<Result<Arc<Aggregate>, String>>(result)
            .is_none());
        drop(binding);
        q.raw_policy.admission.abort.disarm();
        q.raw_policy.admission.abort.begin();
        let value =
            q.db.get::<Result<Arc<Aggregate>, String>>(result, Arc::new(RootParams { input }))
                .unwrap();
        let aggregate = value.as_ref().as_ref().unwrap();
        assert_eq!(aggregate.total, 2);
        assert_eq!(revision, q.db.revision());
    }
}
