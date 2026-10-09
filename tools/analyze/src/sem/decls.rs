//! Declarations that expand to nothing in DM, read from source text.
//!
//! `CAPABILITIES(...)`, `STAT(...)`, `SOURCE_DEF(...)`, `READS_AS(...)`, `READS_FROM(...)` and the
//! rest are generator markers (`code/__defines/engine/markers.dm`): the compiler discards their
//! arguments, so the analysis engine reads them here, from comment-stripped text with balanced
//! parentheses (a marker may span lines). Everything is per file and parallel; the merged
//! [`Decls`] is memoized on the tree.
//!
//! Also collected here, because they too leave no AST: relation declarations
//! (`REL/OWN/...(/type, var)`), tracked-var declarations (`TRACKED/SETTER/OM_FIELD...`),
//! `#define` names (for id resolution) and `PUBLISH_CHANGE(E, KEY)` producers.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::Arc;

use crate::tree::{SourceFile, Tree, CODE_DM};
use crate::{pat, pat_match};

/// Marker names the engine reads at the start of a statement.
pub const MARKERS: &[&str] = &[
    "CAPABILITIES",
    "CAPABILITY_DEF",
    "CAPABILITY_TYPE",
    "cap_keys",
    "ACTION",
    "STAT",
    "SCHEMA",
    "TRACKED_SCHEMA",
    "SYSTEM_ACCESSOR",
    "STAGE_DEF",
    "STATE_GRAPH",
    "RESOURCE_DEF",
    "SOURCE_DEF",
    "READS_AS",
    "READS_FROM",
    "STATIC_ENTRY",
];

/// Markers whose entries may follow as an indented block (doc/rewrite/final_api.html section 1).
pub const BLOCK_MARKERS: &[&str] = &["CAPABILITIES", "CAPABILITY_DEF", "STATE_GRAPH"];

/// The marker the scan makes for an entry proc: a global `/proc/name(...)` whose first statement is `return list(...)` of declaration
/// entries (`op(`, `extend(`, `interface(`, ...). It is the plain-proc form of reuse (doc section 11): a CAPABILITIES block that names
/// `name()` gets those entries, so what reads a block (op keys, handlers, UI types, op order) reads the proc's entries the same way.
/// `args[0]` is the proc's name, the rest are the list's entries; `body` is the text inside `list(...)`.
pub const ENTRY_PROC: &str = "ENTRY_PROC";

/// Calls that make a returned list a list of declaration entries.
const ENTRY_CALLS: &[&str] = &["op(", "extend(", "interface(", "ui_shape(", "on_notice(", "on_change(", "without(", "configure("];

/// The end offset (exclusive, trailing blanks trimmed) of the indented block that follows the marker whose `)` is at `close`,
/// or None when no indented line follows it (the legacy single-macro form, or a header with no entries).
pub fn block_extent(text: &str, close: usize) -> Option<usize> {
    let rest = &text[close + 1..];
    let eol = rest.find('\n').unwrap_or(rest.len());
    if !rest[..eol].trim().is_empty() {
        return None;
    }
    let mut pos = close + 1 + eol;
    let mut end: Option<usize> = None;
    while pos < text.len() {
        // `pos` is at a newline; the next line starts after it.
        let ls = pos + 1;
        if ls > text.len() {
            break;
        }
        let le = text[ls..].find('\n').map(|i| ls + i).unwrap_or(text.len());
        let line = &text[ls..le];
        if line.trim().is_empty() {
            pos = le;
            continue;
        }
        if !line.starts_with(|c: char| c.is_whitespace()) {
            break;
        }
        end = Some(ls + line.trim_end().len());
        pos = le;
    }
    end
}

/// The marker body of a block: `text[from..end]` with the header's `)` and each top-level entry-ending newline replaced by a comma
/// (same length, so offsets and lines are unchanged). The engine then reads one argument list in either form.
pub fn block_body(text: &str, from: usize, close: usize, end: usize) -> String {
    let b = text.as_bytes();
    let mut out: Vec<u8> = b[from..end].to_vec();
    out[close - from] = b',';
    let mut depth = 0i32;
    let mut in_str = false;
    let mut pending: Option<usize> = None; // the last depth-0 newline since the previous entry's text
    let mut seen_entry = false;
    let mut i = close + 1;
    while i < end {
        let c = b[i];
        if in_str {
            if c == b'\\' {
                i += 1;
            } else if c == b'"' {
                in_str = false;
            }
            i += 1;
            continue;
        }
        if depth == 0 && !c.is_ascii_whitespace() {
            // An entry starts here: the newline before it ended the previous one.
            if let Some(nl) = pending.take() {
                if seen_entry {
                    out[nl - from] = b',';
                }
            }
            seen_entry = true;
        }
        match c {
            b'"' => in_str = true,
            b'(' | b'[' | b'{' => depth += 1,
            b')' | b']' | b'}' => depth -= 1,
            b'\n' if depth == 0 => pending = Some(i),
            _ => {}
        }
        i += 1;
    }
    String::from_utf8(out).unwrap_or_default()
}

/// One marker call: its name, raw argument text and top-level arguments, and where it starts.
#[derive(Clone, Debug)]
pub struct Marker {
    pub name: String,
    pub rel: String,
    /// 1-based line of the marker name.
    pub line: u32,
    /// Text between the outer parentheses, comments stripped.
    pub body: String,
    /// `body` split at top-level commas, trimmed.
    pub args: Vec<String>,
    /// Absolute byte offset of `body` in the stripped file text (for line arithmetic).
    pub body_offset: usize,
    /// Line of each `\n` start inside the file, shared: `line_of(offset)` gives a 1-based line.
    pub line_starts: Arc<Vec<u32>>,
}

impl Marker {
    /// The 1-based file line of a byte offset into `body`.
    pub fn line_at(&self, body_off: usize) -> u32 {
        let abs = (self.body_offset + body_off) as u32;
        match self.line_starts.binary_search(&abs) {
            Ok(i) => i as u32 + 1,
            Err(i) => i as u32,
        }
    }
}

#[derive(Default)]
pub struct Decls {
    pub markers: Vec<Marker>,
    /// type path -> relation vars declared with REL/OWN/... (and `relations()` bodies).
    pub relations: HashMap<String, HashSet<String>>,
    /// type path -> tracked vars (TRACKED / SETTER / OM_FIELD ...).
    pub tracked: HashMap<String, HashSet<String>>,
    /// Every `#define NAME` in the tree.
    pub defines: HashSet<String>,
    /// KEY text -> producer sites of `PUBLISH_CHANGE(E, KEY)`.
    pub publishers: BTreeMap<String, Vec<(String, u32)>>,
    /// String-literal key references in `extend/without/configure/perform_op/...` calls.
    pub key_refs: Vec<KeyRef>,
    /// `source = "text"` / `source = null` arguments of hold/grant/release calls.
    pub bad_sources: Vec<(String, u32, String)>,
    /// The ops a capability datum declares in its own `entries()` (type path, op name): a CAPABILITY_TYPE marker carries no entries.
    pub entry_ops: Vec<(String, String)>,
    /// A digest of everything above as read from the files (the cache key of results derived from it).
    pub key: u128,
}

/// What a key literal names, by the call it sits in (doc/rewrite/final_api.html section 4,
/// "Three kinds of key").
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum KeyKind {
    Op,
    Capability,
}

#[derive(Clone, Debug)]
pub struct KeyRef {
    pub kind: KeyKind,
    pub key: String,
    /// The call it sits in.
    pub call: String,
    pub rel: String,
    pub line: u32,
}

/// Calls whose string-literal arguments are op keys, and those whose first literal is a capability key.
pub const OP_KEY_CALLS: &[&str] = &["extend", "without", "on_op", "shares_effects", "above", "perform_op", "e0_perform_op"];
pub const CAP_KEY_CALLS: &[&str] = &["configure"];
/// Calls whose `source =` argument must be a datum or SRC_*, never text or null.
pub const SOURCE_CALLS: &[&str] = &["hold", "hold_until", "hold_override", "grant", "release", "status_end"];

impl Decls {
    pub fn get(tree: &Tree) -> Arc<Decls> {
        tree.memo("sem/decls", || {
            let t_decls = std::time::Instant::now();
            let files = tree.select(&CODE_DM);
            // Per file, cached on disk by content: a one-file edit rescans one file.
            let stored: Vec<Stored> = crate::incr::facts("sem-decls", &files, |f| Stored::from(scan_file(f)));
            let default = Stored::default();
            let nonempty: Vec<(&str, &Stored)> = files.iter().zip(stored.iter()).filter(|(_, s)| **s != default).map(|(f, s)| (f.rel.as_str(), s)).collect();
            let key = crate::incr::ctx_key(&nonempty);
            let parts: Vec<FileDecls> = stored.into_iter().map(FileDecls::from).collect();
            let mut d = Decls { key, ..Decls::default() };
            for p in parts {
                d.markers.extend(p.markers);
                for (t, v) in p.relations {
                    d.relations.entry(t).or_default().insert(v);
                }
                for (t, v) in p.tracked {
                    d.tracked.entry(t).or_default().insert(v);
                }
                d.defines.extend(p.defines);
                d.key_refs.extend(p.key_refs);
                d.bad_sources.extend(p.bad_sources);
                d.entry_ops.extend(p.entry_ops);
                for (k, s) in p.publishers {
                    d.publishers.entry(k).or_default().push(s);
                }
            }
            d.markers.sort_by(|a, b| (a.rel.as_str(), a.line).cmp(&(b.rel.as_str(), b.line)));
            // The relation entries of CAPABILITIES(T, ...) blocks (E1's declaration forms) declare their vars relations of T; link(/A::a, /B::b)
            // declares `a` on /A and `b` on /B.
            let own = regex::Regex::new(r"\b(?:owns_one|owns_many|ref_one|ref_many)\(\s*nameof\((\w+)\)").expect("relation entry pattern");
            let link = regex::Regex::new(r"\blinks?\(\s*(/[\w/]+)::(\w+)\s*,\s*(/[\w/]+)::(\w+)").expect("link entry pattern");
            let mut found: Vec<(String, String)> = Vec::new();
            for m in d.markers.iter().filter(|m| m.name == "CAPABILITIES") {
                if let Some(ty) = m.args.first() {
                    for c in own.captures_iter(&m.body) {
                        found.push((ty.clone(), c[1].to_string()));
                    }
                }
                for c in link.captures_iter(&m.body) {
                    found.push((c[1].to_string(), c[2].to_string()));
                    found.push((c[3].to_string(), c[4].to_string()));
                }
            }
            for (t, v) in found {
                d.relations.entry(t).or_default().insert(v);
            }
            if std::env::var("DQ_ANALYZE_TRACE").is_ok() {
                eprintln!("analyze: Decls built in {:.0?} ({} markers, {} defines)", t_decls.elapsed(), d.markers.len(), d.defines.len());
            }
            d
        })
    }

    pub fn markers_named<'a>(&'a self, name: &'a str) -> impl Iterator<Item = &'a Marker> + 'a {
        self.markers.iter().filter(move |m| m.name == name)
    }

    pub fn is_relation(&self, ty: &str, var: &str) -> bool {
        self.relations.get(ty).map(|s| s.contains(var)).unwrap_or(false)
    }
}

/// The on-disk form of a [`FileDecls`] (a marker's shared line table is stored once per file).
#[derive(serde::Serialize, serde::Deserialize, Default, PartialEq)]
struct Stored {
    key_refs: Vec<(u8, String, String, String, u32)>,
    bad_sources: Vec<(String, u32, String)>,
    /// (name, rel, line, body, args, body_offset)
    markers: Vec<(String, String, u32, String, Vec<String>, usize)>,
    line_starts: Vec<u32>,
    relations: Vec<(String, String)>,
    tracked: Vec<(String, String)>,
    defines: Vec<String>,
    publishers: Vec<(String, (String, u32))>,
    entry_ops: Vec<(String, String)>,
}

impl From<FileDecls> for Stored {
    fn from(f: FileDecls) -> Stored {
        let line_starts = f.markers.first().map(|m| m.line_starts.as_ref().clone()).unwrap_or_default();
        Stored {
            key_refs: f.key_refs.into_iter().map(|k| (matches!(k.kind, KeyKind::Capability) as u8, k.key, k.call, k.rel, k.line)).collect(),
            bad_sources: f.bad_sources,
            markers: f.markers.into_iter().map(|m| (m.name, m.rel, m.line, m.body, m.args, m.body_offset)).collect(),
            line_starts,
            relations: f.relations,
            tracked: f.tracked,
            defines: f.defines,
            publishers: f.publishers,
            entry_ops: f.entry_ops,
        }
    }
}

impl From<Stored> for FileDecls {
    fn from(s: Stored) -> FileDecls {
        let starts = Arc::new(s.line_starts);
        FileDecls {
            key_refs: s.key_refs.into_iter().map(|(k, key, call, rel, line)| KeyRef { kind: if k == 1 { KeyKind::Capability } else { KeyKind::Op }, key, call, rel, line }).collect(),
            bad_sources: s.bad_sources,
            markers: s.markers.into_iter().map(|(name, rel, line, body, args, body_offset)| Marker { name, rel, line, body, args, body_offset, line_starts: starts.clone() }).collect(),
            relations: s.relations,
            tracked: s.tracked,
            defines: s.defines,
            publishers: s.publishers,
            entry_ops: s.entry_ops,
        }
    }
}

struct FileDecls {
    key_refs: Vec<KeyRef>,
    bad_sources: Vec<(String, u32, String)>,
    markers: Vec<Marker>,
    relations: Vec<(String, String)>,
    tracked: Vec<(String, String)>,
    defines: Vec<String>,
    publishers: Vec<(String, (String, u32))>,
    entry_ops: Vec<(String, String)>,
}

/// `text` with comments blanked (same length, newlines kept); strings are kept intact.
pub fn strip_comments_keep_strings(text: &str) -> String {
    let b = text.as_bytes();
    let mut out = b.to_vec();
    let mut i = 0;
    let n = b.len();
    while i < n {
        match b[i] {
            b'"' => {
                // A string: skip to the closing quote ("\\" escapes; `[ ]` interpolation is left alone).
                i += 1;
                while i < n && b[i] != b'"' && b[i] != b'\n' {
                    if b[i] == b'\\' && i + 1 < n {
                        i += 1;
                    }
                    i += 1;
                }
                i += 1;
            }
            b'\'' => {
                i += 1;
                while i < n && b[i] != b'\'' && b[i] != b'\n' {
                    i += 1;
                }
                i += 1;
            }
            b'/' if i + 1 < n && b[i + 1] == b'/' => {
                while i < n && b[i] != b'\n' {
                    out[i] = b' ';
                    i += 1;
                }
            }
            b'/' if i + 1 < n && b[i + 1] == b'*' => {
                let mut depth = 0;
                while i < n {
                    if i + 1 < n && b[i] == b'/' && b[i + 1] == b'*' {
                        depth += 1;
                        out[i] = b' ';
                        out[i + 1] = b' ';
                        i += 2;
                    } else if i + 1 < n && b[i] == b'*' && b[i + 1] == b'/' {
                        depth -= 1;
                        out[i] = b' ';
                        out[i + 1] = b' ';
                        i += 2;
                        if depth == 0 {
                            break;
                        }
                    } else {
                        if b[i] != b'\n' {
                            out[i] = b' ';
                        }
                        i += 1;
                    }
                }
            }
            _ => i += 1,
        }
    }
    String::from_utf8(out).unwrap_or_default()
}

/// Splits `s` at top-level commas (not inside (), [], {} or strings), trimming each piece.
pub fn split_args(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut depth = 0i32;
    let mut cur = String::new();
    let mut in_str = false;
    let mut prev = '\0';
    for c in s.chars() {
        if in_str {
            cur.push(c);
            if c == '"' && prev != '\\' {
                in_str = false;
            }
            prev = c;
            continue;
        }
        match c {
            '"' => {
                in_str = true;
                cur.push(c);
            }
            '(' | '[' | '{' => {
                depth += 1;
                cur.push(c);
            }
            ')' | ']' | '}' => {
                depth -= 1;
                cur.push(c);
            }
            ',' if depth == 0 => {
                out.push(cur.trim().to_string());
                cur.clear();
            }
            _ => cur.push(c),
        }
        prev = c;
    }
    let last = cur.trim().to_string();
    if !last.is_empty() || !out.is_empty() {
        out.push(last);
    }
    out
}

/// Index of the `)` matching the `(` at `open` in `s`, or None.
pub fn matching_paren(s: &str, open: usize) -> Option<usize> {
    let b = s.as_bytes();
    let mut depth = 0i32;
    let mut in_str = false;
    let mut i = open;
    while i < b.len() {
        let c = b[i];
        if in_str {
            if c == b'\\' {
                i += 1;
            } else if c == b'"' {
                in_str = false;
            }
        } else {
            match c {
                b'"' => in_str = true,
                b'(' => depth += 1,
                b')' => {
                    depth -= 1;
                    if depth == 0 {
                        return Some(i);
                    }
                }
                _ => {}
            }
        }
        i += 1;
    }
    None
}

/// The ENTRY_PROC marker of a global proc whose first statement (`t`, on `line`) is `return list(...)` holding declaration entries.
#[allow(clippy::too_many_arguments)]
fn entry_proc(stripped: &str, starts: &Arc<Vec<u32>>, ln0: usize, line: &str, t: &str, name: String, head_line: u32, rel: &str, out: &mut Vec<Marker>) {
    let Some(rest) = t.strip_prefix("return") else { return };
    let rest = rest.trim_start();
    let Some(after) = rest.strip_prefix("list") else { return };
    if !after.trim_start().starts_with('(') {
        return;
    }
    let open = starts[ln0] as usize + (line.len() - rest.len()) + rest.find('(').unwrap();
    let Some(close) = matching_paren(stripped, open) else { return };
    let body = stripped[open + 1..close].to_string();
    if !ENTRY_CALLS.iter().any(|c| body.contains(c)) {
        return;
    }
    let mut args = vec![name];
    args.extend(split_args(&body));
    out.push(Marker { name: ENTRY_PROC.to_string(), rel: rel.to_string(), line: head_line, args, body, body_offset: open + 1, line_starts: starts.clone() });
}

fn scan_file(f: &SourceFile) -> FileDecls {
    let text = f.text();
    let stripped = strip_comments_keep_strings(text);
    let mut starts: Vec<u32> = vec![0];
    for (i, b) in stripped.bytes().enumerate() {
        if b == b'\n' {
            starts.push((i + 1) as u32);
        }
    }
    let starts = Arc::new(starts);
    let mut fd = FileDecls { key_refs: Vec::new(), bad_sources: Vec::new(), markers: Vec::new(), relations: Vec::new(), tracked: Vec::new(), defines: Vec::new(), publishers: Vec::new(), entry_ops: Vec::new() };
    // The datum whose `entries()` body the scan is inside (the proc is declared at column 0 as `/datum/x/entries()`).
    let mut entries_of: Option<String> = None;
    // A global proc (name, header line) whose first statement has not been seen yet: an entry proc when it is `return list(entries)`.
    let mut proc_head: Option<(String, u32)> = None;
    for (ln0, line) in stripped.split('\n').enumerate() {
        let ln = ln0 as u32 + 1;
        let t = line.trim_start();
        if !line.is_empty() && !line.starts_with(|c: char| c.is_whitespace()) {
            proc_head = pat_match!(r"^/proc/(\w+)\([^)]*\)\s*$").captures(line).map(|m| (m.s(1).to_string(), ln));
        } else if !t.is_empty() && !t.starts_with('#') {
            if let Some((name, head_line)) = proc_head.take() {
                entry_proc(&stripped, &starts, ln0, line, t, name, head_line, &f.rel, &mut fd.markers);
            }
        }
        if !line.is_empty() && !line.starts_with(|c: char| c.is_whitespace()) {
            entries_of = pat_match!(r"^(/datum/[\w/]+)/entries\(\)").captures(line).map(|m| m.s(1).to_string());
        } else if let Some(ty) = &entries_of {
            for m in pat!(r#"(?<![\w./])op\(\s*"([^"]+)""#).captures_iter(line) {
                fd.entry_ops.push((ty.clone(), m.s(1).to_string()));
            }
        }
        if let Some(rest) = t.strip_prefix('#') {
            if let Some(m) = pat_match!(r"\s*define\s+(\w+)").captures(rest) {
                fd.defines.push(m.s(1).to_string());
            }
            continue;
        }
        if t.is_empty() {
            continue;
        }
        // Marker at statement start.
        let name_end = t.find(|c: char| !(c.is_alphanumeric() || c == '_')).unwrap_or(t.len());
        let name = &t[..name_end];
        if MARKERS.contains(&name) && t[name_end..].trim_start().starts_with('(') {
            let line_off = starts[ln0] as usize;
            let col = line.len() - t.len() + name_end;
            let open = line_off + col + t[name_end..].find('(').unwrap();
            if let Some(close) = matching_paren(&stripped, open) {
                // Block form (`CAPABILITIES(T)` followed by indented entry statements): the body is the header's arguments and
                // the entries, joined with commas in place of the entry-ending newlines, so every byte keeps its offset.
                let at_col0 = line.len() == t.len();
                let block_end = if at_col0 && BLOCK_MARKERS.contains(&name) { block_extent(&stripped, close) } else { None };
                let body = match block_end {
                    Some(end) => block_body(&stripped, open + 1, close, end),
                    None => stripped[open + 1..close].to_string(),
                };
                fd.markers.push(Marker {
                    name: name.to_string(),
                    rel: f.rel.clone(),
                    line: ln,
                    args: split_args(&body),
                    body,
                    body_offset: open + 1,
                    line_starts: starts.clone(),
                });
            }
        }
        if let Some(m) = pat_match!(r"(?:TRACKED|TRACKED_BRIDGED|SETTER)\(\s*(/[\w/]+)\s*,\s*(\w+)").captures(t) {
            fd.tracked.push((m.s(1).to_string(), m.s(2).to_string()));
        }
        if let Some(m) = pat_match!(r"(?:OWN|OWN_POLICY|OWN_IF|REL|REL_LIST|REL_PAIR|REL_PAIR_LIST|REL_SET|REL_KEYED|REL_KEYED_LIST)\(\s*(/[\w/]+)\s*,\s*(\w+)").captures(t) {
            fd.relations.push((m.s(1).to_string(), m.s(2).to_string()));
        }
        let om = pat_match!(r"(?:OM_FIELD|OM_FLAG_FIELD|OM_FLAG_FIELD_BITS|OM_FIELD_SETTER)\(\s*(/[\w/]+)\s*,\s*(\w+)")
            .captures(t)
            .or_else(|| pat_match!(r"OM_FIELD_TYPED\(\s*(/[\w/]+)\s*,\s*[\w/]+\s*,\s*(\w+)").captures(t));
        if let Some(m) = om {
            fd.tracked.push((m.s(1).to_string(), m.s(2).to_string()));
        }
        if t.contains("PUBLISH_CHANGE(") {
            for m in pat!(r"PUBLISH_CHANGE\(\s*[^,()]+,\s*([\w#]+)\s*\)").captures_iter(t) {
                fd.publishers.push((m.s(1).trim_start_matches('#').to_string(), (f.rel.clone(), ln)));
            }
        }
    }
    scan_calls(f, &stripped, &starts, &mut fd);
    fd
}

/// Finds `name(...)` calls of the key/source families in comment-stripped text.
fn scan_calls(f: &SourceFile, stripped: &str, starts: &[u32], fd: &mut FileDecls) {
    static RE: std::sync::LazyLock<crate::pat::Pat> =
        std::sync::LazyLock::new(|| crate::pat::Pat::new(r"(?<![\w./])(extend|without|on_op|shares_effects|above|perform_op|e0_perform_op|configure|hold|hold_until|hold_override|grant|release|status_end)\s*\("));
    let line_of = |off: usize| -> u32 {
        match starts.binary_search(&(off as u32)) {
            Ok(i) => i as u32 + 1,
            Err(i) => i as u32,
        }
    };
    for m in RE.captures_iter(stripped) {
        let name = m.s(1);
        let open = m.end(0) - 1;
        let Some(close) = matching_paren(stripped, open) else { continue };
        let body = &stripped[open + 1..close];
        let line = line_of(m.start(1));
        let args = split_args(body);
        if OP_KEY_CALLS.contains(&name) {
            for a in &args {
                if let Some(s) = a.strip_prefix('"').and_then(|s| s.strip_suffix('"')) {
                    // `[x]` interpolation makes it a runtime value, not a key.
                    if !s.is_empty() && !s.contains('[') && !s.contains(' ') {
                        fd.key_refs.push(KeyRef { kind: KeyKind::Op, key: s.to_string(), call: name.to_string(), rel: f.rel.clone(), line });
                    }
                }
            }
        }
        if CAP_KEY_CALLS.contains(&name) {
            if let Some(s) = args.first().and_then(|a| a.strip_prefix('"')).and_then(|s| s.strip_suffix('"')) {
                if !s.is_empty() && !s.contains('[') {
                    fd.key_refs.push(KeyRef { kind: KeyKind::Capability, key: s.to_string(), call: name.to_string(), rel: f.rel.clone(), line });
                }
            }
        }
        if SOURCE_CALLS.contains(&name) {
            for a in &args {
                let compact = a.replace(' ', "");
                if let Some(v) = compact.strip_prefix("source=") {
                    if v == "null" || v.starts_with('"') {
                        fd.bad_sources.push((f.rel.clone(), line, v.to_string()));
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_top_level_commas_only() {
        assert_eq!(split_args("a, f(b, c), \"x,y\", [1,2]"), vec!["a", "f(b, c)", "\"x,y\"", "[1,2]"]);
    }

    #[test]
    fn strips_comments_but_keeps_strings_and_newlines() {
        let s = strip_comments_keep_strings("a // x\nb \"//keep\" /* c\n d */ e\n");
        assert_eq!(s.matches('\n').count(), 3);
        assert!(s.contains("\"//keep\""));
        assert!(!s.contains(" x"));
    }

    #[test]
    fn a_marker_can_span_lines() {
        let f = SourceFile::from_text("code/a.dm", "STAT(/obj, foo,\n\tALL,\n\tbase = 1)\n");
        let d = scan_file(&f);
        assert_eq!(d.markers.len(), 1);
        assert_eq!(d.markers[0].args, vec!["/obj", "foo", "ALL", "base = 1"]);
        assert_eq!(d.markers[0].line, 1);
    }

    #[test]
    fn a_global_proc_returning_entries_is_an_entry_proc() {
        let f = SourceFile::from_text(
            "code/a.dm",
            "/proc/door_controls()\n\t// the buttons\n\treturn list(op(\"bolt\", ui_act()),\n\t\textend(\"open\", needs(x())))\n/proc/parts()\n\treturn list(tool(TOOL_CROWBAR))\n/proc/later()\n\tvar/x = 1\n\treturn list(op(\"y\"))\n",
        );
        let d = scan_file(&f);
        let procs: Vec<&Marker> = d.markers.iter().filter(|m| m.name == ENTRY_PROC).collect();
        assert_eq!(procs.len(), 1, "only a first-statement list of entries: {:?}", procs.iter().map(|m| &m.args).collect::<Vec<_>>());
        assert_eq!(procs[0].args, vec!["door_controls", "op(\"bolt\", ui_act())", "extend(\"open\", needs(x()))"]);
        assert_eq!(procs[0].line, 1);
        assert_eq!(procs[0].line_at(procs[0].body.find("extend").unwrap()), 4);
    }
}

#[cfg(test)]
mod block_tests {
    use super::*;

    fn legacy_text() -> String {
        let bs = char::from(92u8);
        format!("CAPABILITIES(/obj/thing, {bs}\n\ta(1, 2), {bs}\n\tb(\"x,y\",\n\t\tc()))\n/obj/thing/proc/x()\n\treturn 1\n")
    }

    #[test]
    fn a_block_marker_reads_like_the_legacy_list() {
        let legacy = SourceFile::from_text("code/a.dm", &legacy_text());
        let block = SourceFile::from_text("code/a.dm", "CAPABILITIES(/obj/thing)\n\ta(1, 2)\n\tb(\"x,y\",\n\t\tc())\n\n/obj/thing/proc/x()\n\treturn 1\n");
        let (l, b) = (scan_file(&legacy), scan_file(&block));
        assert_eq!(l.markers.len(), 1);
        assert_eq!(b.markers.len(), 1);
        assert_eq!(b.markers[0].line, 1);
        let strip = |a: &[String]| -> Vec<String> { a.iter().map(|s| s.trim_start_matches(|c: char| c == char::from(92u8) || c.is_whitespace()).to_string()).collect() };
        assert_eq!(strip(&l.markers[0].args), strip(&b.markers[0].args));
        assert_eq!(b.markers[0].args.len(), 3, "{:?}", b.markers[0].args);
        // Offsets still map to the real lines: the third entry starts on line 3.
        let body = &b.markers[0].body;
        let off = body.find("b(").unwrap();
        assert_eq!(b.markers[0].line_at(off), 3);
    }

    #[test]
    fn no_indented_line_is_no_block() {
        let f = SourceFile::from_text("code/a.dm", "CAPABILITY_DEF(x, CAP_X, key = NONE)\n\n/datum/capability/def/x/entries()\n\treturn list()\n");
        let d = scan_file(&f);
        assert_eq!(d.markers.len(), 1);
        assert_eq!(d.markers[0].args, vec!["x", "CAP_X", "key = NONE"]);
    }

    #[test]
    fn a_block_ends_at_the_next_column_zero_line() {
        let f = SourceFile::from_text("code/a.dm", "STATE_GRAPH(GRAPH_X)\n\tstart(STAGE_A)\n\n\tstage(STAGE_B, then(PROC_REF(y)))\n/obj/thing/proc/x()\n\treturn 1\n");
        let d = scan_file(&f);
        assert_eq!(d.markers[0].args, vec!["GRAPH_X", "start(STAGE_A)", "stage(STAGE_B, then(PROC_REF(y)))"]);
    }
}
