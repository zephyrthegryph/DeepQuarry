//! Moving a kept DreamChecker run to an edited front end revision with the same declarations (doc/rewrite/proposals/lean_unified.md,
//! "2b DREAMCHECKER", proportional work): the places of the model (offsets into the expanded text) move with their declarations,
//! the lines of an edited file move by the lines the edit added or removed, and the bodies the edit changed are named.
//!
//! What is moved and how:
//!
//! * a model place (`Where` at an expanded offset) belongs to the declaration that starts last at or before it; it keeps its
//!   offset from that declaration's start, and the declaration's text from its start to the end of the place's line must read the
//!   same in both revisions (else the move is refused and the run is computed again);
//! * a location (file, line) in a file the edit did not touch stays; in an edited file its line moves by a [`LineMap`]: the lines
//!   before the first changed line stay, the lines after the last changed one move by the difference in length, a line in between
//!   is refused (what holds it is computed again);
//! * a body changed when its expanded text differs or a line of its source changed.
use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;

use dm_tree::frontend::{ColdFrontend, FrontendDelta, SourceFile};
use dreamchecker::native::input::Where;
use dreammaker::{FileId, Location};

/// An edited file's old lines against its new ones: the common first and last lines.
#[derive(Clone, Copy, Debug)]
pub(crate) struct LineMap {
    /// Lines `1..=prefix` are the same.
    prefix: u32,
    /// Old lines after `old_changed_end` (1-based, inclusive of none) are the same, `delta` lines away.
    old_changed_end: u32,
    delta: i64,
    /// A changed line (old or new) is a preprocessor directive: the edit can change the macros and their warnings.
    directive: bool,
}

impl LineMap {
    pub(crate) fn new(old: &SourceFile, new: &SourceFile) -> LineMap {
        fn lines<'t>(t: &'t [u8], starts: &[usize]) -> Vec<&'t [u8]> {
            (0..starts.len())
                .map(|i| {
                    let a = starts[i].min(t.len());
                    let b = starts.get(i + 1).copied().unwrap_or(t.len()).min(t.len()).max(a);
                    &t[a..b]
                })
                .collect()
        }
        LineMap::of(&lines(old.text.as_str().as_bytes(), &old.line_starts), &lines(new.text.as_str().as_bytes(), &new.line_starts))
    }

    /// The map between two files' lines.
    fn of(old: &[&[u8]], new: &[&[u8]]) -> LineMap {
        let (on, nn) = (old.len(), new.len());
        let mut prefix = 0usize;
        while prefix < on && prefix < nn && old[prefix] == new[prefix] {
            prefix += 1;
        }
        let mut suffix = 0usize;
        while suffix < on - prefix && suffix < nn - prefix && old[on - 1 - suffix] == new[nn - 1 - suffix] {
            suffix += 1;
        }
        let is_directive = |l: &&[u8]| l.iter().find(|b| !b.is_ascii_whitespace()) == Some(&b'#');
        let directive = old[prefix..on - suffix].iter().any(is_directive) || new[prefix..nn - suffix].iter().any(is_directive);
        LineMap { prefix: prefix as u32, old_changed_end: (on - suffix) as u32, delta: nn as i64 - on as i64, directive }
    }

    /// Where old line `line` (1-based) is now; `None` for a line the edit changed. Line 0 (no line) stays.
    pub(crate) fn map(&self, line: u32) -> Option<u32> {
        if line == 0 || line <= self.prefix {
            Some(line)
        } else if line > self.old_changed_end {
            u32::try_from(line as i64 + self.delta).ok()
        } else {
            None
        }
    }

    /// Whether old lines `first..=last` are all unchanged.
    pub(crate) fn keeps(&self, first: u32, last: u32) -> bool {
        last <= self.prefix || first > self.old_changed_end
    }
}

/// The edit between two revisions as the checker moves it.
pub(crate) struct Edit<'a> {
    old: &'a ColdFrontend,
    new: &'a ColdFrontend,
    /// By file id: the line maps of the edited files.
    lines: HashMap<FileId, LineMap>,
    /// The edited files' line maps by semantic path.
    dirty: HashMap<Arc<str>, LineMap>,
    old_files: HashMap<&'a Path, &'a SourceFile>,
    /// The old expanded text the edited files' regions wrote, sorted: a place with none of it between its declaration's start
    /// and itself moves with the declaration without reading the text.
    dirty_output: Vec<(usize, usize)>,
    /// The same of the new revision: a body none of it holds is in a file the edit did not touch.
    new_dirty_output: Vec<(usize, usize)>,
}

impl<'a> Edit<'a> {
    /// The edit `delta` (from `old`'s revision to `new`'s) when it keeps every declaration (each one at most moved) and every body
    /// occurrence; else why not.
    pub(crate) fn new(
        old: &'a ColdFrontend,
        new: &'a ColdFrontend,
        delta: &FrontendDelta,
        ids: &HashMap<Arc<str>, FileId>,
    ) -> Result<Edit<'a>, String> {
        use dm_tree::frontend::Change;
        if let Some((key, change)) = delta.declarations.iter().find(|(_, c)| *c != Change::Moved) {
            return Err(format!("a declaration is {change:?} ({}{})", key.owner, key.member.as_ref().map_or(String::new(), |(n, _)| format!("/{n}"))));
        }
        if delta.bodies.iter().any(|(_, c)| matches!(c, Change::Added | Change::Removed)) {
            return Err("a body was added or removed".into());
        }
        if old.bodies.len() != new.bodies.len() || old.bodies.iter().zip(new.bodies.iter()).any(|(a, b)| a.declaration != b.declaration) {
            return Err("the body occurrences differ".into());
        }
        if old.declaration_starts().len() != new.declaration_starts().len() {
            return Err("the declaration count differs".into());
        }
        let sorted = |s: &[u32]| s.windows(2).all(|w| w[0] <= w[1]);
        if !sorted(old.declaration_starts()) || !sorted(new.declaration_starts()) {
            return Err("the declaration starts are not in order".into());
        }
        let old_files: HashMap<&Path, &SourceFile> = old.files.iter().map(|f| (f.path.as_path(), f)).collect();
        let new_files: HashMap<&Path, &SourceFile> = new.files.iter().map(|f| (f.path.as_path(), f)).collect();
        let physical = |fe: &'a ColdFrontend, semantic: &str| fe.plan.occurrences.iter().find(|o| &*o.semantic_path == semantic).map(|o| o.path.as_path());
        let mut lines = HashMap::new();
        let mut dirty = HashMap::new();
        for path in &delta.files {
            let Some(&id) = ids.get(path) else { return Err(format!("{path} has no file id")) };
            let (Some(op), Some(np)) = (physical(old, path), physical(new, path)) else { return Err(format!("{path} is not in both plans")) };
            let (Some(of), Some(nf)) = (old_files.get(op), new_files.get(np)) else { return Err(format!("{path} has no source in both revisions")) };
            let map = LineMap::new(of, nf);
            if map.directive {
                return Err(format!("a preprocessor directive in {path} changed"));
            }
            lines.insert(id, map);
            dirty.insert(Arc::clone(path), map);
        }
        let output_of = |fe: &ColdFrontend| {
            let mut v: Vec<(usize, usize)> = fe
                .expanded
                .receipts
                .iter()
                .filter(|r| {
                    let region = fe.plan.regions.get(r.region());
                    region.and_then(|g| fe.plan.occurrences.get(g.occurrence)).is_some_and(|o| dirty.contains_key(&o.semantic_path))
                })
                .map(|r| (r.output_span().start as usize, r.output_span().end as usize))
                .collect();
            v.sort_unstable();
            v
        };
        let (dirty_output, new_dirty_output) = (output_of(old), output_of(new));
        Ok(Edit { old, new, lines, dirty, old_files, dirty_output, new_dirty_output })
    }

    /// Moves a kept location to the new revision; `false` for one on a changed line.
    pub(crate) fn relocate(&self, l: &mut Location) -> bool {
        match self.lines.get(&l.file) {
            None => true,
            Some(map) => match map.map(l.line) {
                Some(line) => {
                    l.line = line;
                    true
                }
                None => false,
            },
        }
    }

    /// Moves a model place to the new revision (see the module docs); `false` when it cannot be moved.
    pub(crate) fn remap(&self, w: &mut Where) -> bool {
        let x = match w {
            Where::At(x) | Where::LineEnd(x) | Where::DeclEnd(x) => x,
            Where::Fixed(_) => return true,
        };
        let (os, ns) = (self.old.declaration_starts(), self.new.declaration_starts());
        let Some(j) = os.partition_point(|&s| s as usize <= *x).checked_sub(1) else { return false };
        let (ot, nt) = (self.old.expanded.text.as_str().as_bytes(), self.new.expanded.text.as_str().as_bytes());
        let (from, to) = (os[j] as usize, ns[j] as usize);
        // Copied text from the declaration's start through the place: it moved with the declaration.
        let first_dirty = self.dirty_output.partition_point(|&(_, end)| end <= from);
        if self.dirty_output.get(first_dirty).is_none_or(|&(start, _)| start > *x) {
            *x = to + (*x - from);
            return true;
        }
        let end = ot.get(*x..).and_then(|rest| rest.iter().position(|&b| b == b'\n')).map_or(ot.len(), |e| *x + e);
        let Some(old_text) = ot.get(from..end) else { return false };
        if nt.get(to..to + old_text.len()) != Some(old_text) || (end < ot.len() && nt.get(to + old_text.len()) != Some(&b'\n')) {
            return false;
        }
        *x = to + (*x - from);
        true
    }

    /// How far body occurrence `b` moved in the expanded text.
    pub(crate) fn shift(&self, b: usize) -> isize {
        match (self.old.bodies.get(b), self.new.bodies.get(b)) {
            (Some(o), Some(n)) => n.expanded_span.start as isize - o.expanded_span.start as isize,
            _ => 0,
        }
    }

    /// Whether body occurrence `b` changed: in an edited file, its expanded text or a line of its source.
    pub(crate) fn body_changed(&self, b: usize) -> bool {
        let (Some(o), Some(n)) = (self.old.bodies.get(b), self.new.bodies.get(b)) else { return true };
        let first = self.new_dirty_output.partition_point(|&(_, end)| end <= n.expanded_span.start);
        if self.new_dirty_output.get(first).is_none_or(|&(start, _)| start >= n.expanded_span.end.max(n.expanded_span.start + 1)) {
            return false;
        }
        let Some(map) = self.dirty.get(&n.source.semantic_path) else { return false };
        let (ot, nt) = (self.old.expanded.text.as_str(), self.new.expanded.text.as_str());
        if ot.get(o.expanded_span.start..o.expanded_span.end) != nt.get(n.expanded_span.start..n.expanded_span.end) {
            return true;
        }
        let Some(f) = self.old_files.get(o.source.path.as_path()) else { return true };
        let row = |at: usize| f.line_starts.partition_point(|&s| s <= at).saturating_sub(1) as u32 + 1;
        let (start, end) = (o.source.span.start as usize, o.source.span.end as usize);
        let (first, last) = (row(start), row(end.saturating_sub(1).max(start)));
        !map.keeps(first, last)
    }

    /// How many files the edit touched.
    pub(crate) fn files(&self) -> usize {
        self.dirty.len()
    }
}

#[cfg(test)]
mod tests {
    use super::LineMap;

    fn map(old: &str, new: &str) -> LineMap {
        let o: Vec<&[u8]> = old.split_inclusive('\n').map(str::as_bytes).collect();
        let n: Vec<&[u8]> = new.split_inclusive('\n').map(str::as_bytes).collect();
        LineMap::of(&o, &n)
    }

    #[test]
    fn lines_before_and_after_an_edit_move_and_edited_lines_are_refused() {
        // A line added after line 2: lines 1-2 stay, 3-4 move down one.
        let m = map("a\nb\nc\nd\n", "a\nb\nx\nc\nd\n");
        assert_eq!((m.map(1), m.map(2), m.map(3), m.map(4), m.map(0)), (Some(1), Some(2), Some(4), Some(5), Some(0)));
        assert!(m.keeps(1, 2) && m.keeps(3, 4));
        // A line changed in place: it is refused, the others stay.
        let m = map("a\nb\nc\n", "a\nB\nc\n");
        assert_eq!((m.map(1), m.map(2), m.map(3)), (Some(1), None, Some(3)));
        assert!(!m.keeps(1, 2) && m.keeps(3, 3));
        // A line removed: the lines after it move up; a repeated line is matched from the end without overlapping the prefix.
        let m = map("a\na\na\n", "a\na\n");
        assert_eq!((m.map(1), m.map(2), m.map(3)), (Some(1), Some(2), None));
        let m = map("a\nb\nc\n", "a\nc\n");
        assert_eq!((m.map(1), m.map(2), m.map(3)), (Some(1), None, Some(2)));
        // Two edits: everything between them is refused.
        let m = map("a\nb\nc\nd\n", "A\nb\nc\nD\n");
        assert_eq!((m.map(1), m.map(2), m.map(4)), (None, None, None));
        assert!(!m.directive);
        // A directive added, removed or edited is seen.
        assert!(map("a\nb\n", "a\n  #define X 1\nb\n").directive);
        assert!(map("a\n#undef X\nb\n", "a\nb\n").directive);
        assert!(!map("a\n#define X 1\nb\n", "a\n#define X 1\nc\n").directive);
    }
}
