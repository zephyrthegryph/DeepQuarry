//! Unique complete original sound-set lexical facts, merge and judge. No source authority.
use std::collections::HashSet;
use serde::{Serialize,Deserialize};
use crate::{incr,tree::{SourceFile,Tree},pat::Pat,util::{py_lstrip,py_rstrip},pat,pat_match,key_policy_control::Control};
use crate::allow_registry_fields::sys_sfx::RULES;
const NOT_FED: &[&str] = &["src", "null", "TRUE", "FALSE", "usr", "user", "loc"];

fn code_of(line: &str) -> &str {
    line.split("//").next().unwrap_or("")
}

fn literal() -> &'static Pat {
    pat!(r"'[^'\n]+\.(?:ogg|wav|mid|mp3)'")
}

/// The text from `lines[index][start..]` up to its closing paren / end of statement, following open
/// parens and backslash continuations onto later lines. `start` doubles as a flag (quirk: a call at
/// column 0 has `start == 0`, which turns the early return off).
fn statement(lines: &[&str], index: usize, start: usize) -> String {
    let mut depth = 0i32;
    let mut out = String::new();
    let mut k = index;
    let mut col = start;
    while k < lines.len() && k < index + 40 {
        let code = code_of(lines[k]);
        let line = code.get(col..).unwrap_or("");
        col = 0;
        for c in line.chars() {
            out.push(c);
            if c == '(' || c == '[' {
                depth += 1;
            } else if c == ')' || c == ']' {
                depth -= 1;
                if depth <= 0 && start != 0 {
                    return out;
                }
            }
        }
        let stripped = py_rstrip(line);
        if depth <= 0 && !stripped.ends_with('\\') && !(start == 0 && stripped.ends_with(',')) {
            break;
        }
        out.push('\n');
        k += 1;
    }
    out
}

/// `ASSIGN.finditer(code)` as `(name, match end)`. The pattern is
/// `(?:^|[^\w.])(?:var/(?:\w+/)*)?(\w+)\s*(?<![!<>=])=(?!=)\s*(?:pick\s*\(|list\s*\()?`. The lookbehind
/// is always true (a word char or whitespace precedes the `=`), so only `(?!=)` is checked by hand.
fn assign_matches(code: &str) -> Vec<(String, usize)> {
    let mut out = Vec::new();
    let head = pat!(r"(?:^|[^\w.])(?:var/(?:\w+/)*)?(\w+)\s*=");
    let mut pos = 0;
    while pos <= code.len() {
        let Some(c) = head.captures_at(code, pos) else { break };
        let (s, e) = (c.start(0), c.end(0));
        if code.as_bytes().get(e) == Some(&b'=') {
            // `==`: the lookahead fails; the search resumes one character after this start.
            pos = s + code[s..].chars().next().map(|ch| ch.len_utf8()).unwrap_or(1);
            continue;
        }
        let rest = &code[e..];
        let ws = rest.len() - crate::util::py_lstrip(rest).len();
        let mut end = e + ws;
        if let Some(m) = pat_match!(r"(?:pick\s*\(|list\s*\()").find(&code[end..]) {
            end += m.end;
        }
        out.push((c.s(1).to_string(), end));
        pos = end;
    }
    out
}

fn py_slice(text: &str, a: isize, b: isize) -> String {
    let chars: Vec<char> = text.chars().collect();
    let len = chars.len() as isize;
    let norm = |i: isize| if i < 0 { (len + i).max(0) } else { i.min(len) };
    let (a, b) = (norm(a), norm(b));
    if a >= b {
        String::new()
    } else {
        chars[a as usize..b as usize].iter().collect()
    }
}

fn char_find(text: &str, needle: &str) -> isize {
    text.find(needle).map(|byte| text[..byte].chars().count() as isize).unwrap_or(-1)
}

pub fn scan_file_using<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,ctx:&Context,out:&mut Vec<(&'static str,usize)>,keep:&mut C,temp:&mut T)->Result<(),C::Error>{
    keep.checkpoint()?;let(fed,named)=(&ctx.fed,&ctx.named);
    let rel = f.rel.as_str();
    if rel == "code/domains/damage/sound_sets.dm" {
        return Ok(());
    }
    crate::key_policy_control::reserve(temp,||f.text().len().checked_mul(256)?.checked_add(4096))?;let lines = f.raw().lines_vec();
    let have_named = !named.is_empty();
    for (idx, line) in lines.iter().enumerate() {
        keep.checkpoint()?;
        let number = idx + 1;
        let code = code_of(line);
        if pat!(r"\bspark_spread\b").is_match(code) {
            crate::raw_tree_report::row(keep,out)?;out.push(("spark_triple", number));
        }
        let soundy = code.contains("playsound") || code.contains("get_sfx");
        if code.contains("playsound") {
            for m in pat!(r"(?<![\w./])playsound(?:_local)?\s*\(").find_iter(code) {
                keep.checkpoint()?;
                if literal().is_match(&statement(&lines, idx, m.start)) {
                    crate::raw_tree_report::row(keep,out)?;out.push(("literal_playsound", number));
                }
            }
        }
        if soundy && pat!(r#"(?<![\w./])(?:playsound(?:_local)?\s*\([^,()]+|get_sfx\s*\()\s*,?\s*"[a-z_]+""#).is_match(code) {
            crate::raw_tree_report::row(keep,out)?;out.push(("sfx_string_key", number));
        } else if have_named && code.contains('=') {
            for m in pat!(r#"(?:^|[^\w.])(\w+)\s*=\s*"(\w+)""#).captures_iter(code) {
                if fed.contains(m.s(1)) && named.contains(m.s(2)) {
                    crate::raw_tree_report::row(keep,out)?;out.push(("sfx_string_key", number));
                    break;
                }
            }
        }
        if py_lstrip(code).starts_with("#define") {
            continue;
        }
        let mut names: Vec<(String, usize)> = Vec::new();
        let gm = if code.contains("GLOBAL_LIST_INIT") { pat!(r"GLOBAL_LIST_INIT\s*\(\s*(\w+)\s*,").captures(code) } else { None };
        if let Some(gm) = gm {
            names.push((gm.s(1).to_string(), gm.end(0)));
        } else if code.contains('=') {
            names = assign_matches(code);
        }
        for (name, end) in names {
            keep.checkpoint()?;
            if !fed.contains(&name) {
                continue;
            }
            if literal().is_match(statement(&lines, idx, 0).get(end..).unwrap_or("")) {
                crate::raw_tree_report::row(keep,out)?;out.push(("literal_sound_var", number));
                break;
            }
        }
    }
    keep.checkpoint()?;Ok(())
}

/// One file's contribution to the shared context: the names it feeds to a sound call, and (for
/// `code/defines/host/sfx.dm` only) the named-set ids.
#[derive(Clone,Serialize, Deserialize, Default, PartialEq)]
pub struct Facts {
    fed: Vec<String>,
    named: Vec<String>,
}

pub fn facts_of(f:&SourceFile)->Facts{facts_of_using(f,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).expect("original sfx facts")}
pub fn facts_of_using<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,keep:&mut C,temp:&mut T)->Result<Facts,C::Error>{keep.checkpoint()?;crate::key_policy_control::reserve(temp,||f.text().len().checked_mul(256)?.checked_add(4096))?;
    let mut set: HashSet<String> = HashSet::new();
    for line in f.raw().lines() {
        keep.checkpoint()?;
        let code = code_of(line);
        if !code.contains('(') || !(code.contains("playsound") || code.contains("play_sfx") || code.contains("get_sfx")) {
            continue;
        }
        for m in pat!(
            r"(?<![\w./])(?:playsound(?:_local)?|play_sfx)\s*\(\s*[^,()]+(?:\([^()]*\))?\s*,\s*(?:pick\s*\(\s*)?([A-Za-z_][\w.]*)\s*\)?\s*[,)]|(?<![\w./])get_sfx\s*\(\s*(?:pick\s*\(\s*)?([A-Za-z_][\w.]*)\s*\)?\s*\)"
        )
        .captures_iter(code)
        {
            keep.checkpoint()?;let name = if m.matched(1) { m.s(1) } else { m.s(2) };
            set.insert(name.rsplit('.').next().unwrap_or("").to_string());
        }
    }
    let mut fed=Vec::new();for value in set{keep.checkpoint()?;crate::raw_tree_report::row(keep,&mut fed)?;fed.push(if C::CHECKED{crate::raw_tree_report::own(keep,&value)?}else{value});}
    crate::key_policy_control::reserve(keep,||fed.len().checked_mul(4*std::mem::size_of::<String>())?.checked_add(128))?;fed.sort();
    let mut named: Vec<String> = Vec::new();
    if f.rel == "code/defines/host/sfx.dm" {
        let text = f.raw().text.as_str();
        let section = py_slice(text, char_find(text, "// Named sets"), char_find(text, "// File sets."));
        for capture in pat!(r#"#define SFX_\w+ "(\w+)""#).captures_iter(&section).iter(){keep.checkpoint()?;crate::raw_tree_report::row(keep,&mut named)?;named.push(crate::raw_tree_report::own(keep,capture.s(1))?);}
        crate::key_policy_control::reserve(keep,||named.len().checked_mul(4*std::mem::size_of::<String>())?.checked_add(128))?;named.sort();
        named.dedup();
    }
    keep.checkpoint()?;Ok(Facts { fed, named })
}

/// What the judge reads: the fed names (minus the ones that never name a sound) and the named sets.
pub struct Context {
    fed: HashSet<String>,
    named: HashSet<String>,
}

fn hash_insert<C:Control>(set:&mut HashSet<String>,value:&str,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;if set.contains(value){return Ok(())}if C::CHECKED&&set.len()==set.capacity(){let target=set.capacity().checked_mul(2).map(|v|v.max(4)).ok_or_else(||c.overflow())?;let bound=target.checked_mul(4).ok_or_else(||c.overflow())?;crate::key_policy_control::reserve(c,||bound.checked_mul(std::mem::size_of::<String>())?.checked_add(4096))?;set.try_reserve(target-set.len()).map_err(|_|c.allocation_failed())?;if set.capacity()>bound{return Err(c.allocation_failed())}}set.insert(crate::raw_tree_report::own(c,value)?);Ok(())}
pub fn merge<'a,C:Control>(pairs:impl IntoIterator<Item=(&'a str,&'a Facts)>,c:&mut C)->Result<Context,C::Error>{let mut fed=HashSet::new();let mut named=HashSet::new();for(relative,facts)in pairs{c.checkpoint()?;for value in &facts.fed{hash_insert(&mut fed,value,c)?;}if relative=="code/defines/host/sfx.dm"{named.clear();for value in &facts.named{hash_insert(&mut named,value,c)?;}}}for name in NOT_FED{c.checkpoint()?;fed.remove(*name);}c.checkpoint()?;Ok(Context{fed,named})}
pub fn scan(tree:&Tree,files:&[&SourceFile])->Vec<(&'static str,String,usize)>{let _=tree;let(_,results)=incr::two_phase("sys-sfx",files,facts_of,|pairs|merge(pairs.iter().map(|(file,facts)|(file.rel.as_str(),*facts)),&mut crate::key_policy_control::Compatibility).expect("original sfx merge"),|f,ctx|{let mut rows=Vec::new();scan_file_using(f,ctx,&mut rows,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).expect("original sfx judge");rows.into_iter().map(|(rule,line)|(RULES.iter().position(|r|r.name==rule).unwrap_or(0)as u8,line as u32)).collect::<Vec<(u8,u32)>>()});let mut out=Vec::new();for(file,rows)in files.iter().zip(results){for(rule,line)in rows{out.push((RULES[rule as usize].name,file.rel.clone(),line as usize));}}out}
