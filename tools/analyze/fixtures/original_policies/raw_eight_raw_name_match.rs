//! Exact existing per-name raw policies over captured literal identifiers and
//! fixed suffix regexes. Names come from unchanged word-only policy captures.
//! No per-input compiled regex, declaration parser or model is constructed.
fn word_before(line: &str, at: usize) -> bool {
    let Some((start, _)) = line[..at].char_indices().next_back() else { return false };
    crate::pat_match!(r"^\w$").is_match(&line[start..at])
}
pub(crate) fn writes(line: &str, name: &str, field: bool) -> bool {
    if name.is_empty() { return false; }
    for (at, _) in line.match_indices(name) {
        if word_before(line, at) || (!field && line[..at].ends_with('.')) { continue; }
        let suffix = &line[at + name.len()..];
        if field {
            if crate::pat_match!(r"^\.\w+\s*(?:\[[^\]]*\])?\s*(?:\+=|-=|\|=|\*=|/=|&=|=[^=])").is_match(suffix)
                || crate::pat_match!(r"^\.\w+\.(?:Add|Insert|Cut|Remove|Swap)\(").is_match(suffix) { return true; }
        } else if crate::pat_match!(r"^\s*(?:\[[^\]]*\])?\s*(?:\+=|-=|\|=|\*=|/=|&=|=[^=])").is_match(suffix)
            || crate::pat_match!(r"^\.(?:Add|Insert|Cut|Remove|Swap)\(").is_match(suffix) { return true; }
    }
    false
}
fn in_before(line: &str, at: usize) -> bool {
    // Inspect only the immediately preceding whitespace run, avoiding a fresh
    // full-prefix search for every identifier occurrence. Regex whitespace and
    // word domains remain the original Unicode domains, not ASCII approximations.
    let mut start = at;
    for (pos, _) in line[..at].char_indices().rev() {
        if !crate::pat_match!(r"^\s$").is_match(&line[pos..start]) { break; }
        start = pos;
    }
    if start == at { return false; }
    let Some(before) = start.checked_sub(2) else { return false; };
    line.get(before..start) == Some("in") && !word_before(line, before)
}
pub(crate) fn contents_walk(line: &str, name: &str) -> bool {
    if name.is_empty() { return false; }
    for (at, _) in line.match_indices(name) {
        let suffix = &line[at + name.len()..];
        if !word_before(line, at) && crate::pat_match!(r"^\.contents\b").is_match(suffix) { return true; }
        if in_before(line, at)
            && crate::pat_match!(r"^\s*\)").is_match(suffix) { return true; }
    }
    false
}
#[cfg(test)]
mod tests {
    fn old_writes(line: &str, name: &str, field: bool) -> bool {
        let n = regex::escape(name);
        let target = if field { format!(r"\b{}\.\w+", n) } else { format!(r"(?:^|[^.\w]){}", n) };
        let assign = regex::Regex::new(&format!(r"{}\s*(?:\[[^\]]*\])?\s*(?:\+=|-=|\|=|\*=|/=|&=|=[^=])", target)).unwrap();
        let call = regex::Regex::new(&format!(r"{}\.(?:Add|Insert|Cut|Remove|Swap)\(", target)).unwrap();
        assign.is_match(line) || call.is_match(line)
    }
    fn old_contents(line: &str, name: &str) -> bool {
        crate::pat::Pat::new(&format!(r"\b{0}\.contents\b|\bin\s+{0}\s*\)", name)).is_match(line)
    }
    #[test]
    fn literal_identifier_matchers_equal_independent_old_regexes_for_unicode_and_overlap() {
        let names = ["a", "aa", "contents", "x_y", "é", "a\u{301}", "a\u{200d}"];
        let before = ["", ".", "b", "_", "é", "\u{301}", "\u{200d}", " ", "// ", "in ", "begin ", "in\u{85}"];
        let after = [".field = x", ".field == x", ".field += 1", ".field[1] &= 2", ".field.Add(x)", ".field.Remove(x)", " = x", " == x", "[1] = x", ".Add(x)", ".contents", ".contents_more", ".contents.contents", " )", "\u{2028})", "x.contents"];
        for name in names {
            for prefix in before { for suffix in after {
                let line = format!("{prefix}{name}{suffix}");
                for field in [false, true] {
                    assert_eq!(super::writes(&line, name, field), old_writes(&line, name, field), "{line:?}/{name:?}/{field}");
                }
                assert_eq!(super::contents_walk(&line, name), old_contents(&line, name), "{line:?}/{name:?}");
            }}
        }
        assert!(super::contents_walk("b.contents.contents", "contents"));
        assert!(!super::contents_walk("aaa.contents", "aa"));
        assert!(super::contents_walk("in contents)", "contents"));
    }
}
