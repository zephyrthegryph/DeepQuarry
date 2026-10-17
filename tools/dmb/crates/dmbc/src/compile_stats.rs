//! Real-world compile statistics: for every compile the daemon serves, one record of whether a retained session was
//! used (hit) or not (miss, and why), which path ran (unchanged, body patch or full compile), wall time and peak memory.
//!
//! Records are appended as JSON lines to `<daemon state dir>/compile-stats.jsonl` (rotated at 2 MiB to `.1`), summarised
//! on the daemon's lifecycle log as one line per compile, and `dmbc --daemon-stats` prints the totals. The request thread
//! calls the `note_*` functions at the points where the path is decided; the daemon wraps the request with
//! [`begin`] / [`finish`]. Notes live in a thread local: one request runs on one thread.
use serde::{Deserialize, Serialize};
use std::{
    cell::RefCell,
    collections::BTreeMap,
    io::Write,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

const ROTATE_BYTES: u64 = 2 << 20;
const REASON_LIMIT: usize = 160;

/// Which compile path produced the output.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PathTaken {
    /// Retained session proved the published pair current; nothing compiled.
    Hit,
    /// Body patch of the retained base.
    Patch,
    /// Full native compilation (possibly using disk memos).
    Full,
    /// The request failed.
    Failed,
}
impl PathTaken {
    pub fn name(self) -> &'static str {
        match self {
            PathTaken::Hit => "hit",
            PathTaken::Patch => "patch",
            PathTaken::Full => "full",
            PathTaken::Failed => "failed",
        }
    }
}

/// What the daemon knew about the session when the request arrived.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct SessionState {
    /// True when a retained session with state was present and usable.
    pub hot: bool,
    /// Why not, when `hot` is false: `no-session`, `variant-mismatch`, `evicted:<why>`, `degraded-tier-N`, `no-retained-state`.
    pub miss: Option<String>,
    /// Retained sessions in the daemon when the request arrived.
    pub sessions: usize,
}

#[derive(Debug, Default)]
struct Notes {
    path: Option<PathTaken>,
    reason: Option<String>,
    changed_bodies: Option<usize>,
}
thread_local! {
    static NOTES: RefCell<Notes> = RefCell::new(Notes::default());
}

/// Start a request: forget the previous request's notes.
pub fn begin() {
    NOTES.with(|notes| *notes.borrow_mut() = Notes::default());
}
/// The retained session proved the published output current.
pub fn note_hit() {
    NOTES.with(|notes| notes.borrow_mut().path = Some(PathTaken::Hit));
}
/// A body patch of the retained base produced the output.
pub fn note_patch(changed_bodies: usize) {
    NOTES.with(|notes| {
        let mut notes = notes.borrow_mut();
        notes.path = Some(PathTaken::Patch);
        notes.changed_bodies = Some(changed_bodies);
        notes.reason = None;
    });
}
/// The patch path was not taken (or declined); the full compilation runs. `reason` says why, in the compiler's words.
pub fn note_full(reason: impl Into<String>) {
    NOTES.with(|notes| {
        let mut notes = notes.borrow_mut();
        notes.path = Some(PathTaken::Full);
        let mut reason = reason.into();
        reason.truncate(reason.char_indices().nth(REASON_LIMIT).map_or(reason.len(), |(index, _)| index));
        notes.reason = Some(reason);
    });
}

/// One compile, as stored and summarised.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Record {
    pub at_ms: u64,
    pub project: String,
    pub variant: String,
    pub workers: usize,
    pub session: SessionState,
    pub path: PathTaken,
    pub reason: Option<String>,
    pub changed_bodies: Option<usize>,
    pub seconds: f64,
    pub private_before: Option<u64>,
    pub private_after: Option<u64>,
    /// Highest private bytes sampled while the request ran (sampled every 100 ms; transient spikes between samples are missed).
    pub peak_private: Option<u64>,
    pub error: Option<String>,
}

/// Build the record from the notes of the request that just ran. `private` is (before, after, peak).
pub fn finish(
    project: &Path,
    variant: String,
    workers: usize,
    session: SessionState,
    seconds: f64,
    private: (Option<u64>, Option<u64>, Option<u64>),
    error: Option<String>,
) -> Record {
    let notes = NOTES.with(|notes| std::mem::take(&mut *notes.borrow_mut()));
    let path = if error.is_some() { PathTaken::Failed } else { notes.path.unwrap_or(PathTaken::Full) };
    let mut reason = notes.reason;
    if path == PathTaken::Full && reason.is_none() && !session.hot {
        reason = session.miss.clone();
    }
    Record {
        at_ms: SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as u64),
        project: project.display().to_string(),
        variant,
        workers,
        session,
        path,
        reason,
        changed_bodies: notes.changed_bodies,
        seconds,
        private_before: private.0,
        private_after: private.1,
        peak_private: private.2,
        error,
    }
}

impl Record {
    /// The one-line summary written to the lifecycle log and shown to the client.
    pub fn line(&self) -> String {
        let gb = |bytes: Option<u64>| bytes.map_or("?".to_string(), |b| format!("{:.2}GB", b as f64 / 1e9));
        format!(
            "native compile: {} session={}{} wall={:.2}s workers={} peak={} private={}->{} sessions={} variant={} project={}{}",
            self.path.name(),
            if self.session.hot { "hit" } else { "miss" },
            self.session.miss.as_deref().map_or(String::new(), |why| format!("({why})")),
            self.seconds,
            self.workers,
            gb(self.peak_private),
            gb(self.private_before),
            gb(self.private_after),
            self.session.sessions,
            self.variant,
            self.project,
            self.reason.as_deref().map_or(String::new(), |why| format!(" reason=\"{why}\"")),
        )
    }
}

pub fn stats_path(dir: &Path) -> PathBuf {
    dir.join("compile-stats.jsonl")
}

/// Append `record` to the stats file under `dir`, rotating it first when it is over [`ROTATE_BYTES`]. Never fails the compile.
pub fn append(dir: &Path, record: &Record) {
    let path = stats_path(dir);
    let result = (|| -> std::io::Result<()> {
        std::fs::create_dir_all(dir)?;
        if std::fs::metadata(&path).is_ok_and(|meta| meta.len() > ROTATE_BYTES) {
            let _ = std::fs::rename(&path, dir.join("compile-stats.jsonl.1"));
        }
        let mut line = serde_json::to_string(record).map_err(std::io::Error::other)?;
        line.push('\n');
        std::fs::OpenOptions::new().create(true).append(true).open(&path)?.write_all(line.as_bytes())
    })();
    if let Err(error) = result {
        eprintln!("dmbd compile-stats: could not record: {error}");
    }
}

/// Read every record under `dir` (rotated file first), skipping unparseable lines.
pub fn load(dir: &Path) -> Vec<Record> {
    let mut records = Vec::new();
    for name in ["compile-stats.jsonl.1", "compile-stats.jsonl"] {
        if let Ok(text) = std::fs::read_to_string(dir.join(name)) {
            records.extend(text.lines().filter_map(|line| serde_json::from_str::<Record>(line).ok()));
        }
    }
    records
}

fn normalize_reason(reason: &str) -> String {
    // Group reasons that differ only in numbers.
    let mut out = String::new();
    let mut last_digit = false;
    for ch in reason.chars().take(70) {
        if ch.is_ascii_digit() {
            if !last_digit {
                out.push('N');
            }
            last_digit = true;
        } else {
            last_digit = false;
            out.push(ch);
        }
    }
    out
}

/// Totals over `records` newer than `since_ms` (0 for all), as printed by `dmbc --daemon-stats`.
pub fn summary(records: &[Record], since_ms: u64) -> String {
    use std::fmt::Write as _;
    let records: Vec<&Record> = records.iter().filter(|record| record.at_ms >= since_ms).collect();
    let mut out = String::new();
    if records.is_empty() {
        return "no compiles recorded\n".to_string();
    }
    let total = records.len();
    let ok = records.iter().filter(|r| r.path != PathTaken::Failed).count();
    let hot = records.iter().filter(|r| r.session.hot).count();
    let incremental = records.iter().filter(|r| matches!(r.path, PathTaken::Hit | PathTaken::Patch)).count();
    let pct = |n: usize, d: usize| if d == 0 { 0.0 } else { 100.0 * n as f64 / d as f64 };
    let _ = writeln!(out, "compiles: {total} ({ok} succeeded, {} failed)", total - ok);
    let _ = writeln!(out, "session hit rate: {:.1}% ({hot} of {total} found a retained session with state)", pct(hot, total));
    let _ = writeln!(out, "incremental rate: {:.1}% ({incremental} of {total} took the hit or patch path)", pct(incremental, total));
    let mut by_path: BTreeMap<&str, Vec<f64>> = BTreeMap::new();
    for record in &records {
        by_path.entry(record.path.name()).or_default().push(record.seconds);
    }
    let _ = writeln!(out, "by path:");
    for (name, mut times) in by_path {
        times.sort_by(|a, b| a.total_cmp(b));
        let mean = times.iter().sum::<f64>() / times.len() as f64;
        let _ = writeln!(
            out,
            "  {name:<7} {:>4}  mean {mean:>7.2}s  p50 {:>7.2}s  max {:>7.2}s",
            times.len(),
            times[times.len() / 2],
            times[times.len() - 1]
        );
    }
    let mut misses: BTreeMap<String, usize> = BTreeMap::new();
    for record in records.iter().filter(|r| !r.session.hot) {
        *misses.entry(record.session.miss.clone().unwrap_or_else(|| "unknown".into())).or_default() += 1;
    }
    if !misses.is_empty() {
        let _ = writeln!(out, "session misses by cause:");
        let mut misses: Vec<_> = misses.into_iter().collect();
        misses.sort_by(|a, b| b.1.cmp(&a.1));
        for (why, count) in misses {
            let _ = writeln!(out, "  {count:>4}  {why}");
        }
    }
    let mut declines: BTreeMap<String, usize> = BTreeMap::new();
    for record in records.iter().filter(|r| r.path == PathTaken::Full && r.session.hot) {
        *declines.entry(normalize_reason(record.reason.as_deref().unwrap_or("no reason recorded"))).or_default() += 1;
    }
    if !declines.is_empty() {
        let _ = writeln!(out, "hot session but full compile (patch declined) by reason:");
        let mut declines: Vec<_> = declines.into_iter().collect();
        declines.sort_by(|a, b| b.1.cmp(&a.1));
        for (why, count) in declines {
            let _ = writeln!(out, "  {count:>4}  {why}");
        }
    }
    if let Some(peak) = records.iter().filter_map(|r| r.peak_private).max() {
        let _ = writeln!(out, "peak private memory during a compile: {:.2} GB", peak as f64 / 1e9);
    }
    let mut by_variant: BTreeMap<&str, (usize, usize)> = BTreeMap::new();
    for record in &records {
        let entry = by_variant.entry(record.variant.as_str()).or_default();
        entry.0 += 1;
        entry.1 += usize::from(record.session.hot);
    }
    let _ = writeln!(out, "by variant (compiles, session hits):");
    for (variant, (count, hits)) in by_variant {
        let _ = writeln!(out, "  {variant:<28} {count:>4} {hits:>4}");
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(path: PathTaken, hot: bool, miss: Option<&str>, seconds: f64, reason: Option<&str>) -> Record {
        Record {
            at_ms: 1000,
            project: "p".into(),
            variant: "deepquarry.dme".into(),
            workers: 4,
            session: SessionState { hot, miss: miss.map(String::from), sessions: 1 },
            path,
            reason: reason.map(String::from),
            changed_bodies: None,
            seconds,
            private_before: Some(1),
            private_after: Some(2),
            peak_private: Some(3_000_000_000),
            error: None,
        }
    }

    fn hot() -> SessionState {
        SessionState { hot: true, ..Default::default() }
    }

    #[test]
    fn notes_resolve_to_a_path_and_reset_between_requests() {
        begin();
        note_full("declined: 3 bodies changed");
        let first = finish(Path::new("p"), "v".into(), 4, hot(), 1.0, (None, None, None), None);
        assert_eq!(first.path, PathTaken::Full);
        assert_eq!(first.reason.as_deref(), Some("declined: 3 bodies changed"));
        begin();
        note_patch(2);
        let second = finish(Path::new("p"), "v".into(), 4, hot(), 1.0, (None, None, None), None);
        assert_eq!((second.path, second.changed_bodies, second.reason), (PathTaken::Patch, Some(2), None));
        begin();
        let cold_state = SessionState { hot: false, miss: Some("no-session".into()), sessions: 0 };
        let cold = finish(Path::new("p"), "v".into(), 4, cold_state, 1.0, (None, None, None), None);
        assert_eq!((cold.path, cold.reason.as_deref()), (PathTaken::Full, Some("no-session")));
        let failed = finish(Path::new("p"), "v".into(), 4, SessionState::default(), 1.0, (None, None, None), Some("boom".into()));
        assert_eq!(failed.path, PathTaken::Failed);
    }

    #[test]
    fn long_reasons_are_truncated_on_a_char_boundary() {
        begin();
        note_full("é".repeat(500));
        let record = finish(Path::new("p"), "v".into(), 1, SessionState::default(), 0.0, (None, None, None), None);
        assert_eq!(record.reason.unwrap().chars().count(), REASON_LIMIT);
    }

    #[test]
    fn append_load_and_summary_round_trip_with_rotation() {
        let dir = std::env::temp_dir().join(format!("dmbc-stats-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        append(&dir, &record(PathTaken::Hit, true, None, 1.5, None));
        append(&dir, &record(PathTaken::Patch, true, None, 8.0, None));
        append(&dir, &record(PathTaken::Full, true, None, 30.0, Some("declined: skeleton changed (bodies 5 -> 6)")));
        append(&dir, &record(PathTaken::Full, false, Some("evicted:memory-pressure"), 80.0, None));
        let records = load(&dir);
        assert_eq!(records.len(), 4);
        let text = summary(&records, 0);
        assert!(text.contains("compiles: 4"), "{text}");
        assert!(text.contains("session hit rate: 75.0%"), "{text}");
        assert!(text.contains("incremental rate: 50.0%"), "{text}");
        assert!(text.contains("evicted:memory-pressure"), "{text}");
        assert!(text.contains("declined: skeleton changed (bodies N -> N)"), "{text}");
        assert!(summary(&records, 2000).contains("no compiles"));
        std::fs::write(stats_path(&dir), vec![b'x'; (ROTATE_BYTES + 1) as usize]).unwrap();
        append(&dir, &record(PathTaken::Hit, true, None, 1.0, None));
        assert!(dir.join("compile-stats.jsonl.1").exists());
        assert_eq!(load(&dir).len(), 1);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn line_names_path_session_and_reason() {
        let line = record(PathTaken::Full, false, Some("no-session"), 79.0, Some("no-session")).line();
        assert!(line.contains("full session=miss(no-session) wall=79.00s workers=4"), "{line}");
        assert!(line.contains("reason=\"no-session\""), "{line}");
    }
}
