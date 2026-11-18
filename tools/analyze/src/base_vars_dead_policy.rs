//! Unique base-vars-dead lexical classification over caller-borrowed declaration/source DATA.
//! The actual native roster/current-model factory stays with the utility coordinator.
use std::collections::{BTreeMap,HashMap,HashSet};
use crate::key_policy_control::{self as kc,Control};
#[derive(Debug)]pub struct BaseVar{pub owner:String,pub name:String,pub rel:String,pub line:u32}
#[derive(Default,Clone,Copy)]pub(crate) struct Uses{pub reads:u32,pub writes:u32}
#[derive(Clone,Copy)]pub enum Channel{Stdout,Stderr}
fn is_ident(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

/// Classify the occurrence at `[s, e)` of a name in `t` (comments stripped, strings kept).
fn classify<C:Control>(t: &[u8], s: usize, e: usize, in_string: bool, c:&mut C) -> Result<Option<bool>,C::Error> {
    c.checkpoint()?;
    if in_string {
        return Ok(Some(false));
    }
    // A declaration: preceded by `var/` or `var/<type path>/`, or by `/` inside a typed proc argument (`obj/item/x`).
    let mut i = s;
    if i > 0 && t[i - 1] == b'/' {
        // walk back over the path to see whether it starts with `var`, or is a proc argument type (`/obj/item/x,`).
        let mut j = i - 1;
        while j > 0 && (is_ident(t[j - 1]) || t[j - 1] == b'/') {
            c.checkpoint()?;
            j -= 1;
        }
        let path = &t[j..s];
        if path.starts_with(b"var/") || path.windows(5).any(|w| w == b"/var/") {
            return Ok(None);
        }
        // `/obj/item/x` (an absolute path: a typed argument or a type): not a use. `a/x` (a division) is a read.
        if t[j] == b'/' {
            return Ok(None);
        }
    }
    // `.x` is a field access on something: still a use of the name.
    i = e;
    while i < t.len() && (t[i] == b' ' || t[i] == b'\t') {
        c.checkpoint()?;
        i += 1;
    }
    // skip an index `x[...]`
    if i < t.len() && t[i] == b'[' {
        let mut depth = 0i32;
        while i < t.len() {
            c.checkpoint()?;
            match t[i] {
                b'[' => depth += 1,
                b']' => {
                    depth -= 1;
                    if depth == 0 {
                        i += 1;
                        break;
                    }
                }
                b'\n' => break,
                _ => {}
            }
            i += 1;
        }
        while i < t.len() && (t[i] == b' ' || t[i] == b'\t') {
        c.checkpoint()?;
            i += 1;
        }
    }
    let rest = &t[i..t.len().min(i + 3)];
    let write = match rest {
        [b'=', b'=', ..] => false,
        [b'=', ..] => true,
        [b'+' | b'-' | b'*' | b'/' | b'|' | b'&' | b'^' | b'%', b'=', ..] => true,
        [b'<', b'<', b'='] | [b'>', b'>', b'='] => true,
        _ => false,
    };
    if write {
        return Ok(Some(true));
    }
    // `x++`, `++x` and `x--` are reads and writes at once (the value is often used): counted as reads.
    Ok(Some(false))
}

/// Every occurrence of a watched name in `text` (comments stripped, strings kept): (name, line, is_write).
pub(crate) fn scan(text:&str,names:&HashSet<&str>,mut f:impl FnMut(&str,u32,bool)){
    let pending=scan_using(text,names,&mut kc::Compatibility,|name,line,write|{f(name,line,write);Ok(())});
    match pending{Ok(())=>(),Err(never)=>match never{}}
}
pub(crate) fn scan_using<C:Control>(text: &str, names: &HashSet<&str>, c:&mut C, mut f: impl FnMut(&str, u32, bool)->Result<(),C::Error>) -> Result<(),C::Error> {
    c.checkpoint()?;
    let t = text.as_bytes();
    let n = t.len();
    let mut line = 1u32;
    let mut in_string = false;
    let mut i = 0;
    while i < n {
        c.checkpoint()?;
        let byte = t[i];
        if byte == b'\n' {
            line = if C::CHECKED{line.checked_add(1).ok_or_else(||c.overflow())?}else{line+1};
            i += 1;
            continue;
        }
        if byte == b'"' && (i == 0 || t[i - 1] != b'\\') {
            in_string = !in_string;
            i += 1;
            continue;
        }
        if is_ident(byte) && (i == 0 || !is_ident(t[i - 1])) {
            let s = i;
            while i < n && is_ident(t[i]) {
                c.checkpoint()?;
                i += 1;
            }
            let w = &text[s..i];
            if names.contains(w) {
                if let Some(wr) = classify(t, s, i, in_string,c)? {
                    f(w, line, wr)?;
                }
            }
            continue;
        }
        i += 1;
    }
    c.checkpoint()
}


pub(crate) fn report<C:Control>(vars:&[BaseVar],uses:&HashMap<String,Uses>,tsv:bool,few:bool,c:&mut C,mut emit:impl FnMut(Channel,std::fmt::Arguments<'_>)->Result<(),C::Error>)->Result<(),C::Error>{
 kc::reserve(c,||vars.len().checked_mul(std::mem::size_of::<((&str,&str),(&str,&str,u32,u32))>().checked_mul(4)?.checked_add(128)?))?;
 let mut rows:BTreeMap<(&str,&str),(&str,&str,u32,u32)>=BTreeMap::new();
 for v in vars{c.checkpoint()?;let u=uses.get(&v.name).copied().unwrap_or_default();let kind=if u.reads==0&&u.writes==0{"dead"}else if u.reads==0{"write_only"}else if few&&u.reads<=2{"few_reads"}else{continue};rows.insert((&v.owner,&v.name),(kind,&v.rel,v.line,u.writes));}
 let(mut dead,mut wo)=(0,0);
 for((owner,name),(kind,rel,line,writes))in rows{c.checkpoint()?;match kind{"dead"=>dead+=1,"write_only"=>wo+=1,_=>{}}if tsv{emit(Channel::Stdout,format_args!("{}\t{}\t{}\t{}:{}\t{}",kind,owner,name,rel,line,writes))?;}else{emit(Channel::Stdout,format_args!("{:<10} {}/var/{}  ({}:{}, {} writes)",kind,owner,name,rel,line,writes))?;}}
 emit(Channel::Stderr,format_args!("analyze base-vars-dead: {} base vars, {} dead, {} write-only",vars.len(),dead,wo))?;c.checkpoint()
}
