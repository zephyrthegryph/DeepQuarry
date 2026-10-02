//! `Pat`: the one regex type rules use.
//!
//! Most lint patterns are plain regexes the `regex` crate runs as automata. A good number lean on
//! Python `re` features that crate lacks: lookbehind (`(?<![\w.])spawn\s*\(`), lookahead, and
//! backreferences. `Pat` picks the engine per pattern:
//!   * no look-around/backref: `regex::Regex` (linear time);
//!   * a leading negative lookbehind over one character class: the rest runs on `regex` and the
//!     preceding character is checked by hand (as fast as plain regex, and exact);
//!   * anything else: `fancy_regex` (backtracking, correct, slower).
//!
//! Semantics follow Python `re` (leftmost-first alternation, lazy quantifiers), which the
//! `regex` crate shares. `search` = `find`, `match` = `Pat::new_match`, `fullmatch` = `new_full`.

use std::ops::Range;

use fancy_regex::Regex as Fancy;
use regex::Regex;

#[derive(Debug)]
enum Kind {
    Plain(Regex),
    /// `(?<!CLASS)REST` (negative) or `(?<=CLASS)REST` (positive): `re` is REST, `class` the one-char test.
    Behind { re: Regex, class: Regex, negative: bool },
    /// `pre` is the pattern with its look-arounds removed: a superset, run first as a cheap filter.
    Fancy(Fancy, Option<Regex>),
}

#[derive(Debug)]
pub struct Pat {
    src: String,
    kind: Kind,
}

/// A match: byte range within the haystack searched.
#[derive(Clone, Debug)]
pub struct M<'h> {
    pub start: usize,
    pub end: usize,
    pub hay: &'h str,
}

impl<'h> M<'h> {
    pub fn as_str(&self) -> &'h str {
        &self.hay[self.start..self.end]
    }
    pub fn range(&self) -> Range<usize> {
        self.start..self.end
    }
}

/// Capture groups of one match. Group 0 is the whole match; a group that did not participate is None.
#[derive(Clone, Debug)]
pub struct Caps<'h> {
    pub hay: &'h str,
    pub groups: Vec<Option<(usize, usize)>>,
}

impl<'h> Caps<'h> {
    pub fn get(&self, i: usize) -> Option<&'h str> {
        self.groups.get(i).copied().flatten().map(|(s, e)| &self.hay[s..e])
    }
    /// Group text, or "" when the group did not participate (Python's `m.group(i) or ""`).
    pub fn s(&self, i: usize) -> &'h str {
        self.get(i).unwrap_or("")
    }
    pub fn start(&self, i: usize) -> usize {
        self.groups[i].map(|g| g.0).unwrap_or(0)
    }
    pub fn end(&self, i: usize) -> usize {
        self.groups[i].map(|g| g.1).unwrap_or(0)
    }
    pub fn whole(&self) -> &'h str {
        self.s(0)
    }
    pub fn matched(&self, i: usize) -> bool {
        self.groups.get(i).map(|g| g.is_some()).unwrap_or(false)
    }
}

/// Splits a leading `(?<!X)` / `(?<=X)` where X is a single class (`[...]`, `\w`, `\d`, `\s`, or one
/// escaped/literal char); returns (class source, negative, rest).
fn split_leading_lookbehind(p: &str) -> Option<(String, bool, String)> {
    let (negative, rest) = if let Some(r) = p.strip_prefix("(?<!") {
        (true, r)
    } else if let Some(r) = p.strip_prefix("(?<=") {
        (false, r)
    } else {
        return None;
    };
    let bytes = rest.as_bytes();
    let class_end = if bytes.first() == Some(&b'[') {
        // find the closing ] of the class (a `]` right after `[` or `[^` is literal)
        let mut i = 1;
        if bytes.get(i) == Some(&b'^') {
            i += 1;
        }
        if bytes.get(i) == Some(&b']') {
            i += 1;
        }
        loop {
            match bytes.get(i) {
                None => return None,
                Some(b'\\') => i += 2,
                Some(b']') => break i + 1,
                Some(_) => i += 1,
            }
        }
    } else if bytes.first() == Some(&b'\\') {
        2
    } else if bytes.first().map(|b| b.is_ascii_alphanumeric() || *b == b'_' || *b == b'/').unwrap_or(false) {
        1
    } else {
        return None;
    };
    if rest.as_bytes().get(class_end) != Some(&b')') {
        return None;
    }
    let class = &rest[..class_end];
    let remainder = &rest[class_end + 1..];
    // The remainder must itself be free of look-around so it can run on the plain engine, and
    // must not have a top-level `|` (the lookbehind would bind only the first alternative).
    if remainder.contains("(?<") || remainder.contains("(?=") || remainder.contains("(?!") || has_backref(remainder) || has_top_level_alt(remainder) {
        return None;
    }
    Some((class.to_string(), negative, remainder.to_string()))
}

/// True when `p` has a `|` outside any group or class.
fn has_top_level_alt(p: &str) -> bool {
    let b = p.as_bytes();
    let (mut depth, mut i, mut in_class) = (0i32, 0usize, false);
    while i < b.len() {
        match b[i] {
            b'\\' => i += 1,
            b'[' if !in_class => in_class = true,
            b']' if in_class => in_class = false,
            b'(' if !in_class => depth += 1,
            b')' if !in_class => depth -= 1,
            b'|' if !in_class && depth == 0 => return true,
            _ => {}
        }
        i += 1;
    }
    false
}

/// The pattern with every `(?<!..)`, `(?<=..)`, `(?!..)` and `(?=..)` group removed, or None when it
/// has a backreference (removing look-arounds only widens the match, so the result is a superset
/// filter; a backreference cannot be widened this way).
fn strip_lookarounds(p: &str) -> Option<String> {
    if has_backref(p) {
        return None;
    }
    let b = p.as_bytes();
    let mut out = String::new();
    let mut i = 0;
    let mut in_class = false;
    while i < b.len() {
        let c = b[i];
        if c == b'\\' {
            out.push_str(&p[i..(i + 2).min(p.len())]);
            i += 2;
            continue;
        }
        if in_class {
            if c == b']' {
                in_class = false;
            }
            out.push(c as char);
            i += 1;
            continue;
        }
        if c == b'[' {
            in_class = true;
            out.push('[');
            i += 1;
            continue;
        }
        if p[i..].starts_with("(?<!") || p[i..].starts_with("(?<=") || p[i..].starts_with("(?!") || p[i..].starts_with("(?=") {
            // skip to the matching close paren
            let mut depth = 0i32;
            let mut j = i;
            let mut cls = false;
            while j < b.len() {
                match b[j] {
                    b'\\' => j += 1,
                    b'[' if !cls => cls = true,
                    b']' if cls => cls = false,
                    b'(' if !cls => depth += 1,
                    b')' if !cls => {
                        depth -= 1;
                        if depth == 0 {
                            break;
                        }
                    }
                    _ => {}
                }
                j += 1;
            }
            i = j + 1;
            continue;
        }
        let ch = p[i..].chars().next().unwrap();
        out.push(ch);
        i += ch.len_utf8();
    }
    Some(out)
}

fn has_backref(p: &str) -> bool {
    let b = p.as_bytes();
    let mut i = 0;
    while i + 1 < b.len() {
        if b[i] == b'\\' {
            if b[i + 1].is_ascii_digit() && b[i + 1] != b'0' {
                return true;
            }
            i += 2;
        } else {
            i += 1;
        }
    }
    false
}

impl Pat {
    /// Compiles `pattern` (search semantics). Panics on an invalid pattern: patterns are constants.
    pub fn new(pattern: &str) -> Pat {
        Self::try_new(pattern).unwrap_or_else(|e| panic!("bad pattern {:?}: {}", pattern, e))
    }

    /// A compiled pattern kept for the life of the process, keyed by its source. For patterns built
    /// at run time (`format!` with a var name) inside a loop: compiling per call dominated the
    /// profile of several lints.
    pub fn cached(pattern: &str) -> &'static Pat {
        static CACHE: std::sync::LazyLock<std::sync::RwLock<std::collections::HashMap<String, &'static Pat>>> =
            std::sync::LazyLock::new(Default::default);
        if let Some(p) = CACHE.read().unwrap().get(pattern) {
            return p;
        }
        let compiled: &'static Pat = Box::leak(Box::new(Pat::new(pattern)));
        CACHE.write().unwrap().entry(pattern.to_string()).or_insert(compiled)
    }

    pub fn try_new(pattern: &str) -> Result<Pat, String> {
        if let Some((class, negative, rest)) = split_leading_lookbehind(pattern) {
            if let (Ok(re), Ok(cls)) = (Regex::new(&rest), Regex::new(&format!("^(?:{})$", class))) {
                return Ok(Pat { src: pattern.to_string(), kind: Kind::Behind { re, class: cls, negative } });
            }
        }
        match Regex::new(pattern) {
            Ok(re) => Ok(Pat { src: pattern.to_string(), kind: Kind::Plain(re) }),
            Err(plain_err) => {
                let mut builder = fancy_regex::RegexBuilder::new(pattern);
                builder.backtrack_limit(50_000_000);
                match builder.build() {
                    Ok(re) => Ok(Pat { src: pattern.to_string(), kind: Kind::Fancy(re, strip_lookarounds(pattern).and_then(|p| Regex::new(&p).ok())) }),
                    Err(e) => Err(format!("{} / {}", plain_err, e)),
                }
            }
        }
    }

    /// `re.match`: the pattern must match at the start of the haystack.
    pub fn new_match(pattern: &str) -> Pat {
        Pat::new(&format!(r"\A(?:{})", pattern))
    }

    /// `re.fullmatch`.
    pub fn new_full(pattern: &str) -> Pat {
        Pat::new(&format!(r"\A(?:{})\z", pattern))
    }

    pub fn as_str(&self) -> &str {
        &self.src
    }

    fn behind_ok(hay: &str, start: usize, class: &Regex, negative: bool) -> bool {
        if start == 0 {
            return negative; // nothing before: a negative lookbehind holds, a positive one fails
        }
        let prev = hay[..start].chars().next_back().unwrap();
        let mut buf = [0u8; 4];
        let is = class.is_match(prev.encode_utf8(&mut buf));
        is != negative
    }

    /// First match at or after byte `pos`.
    pub fn find_at<'h>(&self, hay: &'h str, pos: usize) -> Option<M<'h>> {
        match &self.kind {
            Kind::Plain(re) => re.find_at(hay, pos).map(|m| M { start: m.start(), end: m.end(), hay }),
            Kind::Behind { re, class, negative } => {
                let mut at = pos;
                while at <= hay.len() {
                    let m = re.find_at(hay, at)?;
                    if Self::behind_ok(hay, m.start(), class, *negative) {
                        return Some(M { start: m.start(), end: m.end(), hay });
                    }
                    // retry just past this start
                    let step = hay[m.start()..].chars().next().map(|c| c.len_utf8()).unwrap_or(1);
                    at = m.start() + step;
                }
                None
            }
            Kind::Fancy(re, pre) => match if pre.as_ref().map(|p| !p.is_match(&hay[pos..])).unwrap_or(false) { Ok(None) } else { re.find_from_pos(hay, pos) } {
                Ok(Some(m)) => Some(M { start: m.start(), end: m.end(), hay }),
                _ => None,
            },
        }
    }

    pub fn find<'h>(&self, hay: &'h str) -> Option<M<'h>> {
        self.find_at(hay, 0)
    }

    pub fn is_match(&self, hay: &str) -> bool {
        match &self.kind {
            Kind::Plain(re) => re.is_match(hay),
            _ => self.find_at(hay, 0).is_some(),
        }
    }

    /// All non-overlapping matches (Python `finditer`).
    pub fn find_iter<'h>(&self, hay: &'h str) -> Vec<M<'h>> {
        let mut out = Vec::new();
        let mut pos = 0;
        while pos <= hay.len() {
            let Some(m) = self.find_at(hay, pos) else { break };
            pos = if m.end == m.start {
                m.end + hay[m.end..].chars().next().map(|c| c.len_utf8()).unwrap_or(1)
            } else {
                m.end
            };
            out.push(m);
        }
        out
    }

    /// Captures of the first match at or after `pos`.
    pub fn captures_at<'h>(&self, hay: &'h str, pos: usize) -> Option<Caps<'h>> {
        match &self.kind {
            Kind::Plain(re) => re.captures_at(hay, pos).map(|c| Caps {
                hay,
                groups: c.iter().map(|g| g.map(|m| (m.start(), m.end()))).collect(),
            }),
            Kind::Behind { re, class, negative } => {
                let mut at = pos;
                while at <= hay.len() {
                    let c = re.captures_at(hay, at)?;
                    let m0 = c.get(0).unwrap();
                    if Self::behind_ok(hay, m0.start(), class, *negative) {
                        return Some(Caps { hay, groups: c.iter().map(|g| g.map(|m| (m.start(), m.end()))).collect() });
                    }
                    let step = hay[m0.start()..].chars().next().map(|ch| ch.len_utf8()).unwrap_or(1);
                    at = m0.start() + step;
                }
                None
            }
            Kind::Fancy(re, pre) => match if pre.as_ref().map(|p| !p.is_match(&hay[pos..])).unwrap_or(false) { Ok(None) } else { re.captures_from_pos(hay, pos) } {
                Ok(Some(c)) => Some(Caps { hay, groups: c.iter().map(|g| g.map(|m| (m.start(), m.end()))).collect() }),
                _ => None,
            },
        }
    }

    pub fn captures<'h>(&self, hay: &'h str) -> Option<Caps<'h>> {
        self.captures_at(hay, 0)
    }

    pub fn captures_iter<'h>(&self, hay: &'h str) -> Vec<Caps<'h>> {
        let mut out = Vec::new();
        let mut pos = 0;
        while pos <= hay.len() {
            let Some(c) = self.captures_at(hay, pos) else { break };
            let (s, e) = c.groups[0].unwrap();
            pos = if e == s { e + hay[e..].chars().next().map(|ch| ch.len_utf8()).unwrap_or(1) } else { e };
            out.push(c);
        }
        out
    }

    /// `re.sub(pattern, repl, hay)` with a literal replacement (no group references).
    pub fn replace_all(&self, hay: &str, repl: &str) -> String {
        let mut out = String::with_capacity(hay.len());
        let mut last = 0;
        for m in self.find_iter(hay) {
            out.push_str(&hay[last..m.start]);
            out.push_str(repl);
            last = m.end;
        }
        out.push_str(&hay[last..]);
        out
    }

    /// `re.sub` with a closure over the captures.
    pub fn replace_with<F: FnMut(&Caps) -> String>(&self, hay: &str, mut f: F) -> String {
        let mut out = String::with_capacity(hay.len());
        let mut last = 0;
        for c in self.captures_iter(hay) {
            let (s, e) = c.groups[0].unwrap();
            out.push_str(&hay[last..s]);
            out.push_str(&f(&c));
            last = e;
        }
        out.push_str(&hay[last..]);
        out
    }
}

/// `pat!(r"...")`: a lazily compiled, process-wide `Pat`. Use for constant patterns.
#[macro_export]
macro_rules! pat {
    ($p:expr) => {{
        static P: ::std::sync::LazyLock<$crate::pat::Pat> = ::std::sync::LazyLock::new(|| $crate::pat::Pat::new($p));
        &*P
    }};
}

/// `pat_match!(r"...")`: `re.match` (anchored at the start).
#[macro_export]
macro_rules! pat_match {
    ($p:expr) => {{
        static P: ::std::sync::LazyLock<$crate::pat::Pat> =
            ::std::sync::LazyLock::new(|| $crate::pat::Pat::new_match($p));
        &*P
    }};
}

/// `pat_full!(r"...")`: `re.fullmatch`.
#[macro_export]
macro_rules! pat_full {
    ($p:expr) => {{
        static P: ::std::sync::LazyLock<$crate::pat::Pat> =
            ::std::sync::LazyLock::new(|| $crate::pat::Pat::new_full($p));
        &*P
    }};
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn leading_lookbehind_matches_python() {
        let p = Pat::new(r"(?<![\w.])spawn\s*\(");
        assert!(p.is_match("spawn(0)"));
        assert!(p.is_match("\tspawn (0)"));
        assert!(!p.is_match("foo.spawn(0)"));
        assert!(!p.is_match("respawn(0)"));
        // a failed first candidate must not hide a later one
        assert_eq!(p.find_iter("x.spawn(1) spawn(2)").len(), 1);
        assert_eq!(p.find_iter("spawn(1) spawn(2)").len(), 2);
    }

    #[test]
    fn lookbehind_binds_only_first_top_level_alternative() {
        let p = Pat::new(r"(?<![\w/])SEND\s*\(|\bHANDLER\b");
        assert!(p.is_match("x/HANDLER"));
        assert!(!p.is_match("x/SEND("));
        assert!(p.is_match("SEND("));
    }

    #[test]
    fn lookahead_goes_fancy() {
        let p = Pat::new(r"(?<![\w.])qdel\s*\((?!\s*src\s*[,)])");
        assert!(p.is_match("qdel(M)"));
        assert!(!p.is_match("qdel(src)"));
        assert!(p.is_match("qdel(src_thing)"));
    }

    #[test]
    fn captures_and_match_anchor() {
        let p = Pat::new_match(r"(/[\w/]+)\s*$");
        let c = p.captures("/obj/item").unwrap();
        assert_eq!(c.s(1), "/obj/item");
        assert!(p.captures(" /obj/item").is_none());
    }
}
