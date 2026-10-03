//! Reports and records: the run summary, `residue.json`, `keys.json`, the revert record and a small JSON
//! reader for them (the crate has no JSON dependency and these files are ours).
//!
//! Every writer here is deterministic: sorted input, fixed key order, no timestamps and no absolute paths.

use std::fmt::Write as _;

use super::keys::KeyReport;
use super::{Codemod, FileChange, Inverse, ResidueSite, RunResult, FRAMEWORK_REASONS};

// ---------------------------------------------------------------------------------------------------------
// JSON

#[derive(Clone, Debug, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(i64),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

impl Json {
    pub fn get(&self, k: &str) -> Option<&Json> {
        match self {
            Json::Obj(v) => v.iter().find(|(n, _)| n == k).map(|(_, v)| v),
            _ => None,
        }
    }
    pub fn str(&self) -> Option<&str> {
        match self {
            Json::Str(s) => Some(s),
            _ => None,
        }
    }
    pub fn num(&self) -> Option<i64> {
        match self {
            Json::Num(n) => Some(*n),
            _ => None,
        }
    }
    pub fn arr(&self) -> &[Json] {
        match self {
            Json::Arr(v) => v,
            _ => &[],
        }
    }
}

pub fn esc(s: &str) -> String {
    let mut o = String::with_capacity(s.len() + 2);
    o.push('"');
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            '\t' => o.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let _ = write!(o, "\\u{:04x}", c as u32);
            }
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

pub fn parse_json(text: &str) -> Result<Json, String> {
    let b: Vec<char> = text.chars().collect();
    let mut i = 0;
    let v = value(&b, &mut i)?;
    skip(&b, &mut i);
    if i != b.len() {
        return Err(format!("trailing text at {}", i));
    }
    Ok(v)
}

fn skip(b: &[char], i: &mut usize) {
    while *i < b.len() && b[*i].is_whitespace() {
        *i += 1;
    }
}

fn value(b: &[char], i: &mut usize) -> Result<Json, String> {
    skip(b, i);
    match b.get(*i) {
        None => Err("unexpected end".into()),
        Some('{') => {
            *i += 1;
            let mut v = Vec::new();
            skip(b, i);
            if b.get(*i) == Some(&'}') {
                *i += 1;
                return Ok(Json::Obj(v));
            }
            loop {
                skip(b, i);
                let k = match value(b, i)? {
                    Json::Str(s) => s,
                    _ => return Err("object key is not a string".into()),
                };
                skip(b, i);
                if b.get(*i) != Some(&':') {
                    return Err(format!("expected ':' at {}", i));
                }
                *i += 1;
                let val = value(b, i)?;
                v.push((k, val));
                skip(b, i);
                match b.get(*i) {
                    Some(',') => *i += 1,
                    Some('}') => {
                        *i += 1;
                        return Ok(Json::Obj(v));
                    }
                    _ => return Err(format!("expected ',' or '}}' at {}", i)),
                }
            }
        }
        Some('[') => {
            *i += 1;
            let mut v = Vec::new();
            skip(b, i);
            if b.get(*i) == Some(&']') {
                *i += 1;
                return Ok(Json::Arr(v));
            }
            loop {
                v.push(value(b, i)?);
                skip(b, i);
                match b.get(*i) {
                    Some(',') => *i += 1,
                    Some(']') => {
                        *i += 1;
                        return Ok(Json::Arr(v));
                    }
                    _ => return Err(format!("expected ',' or ']' at {}", i)),
                }
            }
        }
        Some('"') => {
            *i += 1;
            let mut s = String::new();
            while let Some(&c) = b.get(*i) {
                *i += 1;
                match c {
                    '"' => return Ok(Json::Str(s)),
                    '\\' => {
                        let e = *b.get(*i).ok_or("bad escape")?;
                        *i += 1;
                        match e {
                            'n' => s.push('\n'),
                            'r' => s.push('\r'),
                            't' => s.push('\t'),
                            'u' => {
                                let hex: String = b.get(*i..*i + 4).ok_or("bad \\u escape")?.iter().collect();
                                *i += 4;
                                s.push(char::from_u32(u32::from_str_radix(&hex, 16).map_err(|e| e.to_string())?).unwrap_or('?'));
                            }
                            other => s.push(other),
                        }
                    }
                    c => s.push(c),
                }
            }
            Err("unterminated string".into())
        }
        Some('t') if b[*i..].starts_with(&['t', 'r', 'u', 'e']) => {
            *i += 4;
            Ok(Json::Bool(true))
        }
        Some('f') if b[*i..].starts_with(&['f', 'a', 'l', 's', 'e']) => {
            *i += 5;
            Ok(Json::Bool(false))
        }
        Some('n') if b[*i..].starts_with(&['n', 'u', 'l', 'l']) => {
            *i += 4;
            Ok(Json::Null)
        }
        Some(c) if c.is_ascii_digit() || *c == '-' => {
            let s = *i;
            *i += 1;
            while *i < b.len() && b[*i].is_ascii_digit() {
                *i += 1;
            }
            b[s..*i].iter().collect::<String>().parse::<i64>().map(Json::Num).map_err(|e| e.to_string())
        }
        Some(c) => Err(format!("unexpected {:?} at {}", c, i)),
    }
}

// ---------------------------------------------------------------------------------------------------------
// residue.json

/// What identifies a residue site across edits elsewhere in its file: the line number is left out.
pub fn fingerprint(r: &ResidueSite) -> String {
    format!("{}\t{}\t{}", r.file, r.reason, r.text)
}

pub fn residue_json(cm: &dyn Codemod, res: &RunResult) -> String {
    let mut o = String::new();
    let _ = writeln!(o, "{{");
    let _ = writeln!(o, "  \"codemod\": {},", esc(cm.name()));
    let _ = writeln!(o, "  \"about\": {},", esc(cm.about()));
    let _ = writeln!(o, "  \"residue\": {},", res.residue.len());
    let reasons = res.residue_by_reason();
    let body: Vec<String> = reasons.iter().map(|(k, n)| format!("{}: {}", esc(k), n)).collect();
    let _ = writeln!(o, "  \"reasons\": {{{}}},", body.join(", "));
    let _ = writeln!(o, "  \"sites\": [");
    let n = res.residue.len();
    for (i, r) in res.residue.iter().enumerate() {
        let _ = writeln!(o, "    {{\"file\": {}, \"reason\": {}, \"text\": {}}}{}", esc(&r.file), esc(&r.reason), esc(&r.text), if i + 1 < n { "," } else { "" });
    }
    let _ = writeln!(o, "  ]");
    let _ = writeln!(o, "}}");
    o
}

pub fn parse_residue(text: &str) -> Result<Vec<ResidueSite>, String> {
    let j = parse_json(text)?;
    let mut out = Vec::new();
    for s in j.get("sites").ok_or("no sites")?.arr() {
        out.push(ResidueSite {
            file: s.get("file").and_then(|v| v.str()).ok_or("site without file")?.to_string(),
            line: 0,
            reason: s.get("reason").and_then(|v| v.str()).ok_or("site without reason")?.to_string(),
            text: s.get("text").and_then(|v| v.str()).unwrap_or("").to_string(),
        });
    }
    Ok(out)
}

pub fn keys_json(rep: &KeyReport, keys: &[super::KeyUse]) -> String {
    let mut o = String::new();
    let _ = writeln!(o, "{{");
    let _ = writeln!(o, "  \"synthesized\": {},", rep.synthesized);
    let _ = writeln!(o, "  \"preserved\": {},", rep.preserved);
    let _ = writeln!(o, "  \"unresolved\": {},", rep.unresolved);
    let _ = writeln!(o, "  \"collisions\": [");
    for (i, c) in rep.collisions.iter().enumerate() {
        let uses: Vec<String> = c.uses.iter().map(|(origin, h, s)| format!("{{\"at\": {}, \"handler\": {}, \"synthesized\": {}}}", esc(origin), esc(h), s)).collect();
        let _ = writeln!(
            o,
            "    {{\"owner\": {}, \"key\": {}, \"resolution\": {}, \"uses\": [{}]}}{}",
            esc(&c.owner),
            esc(&c.key),
            esc(if c.resolved { "preserved: the old form already shared this key, the conversion keeps it" } else { "UNRESOLVED" }),
            uses.join(", "),
            if i + 1 < rep.collisions.len() { "," } else { "" }
        );
    }
    let _ = writeln!(o, "  ],");
    let _ = writeln!(o, "  \"keys\": [");
    for (i, k) in keys.iter().enumerate() {
        let _ = writeln!(
            o,
            "    {{\"owner\": {}, \"key\": {}, \"handler\": {}, \"synthesized\": {}}}{}",
            esc(&k.owner),
            esc(&k.key),
            esc(&k.handler),
            k.synthesized,
            if i + 1 < keys.len() { "," } else { "" }
        );
    }
    let _ = writeln!(o, "  ]");
    let _ = writeln!(o, "}}");
    o
}

// ---------------------------------------------------------------------------------------------------------
// revert record

pub fn revert_json(name: &str, changes: &[FileChange], hash: impl Fn(&str) -> String) -> String {
    let mut o = String::new();
    let _ = writeln!(o, "{{");
    let _ = writeln!(o, "  \"codemod\": {},", esc(name));
    let _ = writeln!(o, "  \"files\": [");
    for (i, c) in changes.iter().enumerate() {
        let inv: Vec<String> = c.inverse.iter().map(|x| format!("[{}, {}, {}]", x.start, x.len, esc(&x.text))).collect();
        let _ = writeln!(
            o,
            "    {{\"file\": {}, \"before\": {}, \"after\": {}, \"inverse\": [{}]}}{}",
            esc(&c.rel),
            esc(&hash(&c.before)),
            esc(&hash(&c.after)),
            inv.join(", "),
            if i + 1 < changes.len() { "," } else { "" }
        );
    }
    let _ = writeln!(o, "  ]");
    let _ = writeln!(o, "}}");
    o
}

pub struct RevertFile {
    pub file: String,
    pub before_hash: String,
    pub after_hash: String,
    pub inverse: Vec<Inverse>,
}

pub fn parse_revert(text: &str) -> Result<Vec<RevertFile>, String> {
    let j = parse_json(text)?;
    let mut out = Vec::new();
    for f in j.get("files").ok_or("no files")?.arr() {
        let mut inverse = Vec::new();
        for x in f.get("inverse").ok_or("no inverse")?.arr() {
            let a = x.arr();
            inverse.push(Inverse { start: a.first().and_then(|v| v.num()).ok_or("bad inverse")? as usize, len: a.get(1).and_then(|v| v.num()).ok_or("bad inverse")? as usize, text: a.get(2).and_then(|v| v.str()).ok_or("bad inverse")?.to_string() });
        }
        out.push(RevertFile {
            file: f.get("file").and_then(|v| v.str()).ok_or("no file")?.to_string(),
            before_hash: f.get("before").and_then(|v| v.str()).ok_or("no before")?.to_string(),
            after_hash: f.get("after").and_then(|v| v.str()).ok_or("no after")?.to_string(),
            inverse,
        });
    }
    Ok(out)
}

pub fn revert_recipe(name: &str, res: &RunResult) -> String {
    let mut o = String::new();
    let _ = writeln!(o, "applied {}: {} sites in {} files ({} lines)", name, res.rewrites, res.changes.len(), res.edited_lines());
    let _ = writeln!(o, "revert recipe (the codemod is deterministic, so any of these restores the tree):");
    let _ = writeln!(o, "  1. before it is committed:   analyze codemod {} --revert     (checks each file's hash, then restores it)", name);
    let _ = writeln!(o, "  2. after it is one commit:    git revert <commit>");
    let _ = writeln!(o, "  3. later steps stacked on it: git switch -c redo/{} pre/{} ; fix the codemod ; re-run it and every later step's codemod in order", name, name);
    o
}

// ---------------------------------------------------------------------------------------------------------
// summary

pub fn summary(cm: &dyn Codemod, res: &RunResult, keys: &KeyReport, took: std::time::Duration) -> String {
    let mut o = String::new();
    let _ = writeln!(o, "codemod {}: {}", cm.name(), cm.about());
    let _ = writeln!(o, "  parser sites in scope : {}", res.ast_sites);
    let _ = writeln!(o, "  rewritten             : {} ({} files, {} lines)", res.rewrites, res.changes.len(), res.edited_lines());
    if !res.declared.is_empty() {
        let types: std::collections::BTreeSet<&str> = res.declared.iter().map(|n| n.holder.as_str()).collect();
        let many = res.declared.iter().filter(|n| n.many).count();
        let _ = writeln!(o, "  declarations added    : {} ({} owns_one, {} owns_many, on {} types)", res.declared.len(), res.declared.len() - many, many, types.len());
    }
    let _ = writeln!(o, "  residue               : {}", res.residue.len());
    let by = res.residue_by_reason();
    let mut docs: std::collections::BTreeMap<&str, &str> = std::collections::BTreeMap::new();
    for (c, t) in FRAMEWORK_REASONS.iter().chain(cm.reasons().iter()) {
        docs.insert(c, t);
    }
    for (code, n) in &by {
        let _ = writeln!(o, "      {:<22} {:>5}   {}", code, n, docs.get(code.as_str()).unwrap_or(&""));
    }
    let _ = writeln!(o, "  excluded (framework, tests): {}", res.excluded);
    if res.outside_filter > 0 {
        let _ = writeln!(o, "  left alone by --path  : {}", res.outside_filter);
    }
    let _ = writeln!(o, "  keys                  : {} synthesized, {} preserved, {} collisions ({} unresolved)", keys.synthesized, keys.preserved, keys.collisions.len(), keys.unresolved);
    for c in keys.collisions.iter().take(10) {
        let _ = writeln!(o, "      {} {} {}", c.owner, c.key, if c.resolved { "(preserved)" } else { "(UNRESOLVED)" });
    }
    let _ = write!(o, "  {:.1?}", took);
    o
}
