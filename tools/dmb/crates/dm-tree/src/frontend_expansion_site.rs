//! Which macro invocation written in the source produced a stretch of the expanded text (`SiteMapper::invocation_output`).
//!
//! An origin row's output is its source with each invocation replaced by its expansion; the text between two invocations is copied
//! (blanks may differ: the expander lays a statement out on its own rows). The invocations of an origin are aligned with the output
//! by those copied stretches, in order: each invocation's output is what lies between the copy of the text before it and the copy of
//! the text after it. Analysis reads it to see a BYOND constant (`NORTH`, a dmbc predefine) as the name the source wrote, as
//! SpacemanDMM's tools do (dreamchecker, doc/rewrite/proposals/lean_unified.md "2b DREAMCHECKER").
use super::Mapping;
use std::ops::Range;

/// The invocation behind an expanded byte: the output its expansion occupies (blanks at its ends left out), its macro's name, and
/// the names expanded inside its replacement and arguments (in expansion order).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InvocationOutput<'a> {
    pub output: Range<usize>,
    pub name: &'a str,
    pub nested: Vec<&'a str>,
}

fn is_blank(b: u8) -> bool {
    matches!(b, b' ' | b'\t' | b'\r' | b'\n' | b'\\')
}

/// Match `chunk` (source text) against `out` from `at`, comparing non-blank bytes: the position after the match.
fn match_at(out: &[u8], mut at: usize, chunk: &[u8]) -> Option<usize> {
    let mut c = 0;
    loop {
        while c < chunk.len() && is_blank(chunk[c]) {
            c += 1;
        }
        if c >= chunk.len() {
            return Some(at);
        }
        while at < out.len() && is_blank(out[at]) {
            at += 1;
        }
        if at >= out.len() || out[at] != chunk[c] {
            return None;
        }
        at += 1;
        c += 1;
    }
}

/// The first position at or after `from` where `chunk` matches (non-blank bytes): its start and the position after it.
fn find_from(out: &[u8], from: usize, chunk: &[u8]) -> Option<(usize, usize)> {
    let first = chunk.iter().position(|&b| !is_blank(b))?;
    let lead = chunk[first];
    (from..out.len()).filter(|&p| out[p] == lead).find_map(|p| match_at(out, p, &chunk[first..]).map(|end| (p, end)))
}

fn trimmed(out: &[u8], mut range: Range<usize>) -> Range<usize> {
    while range.start < range.end && is_blank(out[range.start]) {
        range.start += 1;
    }
    while range.end > range.start && is_blank(out[range.end - 1]) {
        range.end -= 1;
    }
    range
}

impl Mapping<'_> {
    pub(super) fn invocation_output(&self, offset: usize) -> Option<InvocationOutput<'_>> {
        let origin = self.origin(offset)?;
        if origin.macro_expansions.is_empty() {
            return None;
        }
        let file = self.file_of(origin.origin.path)?;
        let source = self.files.get(file.index())?.text.as_str().as_bytes();
        let expanded = self.expanded.text.as_str().as_bytes();
        let (src, out) = (origin.source_span, origin.output_span);
        let source = source.get(src.start..src.end.min(source.len()))?;
        let output = expanded.get(out.start..out.end.min(expanded.len()))?;
        let at = offset.checked_sub(out.start)?;
        // The invocations written in this row's own source (a nested one carries a span in its macro's replacement text), in order.
        let mut written: Vec<(usize, &dm_preprocess::regions::MacroExpansion)> = origin
            .macro_expansions
            .iter()
            .enumerate()
            .filter(|(_, e)| e.replacement_chain.is_empty() && source.get(e.invocation_span.start..).is_some_and(|r| r.starts_with(e.name.as_bytes())))
            .collect();
        written.sort_by_key(|(_, e)| e.invocation_span.start);
        let mut s_cursor = 0usize;
        let mut o_cursor = match_at(output, 0, source.get(..written.first()?.1.invocation_span.start)?)?;
        for (k, &(index, expansion)) in written.iter().enumerate() {
            let span = expansion.invocation_span;
            if span.start < s_cursor {
                return None;
            }
            let after = source.get(span.end..written.get(k + 1).map_or(source.len(), |(_, n)| n.invocation_span.start))?;
            let start = o_cursor;
            let (end, next) = if after.iter().all(|&b| is_blank(b)) {
                // Two invocations with only blanks between them (or the row's last one): the output runs to the next copied text.
                match written.get(k + 1) {
                    Some(_) => return None,
                    None => (output.len(), output.len()),
                }
            } else {
                find_from(output, start, after)?
            };
            if (start..end).contains(&at) {
                // The entries after it up to the next invocation written in the source are the ones its expansion made.
                let nested = origin.macro_expansions[index + 1..]
                    .iter()
                    .enumerate()
                    .take_while(|(j, _)| !written.iter().any(|(w, _)| *w == index + 1 + j))
                    .map(|(_, e)| &*e.name)
                    .collect();
                let range = trimmed(output, start..end);
                return Some(InvocationOutput { output: out.start + range.start..out.start + range.end, name: &expansion.name, nested });
            }
            s_cursor = span.end;
            o_cursor = next;
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn copied_text_bounds_each_expansion() {
        let out = b"flags = 1 | 4)";
        assert_eq!(match_at(out, 0, b"flags = "), Some(8));
        assert_eq!(find_from(out, 8, b" | "), Some((10, 11)));
        assert_eq!(find_from(out, 11, b")"), Some((13, 14)));
        assert_eq!(trimmed(out, 8..10), 8..9);
    }
}
