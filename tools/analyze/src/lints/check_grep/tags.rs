//! Port of `tools/TagMatcher/tag-matcher.py` (the "html tag matching" part of check_grep.sh).
//!
//! For each of `<span>`, `<font>`, `<center>`, `<b>`, `<i>` it counts opening minus closing tags per
//! line and keeps a "stack" of unmatched lines per file; a file whose stacks are not empty fails,
//! and every line left in a stack is a site. The script walks `code/` with `os.walk` (dot-files
//! included), reads each `*.dm` through `codecs.open(..., errors='ignore')` and iterates it, which
//! splits lines like `str.splitlines`: besides `\n` also `\v`, `\f`, `\x1c`-`\x1e`, `\x85`, U+2028
//! and U+2029.

use crate::pat::Pat;
use crate::tree::SourceFile;

/// `str.splitlines(keepends=True)`.
fn py_splitlines(text: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut start = 0;
    let mut it = text.char_indices().peekable();
    while let Some((i, c)) = it.next() {
        let is_sep = matches!(c, '\n' | '\r' | '\u{0b}' | '\u{0c}' | '\u{1c}' | '\u{1d}' | '\u{1e}' | '\u{85}' | '\u{2028}' | '\u{2029}');
        if !is_sep {
            continue;
        }
        let mut end = i + c.len_utf8();
        if c == '\r' {
            if let Some(&(j, '\n')) = it.peek() {
                end = j + 1;
                it.next();
            }
        }
        out.push(&text[start..end]);
        start = end;
    }
    if start < text.len() {
        out.push(&text[start..]);
    }
    out
}

struct Tag {
    open: Pat,
    close: Pat,
}

fn tags() -> &'static [Tag; 5] {
    static T: std::sync::LazyLock<[Tag; 5]> = std::sync::LazyLock::new(|| {
        let t = |o: &str, c: &str| Tag { open: Pat::new(o), close: Pat::new(c) };
        [
            t(r"(?i)<span(.*?)>", r"(?i)</span>"),
            t(r"(?i)<font(.*?)>", r"(?i)</font>"),
            t(r"(?i)<center>", r"(?i)</center>"),
            t(r"(?i)<b>", r"(?i)</b>"),
            t(r"(?i)<i>", r"(?i)</i>"),
        ]
    });
    &T
}

/// The lines of `f` the script prints under `Line N` (a line that is unmatched for two tags counts twice).
pub fn mismatch_lines(f: &SourceFile) -> Vec<usize> {
    let text = f.text();
    // The cheap exit: no tag of any kind in the file.
    if !text.contains('<') {
        return Vec::new();
    }
    let tags = tags();
    // `mismatches_by_tag` is a defaultdict: a tag's stack exists from the first line that touches it.
    let mut stacks: Vec<(usize, Vec<i64>)> = Vec::new();
    for (idx, line) in py_splitlines(text).iter().enumerate() {
        let number = (idx + 1) as i64;
        if !line.contains('<') {
            continue;
        }
        for (ti, tag) in tags.iter().enumerate() {
            let count = tag.open.find_iter(line).len() as i64 - tag.close.find_iter(line).len() as i64;
            if count == 0 {
                continue;
            }
            let pos = match stacks.iter().position(|(t, _)| *t == ti) {
                Some(p) => p,
                None => {
                    stacks.push((ti, Vec::new()));
                    stacks.len() - 1
                }
            };
            let stack = &mut stacks[pos].1;
            for _ in 0..count.abs() {
                if stack.is_empty() {
                    stack.push(if count > 0 { number } else { -number });
                } else if stack[0] > 0 {
                    if count > 0 {
                        stack.push(number);
                    } else {
                        stack.pop();
                    }
                } else if count < 0 {
                    stack.push(-number);
                } else {
                    stack.pop();
                }
            }
        }
    }
    let mut out = Vec::new();
    for (_, list) in &stacks {
        let mut set: Vec<i64> = list.clone();
        set.sort();
        set.dedup();
        for v in set {
            out.push(v.unsigned_abs() as usize);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lines(text: &str) -> Vec<usize> {
        let mut v = mismatch_lines(&SourceFile::from_text("code/a.dm", text));
        v.sort();
        v
    }

    #[test]
    fn balanced_tags_pass() {
        assert!(lines("<span class='a'>x</span>\n<b>y</b>\n").is_empty());
    }

    #[test]
    fn unmatched_opening_and_closing_are_reported() {
        assert_eq!(lines("<span>x\ny\n"), vec![1]);
        assert_eq!(lines("x\n</font>\n"), vec![2]);
        // a pair split over two lines matches
        assert!(lines("<b>x\ny</b>\n").is_empty());
    }

    #[test]
    fn splitlines_matches_python() {
        assert_eq!(py_splitlines("a\nb\r\nc\u{0c}d"), vec!["a\n", "b\r\n", "c\u{0c}", "d"]);
        assert_eq!(py_splitlines("x\n"), vec!["x\n"]);
    }
}
