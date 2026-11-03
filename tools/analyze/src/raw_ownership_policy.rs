//! Original raw ownership source events, shared by legacy Index and native
//! declaration policy. This module has no semantic/model/Index dependency.
//! Extraction only: regexes, order, type-part and declaration-kind policy unchanged.
use crate::{
    pat::Pat,
    tree::View,
    util::{is_py_space, py_rstrip, py_strip},
};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    sync::{Arc, LazyLock},
};
macro_rules! re_m {
    ($name:ident,$p:expr) => {
        pub static $name: LazyLock<Pat> = LazyLock::new(|| Pat::new_match($p));
    };
}
/// Flyweights (code/datums/ownership/flyweight.dm, GLOB.flyweight_types; keep in step).
pub const FLYWEIGHT_TYPES: &[&str] = &[
    "/datum/capability",
    "/datum/reaction",
    "/datum/stack_recipe",
    "/datum/stack_recipe_list",
    "/datum/own_entry",
    "/datum/derived_entry",
    "/datum/op_def",
    "/datum/material",
];
pub const MODIFIERS: &[&str] = &["tmp", "static", "global", "const", "final"];

re_m!(TYPE_LINE, r"^(/[\w/]+)\s*(?:\{.*)?$");

re_m!(
    MEMBER,
    r"^\s+(?:var|VAR_PRIVATE|VAR_PROTECTED|VAR_FINAL)/((?:[\w]+/)*)(\w+)\b"
);

re_m!(
    OM_FIELD_DECL,
    r"^OM_FIELD(?:(?:_TYPED|_VIEW)\(\s*(/[\w/]+)\s*,\s*([\w/]+)\s*,|\(\s*(/[\w/]+)\s*,())\s*(\w+)\s*,"
);

re_m!(
    ABS_MEMBER,
    r"^(/[\w/]+?)/(?:var|VAR_PRIVATE|VAR_PROTECTED|VAR_FINAL)/((?:[\w]+/)*)(\w+)\b"
);

re_m!(DECLARE_HEAD, r"^(/[\w/]+)/(?:ownership|relations)\(\)");

re_m!(
    DECLARE_CALL,
    r"^\s+\.\s*\+=\s*(owns|shares|proto|rel_one|rel_many)\(\s*nameof\((\w+)\)\s*(?:,\s*(.*?))?\)\s*(?://.*)?$"
);

re_m!(
    GLOBAL_DECL,
    r"^GLOBAL_(DATUM_INIT|DATUM|LIST_INIT_TYPED|LIST_EMPTY_TYPED|LIST_INIT|LIST_EMPTY|LIST|ALIST_INIT|ALIST_EMPTY|ALIST|VAR_INIT|VAR_CONST|VAR)\(\s*(\w+)\s*(?:,\s*(/[\w/]+))?"
);

re_m!(REGISTRY, r"^REGISTRY_TYPE\(\s*(/[\w/]+)\s*,");

/// One structural fact a file contributes to the legacy structural index, in file order. Replaying every file's
/// events in path order rebuilds the index exactly as walking the files did.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub enum IdxEv {
    Member {
        owner: String,
        vtype: String,
        is_list: bool,
        name: String,
    },
    Decl {
        owner: String,
        name: String,
        macro_name: String,
        opts: String,
        rel: String,
        line: u32,
    },
    Registry(String),
    /// A var of `GLOB` declared through a `GLOBAL_*` macro.
    Global {
        name: String,
        vtype: String,
        is_list: bool,
    },
}

/// `(vtype, is_list)` of a member declared with the path segments `segs`.
pub(crate) fn member_parts(segs: &str) -> (String, bool) {
    let mut parts: Vec<&str> = segs
        .split('/')
        .filter(|p| !p.is_empty() && !MODIFIERS.contains(p))
        .collect();
    let is_list = !parts.is_empty() && parts[0] == "list";
    if is_list {
        parts.remove(0);
    }
    let vtype = if parts.is_empty() {
        String::new()
    } else {
        format!("/{}", parts.join("/"))
    };
    (vtype, is_list)
}

/// The kind a declaration entry is recorded under (its old macro name).
fn decl_macro(func: &str, opts: &str) -> String {
    let own_private = pat_search(r"\bpolicy\s*=\s*OWN_PRIVATE_COPY\b", opts);
    if func == "owns" && own_private {
        "PROTO".into()
    } else if func == "owns" {
        if opts.contains("policy_proc") {
            "OWN_POLICY".into()
        } else if opts.contains("if_var") {
            "OWN_IF".into()
        } else if pat_search(r"\bpolicy\s*=\s*OWN_NONE\b", opts) {
            "ANNOTATE".into()
        } else {
            "OWN".into()
        }
    } else if func == "shares" {
        "SHARED".into()
    } else if func == "rel_one" || func == "rel_many" {
        if pat_search(r"\bkind\s*=\s*RELK_OWNED\b", opts) {
            if own_private {
                "PROTO".into()
            } else {
                "OWN".into()
            }
        } else {
            "REL".into()
        }
    } else {
        func.to_uppercase()
    }
}

/// Every structural fact `code`/`raw` (one file) contributes to the index, in order.
pub fn file_events(rel: &str, raw: &View, code: &View) -> Vec<IdxEv> {
    let mut out = Vec::new();
    visit_file_events(rel, raw, code, |ev| {
        out.push(ev);
        Ok(())
    })
    .expect("infallible legacy collector");
    out
}
pub fn visit_file_events(
    rel: &str,
    raw: &View,
    code: &View,
    mut emit: impl FnMut(IdxEv) -> Result<(), String>,
) -> Result<(), String> {
    try_visit_file_events(rel,raw,code,&mut||Ok::<(),String>(()),emit)
}
/// SAME structural source events; failure/control do not become strings.
pub fn try_visit_file_events<E>(rel:&str,raw:&View,code:&View,checkpoint:&mut impl FnMut()->Result<(),E>,emit:impl FnMut(IdxEv)->Result<(),E>)->Result<(),E>{
    struct OriginalPoll<'a,E,F>{checkpoint:&'a mut F,error:std::marker::PhantomData<fn()->E>}
    impl<E,F:FnMut()->Result<(),E>> crate::key_policy_control::Control for OriginalPoll<'_,E,F>{type Error=E;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),E>{(self.checkpoint)()}fn reserve(&mut self,_:usize)->Result<(),E>{Ok(())}fn overflow(&mut self)->E{unreachable!("original path does not evaluate resource bounds")}fn allocation_failed(&mut self)->E{unreachable!("original allocation APIs unchanged")}}
    try_visit_file_events_funded(rel,raw,code,&mut OriginalPoll{checkpoint,error:std::marker::PhantomData},emit)
}
/// Same original branches/order; only actual matched constructor temporaries are prefunded.
pub fn try_visit_file_events_funded<C:crate::key_policy_control::Control>(rel:&str,raw:&View,code:&View,c:&mut C,mut emit:impl FnMut(IdxEv)->Result<(),C::Error>)->Result<(),C::Error>{
    let mut current: Option<String> = None;
    let mut declaring: Option<String> = None;
    for (no, line) in code.numbered() {
        c.checkpoint()?;
        let first = line.chars().next();
        if matches!(first, Some('"') | Some('\'')) {
            continue; // the tail of a multi-line string, not a new top-level line
        }
        if declaring.is_some() && first.map(is_py_space).unwrap_or(false) {
            if let Some(m) = DECLARE_CALL.captures(raw.line(no)) {
                crate::key_policy_control::temporary(c,0,||declaring.as_ref()?.len().checked_add(m.s(1).len())?.checked_add(m.s(2).len())?.checked_add(m.s(3).len())?.checked_add(rel.len())?.checked_mul(16)?.checked_add(1024))?;
                let owner = declaring.clone().unwrap();
                emit(decl_ev(&owner, m.s(1), m.s(2), m.s(3), rel, no))?;
            }
            continue;
        }
        declaring = None;
        if first.map(|c| !is_py_space(c)).unwrap_or(false) {
            if let Some(m) = DECLARE_HEAD.captures(line) {
                crate::key_policy_control::temporary(c,0,||m.s(1).len().checked_mul(4)?.checked_add(128))?;
                declaring = Some(m.s(1).to_string());
                current = None;
                continue;
            }
            if let Some(m) = REGISTRY.captures(py_strip(raw.line(no))) {
                crate::key_policy_control::temporary(c,0,||m.s(1).len().checked_mul(4)?.checked_add(128))?;
                emit(IdxEv::Registry(m.s(1).to_string()))?;
                continue;
            }
            if let Some(m) = ABS_MEMBER.captures(line) {
                crate::key_policy_control::temporary(c,0,||m.s(1).len().checked_add(m.s(2).len())?.checked_add(m.s(3).len())?.checked_mul(32)?.checked_add(1024))?;
                emit(member_ev(m.s(1), m.s(2), m.s(3)))?;
                current = None;
                continue;
            }
            if let Some(m) = OM_FIELD_DECL.captures(line) {
                // OM_FIELD(T, F, ...) / OM_FIELD_TYPED|_VIEW(T, VT, F, ...) declare T/var/F
                crate::key_policy_control::temporary(c,0,||m.whole().len().checked_mul(32)?.checked_add(1024))?;
                let vt = if m.matched(2) && !m.s(2).is_empty() {
                    format!("{}/", m.s(2).trim_matches('/'))
                } else {
                    String::new()
                };
                let owner = if !m.s(1).is_empty() { m.s(1) } else { m.s(3) };
                emit(member_ev(owner, &vt, m.s(5)))?;
                current = None;
                continue;
            }
            // GLOBAL_*(x, ...) declares a var of /datum/controller/global_vars through a macro.
            if let Some(m) = GLOBAL_DECL.captures(line) {
                crate::key_policy_control::temporary(c,0,||m.whole().len().checked_mul(32)?.checked_add(1024))?;
                let (kind, name) = (m.s(1), m.s(2));
                let ty = if m.matched(3) {
                    m.s(3).trim_matches('/')
                } else {
                    ""
                };
                let segs = match kind {
                    "DATUM" | "DATUM_INIT" if !ty.is_empty() => format!("{}/", ty),
                    "LIST_INIT_TYPED" | "LIST_EMPTY_TYPED" if !ty.is_empty() => {
                        format!("list/{}/", ty)
                    }
                    k if k.starts_with("LIST") => "list/".to_string(),
                    k if k.starts_with("ALIST") => "alist/".to_string(),
                    _ => String::new(),
                };
                let (vtype, is_list) = member_parts(&segs);
                emit(IdxEv::Global {
                    name: name.to_string(),
                    vtype,
                    is_list,
                })?;
                current = None;
                continue;
            }
            // SYSTEM_DEF(x) declares /datum/system/x through a macro: its indented body is that type's block.
            if let Some(m) = crate::pat!(r"^SYSTEM_DEF\((\w+)\)\s*$").captures(py_rstrip(line)) {
                crate::key_policy_control::temporary(c,0,||m.s(1).len().checked_mul(4)?.checked_add(256))?;
                current = Some(format!("/datum/system/{}", m.s(1)));
                continue;
            }
            let m = TYPE_LINE.captures(py_rstrip(line));
            if let Some(m)=&m{crate::key_policy_control::temporary(c,0,||m.s(1).len().checked_mul(4)?.checked_add(128))?;}
            current = match m {
                Some(m) if !line.contains('(') => Some(m.s(1).to_string()),
                _ => None,
            };
            continue;
        }
        if let Some(cur)=current.as_ref(){crate::key_policy_control::temporary(c,0,||cur.len().checked_mul(4)?.checked_add(128))?;}
        if let Some(cur) = current.clone() {
            if let Some(m) = MEMBER.captures(line) {
                crate::key_policy_control::temporary(c,0,||cur.len().checked_add(m.s(1).len())?.checked_add(m.s(2).len())?.checked_mul(32)?.checked_add(1024))?;
                emit(member_ev(&cur, m.s(1), m.s(2)))?;
            }
        }
    }
    Ok(())
}

fn member_ev(owner: &str, segs: &str, name: &str) -> IdxEv {
    let (vtype, is_list) = member_parts(segs);
    IdxEv::Member {
        owner: owner.to_string(),
        vtype,
        is_list,
        name: name.to_string(),
    }
}

pub(crate) fn decl_ev(
    owner: &str,
    func: &str,
    name: &str,
    opts: &str,
    rel: &str,
    no: usize,
) -> IdxEv {
    IdxEv::Decl {
        owner: owner.to_string(),
        name: name.to_string(),
        macro_name: decl_macro(func, opts),
        opts: opts.to_string(),
        rel: rel.to_string(),
        line: no as u32,
    }
}

fn pat_search(p: &str, hay: &str) -> bool {
    // Compiled once per call site string; these four are tiny.
    static CACHE: LazyLock<std::sync::Mutex<HashMap<String, Arc<Pat>>>> =
        LazyLock::new(|| std::sync::Mutex::new(HashMap::new()));
    let pat = {
        let mut g = CACHE.lock().unwrap();
        g.entry(p.to_string())
            .or_insert_with(|| Arc::new(Pat::new(p)))
            .clone()
    };
    pat.is_match(hay)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn original_event_order_registry_global_members_and_legacy_policy_are_unchanged() {
        let f=crate::tree::SourceFile::from_text("code/events.dm","REGISTRY_TYPE(/datum/registry, x)\nGLOBAL_DATUM(holder, /datum)\n/datum/holder\n    var/static/list/datum/refs\n/datum/holder/relations()\n    . += owns(nameof(annotation))\n    . += rel_one(nameof(owned), kind = RELK_OWNED)\n    . += owns(nameof(copy), policy = OWN_PRIVATE_COPY)\nSYSTEM_DEF(grid)\n    var/tick\n");
        let events = file_events(&f.rel, f.raw(), f.code());
        assert_eq!(events.len(), 7);
        assert!(matches!(&events[0],IdxEv::Registry(t) if t=="/datum/registry"));
        assert!(
            matches!(&events[1],IdxEv::Global{name,vtype,is_list:false} if name=="holder"&&vtype=="/datum")
        );
        assert!(
            matches!(&events[2],IdxEv::Member{owner,vtype,is_list:true,name} if owner=="/datum/holder"&&vtype=="/datum"&&name=="refs")
        );
        for (position, name, kind, line) in [
            // The old decl_macro maps plain owns() to OWN; only explicit
            // policy = OWN_NONE is ANNOTATE. Preserve the scanner, repair the oracle.
            (3, "annotation", "OWN", 6),
            (4, "owned", "OWN", 7),
            (5, "copy", "PROTO", 8),
        ] {
            assert!(
                matches!(&events[position],IdxEv::Decl{owner,name:actual,macro_name,line:at,..} if owner=="/datum/holder"&&actual==name&&macro_name==kind&&*at==line)
            );
        }
        assert!(
            matches!(&events[6],IdxEv::Member{owner,name,..} if owner=="/datum/system/grid"&&name=="tick")
        );
    }
    #[test]
    fn native_stream_refuses_immediately_and_vec_wrapper_collects_exactly_the_same_events() {
        let f=crate::tree::SourceFile::from_text("code/events.dm","/datum/holder\n    var/a\n    var/b\n/datum/holder/relations()\n    . += rel_one(nameof(link))\n");
        let mut count = 0;
        let refused = visit_file_events(&f.rel, f.raw(), f.code(), |_| {
            count += 1;
            Err("admission denied".into())
        });
        assert_eq!(refused.unwrap_err(), "admission denied");
        assert_eq!(count, 1);
        let mut streamed = Vec::new();
        visit_file_events(&f.rel, f.raw(), f.code(), |event| {
            streamed.push(event);
            Ok(())
        })
        .unwrap();
        assert_eq!(streamed, file_events(&f.rel, f.raw(), f.code()));
    }
}

// Same original accessor pattern, shared with the lexical schema consumer.
pub const VAR_ARG: &str = r#"(?:"|nameof\((?:/[\w/]+::|\w+\.)?)(\w+)(?:"|\))"#;
pub static ACCESSOR: LazyLock<Pat> = LazyLock::new(|| {
    Pat::new(&format!(
        r"\b(own_set|own_take|own_add|own_remove|own_put|own_take_member|own_clear|own_transfer|rel_set|rel_add|rel_remove|rel_clear|rel_link|rel_unlink|proto_set|proto_private|shared_set)\(\s*([\w.]+)\s*,\s*{}",
        VAR_ARG
    ))
});

/// Exact original inherited lookup order, borrowing source path slices instead
/// of rebuilding a second parent roster. No semantic hierarchy is inferred.
pub fn visit_parents_using<C:crate::key_policy_control::Control>(path:&str,c:&mut C,emit:&mut dyn FnMut(&str,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{visit_parents_until_using(path,c,&mut|parent,c|{emit(parent,c)?;Ok(true)}).map(|_|())}
pub fn visit_parents_until_using<C:crate::key_policy_control::Control>(path:&str,c:&mut C,emit:&mut dyn FnMut(&str,&mut C)->Result<bool,C::Error>)->Result<bool,C::Error>{let mut current=path;let mut slashes=path.bytes().filter(|byte|*byte==b'/').count();let mut root=None;while !current.is_empty()&&slashes>=1{c.checkpoint()?;if !emit(current,c)?{return Ok(false)}if slashes==1{root=Some(current);break}let cut=current.rfind('/').expect("actual counted slash");current=&current[..cut];slashes-=1;}let implicit:&[&str]=match root{Some("/obj"|"/mob")=>&["/atom/movable","/atom","/datum"],Some("/turf"|"/area")=>&["/atom","/datum"],Some("/atom")=>&["/datum"],_=>&[]};for parent in implicit{c.checkpoint()?;if !emit(parent,c)?{return Ok(false)}}Ok(true)}
