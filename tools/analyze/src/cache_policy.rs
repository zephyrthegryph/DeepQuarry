//! Unique cache lexical policy, no filesystem, source receipt or semantic model.
use crate::{lint::{Meta,Policy,RuleMeta,ScanKind},tree::Select,pat::Pat,util::{before_slashes,py_lstrip,py_strip},key_policy_control::{self as kc,Control},pat};
pub static META: Meta = Meta {
    name: crate::allow_registry_fields::cache::SCOPE_META_0.name,
    group: crate::allow_registry_fields::cache::SCOPE_META_0.group,
    label: "cache",
    legacy: "tools/ci/cache_lint.py",
    // Path.rglob: dot-files and dot-directories included.
    select: Select { roots: &[("code", "dm")], hidden: true },
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "hand_rolled",
        hint: "use DECLARE_SHARED_CACHE / CACHED() (doc/rewrite/caching.md), or annotate a genuine exception with `// ALLOW(cache): <reason>`",
    }],
    allow: crate::allow_registry_fields::cache::ALLOW_0,
    lists: crate::allow_registry_fields::cache::SCOPE_META_0.lists,
};

pub fn py_splitlines(text: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut start = 0;
    for (i, c) in text.char_indices() {
        if matches!(c, '\n' | '\r' | '\u{0b}' | '\u{0c}' | '\u{1c}' | '\u{1d}' | '\u{1e}' | '\u{85}' | '\u{2028}' | '\u{2029}') {
            out.push(&text[start..i]);
            start = i + c.len_utf8();
        }
    }
    if start < text.len() {
        out.push(&text[start..]);
    }
    out
}


fn patterns()->[&'static Pat;4]{[pat!(r"(?i)\bvar/static/list/(\w*cache\w*)"),pat!(r"(?i)\bGLOBAL_LIST_(?:EMPTY|INIT|EMPTY_TYPED|INIT_TYPED)\(\s*(\w*cache\w*)"),pat!(r"(?i)^var/(?:global/)?list/(\w*cache\w*)"),pat!(r"(?i)\bvar/global/list/(\w*cache\w*)")]}
fn has_cache(s:&str)->bool{s.as_bytes().windows(5).any(|w|w.eq_ignore_ascii_case(b"cache"))}
fn kept<C:Control>(lines:&[&str],number:usize,c:&mut C)->Result<Option<(usize,Option<String>)>,C::Error>{if number>=1&&number<=lines.len(){if let Some(code)=crate::allow::keeps_with(lines[number-1],"cache",c)?{return Ok(Some((number,code)))}}if number>=2{let above=lines.get(number-2).copied().unwrap_or("");if py_lstrip(above).starts_with("//"){if let Some(code)=crate::allow::keeps_with(above,"cache",c)?{return Ok(Some((number-1,code)))}}}Ok(None)}
pub fn judge_using<C:Control>(text:&str,c:&mut C,allowed:&mut dyn FnMut(usize,Option<String>,&mut C)->Result<(),C::Error>,emit:&mut dyn FnMut(usize,&str,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{
 // At most one extra row per scalar; reserve the actual split-line backing.
 let count=text.chars().try_fold(1usize,|n,ch|{c.checkpoint()?;if matches!(ch,'\n'|'\r'|'\u{0b}'|'\u{0c}'|'\u{1c}'|'\u{1d}'|'\u{1e}'|'\u{85}'|'\u{2028}'|'\u{2029}'){n.checked_add(1).ok_or_else(||c.overflow())}else{Ok(n)}})?;kc::reserve(c,||count.checked_mul(4*std::mem::size_of::<&str>())?.checked_add(128))?;let lines=py_splitlines(text);if C::CHECKED&&lines.capacity()>count.saturating_mul(4){return Err(c.allocation_failed())}let patterns=patterns();let max=patterns.iter().map(|p|p.capture_group_count()).max().unwrap_or(0);kc::reserve(c,||max.checked_mul(4*std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128))?;
 for(idx,line)in lines.iter().enumerate(){c.checkpoint()?;let number=idx+1;let code=before_slashes(line);if !has_cache(code){continue}for pattern in patterns{c.checkpoint()?;let Some(m)=pattern.captures(code)else{continue};kc::reserve(c,||m.s(1).len().checked_mul(8)?.checked_add(128))?;if m.s(1).to_lowercase().contains("typecache"){break}if let Some((at,code))=kept(&lines,number,c)?{allowed(at,code,c)?;break}emit(number,py_strip(line),c)?;break;}}
 c.checkpoint()
}

/// Pure membership DATA from the same actual registered Select.
pub fn selects_path(relative:&str)->bool{META.select.matches_path(relative)}
