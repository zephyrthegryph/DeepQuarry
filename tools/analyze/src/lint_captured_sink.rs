//! Optional capture-only output admission. Ordinary Engine sinks remain unbounded.
//! Policy-created individual message temporaries are not an RSS/CPU guarantee;
//! this bounds what the sink retains and refuses the entire result on overflow.
use super::{AllowUse, Sink, Site};
#[derive(Clone, Debug)]
pub(super) struct Bound {
    pub(super) rows: usize,
    pub(super) bytes: usize,
    used: usize,
    records: usize,
    pub(super) error: Option<String>,
    pub(super) allow_start: usize,
}
impl Bound {
    pub(super) fn new(rows: usize, bytes: usize) -> Self {
        Self {
            rows,
            bytes,
            used: 1024,
            records: 0,
            error: None,
            allow_start: 0,
        }
    }
    fn admit(&mut self, strings: usize, slots: usize) -> bool {
        if self.error.is_some() {
            return false;
        }
        let next = self
            .used
            .checked_add(strings)
            .and_then(|n| n.checked_add(slots));
        if self.records >= self.rows || next.is_none_or(|n| n > self.bytes) {
            self.error = Some("captured raw findings exceed count/retained-byte admission".into());
            return false;
        }
        self.used = next.unwrap();
        self.records += 1;
        true
    }
}
fn grow<T>(vector: &mut Vec<T>, max: usize) -> Result<usize, String> {
    if vector.len() < vector.capacity() {
        return Ok(0);
    }
    let add = max.saturating_sub(vector.capacity()).min(64);
    if add == 0 {
        return Err("captured finding vector exceeds count admission".into());
    }
    Ok(add * std::mem::size_of::<T>())
}
fn allocate<T>(vector: &mut Vec<T>, bytes: usize) -> Result<(), String> {
    if bytes == 0 {
        return Ok(());
    }
    let count = bytes / std::mem::size_of::<T>();
    let before = vector.capacity();
    vector
        .try_reserve_exact(count)
        .map_err(|_| "captured finding allocation refused")?;
    if vector.capacity() > before + count {
        return Err("captured finding allocator exceeded reserved capacity".into());
    }
    Ok(())
}
impl Sink {
    pub(crate) fn bounded(rows: usize, bytes: usize) -> Self {
        Self {
            bound: Some(Bound::new(rows, bytes)),
            ..Self::default()
        }
    }
    /// Equivalent to a fresh legacy Sink for annotation dedup, while retaining
    /// all preceding output in the same admitted vectors and row/byte family.
    pub(crate) fn begin_captured_phase(&mut self, rel: &str) {
        let bound = self.bound.as_mut().expect("captured phase requires bounded sink");
        bound.allow_start = self.allow_used.len();
        self.set_current(rel);
    }
    pub(crate) fn set_current(&mut self, rel: &str) {
        if let Some(bound) = &mut self.bound {
            let used = bound.used.saturating_sub(self.cur.capacity());
            let Some(next) = used.checked_add(rel.len()).filter(|n| *n <= bound.bytes) else {
                bound.error = Some("captured finding path exceeds byte admission".into());
                return;
            };
            bound.used = next;
        }
        self.cur = rel.to_owned();
    }
    pub(crate) fn admission_error(&self) -> Option<String> {
        let bound = self.bound.as_ref()?;
        if let Some(error) = &bound.error {
            return Some(error.clone());
        }
        let rows = self
            .sites
            .len()
            .checked_add(self.allow_used.len())
            .and_then(|n| n.checked_add(self.notes.len()));
        let mut bytes = Some(1024 + self.cur.capacity());
        let mut add = |n: usize| {
            bytes = bytes.and_then(|old| old.checked_add(n));
        };
        add(self.sites.capacity() * std::mem::size_of::<Site>());
        add(self.notes.capacity() * std::mem::size_of::<String>());
        add(self.allow_used.capacity() * std::mem::size_of::<AllowUse>());
        for row in &self.sites {
            for value in [&row.rule, &row.rel, &row.msg, &row.key, &row.ident] {
                add(value.capacity());
            }
        }
        for row in &self.allow_used {
            add(row.rel.capacity());
            add(row.name.capacity());
            add(row.code.capacity());
        }
        for row in &self.notes {
            add(row.capacity());
        }
        (rows.is_none_or(|n| n > bound.rows) || bytes.is_none_or(|n| n > bound.bytes))
            .then(|| "captured raw finding storage exceeds admission".into())
    }
    pub(super) fn push_site(&mut self, row: Site) {
        if let Some(bound) = &mut self.bound {
            let slots = match grow(&mut self.sites, bound.rows) {
                Ok(n) => n,
                Err(e) => {
                    bound.error = Some(e);
                    return;
                }
            };
            let strings = [&row.rule, &row.rel, &row.msg, &row.key, &row.ident]
                .iter()
                .try_fold(0usize, |n, v| n.checked_add(v.capacity()));
            let Some(strings) = strings else {
                bound.error = Some("captured finding string accounting overflow".into());
                return;
            };
            if !bound.admit(strings, slots) {
                return;
            }
            if let Err(error) = allocate(&mut self.sites, slots) {
                bound.error = Some(error);
                return;
            }
        }
        self.sites.push(row);
    }
    pub(super) fn push_note(&mut self, row: String) {
        if let Some(bound) = &mut self.bound {
            let slots = match grow(&mut self.notes, bound.rows) {
                Ok(n) => n,
                Err(e) => {
                    bound.error = Some(e);
                    return;
                }
            };
            if !bound.admit(row.capacity(), slots) {
                return;
            }
            if let Err(error) = allocate(&mut self.notes, slots) {
                bound.error = Some(error);
                return;
            }
        }
        self.notes.push(row);
    }
    pub(super) fn push_allow(&mut self, row: AllowUse) {
        if let Some(bound) = &mut self.bound {
            let slots = match grow(&mut self.allow_used, bound.rows) {
                Ok(n) => n,
                Err(e) => {
                    bound.error = Some(e);
                    return;
                }
            };
            let Some(strings) = row
                .rel
                .capacity()
                .checked_add(row.name.capacity())
                .and_then(|n| n.checked_add(row.code.capacity()))
            else {
                bound.error = Some("captured allow accounting overflow".into());
                return;
            };
            if !bound.admit(strings, slots) {
                return;
            }
            if let Err(error) = allocate(&mut self.allow_used, slots) {
                bound.error = Some(error);
                return;
            }
        }
        self.allow_used.push(row);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn all_report_shapes_share_sticky_count_and_byte_admission() {
        let mut sink = Sink::bounded(3, 16384);
        sink.set_current("code/test.dm");
        sink.site_keyed("rule", "code/test.dm", 1, "message", "key");
        sink.note("note");
        sink.push_allow(AllowUse {
            rel: "code/test.dm".into(),
            line: 1,
            name: "scheduler".into(),
            code: "".into(),
        });
        assert!(sink.admission_error().is_none());
        sink.site_decl("rule", "code/test.dm", 2, "other", "/datum::value");
        assert!(sink.admission_error().is_some());
        assert_eq!(sink.sites.len(), 1);
        assert_eq!(sink.notes.len(), 1);
        assert_eq!(sink.allow_used.len(), 1);
        let mut bytes = Sink::bounded(100, 1100);
        bytes.note("x".repeat(1000));
        assert!(bytes.admission_error().is_some());
        assert!(bytes.notes.is_empty());
    }
    #[test]
    fn captured_phases_preserve_fresh_sink_allow_duplicates_and_global_budget() {
        let row = AllowUse { rel: "code/test.dm".into(), line: 3,
            name: "pollers".into(), code: "".into() };
        let mut sink = Sink::bounded(3, 16384);
        sink.begin_captured_phase("code/test.dm");
        sink.replay_allow(row.clone()); sink.replay_allow(row.clone());
        sink.site("file", 3);
        assert_eq!(sink.allow_used.len(), 1);
        sink.begin_captured_phase("");
        sink.replay_allow(row.clone()); sink.replay_allow(row);
        assert_eq!(sink.allow_used.len(), 2);
        assert_eq!(sink.sites[0].rel, "code/test.dm");
        assert!(sink.admission_error().is_none());
        sink.note("fourth record must fail across phases");
        assert!(sink.admission_error().is_some());
        assert!(sink.notes.is_empty());
    }
    #[test]
    fn ordinary_sink_keeps_its_existing_unlimited_protocol() {
        let mut sink = Sink::new();
        for _ in 0..20 {
            sink.site("same", 1);
        }
        assert_eq!(sink.sites.len(), 20);
        assert!(sink.admission_error().is_none());
    }
}
