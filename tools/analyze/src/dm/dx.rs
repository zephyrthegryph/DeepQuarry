//! Port of `tools/ci/sys_rules/_dx_dm.py`: the DM scanning helpers the dx_* rules, `ui_actions`
//! and `doc_snippets` share. Everything here is a static approximation of DM, good enough for
//! ratchet lints:
//!
//! * [`crate::strip::sanitize`] (via `SourceFile::clean()`): comments removed and string text
//!   blanked, code inside an embedded `[expr]` kept; same length, same newlines.
//! * [`DxIndex`]: every absolute proc definition ([`Proc`]) and `{type path: var names}`, built once
//!   per file set and shared by every rule that asks (`DxIndex::get`).
//! * [`lineage`] / [`vars_of`]: a type's ancestors (path prefixes plus DM's implicit parents).
//! * [`call_args`], [`enclosing_call`], [`pick_arg`], [`proc_ref`]: call-site parsing.
//!
//! Limits (unchanged from the Python): relative proc definitions are not seen, `parent_type`
//! overrides are ignored, macro-generated procs are invisible.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use crate::pat;
use crate::tree::{SourceFile, Tree};
use crate::util::{py_rstrip, py_strip};

/// DM's builtin vars (datum, atom, movable, mob, obj, turf, area, client-facing), never declared in code.
pub const BUILTIN_VARS: &[&str] = &[
    "type",
    "parent_type",
    "tag",
    "vars",
    "name",
    "desc",
    "suffix",
    "text",
    "icon",
    "icon_state",
    "icon_w",
    "icon_h",
    "dir",
    "layer",
    "plane",
    "alpha",
    "color",
    "blend_mode",
    "appearance",
    "appearance_flags",
    "density",
    "opacity",
    "anchored",
    "loc",
    "locs",
    "x",
    "y",
    "z",
    "contents",
    "overlays",
    "underlays",
    "vis_contents",
    "vis_locs",
    "vis_flags",
    "verbs",
    "luminosity",
    "invisibility",
    "infra_luminosity",
    "mouse_opacity",
    "mouse_over_pointer",
    "mouse_drag_pointer",
    "mouse_drop_pointer",
    "mouse_drop_zone",
    "pixel_x",
    "pixel_y",
    "pixel_w",
    "pixel_z",
    "step_x",
    "step_y",
    "step_size",
    "bound_x",
    "bound_y",
    "bound_width",
    "bound_height",
    "glide_size",
    "gender",
    "maptext",
    "maptext_width",
    "maptext_height",
    "maptext_x",
    "maptext_y",
    "transform",
    "filters",
    "render_source",
    "render_target",
    "screen_loc",
    "animate_movement",
    "override",
    "ckey",
    "key",
    "client",
    "sight",
    "see_in_dark",
    "see_invisible",
    "see_infrared",
    "group",
    "particles",
    "areas",
    "world",
];

// ---- small parsing helpers --------------------------------------------------------------------

/// `split_top`: splits `text` on `sep` outside `()`, `[]`, `{}` and quotes.
pub fn split_top(text:&str,sep:char)->Vec<String>{match split_top_using(text,sep,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}
pub fn split_top_using<C:crate::key_policy_control::Control>(text:&str,sep:char,c:&mut C)->Result<Vec<String>,C::Error>{use crate::key_policy_control as kc;let mut parts=Vec::new();let mut depth=0i32;let mut cur=String::new();let mut quote=None;for ch in text.chars(){c.checkpoint()?;if let Some(q)=quote{controlled_char(&mut cur,ch,c)?;if ch==q{quote=None}continue}if ch=='"'||ch=='\''{quote=Some(ch)}else if ch=='('||ch=='['||ch=='{'{depth+=1;}else if ch==')'||ch==']'||ch=='}'{depth-=1;}else if ch==sep&&depth==0{kc::row(c,&mut parts)?;parts.push(std::mem::take(&mut cur));continue}controlled_char(&mut cur,ch,c)?;}kc::row(c,&mut parts)?;parts.push(cur);Ok(parts)}
fn controlled_char<C:crate::key_policy_control::Control>(out:&mut String,ch:char,c:&mut C)->Result<(),C::Error>{if C::CHECKED{let need=out.len().checked_add(ch.len_utf8()).ok_or_else(||c.overflow())?;if need>out.capacity(){let cap=need.max(out.capacity().saturating_mul(2)).max(64);crate::key_policy_control::reserve(c,||cap.checked_add(64))?;out.try_reserve_exact(cap-out.len()).map_err(|_|c.allocation_failed())?;}}out.push(ch);Ok(())}
/// Original parameter normalization, including its raw '='/'as' quirks.
pub fn param_names(params:&str)->Vec<String>{match param_names_using(params,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}
pub fn param_names_using<C:crate::key_policy_control::Control>(params:&str,c:&mut C)->Result<Vec<String>,C::Error>{use crate::key_policy_control as kc;let mut names=Vec::new();for part in split_top_using(params,',',c)?{c.checkpoint()?;let name=py_strip(part.split('=').next().unwrap_or(""));kc::reserve(c,||name.len().checked_add(64))?;let pattern=pat!(r"\bas\b.*$");let mut normalized=String::with_capacity(name.len());let(mut last,mut pos)=(0,0);while pos<=name.len(){c.checkpoint()?;let Some(found)=pattern.find_at(name,pos)else{break};normalized.push_str(&name[last..found.start]);last=found.end;pos=if found.start==found.end{found.end+name[found.end..].chars().next().map(|ch|ch.len_utf8()).unwrap_or(1)}else{found.end};}normalized.push_str(&name[last..]);let value=py_strip(py_strip(&normalized).rsplit('/').next().unwrap_or(""));let value=kc::own(c,value)?;if !value.is_empty()&&value!="..."{kc::row(c,&mut names)?;names.push(value);}}Ok(names)}

/// A proc definition: `/T/proc/name(args)`, `/T/verb/name(args)`, `/T/name(args)` (an override)
/// or `/proc/name(args)`. Bodies are line ranges into the file's sanitized view.
#[derive(Clone, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Proc {
    /// Set from the file after a facts load (not stored: the store is keyed by file).
    #[serde(skip)]
    pub rel: String,
    /// 1-based line of the head.
    pub line: usize,
    /// Owning type path; "/" for a global proc.
    pub path: String,
    pub name: String,
    pub params: Vec<String>,
    /// 1-based number of the first body line, and how many lines the body has.
    pub body_start: usize,
    pub body_len: usize,
}

impl Proc {
    pub fn is_global(&self) -> bool {
        self.path == "/"
    }

    /// `(line number, sanitized text)` of each body line.
    pub fn lines<'t>(&self, tree: &'t Tree) -> Vec<(usize, &'t str)> {
        match tree.get(&self.rel) {
            Some(f) => {
                let clean = f.clean();
                (0..self.body_len)
                    .map(|k| (self.body_start + k, clean.line(self.body_start + k)))
                    .collect()
            }
            None => Vec::new(),
        }
    }

    /// The sanitized body lines.
    pub fn body<'t>(&self, tree: &'t Tree) -> Vec<&'t str> {
        self.lines(tree).into_iter().map(|(_, t)| t).collect()
    }

    /// The raw (comment-bearing) body lines.
    pub fn raw_body<'t>(&self, tree: &'t Tree) -> Vec<&'t str> {
        match tree.get(&self.rel) {
            Some(f) => (0..self.body_len)
                .map(|k| f.line(self.body_start + k))
                .collect(),
            None => Vec::new(),
        }
    }

    /// The sanitized head line.
    pub fn head<'t>(&self, tree: &'t Tree) -> &'t str {
        tree.get(&self.rel)
            .map(|f| f.clean().line(self.line))
            .unwrap_or("")
    }
}

/// `procs_in`: every absolute proc definition in one file.
struct ProcHeaderParts<'a>{rel:&'a str,line:usize,path:String,name:&'a str,params:&'a str,body_start:usize,body_len:usize}
pub fn procs_in(f:&SourceFile)->Vec<Proc>{match procs_in_using(f,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}
/// SAME borrowed policy header producer, with owned row growth admitted once.
pub fn procs_in_using<C:crate::key_policy_control::Control>(f:&SourceFile,c:&mut C)->Result<Vec<Proc>,C::Error>{
 use crate::key_policy_control as kc;let mut out=Vec::new();
 walk_proc_headers(f,c,&mut|p,c|{kc::row(c,&mut out)?;out.push(Proc{rel:kc::own(c,p.rel)?,line:p.line,path:kc::own(c,&p.path)?,name:kc::own(c,p.name)?,params:param_names_using(p.params,c)?,body_start:p.body_start,body_len:p.body_len});Ok(())})?;c.checkpoint()?;Ok(out)
}
/// Exact original acceptance/owner/name projection, with source cancellation.
/// Borrowed names grant no source, declaration or model authority.
pub fn visit_proc_names_using<C:crate::key_policy_control::Control>(f:&SourceFile,control:&mut C,mut visit:impl FnMut(&str,&str)->Result<(),C::Error>)->Result<(),C::Error>{walk_proc_headers(f,control,&mut|p,_|visit(&p.path,p.name))}
/// Borrowed facts from the SAME policy-specific raw header walk. This lends
/// no model/source completion, and none of the header strings escape this call.
pub struct SourceProcHeader<'a>{pub rel:&'a str,pub line:usize,pub path:&'a str,pub name:&'a str,pub params:&'a str,pub body_start:usize,pub body_len:usize}
pub fn visit_proc_headers_using<C:crate::key_policy_control::Control>(f:&SourceFile,control:&mut C,mut visit:impl FnMut(SourceProcHeader<'_>,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{walk_proc_headers(f,control,&mut|p,control|visit(SourceProcHeader{rel:p.rel,line:p.line,path:&p.path,name:p.name,params:p.params,body_start:p.body_start,body_len:p.body_len},control))}
fn header_scratch<C:crate::key_policy_control::Control>(control:&mut C,held:&mut usize,width:usize)->Result<(),C::Error>{crate::raw_tree_report::peak(control,held,||width.checked_mul(12)?.checked_add(8192))}
fn walk_proc_headers<C:crate::key_policy_control::Control>(f:&SourceFile,control:&mut C,emit:&mut impl FnMut(ProcHeaderParts<'_>,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{
    control.checkpoint()?;
    let clean = f.clean();
    let n = clean.num_lines();
    let mut header_peak=0usize;
    let mut i = 0usize; // 0-based index into lines
    let line0 = |k: usize| clean.line(k + 1);
    while i < n {
        control.checkpoint()?;
        header_scratch(control,&mut header_peak,py_rstrip(line0(i)).len())?;
        let mut head = py_rstrip(line0(i)).to_string();
        let mut last = i;
        // A head continued with `\` (discouraged, but it exists): join its lines.
        while head.ends_with('\\') && last + 1 < n && head.starts_with('/') {
            control.checkpoint()?;
            last += 1;
            let width=head.len().checked_add(line0(last).len()).and_then(|n|n.checked_add(1)).ok_or_else(||control.overflow())?;header_scratch(control,&mut header_peak,width)?;
            head = format!("{} {}", &head[..head.len() - 1], py_strip(line0(last)));
        }
        // A parameter list spread over several lines: join until balanced.
        if head.starts_with('/') && head.contains('(') && count(&head, '(') > count(&head, ')') {
            let mut joined = head.clone();
            let mut k = last;
            while count(&joined, '(') > count(&joined, ')') && k + 1 < n && k - last < 40 {
                control.checkpoint()?;
                k += 1;
                let width=joined.len().checked_add(line0(k).len()).and_then(|n|n.checked_add(1)).ok_or_else(||control.overflow())?;header_scratch(control,&mut header_peak,width)?;
                joined = format!("{} {}", joined, py_strip(line0(k)));
            }
            if count(&joined, '(') == count(&joined, ')') {
                head = joined;
                last = k;
            }
        }
        let Some(m) = pat!(r"^(/[\w/]*?)/(?:(?:proc|verb)/)?(\w+)\((.*)\)\s*(?:as\s+[\w/|]+\s*)?$")
            .captures(&head)
        else {
            i += 1;
            continue;
        };
        if format!("{}/", m.s(1)).contains("/var/") {
            i += 1;
            continue;
        }
        let mut path = if m.s(1).is_empty() {
            "/".to_string()
        } else {
            m.s(1).to_string()
        };
        if path == "/proc" || path == "/verb" {
            path = "/".to_string();
        }
        let start = last + 1;
        let mut j = start;
        while j < n {
            control.checkpoint()?;
            let l = line0(j);
            if py_strip(l).is_empty() || l.starts_with([' ', '\t']) || l.is_empty() {
                j += 1;
            } else {
                break;
            }
        }
        emit(ProcHeaderParts {
            rel: &f.rel,
            line: i + 1,
            path,
            name: m.s(2),
            params: m.s(3),
            body_start: start + 1,
            body_len: j - start,
        },control)?;
        i = j;
    }
    control.checkpoint()?;Ok(())
}

fn count(s: &str, c: char) -> usize {
    s.chars().filter(|&x| x == c).count()
}

/// [`type_vars`] of every `.dm` file of the tree, each file's table cached by content (`incr::facts`) and built once per run: only an
/// edited file is scanned again.
pub fn type_vars_by_file(
    tree: &crate::tree::Tree,
) -> std::sync::Arc<HashMap<String, Vec<(String, Vec<String>)>>> {
    tree.memo("dx/type-vars-by-file", || {
        let files = tree.select(&crate::tree::CODE_DM);
        let per: Vec<Vec<(String, Vec<String>)>> =
            crate::incr::facts("dx-type-vars", &files, |f| {
                let mut v: Vec<(String, Vec<String>)> = type_vars(&[f])
                    .into_iter()
                    .map(|(k, s)| {
                        let mut s: Vec<String> = s.into_iter().collect();
                        s.sort();
                        (k, s)
                    })
                    .collect();
                v.sort();
                v
            });
        files.iter().map(|f| f.rel.clone()).zip(per).collect()
    })
}

/// [`type_vars`] of `files` (files of `tree`), from [`type_vars_by_file`].
pub fn type_vars_in(
    tree: &crate::tree::Tree,
    files: &[&SourceFile],
) -> HashMap<String, HashSet<String>> {
    let by = type_vars_by_file(tree);
    let mut table: HashMap<String, HashSet<String>> = HashMap::new();
    for f in files {
        match by.get(&f.rel) {
            Some(rows) => {
                for (t, vs) in rows {
                    table
                        .entry(t.clone())
                        .or_default()
                        .extend(vs.iter().cloned());
                }
            }
            None => {
                for (t, vs) in type_vars(&[f]) {
                    table.entry(t).or_default().extend(vs);
                }
            }
        }
    }
    table
}

/// `type_vars`: `{type path: var names}` declared in the files (both `/T/var/x` and a `var/x` line
/// inside a `/T` block, and grouped `var` blocks).
pub fn type_vars(files: &[&SourceFile]) -> HashMap<String, HashSet<String>> {
    let mut table: HashMap<String, HashSet<String>> = HashMap::new();
    for file in files {
        crate::raw_type_vars_policy::visit(&file.clean().text, |owner, name| {
            table
                .entry(owner.to_string())
                .or_default()
                .insert(name.to_string());
        });
    }
    table
}

/// One file's contribution to every [`DxIndex`]: its procs and its `{type: vars}` table. A pure
/// function of the file, cached on disk by content.
#[derive(Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct FileDx {
    pub procs: Vec<Proc>,
    /// `(type path, var names)`, sorted.
    pub vars: Vec<(String, Vec<String>)>,
}

fn file_dx(f:&SourceFile)->FileDx{match file_dx_using(f,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}
/// SAME original absolute-proc and raw type-var projections. No model/source
/// witness or incremental cache is issued by this standalone DATA operation.
pub fn file_dx_using<C:crate::key_policy_control::Control,T:crate::key_policy_control::Control<Error=C::Error>>(f:&SourceFile,keep:&mut C,temp:&mut T)->Result<FileDx,C::Error>{
 use crate::key_policy_control as kc;let mut table=HashMap::<String,HashSet<String>>::new();
 crate::raw_type_vars_policy::visit_with(&f.clean().text,temp,&mut|owner,name|{keep.checkpoint()?;if !table.contains_key(owner){kc::hash_room(keep,&mut table)?;table.insert(kc::own(keep,owner)?,HashSet::new());}let names=table.get_mut(owner).expect("actual just-admitted own-var row");if !names.contains(name){kc::set_room(keep,names)?;names.insert(kc::own(keep,name)?);}Ok(())})?;
 let mut vars=Vec::new();for(owner,names)in table{keep.checkpoint()?;let mut owned_names=Vec::new();for name in names{kc::row(keep,&mut owned_names)?;owned_names.push(name);}let mut names=owned_names;kc::sort_data(&mut names,&mut|a,b|->Result<std::cmp::Ordering,C::Error>{keep.checkpoint()?;Ok(a.cmp(b))})?;kc::row(keep,&mut vars)?;vars.push((owner,names));}
 kc::sort_data(&mut vars,&mut|a,b|->Result<std::cmp::Ordering,C::Error>{keep.checkpoint()?;Ok(a.0.cmp(&b.0))})?;
 let procs=procs_in_using(f,keep)?;keep.checkpoint()?;Ok(FileDx{procs,vars})
}
/// The cached [`FileDx`] of every `.dm` file under `code/` and `maps/` (dot-files included), looked
/// up by path. One superset store serves every file set a lint asks about, so a lint with
/// different exemptions never evicts another's entries.
pub struct DxFacts {
    facts: Vec<FileDx>,
    index: HashMap<String, usize>,
}

impl DxFacts {
    /// The facts of the whole tree, built once per run.
    pub fn all(tree: &Tree) -> Arc<DxFacts> {
        tree.memo("dx-facts-all", || {
            let sel = crate::tree::Select {
                roots: &[("code", "dm"), ("maps", "dm")],
                hidden: true,
            };
            let files = tree.select(&sel);
            let mut facts = crate::incr::facts("dx-file-facts", &files, file_dx);
            for (fd, f) in facts.iter_mut().zip(&files) {
                for p in &mut fd.procs {
                    p.rel.clone_from(&f.rel);
                }
            }
            let index = files
                .iter()
                .enumerate()
                .map(|(i, f)| (f.rel.clone(), i))
                .collect();
            DxFacts { facts, index }
        })
    }

    /// The facts of `f`, from the store when it is in the tree's superset.
    pub fn of(&self, f: &SourceFile) -> std::borrow::Cow<'_, FileDx> {
        match self.index.get(&f.rel) {
            Some(&i) => std::borrow::Cow::Borrowed(&self.facts[i]),
            None => std::borrow::Cow::Owned(file_dx(f)),
        }
    }
}

/// One parse of a file set, shared by every rule that asks for the same set.
pub struct DxIndex {
    pub procs: Vec<Proc>,
    pub type_vars: HashMap<String, HashSet<String>>,
    by_name: HashMap<String, Vec<usize>>,
}

impl DxIndex {
    /// The index for exactly this list of files, built once per run.
    pub fn get(tree: &Tree, files: &[&SourceFile]) -> Arc<DxIndex> {
        let mut h = blake3::Hasher::new();
        h.update(b"dx-index");
        for f in files {
            h.update(&f.fkey.to_le_bytes());
        }
        let key = h.finalize().to_hex().to_string();
        let facts = DxFacts::all(tree);
        tree.memo(&key, || {
            let mut procs: Vec<Proc> = Vec::new();
            let mut table: HashMap<String, HashSet<String>> = HashMap::new();
            for f in files {
                let fd = facts.of(f);
                procs.extend(fd.procs.iter().cloned());
                for (t, vs) in &fd.vars {
                    table
                        .entry(t.clone())
                        .or_default()
                        .extend(vs.iter().cloned());
                }
            }
            let mut by_name: HashMap<String, Vec<usize>> = HashMap::new();
            for (i, p) in procs.iter().enumerate() {
                by_name.entry(p.name.clone()).or_default().push(i);
            }
            DxIndex {
                type_vars: table,
                procs,
                by_name,
            }
        })
    }

    pub fn procs_named(&self, name: &str) -> Vec<&Proc> {
        self.by_name
            .get(name)
            .map(|v| v.iter().map(|&i| &self.procs[i]).collect())
            .unwrap_or_default()
    }
}

// ---- types ------------------------------------------------------------------------------------

fn implicit_parent(path: &str) -> Option<&'static str> {
    match path {
        "/obj" | "/mob" => Some("/atom/movable"),
        "/atom/movable" => Some("/atom"),
        "/turf" | "/area" => Some("/atom"),
        "/atom" => Some("/datum"),
        _ => None,
    }
}

/// The path prefixes of `path`, shortest first (`path` included).
pub fn ancestors(path:&str)->Vec<String>{match ancestors_using(path,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}
pub fn ancestors_using<C:crate::key_policy_control::Control>(path:&str,c:&mut C)->Result<Vec<String>,C::Error>{use crate::key_policy_control as kc;c.checkpoint()?;let trimmed=path.trim_end_matches('/');let mut parts=Vec::new();for part in trimmed.split('/'){c.checkpoint()?;kc::row(c,&mut parts)?;parts.push(part);}let mut out=Vec::new();for k in 2..=parts.len(){c.checkpoint()?;let mut bytes=k-1;for part in &parts[..k]{c.checkpoint()?;bytes=bytes.checked_add(part.len()).ok_or_else(||c.overflow())?;}kc::reserve(c,||bytes.checked_add(64))?;let value=parts[..k].join("/");kc::row(c,&mut out)?;out.push(value);}Ok(out)}
/// Original lexical ancestry and implicit-parent table; not native model inheritance.
pub fn lineage(path:&str)->Vec<String>{match lineage_using(path,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}
pub fn lineage_using<C:crate::key_policy_control::Control>(path:&str,c:&mut C)->Result<Vec<String>,C::Error>{use crate::key_policy_control as kc;let mut out=ancestors_using(path,c)?;out.reverse();let mut root=match out.last(){Some(value)=>Some(kc::own(c,value)?),None=>None};loop{c.checkpoint()?;let Some(r)=&root else{break};match implicit_parent(r){Some(p)=>{let row=kc::own(c,p)?;kc::row(c,&mut out)?;out.push(row);root=Some(kc::own(c,p)?);},None=>break}}
    const NON_DATUM: &[&str] = &[
        "/client",
        "/world",
        "/list",
        "/savefile",
        "/regex",
        "/icon",
        "/image",
        "/sound",
        "/matrix",
        "/database",
        "/exception",
        "/generator",
        "/mutable_appearance",
        "/particles",
        "/dm_filter",
        "/callee",
    ];
    if let Some(last)=out.last(){c.checkpoint()?;if last!="/datum"&&!NON_DATUM.contains(&last.as_str()){let row=kc::own(c,"/datum")?;kc::row(c,&mut out)?;out.push(row);}}Ok(out)
}

pub fn is_subtype(path: &str, base: &str) -> bool {
    lineage(path).iter().any(|p| p == base)
}

/// `a` and `b` are the same type, or one descends from the other.
pub fn related(a: &str, b: &str) -> bool {
    is_subtype(a, b) || is_subtype(b, a)
}

/// The vars of `path` and its lineage, plus DM's builtin atom vars when `builtins`.
pub fn vars_of(table:&HashMap<String,HashSet<String>>,path:&str,builtins:bool)->HashSet<String>{match vars_of_using(table,path,builtins,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}
pub fn vars_of_using<C:crate::key_policy_control::Control>(table:&HashMap<String,HashSet<String>>,path:&str,builtins:bool,c:&mut C)->Result<HashSet<String>,C::Error>{
 use crate::key_policy_control as kc;let mut out=HashSet::new();
 let mut add=|name:&str,c:&mut C|->Result<(),C::Error>{c.checkpoint()?;if !out.contains(name){kc::set_room(c,&mut out)?;out.insert(kc::own(c,name)?);}Ok(())};
 if builtins{for name in BUILTIN_VARS{add(name,c)?;}}
 for ancestor in lineage_using(path,c)?{c.checkpoint()?;if let Some(names)=table.get(&ancestor){for name in names{add(name,c)?;}}}
 c.checkpoint()?;Ok(out)
}

// ---- calls ------------------------------------------------------------------------------------

/// Index of the `)` closing the `(` at `text[i]` (brackets count like parens), or None.
pub fn match_paren(text: &str, i: usize) -> Option<usize> {
    let b = text.as_bytes();
    let mut depth = 0i32;
    for (j, &c) in b.iter().enumerate().skip(i) {
        if c == b'(' || c == b'[' {
            depth += 1;
        } else if c == b')' || c == b']' {
            depth -= 1;
            if depth == 0 {
                return Some(j);
            }
        }
    }
    None
}

/// The argument strings (trimmed) of the call whose `(` is at `text[i]`.
pub fn call_args(text:&str,i:usize)->Option<Vec<String>>{match call_args_using(text,i,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}
pub fn call_args_using<C:crate::key_policy_control::Control>(text:&str,i:usize,c:&mut C)->Result<Option<Vec<String>>,C::Error>{use crate::key_policy_control as kc;c.checkpoint()?;let Some(end)=match_paren(text,i)else{return Ok(None)};let mut out=Vec::new();for arg in split_top_using(&text[i+1..end],',',c)?{c.checkpoint()?;kc::row(c,&mut out)?;out.push(kc::own(c,py_strip(&arg))?);}c.checkpoint()?;Ok(Some(out))}

/// `(start, end)` byte offsets of each argument of the call whose `(` is at `text[i]`.
pub fn call_arg_spans(text: &str, i: usize) -> Option<Vec<(usize, usize)>> {
    let end = match_paren(text, i)?;
    let b = text.as_bytes();
    let mut spans = Vec::new();
    let mut depth = 0i32;
    let mut start = i + 1;
    for k in i + 1..end {
        match b[k] {
            b'(' | b'[' | b'{' => depth += 1,
            b')' | b']' | b'}' => depth -= 1,
            b',' if depth == 0 => {
                spans.push((start, k));
                start = k + 1;
            }
            _ => {}
        }
    }
    spans.push((start, end));
    Some(spans)
}

/// The argument at positional `index` (counting only positional args before any named one) or
/// named `name`, from [`call_args`] output.
pub fn pick_arg(args: &[String], index: Option<usize>, name: &str) -> Option<String> {
    let mut positional: Vec<&String> = Vec::new();
    for arg in args {
        if let Some(m) = pat!(r"^\s*([A-Za-z_]\w*)\s*=(?!=)").captures(arg) {
            if m.s(1) == name {
                return Some(py_strip(&arg[m.end(0)..]).to_string());
            }
            continue;
        }
        positional.push(arg);
    }
    match index {
        Some(i) if i < positional.len() => Some(positional[i].clone()),
        _ => None,
    }
}

/// For the expression starting at `text[i]`: (name, positional index, named-arg key, member call?)
/// of the innermost call it is a direct argument of. `member` is only meaningful with
/// `want_member`.
#[derive(Clone, Debug, PartialEq)]
pub struct Enclosing {
    pub name: String,
    pub index: usize,
    pub key: Option<String>,
    pub member: bool,
}

pub fn enclosing_call(text:&str,i:usize)->Option<Enclosing>{match enclosing_call_using(text,i,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}
/// SAME backward/argument scan, including its original bracket/string quirks.
/// Actual typed failure returns immediately and never becomes a missing call.
pub fn enclosing_call_using<C:crate::key_policy_control::Control>(text:&str,i:usize,c:&mut C)->Result<Option<Enclosing>,C::Error>{
 use crate::key_policy_control as kc;c.checkpoint()?;let b=text.as_bytes();let mut depth=0i32;let mut commas=0usize;let mut j=i as isize-1;
 while j>=0{c.checkpoint()?;let ju=j as usize;let ch=b[ju];if ch==b')'||ch==b']'{depth+=1;}else if ch==b'('||ch==b'['{if depth==0{if ch==b'['{return Ok(None)}let before=&text[..ju];let pattern=pat!(r"([A-Za-z_]\w*)\s*$");kc::reserve(c,||pattern.capture_group_count().checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128))?;let Some(m)=pattern.captures(before)else{return Ok(None)};let mut seg_start=ju+1;let mut d2=0i32;for k in ju+1..i{c.checkpoint()?;match b[k]{b'('|b'['=>d2+=1,b')'|b']'=>d2-=1,b',' if d2==0=>seg_start=k+1,_=>{}}}let pattern=pat!(r"\A\s*([A-Za-z_]\w*)\s*=(?!=)");kc::reserve(c,||pattern.capture_group_count().checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128))?;c.checkpoint()?;let key=match pattern.captures(&text[seg_start..i]){Some(k)=>Some(kc::own(c,k.s(1))?),None=>None};let head=py_rstrip(&text[..m.start(0)]);let name=kc::own(c,m.s(1))?;c.checkpoint()?;return Ok(Some(Enclosing{name,index:commas,key,member:head.ends_with('.')||head.ends_with(':')}));}depth-=1;}else if ch==b','&&depth==0{commas+=1;}j-=1;}Ok(None)
}

/// `proc_ref`: `(kind, type, name)` for a PROC_REF-family argument. `kind` is "src" (PROC_REF,
/// VERB_REF: the calling type), "type" (TYPE_PROC_REF/TYPE_VERB_REF) or "global".
pub fn proc_ref(arg: &str) -> Option<(&'static str, Option<String>, String)> {
    let m = pat!(
        r"^\s*(?:PROC_REF\(\s*(\w+)\s*\)|TYPE_PROC_REF\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)|GLOBAL_PROC_REF\(\s*(\w+)\s*\)|TYPE_VERB_REF\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)|VERB_REF\(\s*(\w+)\s*\))\s*$"
    )
    .captures(arg)?;
    if m.matched(1) {
        return Some(("src", None, m.s(1).to_string()));
    }
    if m.matched(3) {
        return Some(("type", Some(m.s(2).to_string()), m.s(3).to_string()));
    }
    if m.matched(4) {
        return Some(("global", None, m.s(4).to_string()));
    }
    if m.matched(6) {
        return Some(("type", Some(m.s(5).to_string()), m.s(6).to_string()));
    }
    Some(("src", None, m.s(7).to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn split_top_respects_nesting() {
        assert_eq!(
            split_top("a, f(b, c), [d, e], \"x,y\"", ','),
            vec!["a", " f(b, c)", " [d, e]", " \"x,y\""]
        );
    }

    #[test]
    fn procs_and_params() {
        let f = SourceFile::from_text(
            "code/a.dm",
            "/obj/thing/proc/poke(mob/user, amount = 1)\n\tif(amount)\n\t\treturn\n\n/obj/thing/other()\n\treturn 1\n",
        );
        let p = procs_in(&f);
        assert_eq!(p.len(), 2);
        assert_eq!(p[0].path, "/obj/thing");
        assert_eq!(p[0].name, "poke");
        assert_eq!(p[0].params, vec!["user", "amount"]);
        assert_eq!(p[0].body_len, 3);
        assert_eq!(p[1].name, "other");
    }

    #[test]
    fn lineage_adds_implicit_parents() {
        assert_eq!(
            lineage("/obj/item"),
            vec!["/obj/item", "/obj", "/atom/movable", "/atom", "/datum"]
        );
        assert_eq!(lineage("/datum/foo"), vec!["/datum/foo", "/datum"]);
        assert!(lineage("/").is_empty());
        assert_eq!(lineage("/client"), vec!["/client"]);
    }

    #[test]
    fn enclosing_call_finds_argument_position() {
        let text = "foo(a, bar(x, y = baz))";
        let at = text.find("baz").unwrap();
        let e = enclosing_call(text, at).unwrap();
        assert_eq!(e.name, "bar");
        assert_eq!(e.index, 1);
        assert_eq!(e.key.as_deref(), Some("y"));
    }

    #[test]
    fn type_vars_collects_blocks() {
        let f = SourceFile::from_text(
            "code/a.dm",
            "/obj/thing\n\tvar/a = 1\n\tvar\n\t\tb\n\t\tc = 2\n/obj/thing/var/d\n",
        );
        let t = type_vars(&[&f]);
        let v = &t["/obj/thing"];
        assert!(v.contains("a") && v.contains("b") && v.contains("c") && v.contains("d"));
    }
}
