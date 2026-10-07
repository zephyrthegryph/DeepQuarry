//! The declarative core of the `check_grep` lint: a [`Part`] is one `rg`/`grep` pipeline of the old
//! script (a search, then `grep -v`-style filters over the printed `file:line:text` lines), written
//! as data and compiled once into a [`Compiled`] that scans one file at a time.
//!
//! The old script's output lines are reproduced exactly where it matters: a filter sees the
//! composite `rel:line:text` that `rg -n` / `grep -n` printed, so a path allowlist, a `:\s*//`
//! comment test and a `var/` substring all behave as they did in the shell.

use fancy_regex::RegexBuilder as FancyBuilder;
use regex::Regex;

use crate::lint::Sink;
use crate::lint::Cx;
use crate::tree::SourceFile;

/// A regex that is a plain `regex::Regex` when it can be and `fancy_regex` when it needs look-around.
pub enum Rx {
    /// `multi` is the same pattern with `(?m)`: a superset test over a whole file text (any line
    /// that matches alone also matches there), used to skip files that cannot have a hit.
    Plain { re: Regex, multi: Regex },
    Fancy(fancy_regex::Regex),
}

/// `\/` is not a legal escape for the `regex` crate; PCRE and grep accept it.
pub fn fix(p: &str) -> String {
    let mut out = String::with_capacity(p.len());
    let mut it = p.chars();
    while let Some(c) = it.next() {
        if c == '\\' {
            match it.next() {
                Some(c @ ('/' | '"' | '\'')) => out.push(c),
                Some(n) => {
                    out.push('\\');
                    out.push(n);
                }
                None => out.push('\\'),
            }
        } else {
            out.push(c);
        }
    }
    out
}

/// GNU `grep -P` runs PCRE2 in UTF mode without UCP: `\w`, `\s`, `\d`, `\b` are ASCII. Rewrites a
/// pattern to those classes (the `regex` crate's are Unicode).
pub fn ascii(p: &str) -> String {
    let b: Vec<char> = p.chars().collect();
    let mut out = String::with_capacity(p.len() + 16);
    let mut i = 0;
    let mut in_class = false;
    while i < b.len() {
        let c = b[i];
        if c == '\\' && i + 1 < b.len() {
            let n = b[i + 1];
            let rep: Option<&str> = match (n, in_class) {
                ('w', false) => Some("[A-Za-z0-9_]"),
                ('w', true) => Some("A-Za-z0-9_"),
                ('W', false) => Some("[^A-Za-z0-9_]"),
                ('s', false) => Some(r"[ \t\n\x0B\f\r]"),
                ('s', true) => Some(r" \t\n\x0B\f\r"),
                ('S', false) => Some(r"[^ \t\n\x0B\f\r]"),
                ('d', false) => Some("[0-9]"),
                ('d', true) => Some("0-9"),
                ('D', false) => Some("[^0-9]"),
                ('b', false) => Some(r"(?-u:\b)"),
                _ => None,
            };
            match rep {
                Some(r) => out.push_str(r),
                None => {
                    out.push(c);
                    out.push(n);
                }
            }
            i += 2;
            continue;
        }
        if !in_class && c == '[' {
            in_class = true;
            out.push(c);
            i += 1;
            if i < b.len() && b[i] == '^' {
                out.push('^');
                i += 1;
            }
            if i < b.len() && b[i] == ']' {
                out.push(']');
                i += 1;
            }
            continue;
        }
        if in_class && c == ']' {
            in_class = false;
        }
        out.push(c);
        i += 1;
    }
    out
}

impl Rx {
    pub fn new(pattern: &str) -> Rx {
        let p = fix(pattern);
        match Regex::new(&p) {
            Ok(re) => {
                let multi = Regex::new(&format!("(?m){}", p)).unwrap_or_else(|_| re.clone());
                Rx::Plain { re, multi }
            }
            Err(plain) => match FancyBuilder::new(&p).backtrack_limit(50_000_000).build() {
                Ok(r) => Rx::Fancy(r),
                Err(e) => panic!("check_grep: bad pattern {:?}: {} / {}", p, plain, e),
            },
        }
    }

    pub fn is_match(&self, s: &str) -> bool {
        match self {
            Rx::Plain { re, .. } => re.is_match(s),
            Rx::Fancy(r) => r.is_match(s).unwrap_or(false),
        }
    }

    /// False only when no line of `text` can match.
    pub fn may_match(&self, text: &str) -> bool {
        match self {
            Rx::Plain { multi, .. } => multi.is_match(text),
            Rx::Fancy(_) => true,
        }
    }

    /// First match at or after byte `pos`: (start, end).
    pub fn find_at(&self, text: &str, pos: usize) -> Option<(usize, usize)> {
        match self {
            Rx::Plain { re, .. } => re.find_at(text, pos).map(|m| (m.start(), m.end())),
            Rx::Fancy(r) => match r.find_from_pos(text, pos) {
                Ok(Some(m)) => Some((m.start(), m.end())),
                _ => None,
            },
        }
    }
}

/// Which files a part searches.
#[derive(Clone, Copy, Debug)]
pub enum Files {
    /// `code/**/**.dm` by the shell glob (no dot-files).
    Code,
    /// The same minus `__byond_version_compat.dm` (`code/**/!(__byond_version_compat).dm`).
    CodeX515,
    /// `maps/**/**.dmm` by the shell glob.
    Maps,
    /// `find` / `grep -R`: the listed files and directories, with these extensions, dot-files
    /// included, `node_modules` excluded.
    Under(&'static [&'static str], &'static [&'static str]),
}

fn under(rel: &str, path: &str) -> bool {
    rel == path || (rel.len() > path.len() && rel.starts_with(path) && rel.as_bytes()[path.len()] == b'/')
}

impl Files {
    pub fn matches(&self, f: &SourceFile) -> bool {
        let ext = f.ext();
        match self {
            Files::Code => ext == "dm" && !f.hidden && f.rel.starts_with("code/"),
            Files::CodeX515 => ext == "dm" && !f.hidden && f.rel.starts_with("code/") && f.rel.rsplit('/').next() != Some("__byond_version_compat.dm"),
            Files::Maps => ext == "dmm" && !f.hidden && f.rel.starts_with("maps/"),
            Files::Under(paths, exts) => {
                exts.contains(&ext) && paths.iter().any(|p| under(&f.rel, p)) && !f.rel.split('/').any(|c| c == "node_modules")
            }
        }
    }
}

/// How a whole-file search reports its matches.
#[derive(Clone, Copy, Debug)]
pub enum Lines {
    /// `rg -U`: every line the match touches.
    Span,
    /// `grep -z -o`: one hit per match, at the line it starts on.
    Start,
}

/// The search of a part.
#[derive(Clone)]
pub enum Find {
    /// Per line, the pattern as `rg` (or `rg -P`) ran it.
    Line(String),
    /// Per line, as GNU `grep -P` ran it (ASCII classes).
    LineG(String),
    /// Per line, case-insensitive (`rg -i`).
    LineI(String),
    /// Over the whole file text; `rg -PU` (`m`: multi-line anchors, Unicode classes) or `grep -Pz`.
    Multi { pat: String, lines: Lines, grep_z: bool, check: Option<fn(&str, usize, usize) -> bool> },
    /// `grep -l`: the first matching line of a file that has one.
    FileAny(String),
    /// Hand-written (a rule that is not a regex).
    Custom(fn(&SourceFile) -> Vec<usize>),
    /// Not a per-file search: the lint's `scan_tree` produces this rule's sites.
    Tree,
}

pub fn line(p: &str) -> Find {
    Find::Line(p.to_string())
}

pub fn line_g(p: &str) -> Find {
    Find::LineG(p.to_string())
}

pub fn line_i(p: &str) -> Find {
    Find::LineI(p.to_string())
}

/// `rg -PU`: whole file, multi-line anchors, every line of the match.
pub fn multi_u(p: &str) -> Find {
    Find::Multi { pat: p.to_string(), lines: Lines::Span, grep_z: false, check: None }
}

/// `grep -Pzo`: whole file, one hit per match.
pub fn multi_z(p: &str, check: Option<fn(&str, usize, usize) -> bool>) -> Find {
    Find::Multi { pat: p.to_string(), lines: Lines::Start, grep_z: true, check }
}

pub fn drop(p: &str) -> Flt {
    Flt::Drop(p.to_string())
}

pub fn keep(p: &str) -> Flt {
    Flt::Keep(p.to_string())
}

/// One stage of the shell pipeline after the search, over the composite line.
#[derive(Clone)]
pub enum Flt {
    /// `grep -v` / `rg -v` / `grep -vE`: drop a line the regex matches.
    Drop(String),
    /// `grep -E` / `grep -iE`: keep only a line the regex matches.
    Keep(String),
    KeepI(String),
    /// `grep -v 'literal'` (BRE with no specials): drop a line containing the text.
    DropLit(&'static str),
    /// `sed 's#//.*##'`.
    Strip,
    /// A path allowlist (`grep -v '^code/a|^code/b/'`): drop a hit whose file is in the named
    /// `[lint.check_grep.lists]` list: an exact file, or a directory written with a trailing `/`.
    DropPaths(&'static str),
    /// Keep only findings in the folders that completed a migration.
    KeepPaths(&'static str),
}

/// How a hit line is excused by an annotation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Allow {
    /// `allow_grep`: `ALLOW(...check_grep...): reason` on the line itself.
    Strict,
    /// `grep -v 'ALLOW([^)]*check_grep'`: the bare text.
    Loose,
    /// A plain `grep` that never looked.
    None,
}

#[derive(Clone)]
pub struct Part {
    /// The rule name: the slug of `title`, plus `__what` for a second check under the same title.
    pub rule: &'static str,
    /// The old script's `part "..."` title.
    pub title: &'static str,
    /// The old script's `ERROR:` text.
    pub msg: &'static str,
    pub files: Files,
    pub find: Find,
    pub allow: Allow,
    pub flt: Vec<Flt>,
    /// A literal every matching line contains: files without it are skipped (needed for a pattern
    /// that has look-around, where there is no whole-file prefilter).
    pub needle: Option<&'static str>,
    /// Rules of the same group are alternatives of an `a || b || c`: only the first with a hit counts.
    pub group: &'static str,
}

impl Part {
    pub fn new(rule: &'static str, title: &'static str, msg: &'static str, files: Files, find: Find) -> Part {
        Part { rule, title, msg, files, find, allow: Allow::None, flt: Vec::new(), needle: None, group: "" }
    }

    pub fn allow(mut self, a: Allow) -> Part {
        self.allow = a;
        self
    }

    pub fn flt(mut self, f: Vec<Flt>) -> Part {
        self.flt = f;
        self
    }

    pub fn needle(mut self, n: &'static str) -> Part {
        self.needle = Some(n);
        self
    }

    pub fn group(mut self, g: &'static str) -> Part {
        self.group = g;
        self
    }

    /// `[check_grep/rule]` hint: the title and the old error text.
    pub fn hint(&self) -> String {
        format!("{}: {}", self.title, self.msg)
    }

    pub fn compile(&self) -> Compiled {
        let find = match &self.find {
            Find::Line(p) => CFind::Line(Rx::new(p)),
            Find::LineG(p) => CFind::Line(Rx::new(&ascii(p))),
            Find::LineI(p) => CFind::Line(Rx::new(&format!("(?i){}", p))),
            Find::Multi { pat, lines, grep_z, check } => {
                let p = if *grep_z { ascii(pat) } else { format!("(?m){}", pat) };
                CFind::Multi { rx: Rx::new(&p), lines: *lines, check: *check }
            }
            Find::FileAny(p) => CFind::FileAny(Rx::new(p)),
            Find::Custom(f) => CFind::Custom(*f),
            Find::Tree => CFind::Tree,
        };
        let flt = self
            .flt
            .iter()
            .map(|f| match f {
                Flt::Drop(p) => CFlt::Drop(Rx::new(p)),
                Flt::Keep(p) => CFlt::Keep(Rx::new(p)),
                Flt::KeepI(p) => CFlt::Keep(Rx::new(&format!("(?i){}", p))),
                Flt::DropLit(s) => CFlt::DropLit(s),
                Flt::Strip => CFlt::Strip,
                Flt::DropPaths(k) => CFlt::DropPaths(k),
                Flt::KeepPaths(k) => CFlt::KeepPaths(k),
            })
            .collect();
        Compiled { rule: self.rule, files: self.files, find, allow: self.allow, flt, needle: self.needle }
    }
}

enum CFind {
    Line(Rx),
    Multi { rx: Rx, lines: Lines, check: Option<fn(&str, usize, usize) -> bool> },
    FileAny(Rx),
    Custom(fn(&SourceFile) -> Vec<usize>),
    Tree,
}

enum CFlt {
    Drop(Rx),
    Keep(Rx),
    DropLit(&'static str),
    Strip,
    DropPaths(&'static str),
    KeepPaths(&'static str),
}

pub struct Compiled {
    pub rule: &'static str,
    files: Files,
    find: CFind,
    allow: Allow,
    flt: Vec<CFlt>,
    needle: Option<&'static str>,
}

fn strict_allow() -> &'static Rx {
    static R: std::sync::LazyLock<Rx> =
        std::sync::LazyLock::new(|| Rx::new(r"ALLOW\([^)]*check_grep[^)]*\)[[:space:]]*:[[:space:]]*[^[:space:]]"));
    &R
}

fn loose_allow() -> &'static Rx {
    static R: std::sync::LazyLock<Rx> = std::sync::LazyLock::new(|| Rx::new(r"ALLOW\([^)]*check_grep"));
    &R
}

/// A path is in a list: the exact file, or under a directory entry written with a trailing `/`.
pub fn in_list(rel: &str, list: &[String]) -> bool {
    list.iter().any(|e| rel == e || (e.ends_with('/') && rel.starts_with(e.as_str())))
}

impl Compiled {
    /// The 1-based lines of `f` this search hits (a line twice for two `-o` matches).
    fn hits(&self, f: &SourceFile, text: &str) -> Vec<usize> {
        let raw = f.raw();
        match &self.find {
            CFind::Line(rx) => {
                if !rx.may_match(text) {
                    return Vec::new();
                }
                let n = raw.num_lines();
                let phantom = text.ends_with('\n') || text.is_empty();
                let mut out = Vec::new();
                for (no, line) in raw.numbered() {
                    // `text.split("\n")` ends with an empty line when the text ends in a newline;
                    // `rg` has no such line.
                    if no == n && phantom && line.is_empty() {
                        continue;
                    }
                    if rx.is_match(line) {
                        out.push(no);
                    }
                }
                out
            }
            CFind::FileAny(rx) => {
                if !rx.may_match(text) {
                    return Vec::new();
                }
                for (no, line) in raw.numbered() {
                    if rx.is_match(line) {
                        return vec![no];
                    }
                }
                Vec::new()
            }
            CFind::Multi { rx, lines, check } => {
                let mut out = Vec::new();
                let mut pos = 0;
                while pos <= text.len() {
                    let Some((s, e)) = rx.find_at(text, pos) else { break };
                    if let Some(c) = check {
                        if !c(text, s, e) {
                            // The look-around that was cut out of the pattern failed here: the
                            // search goes on from the next character, as a backtracking engine would.
                            pos = s + text[s..].chars().next().map(|c| c.len_utf8()).unwrap_or(1);
                            continue;
                        }
                    }
                    let first = raw.line_of(s);
                    match lines {
                        Lines::Start => out.push(first),
                        Lines::Span => {
                            let last = if e > s { raw.line_of(e - 1) } else { first };
                            for l in first..=last {
                                if !out.contains(&l) {
                                    out.push(l);
                                }
                            }
                        }
                    }
                    pos = if e > s { e } else { e + 1 };
                }
                out
            }
            CFind::Custom(func) => func(f),
            CFind::Tree => Vec::new(),
        }
    }

    pub fn scan(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        if !self.files.matches(f) {
            return;
        }
        let text = f.text();
        if let Some(n) = self.needle {
            if !text.contains(n) {
                return;
            }
        }
        let hits = self.hits(f, text);
        if hits.is_empty() {
            return;
        }
        let raw = f.raw();
        for line in hits {
            let mut comp = format!("{}:{}:{}", f.rel, line, raw.line(line));
            match self.allow {
                Allow::Strict => {
                    if strict_allow().is_match(&comp) {
                        let _ = out.allowed_here(f, line, "check_grep");
                        continue;
                    }
                }
                Allow::Loose => {
                    if loose_allow().is_match(&comp) {
                        continue;
                    }
                }
                Allow::None => {}
            }
            let mut keep = true;
            for flt in &self.flt {
                match flt {
                    CFlt::Drop(rx) => {
                        if rx.is_match(&comp) {
                            keep = false;
                        }
                    }
                    CFlt::Keep(rx) => {
                        if !rx.is_match(&comp) {
                            keep = false;
                        }
                    }
                    CFlt::DropLit(s) => {
                        if comp.contains(s) {
                            keep = false;
                        }
                    }
                    CFlt::Strip => {
                        if let Some(i) = comp.find("//") {
                            comp.truncate(i);
                        }
                    }
                    CFlt::DropPaths(key) => {
                        if in_list(&f.rel, cx.list(key)) {
                            keep = false;
                        }
                    }
                    CFlt::KeepPaths(key) => {
                        if !in_list(&f.rel, cx.list(key)) {
                            keep = false;
                        }
                    }
                }
                if !keep {
                    break;
                }
            }
            if keep {
                out.site(self.rule, line);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ascii_rewrites_shorthand_classes() {
        assert_eq!(ascii(r"\W/turf\s*[,\){]"), r"[^A-Za-z0-9_]/turf[ \t\n\x0B\f\r]*[,\){]");
        assert_eq!(ascii(r"[/\w]x[^\d]"), r"[/A-Za-z0-9_]x[^0-9]");
        assert_eq!(ascii(r"\\w"), r"\\w");
    }

    #[test]
    fn fix_drops_the_slash_escape() {
        assert_eq!(fix(r"a\/b[^\/\n]\\/"), r"a/b[^/\n]\\/");
    }

    #[test]
    fn plain_prefilter_is_a_superset() {
        let rx = Rx::new(r"^\tfoo$");
        assert!(rx.may_match("x\n\tfoo\ny"));
        assert!(rx.is_match("\tfoo"));
        assert!(!rx.may_match("x\n foo\ny"));
    }

    #[test]
    fn fancy_patterns_compile() {
        let rx = Rx::new(r"to_chat\((?!.*,).*\)");
        assert!(rx.is_match("to_chat(x)"));
        assert!(!rx.is_match("to_chat(x, y)"));
    }
}
