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


#[derive(Debug)]enum ParseFailure{Operational(std::io::Error),Static(&'static str),Message(String)}
impl From<std::io::Error> for ParseFailure{fn from(value:std::io::Error)->Self{Self::Operational(value)}}
impl std::error::Error for ParseFailure{}
impl std::fmt::Display for ParseFailure{fn fmt(&self,out:&mut std::fmt::Formatter<'_>)->std::fmt::Result{match self{Self::Operational(value)=>value.fmt(out),Self::Static(value)=>out.write_str(value),Self::Message(value)=>out.write_str(value)}}}
fn push_char_using(out:&mut String,ch:char,work:Option<&dyn crate::policy_finish::admitted::Work>)->std::io::Result<()>{let mut bytes=[0;4];super::work::push_str(work,out,ch.encode_utf8(&mut bytes))}
fn chars_using(chars:&[char],work:Option<&dyn crate::policy_finish::admitted::Work>)->std::io::Result<String>{let mut size=0usize;for ch in chars{super::work::checkpoint(work)?;size=super::work::size(work,size.checked_add(ch.len_utf8()))?;}let mut output=super::work::string_capacity(work,size)?;for ch in chars{super::work::checkpoint(work)?;output.push(*ch);}Ok(output)}
pub fn parse_json(text:&str)->Result<Json,String>{parse_json_inner(text,None).map_err(|error|error.to_string())}
pub fn parse_json_using(text:&str,work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<Json>{match parse_json_inner(text,Some(work)){Ok(value)=>Ok(value),Err(ParseFailure::Operational(first))=>Err(first),Err(error)=>Err(std::io::Error::new(std::io::ErrorKind::InvalidData,error))}}
fn parse_json_inner(text:&str,work:Option<&dyn crate::policy_finish::admitted::Work>)->Result<Json,ParseFailure>{
    let mut b=super::work::vec_capacity(work,text.chars().count())?;for ch in text.chars(){super::work::checkpoint(work)?;b.push(ch);}
    let mut i = 0;
    let v = value_using(&b,&mut i,work,0)?;
    skip(&b, &mut i);
    if i != b.len() {
        return Err(ParseFailure::Message(super::work::format(work,format_args!("trailing text at {}", i))?));
    }
    Ok(v)
}

fn skip(b: &[char], i: &mut usize) {
    while *i < b.len() && b[*i].is_whitespace() {
        *i += 1;
    }
}

fn value_using(b:&[char],i:&mut usize,work:Option<&dyn crate::policy_finish::admitted::Work>,depth:usize)->Result<Json,ParseFailure>{
 super::work::checkpoint(work)?;
 if work.is_some()&&depth>=64{return Err(ParseFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"codemod artifact nesting budget exceeded")))}
    skip(b, i);
    match b.get(*i) {
        None => Err(ParseFailure::Static("unexpected end")),
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
                let k = match value_using(b,i,work,depth+1)? {
                    Json::Str(s) => s,
                    _ => return Err(ParseFailure::Static("object key is not a string")),
                };
                skip(b, i);
                if b.get(*i) != Some(&':') {
                    return Err(ParseFailure::Message(super::work::format(work,format_args!("expected ':' at {}", i))?));
                }
                *i += 1;
                let val = value_using(b,i,work,depth+1)?;
                super::work::row(work,&mut v)?;v.push((k,val));
                skip(b, i);
                match b.get(*i) {
                    Some(',') => *i += 1,
                    Some('}') => {
                        *i += 1;
                        return Ok(Json::Obj(v));
                    }
                    _ => return Err(ParseFailure::Message(super::work::format(work,format_args!("expected ',' or '}}' at {}", i))?)),
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
                let item=value_using(b,i,work,depth+1)?;super::work::row(work,&mut v)?;v.push(item);
                skip(b, i);
                match b.get(*i) {
                    Some(',') => *i += 1,
                    Some(']') => {
                        *i += 1;
                        return Ok(Json::Arr(v));
                    }
                    _ => return Err(ParseFailure::Message(super::work::format(work,format_args!("expected ',' or ']' at {}", i))?)),
                }
            }
        }
        Some('"') => {
            *i += 1;
            let mut s = String::new();
            while let Some(&c)=b.get(*i){super::work::checkpoint(work)?;
                *i += 1;
                match c {
                    '"' => return Ok(Json::Str(s)),
                    '\\' => {
                        let e = *b.get(*i).ok_or(ParseFailure::Static("bad escape"))?;
                        *i += 1;
                        match e {
                            'n' => push_char_using(&mut s,'\n',work)?,
                            'r' => push_char_using(&mut s,'\r',work)?,
                            't' => push_char_using(&mut s,'\t',work)?,
                            'u' => {
                                let hex=chars_using(b.get(*i..*i+4).ok_or(ParseFailure::Static("bad \\u escape"))?,work)?;
                                *i += 4;
                                let number=match u32::from_str_radix(&hex,16){Ok(value)=>value,Err(error)=>return Err(ParseFailure::Message(super::work::format(work,format_args!("{error}"))?))};push_char_using(&mut s,char::from_u32(number).unwrap_or('?'),work)?;
                            }
                            other => push_char_using(&mut s,other,work)?,
                        }
                    }
                    c => push_char_using(&mut s,c,work)?,
                }
            }
            Err(ParseFailure::Static("unterminated string"))
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
            match chars_using(&b[s..*i],work)?.parse::<i64>(){Ok(value)=>Ok(Json::Num(value)),Err(error)=>Err(ParseFailure::Message(super::work::format(work,format_args!("{error}"))?))}
        }
        Some(c) => Err(ParseFailure::Message(super::work::format(work,format_args!("unexpected {:?} at {}", c, i))?)),
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
    if res.followed > 0 {
        let _ = writeln!(o, "  definitions followed  : {}", res.followed);
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

// Native formatting uses the original field order/whitespace and scalar
// escaping, with borrowed lists instead of intermediate Vec<String>/joins.
struct Escaped<'a>(&'a str);
impl std::fmt::Display for Escaped<'_>{fn fmt(&self,out:&mut std::fmt::Formatter<'_>)->std::fmt::Result{out.write_str("\"")?;for ch in self.0.chars(){match ch{'"'=>out.write_str("\\\"")?,'\\'=>out.write_str("\\\\")?,'\n'=>out.write_str("\\n")?,'\r'=>out.write_str("\\r")?,'\t'=>out.write_str("\\t")?,ch if(ch as u32)<0x20=>write!(out,"\\u{:04x}",ch as u32)?,ch=>write!(out,"{ch}")?}}out.write_str("\"")}}
struct AdmittedOutput<'a>{text:String,work:&'a dyn crate::policy_finish::admitted::Work,first:Option<std::io::Error>}
impl std::fmt::Write for AdmittedOutput<'_>{fn write_str(&mut self,text:&str)->std::fmt::Result{if self.first.is_some(){return Err(std::fmt::Error)}match super::work::push_str(Some(self.work),&mut self.text,text){Ok(())=>Ok(()),Err(first)=>{self.first=Some(first);Err(std::fmt::Error)}}}}
impl<'a>AdmittedOutput<'a>{fn new(work:&'a dyn crate::policy_finish::admitted::Work)->Self{Self{text:String::new(),work,first:None}}fn args(&mut self,args:std::fmt::Arguments<'_>)->std::io::Result<()>{let pending=std::fmt::write(self,args);if let Some(first)=self.first.take(){return Err(first)}pending.map_err(|_|std::io::Error::other("codemod formatter failed without operational cause"))}fn finish(self)->std::io::Result<String>{self.work.checkpoint()?;Ok(self.text)}}
pub fn residue_json_using(cm:&dyn Codemod,res:&RunResult,work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<String>{
 let mut o=AdmittedOutput::new(work);o.args(format_args!("{{\n  \"codemod\": {},\n  \"about\": {},\n  \"residue\": {},\n  \"reasons\": {{",Escaped(cm.name()),Escaped(cm.about()),res.residue.len()))?;
 let mut reasons:Vec<(&str,usize)>=Vec::new();for site in &res.residue{work.checkpoint()?;match reasons.binary_search_by(|(key,_)|(*key).cmp(&site.reason)){Ok(at)=>reasons[at].1+=1,Err(at)=>{super::work::row(Some(work),&mut reasons)?;reasons.insert(at,(&site.reason,1));}}}
 for(index,(reason,count))in reasons.iter().enumerate(){if index>0{o.args(format_args!(", "))?}o.args(format_args!("{}: {}",Escaped(reason),count))?;}
 o.args(format_args!("}},\n  \"sites\": [\n"))?;
 for(index,site)in res.residue.iter().enumerate(){o.args(format_args!("    {{\"file\": {}, \"reason\": {}, \"text\": {}}}{}\n",Escaped(&site.file),Escaped(&site.reason),Escaped(&site.text),if index+1<res.residue.len(){","}else{""}))?;}
 o.args(format_args!("  ]\n}}\n"))?;o.finish()
}
pub fn keys_json_using(rep:&KeyReport,keys:&[super::KeyUse],work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<String>{
 let mut o=AdmittedOutput::new(work);o.args(format_args!("{{\n  \"synthesized\": {},\n  \"preserved\": {},\n  \"unresolved\": {},\n  \"collisions\": [\n",rep.synthesized,rep.preserved,rep.unresolved))?;
 for(index,collision)in rep.collisions.iter().enumerate(){o.args(format_args!("    {{\"owner\": {}, \"key\": {}, \"resolution\": {}, \"uses\": [",Escaped(&collision.owner),Escaped(&collision.key),Escaped(if collision.resolved{"preserved: the old form already shared this key, the conversion keeps it"}else{"UNRESOLVED"})))?;for(i,(origin,handler,synthesized))in collision.uses.iter().enumerate(){if i>0{o.args(format_args!(", "))?}o.args(format_args!("{{\"at\": {}, \"handler\": {}, \"synthesized\": {}}}",Escaped(origin),Escaped(handler),synthesized))?;}o.args(format_args!("]}}{}\n",if index+1<rep.collisions.len(){","}else{""}))?;}
 o.args(format_args!("  ],\n  \"keys\": [\n"))?;for(index,key)in keys.iter().enumerate(){o.args(format_args!("    {{\"owner\": {}, \"key\": {}, \"handler\": {}, \"synthesized\": {}}}{}\n",Escaped(&key.owner),Escaped(&key.key),Escaped(&key.handler),key.synthesized,if index+1<keys.len(){","}else{""}))?;}o.args(format_args!("  ]\n}}\n"))?;o.finish()
}
fn actual_hash(text:&str,work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<blake3::Hash>{let mut hash=blake3::Hasher::new();for chunk in text.as_bytes().chunks(8192){work.checkpoint()?;hash.update(chunk);}Ok(hash.finalize())}
pub fn revert_json_using(name:&str,changes:&[FileChange],work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<String>{
 let mut o=AdmittedOutput::new(work);o.args(format_args!("{{\n  \"codemod\": {},\n  \"files\": [\n",Escaped(name)))?;
 for(index,change)in changes.iter().enumerate(){let before=actual_hash(&change.before,work)?.to_hex();let after=actual_hash(&change.after,work)?.to_hex();o.args(format_args!("    {{\"file\": {}, \"before\": {}, \"after\": {}, \"inverse\": [",Escaped(&change.rel),Escaped(before.as_str()),Escaped(after.as_str())))?;for(i,inverse)in change.inverse.iter().enumerate(){if i>0{o.args(format_args!(", "))?}o.args(format_args!("[{}, {}, {}]",inverse.start,inverse.len,Escaped(&inverse.text)))?;}o.args(format_args!("]}}{}\n",if index+1<changes.len(){","}else{""}))?;}
 o.args(format_args!("  ]\n}}\n"))?;o.finish()
}
fn residue_from_json(actual:&Json,work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<Result<Vec<ResidueSite>,&'static str>>{
 let Some(sites)=actual.get("sites")else{return Ok(Err("no sites"))};let mut output=super::work::vec_capacity(Some(work),sites.arr().len())?;
 for site in sites.arr(){work.checkpoint()?;let Some(file)=site.get("file").and_then(Json::str)else{return Ok(Err("site without file"))};let file=super::work::own(Some(work),file)?;let Some(reason)=site.get("reason").and_then(Json::str)else{return Ok(Err("site without reason"))};let reason=super::work::own(Some(work),reason)?;let text=super::work::own(Some(work),site.get("text").and_then(Json::str).unwrap_or(""))?;output.push(ResidueSite{file,line:0,reason,text});}Ok(Ok(output))
}
/// A malformed committed artifact is ordinary gate DATA; a genuine IO from
/// the SAME parser's work is kept separate even if its kind is InvalidData.
fn parse_residue_checked(text:&str,work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<Result<Vec<ResidueSite>,String>>{
 let actual=match parse_json_inner(text,Some(work)){Ok(value)=>value,Err(ParseFailure::Operational(first))=>return Err(first),Err(ParseFailure::Static(message))=>return Ok(Err(super::work::own(Some(work),message)?)),Err(ParseFailure::Message(message))=>return Ok(Err(message))};
 match residue_from_json(&actual,work)?{Ok(rows)=>Ok(Ok(rows)),Err(message)=>Ok(Err(super::work::own(Some(work),message)?))}
}
pub fn parse_residue_using(text:&str,work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<Vec<ResidueSite>>{match parse_residue_checked(text,work)?{Ok(rows)=>Ok(rows),Err(message)=>Err(std::io::Error::new(std::io::ErrorKind::InvalidData,message))}}
pub fn parse_revert_using(text:&str,work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<Vec<RevertFile>>{
 let actual=parse_json_using(text,work)?;let files=actual.get("files").ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidData,"no files"))?;let mut output=super::work::vec_capacity(Some(work),files.arr().len())?;
 for file in files.arr(){work.checkpoint()?;let inverse=file.get("inverse").ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidData,"no inverse"))?;let mut inverse_output=super::work::vec_capacity(Some(work),inverse.arr().len())?;for row in inverse.arr(){work.checkpoint()?;let values=row.arr();let invalid=||std::io::Error::new(std::io::ErrorKind::InvalidData,"bad inverse");inverse_output.push(Inverse{start:values.first().and_then(Json::num).ok_or_else(invalid)? as usize,len:values.get(1).and_then(Json::num).ok_or_else(invalid)? as usize,text:super::work::own(Some(work),values.get(2).and_then(Json::str).ok_or_else(invalid)?)?});}let field=|key|file.get(key).and_then(Json::str).ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidData,match key{"file"=>"no file","before"=>"no before",_=>"no after"}));output.push(RevertFile{file:super::work::own(Some(work),field("file")?)?,before_hash:super::work::own(Some(work),field("before")?)?,after_hash:super::work::own(Some(work),field("after")?)?,inverse:inverse_output});}Ok(output)
}
fn edited_lines_using(res:&RunResult,work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<usize>{let mut total=0usize;for change in &res.changes{let(mut left,mut right)=(change.before.split('\n'),change.after.split('\n'));loop{work.checkpoint()?;match(left.next(),right.next()){(None,None)=>break,(a,b)=>if a!=b{total=total.checked_add(1).ok_or_else(||work.overflow())?}}}}Ok(total)}
fn reason_rows<'a>(res:&'a RunResult,work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<Vec<(&'a str,usize)>>{let mut reasons:Vec<(&str,usize)>=Vec::new();for site in &res.residue{work.checkpoint()?;match reasons.binary_search_by(|(key,_)|(*key).cmp(&site.reason)){Ok(at)=>reasons[at].1+=1,Err(at)=>{super::work::row(Some(work),&mut reasons)?;reasons.insert(at,(&site.reason,1));}}}Ok(reasons)}
pub fn summary_using(cm:&dyn Codemod,res:&RunResult,keys:&KeyReport,took:std::time::Duration,work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<String>{
 let mut o=AdmittedOutput::new(work);o.args(format_args!("codemod {}: {}\n  parser sites in scope : {}\n  rewritten             : {} ({} files, {} lines)\n",cm.name(),cm.about(),res.ast_sites,res.rewrites,res.changes.len(),edited_lines_using(res,work)?))?;
 if !res.declared.is_empty(){let mut types=0usize;for(index,value)in res.declared.iter().enumerate(){work.checkpoint()?;if !res.declared[..index].iter().any(|prior|prior.holder==value.holder){types+=1}}let many=res.declared.iter().filter(|value|value.many).count();o.args(format_args!("  declarations added    : {} ({} owns_one, {} owns_many, on {} types)\n",res.declared.len(),res.declared.len()-many,many,types))?;}
 if res.followed>0{o.args(format_args!("  definitions followed  : {}\n",res.followed))?;}o.args(format_args!("  residue               : {}\n",res.residue.len()))?;
 for(code,count)in reason_rows(res,work)?{let doc=FRAMEWORK_REASONS.iter().chain(cm.reasons()).rev().find(|(key,_)|*key==code).map_or("",|(_,value)|*value);o.args(format_args!("      {:<22} {:>5}   {}\n",code,count,doc))?;}
 o.args(format_args!("  excluded (framework, tests): {}\n",res.excluded))?;if res.outside_filter>0{o.args(format_args!("  left alone by --path  : {}\n",res.outside_filter))?;}o.args(format_args!("  keys                  : {} synthesized, {} preserved, {} collisions ({} unresolved)\n",keys.synthesized,keys.preserved,keys.collisions.len(),keys.unresolved))?;for value in keys.collisions.iter().take(10){o.args(format_args!("      {} {} {}\n",value.owner,value.key,if value.resolved{"(preserved)"}else{"(UNRESOLVED)"}))?;}o.args(format_args!("  {:.1?}",took))?;o.finish()
}
pub fn revert_recipe_using(name:&str,res:&RunResult,work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<String>{let mut o=AdmittedOutput::new(work);o.args(format_args!("applied {}: {} sites in {} files ({} lines)\nrevert recipe (the codemod is deterministic, so any of these restores the tree):\n  1. before it is committed:   analyze codemod {} --revert     (checks each file's hash, then restores it)\n  2. after it is one commit:    git revert <commit>\n  3. later steps stacked on it: git switch -c redo/{} pre/{} ; fix the codemod ; re-run it and every later step's codemod in order\n",name,res.rewrites,res.changes.len(),edited_lines_using(res,work)?,name,name,name))?;o.finish()}
/// Same concatenated fingerprint equality, without allocating its two strings.
fn fingerprint_eq(a:&ResidueSite,b:&ResidueSite)->bool{fn bytes(value:&ResidueSite)->impl Iterator<Item=u8>+'_ {value.file.bytes().chain(std::iter::once(b'\t')).chain(value.reason.bytes()).chain(std::iter::once(b'\t')).chain(value.text.bytes())}bytes(a).eq(bytes(b))}
pub fn gate_using(cm:&dyn Codemod,res:&RunResult,keys:&KeyReport,committed:Option<&str>,work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<(bool,String)>{
 let mut o=AdmittedOutput::new(work);let mut fail=false;
 match committed{
  None=>{o.args(format_args!("analyze codemod: {} has no committed residue.json; run --write-residue\n",cm.name()))?;fail=true;},
  Some(text)=>match parse_residue_checked(text,work)?{Err(error)=>{o.args(format_args!("analyze codemod: residue.json: {}\n",error))?;fail=true;},Ok(known)=>{
   let mut fresh=Vec::new();for site in &res.residue{work.checkpoint()?;if !known.iter().any(|prior|fingerprint_eq(site,prior)){super::work::row(Some(work),&mut fresh)?;fresh.push(site)}}if !fresh.is_empty(){o.args(format_args!("analyze codemod: {} residue sites not in residue.json:\n",fresh.len()))?;for site in fresh.iter().take(25){o.args(format_args!("  {}:{}: [{}] {}\n",site.file,site.line,site.reason,site.text))?;}fail=true;}
  }}
 }
 if keys.unresolved>0{o.args(format_args!("analyze codemod: {} unresolved key collisions\n",keys.unresolved))?;fail=true;}
 Ok((fail,o.finish()?))
}
#[cfg(test)]mod native_report_controls{
 use super::*;use std::{cell::Cell,io};
 struct Work{calls:Cell<usize>,deny:Option<usize>,kind:io::ErrorKind}
 impl crate::policy_finish::admitted::Work for Work{fn checkpoint(&self)->io::Result<()>{Ok(())}fn reserve(&self,_:usize)->io::Result<()>{let next=self.calls.get()+1;self.calls.set(next);if self.deny==Some(next){if self.kind==io::ErrorKind::InvalidData{return Err(io::Error::new(self.kind,"actual work error, not malformed JSON"))}return Err(io::Error::from_raw_os_error(1450))}Ok(())}fn overflow(&self)->io::Error{io::ErrorKind::OutOfMemory.into()}}
 fn open()->Work{Work{calls:Cell::new(0),deny:None,kind:io::ErrorKind::Other}}
 fn sample()->RunResult{RunResult{name:"om_after".into(),residue:vec![ResidueSite{file:"code/x.dm".into(),line:8,reason:"z".into(),text:"quote \" line\n \\ \u{3b1}".into()},ResidueSite{file:"code/y.dm".into(),line:2,reason:"a".into(),text:"next".into()}],keys:vec![super::super::KeyUse{owner:"/obj/x".into(),key:"timer".into(),origin:"code/x.dm:8".into(),handler:"PROC_REF(x)".into(),synthesized:true},super::super::KeyUse{owner:"/obj/x".into(),key:"timer".into(),origin:"code/y.dm:2".into(),handler:"PROC_REF(y)".into(),synthesized:false}],changes:vec![FileChange{rel:"code/x.dm".into(),before:"old\r\n".into(),after:"new\r\n".into(),inverse:vec![Inverse{start:0,len:3,text:"old".into()}],sites:1}],rewrites:1,ast_sites:3,..Default::default()}}
 #[test]fn paid_reports_preserve_original_artifact_bytes_and_key_group_order(){let work=open();let cm=crate::codemod::native_find("om_after").unwrap();let res=sample();let original=crate::codemod::keys::analyze(&res.keys);let native=crate::codemod::keys::analyze_using(&res.keys,&work).unwrap();assert_eq!(native,original);assert_eq!(residue_json_using(cm,&res,&work).unwrap(),residue_json(cm,&res));assert_eq!(keys_json_using(&native,&res.keys,&work).unwrap(),keys_json(&original,&res.keys));assert_eq!(revert_json_using("om_after",&res.changes,&work).unwrap(),revert_json("om_after",&res.changes,|text|blake3::hash(text.as_bytes()).to_hex().to_string()));assert!(work.calls.get()>0);}
 #[test]fn paid_summary_and_recipe_preserve_original_words_spacing_and_clock_data(){let work=open();let cm=crate::codemod::native_find("om_after").unwrap();let res=sample();let keys=crate::codemod::keys::analyze_using(&res.keys,&work).unwrap();let took=std::time::Duration::from_millis(117);assert_eq!(summary_using(cm,&res,&keys,took,&work).unwrap(),summary(cm,&res,&keys,took));assert_eq!(revert_recipe_using(cm.name(),&res,&work).unwrap(),revert_recipe(cm.name(),&res));}
 #[test]fn shared_paid_parser_preserves_original_scalar_escape_and_error_semantics(){let work=open();let actual=parse_json_using("[\"a\\u03b1\\q\",-17,true,false,null]",&work).unwrap();assert_eq!(actual,Json::Arr(vec![Json::Str("a\u{3b1}q".into()),Json::Num(-17),Json::Bool(true),Json::Bool(false),Json::Null]));assert_eq!(parse_json("[1,]").unwrap_err(),"unexpected ']' at 3");assert_eq!(parse_json_using("[1,]",&work).unwrap_err().to_string(),"unexpected ']' at 3");}
 #[test]fn actual_parser_reserve_failure_keeps_original_os_error(){let work=Work{calls:Cell::new(0),deny:Some(1),kind:io::ErrorKind::Other};let error=parse_json_using("[]",&work).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));}
 #[test]fn gate_never_confuses_operational_invaliddata_with_a_malformed_artifact(){let cm=crate::codemod::native_find("om_after").unwrap();let work=Work{calls:Cell::new(0),deny:Some(1),kind:io::ErrorKind::InvalidData};let error=gate_using(cm,&RunResult::default(),&KeyReport::default(),Some("{\"sites\":[]}"),&work).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::InvalidData);assert_eq!(error.to_string(),"actual work error, not malformed JSON");}
 #[test]fn fingerprint_gate_preserves_exact_joined_fields_but_ignores_line_numbers(){let work=open();let cm=crate::codemod::native_find("om_after").unwrap();let mut res=sample();res.keys.clear();let committed=residue_json(cm,&res);res.residue[0].line=999;let(fails,text)=gate_using(cm,&res,&KeyReport::default(),Some(&committed),&work).unwrap();assert!(!fails);assert!(text.is_empty());res.residue[0].text.push('x');let(fails,text)=gate_using(cm,&res,&KeyReport::default(),Some(&committed),&work).unwrap();assert!(fails);assert!(text.contains("1 residue sites not in residue.json:"));}
}

#[cfg(test)]mod nesting_control{use super::*;
 struct Work;impl crate::policy_finish::admitted::Work for Work{fn checkpoint(&self)->std::io::Result<()>{Ok(())}fn reserve(&self,_:usize)->std::io::Result<()>{Ok(())}fn overflow(&self)->std::io::Error{std::io::ErrorKind::OutOfMemory.into()}}
 #[test]fn native_artifact_depth_refuses_before_recursive_stack_or_recursive_drop_can_grow_unbounded(){let mut text="[".repeat(1000);text.push('0');text.push_str(&"]".repeat(1000));let error=parse_json_using(&text,&Work).unwrap_err();assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(error.to_string(),"codemod artifact nesting budget exceeded");}
}
