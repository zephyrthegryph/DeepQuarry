//! Unique original accessor discovery/fallback and literal-argument judge; no source authority.
use std::{collections::HashMap,sync::OnceLock};
use crate::{dm::dx::{call_arg_spans,DxIndex,Proc},incr,pat::Pat,tree::{SourceFile,Tree},pat_match,key_policy_control::Control};
/// name -> positional indexes of var-name arguments (fallback when the tree defines none).
const ACCESSORS: &[(&str, &[usize])] = &[
    ("own_set", &[1]),
    ("own_add", &[1]),
    ("own_remove", &[1]),
    ("own_take", &[1]),
    ("own_clear", &[1]),
    ("own_put", &[1]),
    ("own_take_member", &[1]),
    ("own_take_all", &[1]),
    ("own_values", &[1]),
    ("own_transfer", &[1, 3]),
    ("own_move", &[2]),
    ("rel_set", &[1]),
    ("rel_add", &[1]),
    ("rel_remove", &[1]),
    ("rel_clear", &[1]),
    ("rel_targets", &[1]),
    ("om_set", &[1]),
    ("timed_set", &[1]),
    ("time_left", &[1]),
    ("timed_cancel", &[1]),
];

const NAME_PARAMS: &[&str] = &["var_name", "from_var", "dest_var"];

pub type Accessors = HashMap<String, Vec<usize>>;

pub(crate) fn fallback()->Accessors{fallback_using(&mut crate::key_policy_control::Compatibility).expect("original accessor fallback")}
pub fn fallback_using<C:Control>(c:&mut C)->Result<Accessors,C::Error>{let mut map=HashMap::new();for(name,idx)in ACCESSORS{put(&mut map,name,idx,c)?;}c.checkpoint()?;Ok(map)}

/// `accessors_from`: `{name: indexes}` for every global accessor proc with a var-name parameter.
pub(crate) fn accessors_from(procs:&[Proc])->Accessors{accessors_from_using(procs,&mut crate::key_policy_control::Compatibility).expect("original accessor table")}
pub fn accessors_from_using<C:Control>(procs:&[Proc],c:&mut C)->Result<Accessors,C::Error>{c.checkpoint()?;
    let name_re = pat_match!(r"(?:own_\w+|rel_\w+|om_set|timed_\w+|time_left)$");
    let mut out = Accessors::new();
    for proc in procs {
        c.checkpoint()?;
        if !proc.is_global() || !name_re.is_match(&proc.name) {
            continue;
        }
        let om_set = proc.name == "om_set";
        let mut idx=Vec::new();for(k,p)in proc.params.iter().enumerate(){c.checkpoint()?;if NAME_PARAMS.contains(&p.as_str())||(om_set&&p=="name"){crate::raw_tree_report::row(c,&mut idx)?;idx.push(k);}}
        if !idx.is_empty() {
            put(&mut out,&proc.name,&idx,c)?;
        }
    }
    c.checkpoint()?;Ok(out)
}

/// `call_pattern`: `(?<![\w./:])(a|b|...)\s*\(` over the sorted accessor names.
pub(crate) fn call_pattern(accessors:&Accessors)->Pat{call_pattern_using(accessors,&mut crate::key_policy_control::Compatibility).expect("original accessor pattern")}
pub fn call_pattern_using<C:Control>(accessors:&Accessors,c:&mut C)->Result<Pat,C::Error>{c.checkpoint()?;let mut size=0usize;for name in accessors.keys(){c.checkpoint()?;size=size.checked_add(name.len()).and_then(|n|n.checked_add(1)).ok_or_else(||c.overflow())?;}crate::key_policy_control::reserve(c,||size.checked_mul(8)?.checked_add(accessors.len().checked_mul(4*std::mem::size_of::<&str>())?)?.checked_add(4096))?;
    let mut names: Vec<&str> = accessors.keys().map(|s| s.as_str()).collect();
    names.sort();
    c.checkpoint()?;Ok(Pat::new(&format!(r"(?<![\w./:])({})\s*\(", names.join("|"))))
}

/// `scan_file` of the Python: a call whose var-name argument, in the raw text, is a string literal.
pub(crate) fn scan_lines(f:&SourceFile,accessors:&Accessors,pattern:&Pat,out:&mut Vec<(&'static str,usize)>){scan_lines_using(f,accessors,pattern,out,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).expect("original string-name judge")}
pub fn scan_lines_using<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,accessors:&Accessors,pattern:&Pat,out:&mut Vec<(&'static str,usize)>,keep:&mut C,temp:&mut T)->Result<(),C::Error>{keep.checkpoint()?;crate::key_policy_control::reserve(temp,||f.text().len().checked_mul(128)?.checked_add(4096))?;
    let named_arg = pat_match!(r"\s*([A-Za-z_]\w*)\s*=(?!=)");
    let string_arg = pat_match!(r#"\s*(?:"|\{")"#);
    let raw = f.raw();
    for (number, code) in f.clean().numbered() {
        keep.checkpoint()?;
        let rawline = raw.line(number);
        for m in pattern.captures_iter(code) {
            keep.checkpoint()?;
            // Definitions (`/proc/own_set(`) are excluded by the lookbehind on "/".
            let Some(spans) = call_arg_spans(code, m.end(0) - 1) else { continue };
            let positional: Vec<&(usize, usize)> = spans.iter().filter(|sp| !named_arg.is_match(code.get(sp.0..sp.1).unwrap_or(""))).collect();
            let mut hit = false;
            for index in &accessors[m.s(1)] {
                keep.checkpoint()?;
                if *index < positional.len() {
                    let (start, end) = *positional[*index];
                    // Argument boundaries come from the sanitized text; the literal check from the raw text.
                    if string_arg.is_match(rawline.get(start..end).unwrap_or("")) {
                        hit = true;
                        break;
                    }
                }
            }
            if hit {
                crate::raw_tree_report::row(keep,out)?;out.push(("dx_string_names",number));
                break;
            }
        }
    }
    keep.checkpoint()?;Ok(())
}

pub fn scan(tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let idx = DxIndex::get(tree, files);
    let mut accessors = accessors_from(&idx.procs);
    if accessors.is_empty() {
        accessors = fallback();
    }
    let mut keyed_view: Vec<(&String, &Vec<usize>)> = accessors.iter().collect();
    keyed_view.sort();
    let key = incr::ctx_key(&keyed_view);
    // The regex is compiled on first use only: a fully cached run never needs it.
    let pattern: OnceLock<Pat> = OnceLock::new();
    let results = incr::keyed("sys-dx-string-names", key, files, |f| {
        let text = f.text();
        if !text.contains("own_") && !text.contains("rel_") && !text.contains("om_set") && !text.contains("time") {
            return Vec::new();
        }
        let mut v = Vec::new();
        scan_lines(f, &accessors, pattern.get_or_init(|| call_pattern(&accessors)), &mut v);
        v.into_iter().map(|(_, n)| n as u32).collect::<Vec<u32>>()
    });
    let mut out = Vec::new();
    for (f, v) in files.iter().zip(results) {
        out.extend(v.into_iter().map(|n| ("dx_string_names", f.rel.clone(), n as usize)));
    }
    out
}


fn put<C:Control>(map:&mut Accessors,name:&str,idx:&[usize],c:&mut C)->Result<(),C::Error>{c.checkpoint()?;if C::CHECKED&&map.len()==map.capacity()&&!map.contains_key(name){let target=map.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||c.overflow())?;let bound=target.checked_mul(4).ok_or_else(||c.overflow())?;crate::key_policy_control::reserve(c,||bound.checked_mul(std::mem::size_of::<(String,Vec<usize>)>())?.checked_add(4096))?;map.try_reserve(target-map.len()).map_err(|_|c.allocation_failed())?;if map.capacity()>bound{return Err(c.allocation_failed())}}let mut values=Vec::new();for &index in idx{c.checkpoint()?;crate::raw_tree_report::row(c,&mut values)?;values.push(index);}map.insert(crate::raw_tree_report::own(c,name)?,values);Ok(())}
pub fn file_accessors<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,c:&mut C,temp:&mut T)->Result<Accessors,C::Error>{c.checkpoint()?;crate::key_policy_control::reserve(temp,||f.text().len().checked_mul(f.rel.len().checked_mul(4)?.checked_add(512)?)?.checked_add(4096))?;let procs=crate::dm::dx::procs_in(f);accessors_from_using(&procs,c)}
pub fn merge<'a,C:Control>(rows:impl IntoIterator<Item=&'a Accessors>,c:&mut C)->Result<Accessors,C::Error>{let mut map=HashMap::new();for row in rows{c.checkpoint()?;for(name,idx)in row{put(&mut map,name,idx,c)?;}}if map.is_empty(){map=fallback_using(c)?;}c.checkpoint()?;Ok(map)}
pub fn selected(text:&str)->bool{text.contains("own_")||text.contains("rel_")||text.contains("om_set")||text.contains("time")}
