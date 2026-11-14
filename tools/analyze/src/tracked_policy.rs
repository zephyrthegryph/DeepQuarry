//! Unique tracked/tracked_tests lexical judgment and fix policy.
//! Borrowed SourceFile views are actual caller loans; no Tree/Sem or completion is issued.
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};


use crate::lint::{Meta,Policy,RuleMeta,ScanKind,Sink};
use crate::pat::Pat;
use crate::tree::{SourceFile, View, CODE_MAPS_DM};
use crate::util::{is_py_space, py_lstrip, py_rstrip, py_strip};
use crate::{pat, pat_match};

pub(crate) const LINT: &str = "tracked";
pub(crate) const HINT: &str = "write it through the setter, or `// ALLOW(tracked): <reason>`";
pub(crate) const LIST_HINT: &str = "mutate a tracked list through its generated add_<v>() / include_<v>() / remove_<v>() / set_<v>_at() / clear_<v>() (`analyze fix` rewrites most); a raw edit publishes nothing";

pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::tracked::SCOPE_META_0.name,
    group: crate::allow_registry_fields::tracked::SCOPE_META_0.group,
    label: "tracked",
    legacy: "tools/ci/tracked_lint.py",
    select: CODE_MAPS_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "outside_setter", hint: HINT }, RuleMeta { name: "list_mutation", hint: LIST_HINT }],
    allow: crate::allow_registry_fields::tracked::ALLOW_1,
    lists: crate::allow_registry_fields::tracked::SCOPE_META_0.lists,
};

/// The same writes in the test and benchmark trees, which `[lint.tracked]` exempts: a fixture that writes a tracked or stat var raw
/// leaves shared map state changed with no mark (a later test's refresh sweep reports REFRESH DRIFT on it). Hard-banned; write through the setter (`A.set_equipment(...)`) or `set_var()` in a test.
pub(crate) static META_TESTS: Meta = Meta {
    name: crate::allow_registry_fields::tracked::SCOPE_META_1.name,
    group: crate::allow_registry_fields::tracked::SCOPE_META_1.group,
    label: "tracked_tests",
    legacy: "",
    select: CODE_MAPS_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "outside_setter", hint: "a test writes state through its setter too (A.set_x(v)), or set_var() when it must restore it" }, RuleMeta { name: "list_mutation", hint: LIST_HINT }],
    allow: crate::allow_registry_fields::tracked::ALLOW_0,
    lists: crate::allow_registry_fields::tracked::SCOPE_META_1.lists,
};

/// The test and benchmark trees `tracked_tests` reads (and `tracked` leaves to it).
pub const TEST_PREFIXES: &[&str] = &["code/tests/unit_tests/", "code/tests/benchmarks/", "code/tests/"];

/// The procs that construct an instance. A write of the instance's own tracked var there (`v = x`, `src.v = x`, `LAZYADD(v, x)`) is the construction of
/// the instance, not a change of a live one: nothing reads or watches an object that is still being built, so the write sets the var and publishes
/// nothing (the same as a type-level default, which is not a write either). A write to a part of the instance a loop walks (`for(var/T/P in ports)`, `P.v = x`) is the same construction. A write to ANOTHER object's tracked var (`O.v = x`) is judged as anywhere
/// else, and so is a write in `on_holder_init()`, `after_init()` and every other proc, which run once the holder is live. The init lint counts each
/// imperative line of an `Initialize()` body (`init_lines`), so rewriting these lines to setter calls would also change their fingerprints and read as
/// new init debt: the two lints agree by leaving construction alone.
pub(crate) const PRE_LIVE: &[&str] = &["Initialize", "New"];

pub(crate) const OPS: &str = r"(?:=(?!=)|\+=|-=|\*=|/=|\|=|&=|\^=|<<=|>>=|\+\+|--)";

/// `{var: {types}}` (the Python `tracked` dict of sets).
pub(crate) type Tracked = BTreeMap<String, BTreeSet<String>>;

pub(crate) fn is_subtype(path:&str,base:&str)->bool{fn full(path:&str)->impl Iterator<Item=u8>+'_ {let mut prefix="";let mut suffix=path;for(short,long)in[("/obj","/atom/movable/obj"),("/mob","/atom/movable/mob"),("/turf","/atom/turf"),("/area","/atom/area")]{if path==short||(path.starts_with(short)&&path.as_bytes().get(short.len())==Some(&b'/')){prefix=long;suffix=&path[short.len()..];break}}prefix.bytes().chain(suffix.bytes())}let mut child=full(path);for byte in full(base){if child.next()!=Some(byte){return false}}matches!(child.next(),None|Some(b'/'))}

/// DM's implicit parents: `/obj` and `/mob` are `/atom/movable/...`, `/turf` and `/area` are `/atom/...`. A `SETTER(/atom, dir)` covers a
/// proc of `/obj/item/x` only when the path is compared in full.
pub(crate) fn builtin_full_path(path: &str) -> String {
    for (short, full) in [("/obj", "/atom/movable/obj"), ("/mob", "/atom/movable/mob"), ("/turf", "/atom/turf"), ("/area", "/atom/area")] {
        if path == short || (path.starts_with(short) && path.as_bytes().get(short.len()) == Some(&b'/')) {
            return format!("{}{}", full, &path[short.len()..]);
        }
    }
    path.to_string()
}

/// A bare `name = x` at `pos` that is a named argument of a call the AST did not see (inside a macro's arguments, `image(...)` or
/// `new/icon(...)`): the text before it on the line is `call(` or `..., ` at a paren depth above zero, and the innermost open paren is a
/// call's, not `for(`/`if(`/`while(`/`switch(`.
pub(crate) fn in_call_args(line: &str, pos: usize) -> bool {
    let before = &line[..pos];
    match before.trim_end().chars().last() {
        Some('(') | Some(',') => {}
        _ => return false,
    }
    let bytes = before.as_bytes();
    let mut depth = 0i32;
    let mut i = bytes.len();
    while i > 0 {
        i -= 1;
        match bytes[i] {
            b')' | b']' => depth += 1,
            b'(' | b'[' if depth > 0 => depth -= 1,
            b'(' => {
                let head = before[..i].trim_end();
                let word: String = head.chars().rev().take_while(|c| c.is_alphanumeric() || *c == '_' || *c == '/').collect::<Vec<_>>().into_iter().rev().collect();
                return !word.is_empty() && !matches!(word.as_str(), "for" | "if" | "while" | "switch" | "return");
            }
            b'[' => return false,
            _ => {}
        }
    }
    false
}

/// `normalize_type`: strip, a leading `/`, no trailing `/`.
pub(crate) fn normalize_type(path: &str) -> String {
    let p = py_strip(path);
    let p = if p.starts_with('/') { p.to_string() } else { format!("/{}", p) };
    p.trim_end_matches('/').to_string()
}

/// `tracked_type_of`: the first tracked base of `var` that `owner` is under (may be "": the Python
/// treats that as falsy).
pub(crate) fn tracked_base<'a>(tracked:&'a Tracked,var:&str,owner:&str)->Option<&'a str>{tracked.get(var)?.iter().find(|base|is_subtype(owner,base)).map(String::as_str)}
pub(crate) fn tracked_type_of(tracked:&Tracked,var:&str,owner:&str)->Option<String>{tracked_base(tracked,var,owner).map(str::to_owned)}

/// A top-level proc: `(owner, name, argument text, [(line number, line)])`.
pub(crate) struct Proc<'a> {
    owner: &'a str,
    name: &'a str,
    args: &'a str,
    body: Vec<(usize, &'a str)>,
}

/// `parse_procs(code)`: every top-level proc of a code view; type blocks are ignored (var defaults
/// are not writes).
pub(crate) fn parse_procs(code: &View) -> Vec<Proc<'_>> {
parse_procs_using(code,&mut crate::key_policy_control::Compatibility).expect("original unchecked proc scan")
}
pub(crate) fn parse_procs_using<'a,C:crate::key_policy_control::Control>(code:&'a View,control:&mut C)->Result<Vec<Proc<'a>>,C::Error>{
 use crate::key_policy_control as kc;
    let mut out = Vec::new();
    let mut current: Option<Proc> = None;
    for (number,line)in code.numbered(){control.checkpoint()?;
        if line.chars().next().map(|c| !is_py_space(c)).unwrap_or(false) {
            if let Some(cur) = current.take() {
                kc::row(control,&mut out)?;out.push(cur);
            }
            let stripped = py_rstrip(line);
            if stripped.starts_with('#') || lexical_pattern_0().is_match(stripped) {
                continue;
            }
            if let Some(m) = lexical_pattern_1().captures(stripped) {
                let owner = if m.s(1).is_empty() { "/" } else { m.s(1) };
                current = Some(Proc { owner, name: m.s(2), args: m.s(3), body: Vec::new() });
            }
            continue;
        }
        if let Some(cur) = current.as_mut() {
            if !py_strip(line).is_empty() {
                kc::row(control,&mut cur.body)?;cur.body.push((number,line));
            }
        }
    }
    if let Some(cur) = current {
        kc::row(control,&mut out)?;out.push(cur);
    }
    control.checkpoint()?;Ok(out)
}

/// `tracked_from_text`: adds the vars this file declares tracked (TRACKED / SETTER lines, derive()
/// values) to `tracked`.
pub(crate) fn tracked_from_text(f: &SourceFile, tracked: &mut Tracked) {
    tracked_from_text_with(f, tracked, false)
}

/// `stats`: also the vars non-virtual STAT() declarations compose (`tracked_tests` only: in code the stat engine and the look builder
/// write them, and a few legacy sites still do).
pub(crate) fn tracked_from_text_with(f: &SourceFile, tracked: &mut Tracked, stats: bool) {
 tracked_from_text_using(f,tracked,stats,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).expect("original unchecked tracked index")
}
fn insert_tracked<C:crate::key_policy_control::Control>(tracked:&mut Tracked,var:&str,path:&str,control:&mut C)->Result<(),C::Error>{use crate::key_policy_control as kc;control.checkpoint()?;kc::reserve(control,||path.len().checked_mul(8)?.checked_add(256))?;let path=normalize_type(path);if !tracked.contains_key(var){kc::reserve(control,||Some(2048))?;tracked.insert(kc::own(control,var)?,BTreeSet::new());}let bases=tracked.get_mut(var).expect("actual admitted tracked name");if !bases.contains(&path){kc::reserve(control,||Some(2048))?;bases.insert(path);}Ok(())}
pub(crate) fn tracked_from_text_using<C:crate::key_policy_control::Control,T:crate::key_policy_control::Control<Error=C::Error>>(f:&SourceFile,tracked:&mut Tracked,stats:bool,control:&mut C,temp:&mut T)->Result<(),C::Error>{control.checkpoint()?;
    let raw = f.text();
    if raw.contains("TRACKED") || raw.contains("SETTER(") {
        for line in f.raw().lines(){control.checkpoint()?;
            if py_lstrip(line).starts_with("#define") {
                continue;
            }
            let re = lexical_pattern_2();
            if let Some(m) = re.captures(line) {
                let var = if m.s(2).is_empty() { m.s(4) } else { m.s(2) };
                let path = if m.s(1).is_empty() { m.s(3) } else { m.s(1) };
                insert_tracked(tracked,var,path,control)?;
            }
        }
    }
    if raw.contains("derive(") {
        for p in parse_procs_using(f.code(),temp)?{control.checkpoint()?;
            if p.name != "derived" || p.owner == "/" {
                continue;
            }
            crate::key_policy_control::reserve(temp,||p.body.len().checked_mul(4*std::mem::size_of::<&str>())?.checked_add(p.body.iter().try_fold(0usize,|n,(_,line)|n.checked_add(line.len())?.checked_add(1))?.checked_mul(4)?)?.checked_add(128))?;
            let text = p.body.iter().map(|(_, t)| *t).collect::<Vec<_>>().join("\n");
            for m in lexical_pattern_3().captures_iter(&text) {
                control.checkpoint()?;insert_tracked(tracked,m.s(1),p.owner,control)?;
            }
        }
    }
    // STAT(T, name, rule, ...) declares a var the stat engine composes and writes; a virtual stat has no var.
    if stats && raw.contains("STAT(") {
        for line in f.raw().lines(){control.checkpoint()?;
            if py_lstrip(line).starts_with("#define") || line.contains("virtual = TRUE") {
                continue;
            }
            let re = lexical_pattern_4();
            if let Some(m) = re.captures(line) {
                insert_tracked(tracked,m.s(2),m.s(1),control)?;
            }
        }
    }
 control.checkpoint()?;Ok(())
}

/// `(owner type, x)` for every `setup(PROC_REF(x))` in a `CAPABILITIES(T)` block: InitAtom() runs them as soon as the instance's Initialize() chain
/// returns, before after_init() and before any other code can reach the instance, so the writes of the proc `x` resolved on T (or a subtype of T)
/// to the instance's own vars are construction (PRE_LIVE). A same-named proc on an unrelated type is not.
pub(crate) fn setup_hook_names(files:Vec<&SourceFile>)->BTreeSet<(String,String)>{let mut out=BTreeSet::new();for f in files{setup_hooks_file(f,&mut out);}out}
pub(crate) fn setup_hooks_file(f:&SourceFile,out:&mut BTreeSet<(String,String)>){
setup_hooks_file_using(f,out,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).expect("original unchecked setup hooks")
}
pub(crate) fn setup_hooks_file_using<C:crate::key_policy_control::Control,T:crate::key_policy_control::Control<Error=C::Error>>(f:&SourceFile,out:&mut BTreeSet<(String,String)>,control:&mut C,temp:&mut T)->Result<(),C::Error>{use crate::key_policy_control as kc;control.checkpoint()?;
        if !f.text().contains("setup(") {
            return Ok(());
        }
        let mut owner: Option<String> = None;
        for line in f.clean().text.split('\n'){control.checkpoint()?;
            if let Some(m) = lexical_pattern_5().captures(line) {
                kc::reserve(temp,||m.s(1).len().checked_mul(8)?.checked_add(256))?;owner=Some(normalize_type(m.s(1)));
            } else if !line.starts_with(|c: char| c == '\t' || c == ' ') && !line.trim().is_empty() {
                owner = None;
            }
            if let (Some(o), Some(m)) = (&owner, lexical_pattern_6().captures(line)) {
                kc::reserve(control,||Some(2048))?;out.insert((kc::own(control,o)?,kc::own(control,m.s(1))?));
            }
        }

 control.checkpoint()?;Ok(())
}

/// The patterns built from the tracked names (`scan`).
pub(crate) struct Pats {
    /// does the raw text mention any tracked name at all (`any(v in raw for v in tracked)`)
    any: Pat,
    bare: Pat,
    dotted: Pat,
    /// names of procs some `setup(PROC_REF(x))` entry runs: construction, like `Initialize()` (see PRE_LIVE)
    pub(crate) setup: BTreeSet<(String, String)>,
}

pub(crate) fn build_pats(tracked:&Tracked)->Option<Pats>{build_pats_using(tracked,&mut crate::key_policy_control::Compatibility).expect("original unchecked tracked patterns")}
fn admitted_pattern<C:crate::key_policy_control::Control>(control:&mut C,source:String)->Result<Pat,C::Error>{crate::key_policy_control::reserve(control,||source.len().checked_mul(4)?.checked_add(128))?;if C::CHECKED{Pat::try_new(&source).map_err(|_|control.allocation_failed())}else{Ok(Pat::new(&source))}}
fn pattern_names<C:crate::key_policy_control::Control>(tracked:&Tracked,control:&mut C)->Result<String,C::Error>{use crate::key_policy_control as kc;let mut escaped=Vec::new();for key in tracked.keys(){control.checkpoint()?;kc::reserve(control,||key.len().checked_mul(8)?.checked_add(128))?;let key=regex::escape(key);kc::row(control,&mut escaped)?;escaped.push(key);}kc::reserve(control,||escaped.len().checked_mul(2*std::mem::size_of::<String>())?.checked_add(64))?;escaped.sort();kc::reserve(control,||escaped.iter().try_fold(0usize,|n,key|n.checked_add(key.len())?.checked_add(1))?.checked_mul(4)?.checked_add(128))?;Ok(escaped.join("|"))}
pub(crate) fn build_pats_using<C:crate::key_policy_control::Control>(tracked:&Tracked,control:&mut C)->Result<Option<Pats>,C::Error>{use crate::key_policy_control as kc;control.checkpoint()?;if tracked.is_empty(){return Ok(None)}let names=pattern_names(tracked,control)?;let any_source=kc::format(control,format_args!("(?:{})",names))?;let any=admitted_pattern(control,any_source)?;let bare_source=kc::format(control,format_args!(r"(?<![\w.])(?:src\.)?({names})\s*{ops}|(?:\+\+|--)\s*(?<![\w.])(?:src\.)?({names})\b",names=names,ops=OPS))?;let bare=admitted_pattern(control,bare_source)?;let dotted_source=kc::format(control,format_args!(r"(?<![\w.])(\w+)\.({names})\s*{ops}|(?:\+\+|--)\s*(\w+)\.({names})\b",names=names,ops=OPS))?;let dotted=admitted_pattern(control,dotted_source)?;Ok(Some(Pats{any,bare,dotted,setup:BTreeSet::new()}))}

/// One write outside a setter: the line, the message, the rule, and (for a list mutation `analyze fix` can rewrite) the edit.
pub(crate) struct Hit {
    pub(crate) line: usize,
    pub(crate) msg: String,
    pub(crate) rule: u8,
    pub(crate) fix: Option<Fix>,
    pub(crate) list_macro: bool,
}

/// Rule indexes (the order of `Meta::rules`).
pub(crate) const RULE_SETTER: u8 = 0;
pub(crate) const RULE_LIST: u8 = 1;

/// A single-line edit: bytes `start..end` of the line become `text`; `was` is the text it expects there.

#[derive(Clone,Copy,Debug,Default,PartialEq,Eq,PartialOrd,Ord,serde::Serialize,serde::Deserialize)]
#[serde(rename_all="snake_case")]
pub enum FixAction{#[default]Unknown,Set,Add,Remove,Include,SetAt,Clear,Cut,Insert,Swap}
impl FixAction{pub(crate) fn method(self,var:&str)->Option<String>{let(prefix,suffix)=match self{Self::Unknown=>return None,Self::Set=>("set_",""),Self::Add=>("add_",""),Self::Remove=>("remove_",""),Self::Include=>("include_",""),Self::SetAt=>("set_","_at"),Self::Clear=>("clear_",""),Self::Cut=>("cut_",""),Self::Insert=>("insert_",""),Self::Swap=>("swap_","")};Some(format!("{prefix}{var}{suffix}"))}}
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, serde::Serialize, serde::Deserialize, Default)]
pub struct Fix {
    #[serde(skip)]
    pub action: FixAction,
    pub start: u32,
    pub end: u32,
    pub was: String,
    pub text: String,
    /// Further edits of the same rewrite on later lines (a multi-line right-hand side closes its setter call where it ends).
    pub more: Vec<MoreEdit>,
}

/// An edit of a [`Fix`] on a later line: `line_off` lines after the hit's.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, serde::Serialize, serde::Deserialize, Default)]
pub struct MoreEdit {
    pub line_off: u32,
    pub start: u32,
    pub end: u32,
    pub was: String,
    pub text: String,
}

/// The in-place list mutations of tracked list vars (`LAZYADD(v, x)`, `v.Add(x)`, `v[i] = x`).
pub(crate) struct ListPats {
    r#macro: Pat,
    method: Pat,
    index: Pat,
}

pub(crate) fn build_list_pats(lists:&Tracked)->Option<ListPats>{build_list_pats_using(lists,&mut crate::key_policy_control::Compatibility).expect("original unchecked tracked list patterns")}
pub(crate) fn build_list_pats_using<C:crate::key_policy_control::Control>(lists:&Tracked,control:&mut C)->Result<Option<ListPats>,C::Error>{use crate::key_policy_control as kc;control.checkpoint()?;if lists.is_empty(){return Ok(None)}let names=pattern_names(lists,control)?;let macro_source=kc::format(control,format_args!(r"\b(LAZY(?:ADD|REMOVE|OR|DISTINCTADD|SET|CLEARLIST|NULL))\(\s*(?:(\w+)\.)?({names})\s*[,)]",names=names))?;let method_source=kc::format(control,format_args!(r"(?<![\w.])(?:(\w+)\.)?({names})\.(Add|Remove|Cut|Insert|Swap)\(",names=names))?;let index_source=kc::format(control,format_args!(r"(?<![\w.])(?:(\w+)\.)?({names})\s*\[(?:[^\[\]]|\[[^\]]*\])*\]\s*{ops}",names=names,ops=OPS))?;Ok(Some(ListPats{r#macro:admitted_pattern(control,macro_source)?,method:admitted_pattern(control,method_source)?,index:admitted_pattern(control,index_source)?}))}

/// The index of the `)` closing the `(` at `open`, in `line` (strings and comments are blanked in the clean view).
pub(crate) fn close_paren(line: &str, open: usize) -> Option<usize> {
    let mut depth = 0i32;
    for (i, c) in line[open..].char_indices() {
        match c {
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if depth == 0 {
                    return Some(open + i);
                }
            }
            _ => {}
        }
    }
    None
}

/// Top-level argument spans (byte ranges into `line`) of the call whose `(` is at `open` and `)` at `close`.
pub(crate) fn arg_spans(line: &str, open: usize, close: usize) -> Vec<(usize, usize)> {
    let mut spans = Vec::new();
    let (mut depth, mut start) = (0i32, open + 1);
    for (i, c) in line[open + 1..close].char_indices() {
        let at = open + 1 + i;
        match c {
            '(' | '[' | '{' => depth += 1,
            ')' | ']' | '}' => depth -= 1,
            ',' if depth == 0 => {
                spans.push((start, at));
                start = at + 1;
            }
            _ => {}
        }
    }
    if !line[start..close].trim().is_empty() || !spans.is_empty() {
        spans.push((start, close));
    }
    spans
}

/// The call prefix a holder text gives the generated proc: `src` and none are the bare form.
pub(crate) fn holder_prefix(holder: &str) -> String {
    if holder.is_empty() || holder == "src" {
        String::new()
    } else {
        format!("{holder}.")
    }
}

/// The rewrite of one list mutation, or None when it is not a plain statement-level form `analyze fix` can express.
/// `clean` and `raw` are the same line; `m_start` is where the match starts.
pub(crate) fn list_fix(clean: &str, raw: &str, kind: &str, m_start: usize, holder: &str, var: &str, form: &str) -> Option<Fix> {
    if clean.len() != raw.len() {
        return None;
    }
    let pre = holder_prefix(holder);
    let arg = |a: (usize, usize)| raw[a.0..a.1].trim().to_string();
    match kind {
        "macro" => {
            let open = m_start + form.len();
            if clean.as_bytes().get(open) != Some(&b'(') {
                return None;
            }
            let close = close_paren(clean, open)?;
            let spans = arg_spans(clean, open, close);
            let action=match form{"LAZYADD"=>FixAction::Add,"LAZYREMOVE"=>FixAction::Remove,"LAZYOR"|"LAZYDISTINCTADD"=>FixAction::Include,"LAZYSET"=>FixAction::SetAt,"LAZYCLEARLIST"=>FixAction::Clear,"LAZYNULL"=>FixAction::Set,_=>FixAction::Unknown};
            let text = match (form, spans.len()) {
                ("LAZYADD", 2) => format!("{pre}add_{var}({})", arg(spans[1])),
                ("LAZYREMOVE", 2) => format!("{pre}remove_{var}({})", arg(spans[1])),
                ("LAZYOR" | "LAZYDISTINCTADD", 2) => format!("{pre}include_{var}({})", arg(spans[1])),
                ("LAZYSET", 3) => format!("{pre}set_{var}_at({}, {})", arg(spans[1]), arg(spans[2])),
                ("LAZYCLEARLIST", 1) => format!("{pre}clear_{var}()"),
                ("LAZYNULL", 1) => format!("{pre}set_{var}(null)"),
                _ => return None,
            };
            Some(Fix { action,start: m_start as u32, end: close as u32 + 1, was: raw[m_start..=close].to_string(), text, more: Vec::new() })
        }
        "method" => {
            // A statement: nothing before it on the line, and the call closes the line.
            if !clean[..m_start].trim().is_empty() {
                return None;
            }
            let open = clean[m_start..].find(&format!(".{form}("))? + m_start + 1 + form.len();
            let close = close_paren(clean, open)?;
            if !clean[close + 1..].trim().trim_start_matches(';').trim().is_empty() {
                return None;
            }
            let spans = arg_spans(clean, open, close);
            let action=match form{"Add"=>FixAction::Add,"Remove"=>FixAction::Remove,"Cut" if spans.is_empty()=>FixAction::Clear,"Cut"=>FixAction::Cut,"Insert"=>FixAction::Insert,"Swap"=>FixAction::Swap,_=>FixAction::Unknown};
            let text = match (form, spans.len()) {
                ("Add", 1) => format!("{pre}add_{var}({})", arg(spans[0])),
                ("Add", n) if n > 1 => format!("{pre}add_{var}(list({}))", spans.iter().map(|s| arg(*s)).collect::<Vec<_>>().join(", ")),
                ("Remove", 1) => format!("{pre}remove_{var}({})", arg(spans[0])),
                ("Remove", n) if n > 1 => format!("{pre}remove_{var}(list({}))", spans.iter().map(|s| arg(*s)).collect::<Vec<_>>().join(", ")),
                ("Cut", 0) => format!("{pre}clear_{var}()"),
                ("Cut", 1 | 2) => format!("{pre}cut_{var}({})", spans.iter().map(|s| arg(*s)).collect::<Vec<_>>().join(", ")),
                ("Insert", 2) => format!("{pre}insert_{var}({}, {})", arg(spans[0]), arg(spans[1])),
                ("Swap", 2) => format!("{pre}swap_{var}({}, {})", arg(spans[0]), arg(spans[1])),
                _ => return None,
            };
            Some(Fix { action,start: m_start as u32, end: close as u32 + 1, was: raw[m_start..=close].to_string(), text, more: Vec::new() })
        }
        "index" => {
            if !clean[..m_start].trim().is_empty() {
                return None;
            }
            let name_at = clean[m_start..].find(var)? + m_start;
            let open = clean[name_at..].find('[')? + name_at;
            let mut depth = 0i32;
            let mut close = None;
            for (i, c) in clean[open..].char_indices() {
                match c {
                    '[' => depth += 1,
                    ']' => {
                        depth -= 1;
                        if depth == 0 {
                            close = Some(open + i);
                            break;
                        }
                    }
                    _ => {}
                }
            }
            let close = close?;
            let after = clean[close + 1..].trim_start();
            let rest = after.strip_prefix('=')?;
            if rest.starts_with('=') {
                return None;
            }
            let end = clean.trim_end().trim_end_matches(';').trim_end().len();
            let value_start = clean.len() - rest.len();
            let value = raw[value_start..end].trim();
            if value.is_empty() || value.matches(['(', '[', '{']).count() != value.matches([')', ']', '}']).count() {
                return None; // a value that continues on the next line
            }
            let idx = raw[open + 1..close].trim();
            Some(Fix { action:FixAction::SetAt,start: m_start as u32, end: end as u32, was: raw[m_start..end].to_string(), text: format!("{pre}set_{var}_at({idx}, {value})"), more: Vec::new() })
        }
        _ => None,
    }
}

/// Whether `prefix` (the clean text before a write) leaves the write a statement of its own: nothing, `else`, `if(...)` or `else if(...)`.
pub(crate) fn statement_prefix_ok(prefix: &str) -> bool {
    let p = prefix.trim();
    if p.is_empty() {
        return true;
    }
    // A statement before it on the same line (`a = 1; b = 2`): the prefix is whole statements when its brackets balance.
    if p.ends_with(';') {
        let mut depth = 0i32;
        for c in p.chars() {
            match c {
                '(' | '[' | '{' => depth += 1,
                ')' | ']' | '}' => depth -= 1,
                _ => {}
            }
        }
        return depth == 0;
    }
    let p = match p.strip_prefix("else") {
        Some(rest) if rest.is_empty() || rest.starts_with(char::is_whitespace) || rest.starts_with('(') => rest.trim_start(),
        _ => p,
    };
    if p.is_empty() {
        return true;
    }
    let Some(rest) = p.strip_prefix("if") else { return false };
    let rest = rest.trim_start();
    if !rest.starts_with('(') {
        return false;
    }
    close_paren(rest, 0) == Some(rest.len() - 1)
}

/// Where the statement whose right-hand side starts at `(line, col)` ends: the first `;` at depth 0, or the end of the line that closes every
/// bracket opened on the way. Returns `(line_off, end_col)` of the last non-blank character plus one, or None when the statement continues in a
/// way this cannot follow (a trailing `\`, a bracket closed that this statement did not open, no end within 80 lines).
pub(crate) fn statement_end(clean: &[&str], line: usize, col: usize) -> Option<(usize, usize)> {
    let mut depth = 0i32;
    let mut last: Option<(usize, usize)> = None;
    for off in 0..80 {
        let text = clean.get(line - 1 + off)?;
        let start = if off == 0 { col } else { 0 };
        let mut stopped = false;
        for (i, c) in text[start..].char_indices() {
            let at = start + i;
            match c {
                '(' | '[' | '{' => depth += 1,
                ')' | ']' | '}' => {
                    depth -= 1;
                    if depth < 0 {
                        return None;
                    }
                }
                ';' if depth == 0 => {
                    stopped = true;
                    break;
                }
                _ => {}
            }
            if !c.is_whitespace() {
                last = Some((off, at + c.len_utf8()));
            }
        }
        if stopped || depth == 0 {
            if text.trim_end().ends_with('\\') {
                return None;
            }
            return last;
        }
    }
    None
}

/// The rewrite of one raw write of a tracked var to its setter call, or None when the write is not a statement this can express (a write whose
/// value is used, one inside a `for(...)` header or a conditional expression, a chained assignment). `clean` and `raw` are the physical lines
/// of the file (the same indexing), `number` the 1-based line of the hit and `m_start` where the match starts on it.
pub(crate) fn setter_fix(clean: &[&str], raw: &[&str], number: usize, m_start: usize, holder: &str, var: &str, list: bool) -> Option<Fix> {
    let cl = *clean.get(number - 1)?;
    let rl = *raw.get(number - 1)?;
    if cl.len() != rl.len() || !statement_prefix_ok(&cl[..m_start]) {
        return None;
    }
    let pre = holder_prefix(holder);
    let read = if holder.is_empty() { var.to_string() } else { format!("{holder}.{var}") };
    let tlen = read.len();
    let s = &cl[m_start..];
    let (pre_op, after_target) = if s.starts_with("++") || s.starts_with("--") {
        let rest = s[2..].trim_start();
        let skipped = s.len() - rest.len();
        if !rest.starts_with(&read) || rest[tlen..].starts_with(|c: char| c.is_alphanumeric() || c == '_' || c == '.') {
            return None;
        }
        (Some(s[..2].to_string()), m_start + skipped + tlen)
    } else {
        if !s.starts_with(&read) {
            return None;
        }
        (None, m_start + tlen)
    };
    let tail = &cl[after_target..];
    let op_at = after_target + (tail.len() - tail.trim_start().len());
    let optext = &cl[op_at..];
    let end_of_line = cl.trim_end().trim_end_matches(';').trim_end().len();
    // `++V` / `--V` / `V++` / `V--` as a statement
    if let Some(op) = &pre_op {
        let rest = cl[after_target..].trim();
        if (!rest.is_empty() && !rest.starts_with(';')) || list {
            return None;
        }
        let delta = if op == "++" { "+" } else { "-" };
        return Some(Fix { action:FixAction::Set,start: m_start as u32, end: end_of_line as u32, was: rl[m_start..end_of_line].to_string(), text: format!("{pre}set_{var}({read} {delta} 1)"), more: Vec::new() });
    }
    if optext.starts_with("++") || optext.starts_with("--") {
        let rest = cl[op_at + 2..].trim();
        if (!rest.is_empty() && !rest.starts_with(';')) || list {
            return None;
        }
        let delta = if optext.starts_with("++") { "+" } else { "-" };
        return Some(Fix { action:FixAction::Set,start: m_start as u32, end: end_of_line as u32, was: rl[m_start..end_of_line].to_string(), text: format!("{pre}set_{var}({read} {delta} 1)"), more: Vec::new() });
    }
    // `=` or a compound assignment
    let op = ["<<=", ">>=", "+=", "-=", "*=", "/=", "|=", "&=", "^=", "="].iter().find(|o| optext.starts_with(**o))?;
    if *op == "=" && optext[1..].starts_with('=') {
        return None;
    }
    let rhs_from = op_at + op.len();
    let rhs_start = rhs_from + (cl[rhs_from..].len() - cl[rhs_from..].trim_start().len());
    if rhs_start >= cl.len() {
        return None; // the right-hand side starts on the next line
    }
    let (end_off, end_col) = statement_end(clean, number, rhs_start)?;
    if end_off > 0 && clean.get(number - 1 + end_off).map(|c| c.len()) != raw.get(number - 1 + end_off).map(|r| r.len()) {
        return None;
    }
    let simple = end_off == 0 && rl[rhs_start..end_col].chars().all(|c| c.is_alphanumeric() || c == '_' || c == '.');
    let (open_text, close_text) = if *op == "=" {
        (format!("{pre}set_{var}("), ")")
    } else if list {
        let proc = match *op {
            "+=" => "add",
            "-=" => "remove",
            "|=" => "include",
            _ => return None,
        };
        (format!("{pre}{proc}_{var}("), ")")
    } else {
        let binop = &op[..op.len() - 1];
        if simple {
            (format!("{pre}set_{var}({read} {binop} "), ")")
        } else {
            (format!("{pre}set_{var}({read} {binop} ("), "))")
        }
    };
    Some(Fix {
        action:if !list||*op=="="{FixAction::Set}else{match *op{"+="=>FixAction::Add,"-="=>FixAction::Remove,"|="=>FixAction::Include,_=>return None}},
        start: m_start as u32,
        end: rhs_start as u32,
        was: rl[m_start..rhs_start].to_string(),
        text: open_text,
        more: vec![MoreEdit { line_off: end_off as u32, start: end_col as u32, end: end_col as u32, was: String::new(), text: close_text.to_string() }],
    })
}

/// `scan` for one file: its hits (in order) and the setters it defines `(owner, proc name)`.
pub(crate) fn scan_one(tracked: &Tracked, pats: &Pats, lists: &Tracked, lpats: Option<&ListPats>, f: &SourceFile, sink: &mut Sink, named_args: &BTreeSet<(usize, usize)>) -> (Vec<Hit>, Vec<(String, String)>) {
 scan_one_using(tracked,pats,lists,lpats,f,named_args,&mut crate::key_policy_control::Compatibility,&mut|line|Ok(sink.allowed(f,line,LINT))).expect("original unchecked tracked scanner")
}
fn temporary_peak<C:crate::key_policy_control::Control>(control:&mut C,peak:&mut usize,bytes:impl FnOnce()->Option<usize>)->Result<(),C::Error>{if !C::CHECKED{return Ok(())}let bytes=bytes().ok_or_else(||control.overflow())?;if bytes>*peak{control.reserve(bytes-*peak)?;*peak=bytes;}Ok(())}
fn declares_local<C:crate::key_policy_control::Control>(line:&str,var:&str,control:&mut C,peak:&mut usize)->Result<bool,C::Error>{if !C::CHECKED{return Ok(Pat::cached(&format!(r"\bvar/(?:[\w/]*/)?{}\b",regex::escape(var))).is_match(line))}temporary_peak(control,peak,||var.len().checked_mul(24)?.checked_add(1024))?;let source=format!(r"\bvar/(?:[\w/]*/)?{}\b",regex::escape(var));let pattern=Pat::try_new(&source).map_err(|_|control.allocation_failed())?;Ok(pattern.is_match(line))}
fn in_call_args_using<C:crate::key_policy_control::Control>(line:&str,pos:usize,control:&mut C,peak:&mut usize)->Result<bool,C::Error>{temporary_peak(control,peak,||pos.checked_mul(12)?.checked_add(128))?;control.checkpoint()?;Ok(in_call_args(line,pos))}
pub(crate) fn scan_one_using<C:crate::key_policy_control::Control>(tracked:&Tracked,pats:&Pats,lists:&Tracked,lpats:Option<&ListPats>,f:&SourceFile,named_args:&BTreeSet<(usize,usize)>,control:&mut C,allowed:&mut impl FnMut(usize)->Result<bool,C::Error>)->Result<(Vec<Hit>,Vec<(String,String)>),C::Error>{
 scan_one_for_fix_using(tracked,pats,lists,lpats,f,named_args,control,allowed,false)
}
fn fix_lines<'a,C:crate::key_policy_control::Control>(view:&'a crate::tree::View,control:&mut C)->Result<Vec<&'a str>,C::Error>{
 use crate::key_policy_control as kc;let count=view.num_lines();kc::reserve(control,||count.checked_mul(4*std::mem::size_of::<&str>())?.checked_add(64))?;let mut rows=Vec::new();rows.try_reserve_exact(count).map_err(|_|control.allocation_failed())?;if rows.capacity()>count.saturating_mul(4){return Err(control.allocation_failed())}for line in view.lines(){control.checkpoint()?;rows.push(line)}Ok(rows)
}
fn admitted_setter_fix<C:crate::key_policy_control::Control>(clean:&[&str],raw:&[&str],number:usize,start:usize,holder:&str,var:&str,list:bool,control:&mut C)->Result<Option<Fix>,C::Error>{
 use crate::key_policy_control as kc;let width=raw.get(number.saturating_sub(1)).map_or(0,|line|line.len());kc::reserve(control,||width.checked_mul(16)?.checked_add(holder.len().checked_mul(8)?)?.checked_add(var.len().checked_mul(8)?)?.checked_add(1024+4*std::mem::size_of::<MoreEdit>()))?;
 let fix=setter_fix(clean,raw,number,start,holder,var,list);control.checkpoint()?;if fix.as_ref().is_some_and(|fix|fix.more.is_empty()&&fix.was.contains(';')){return Ok(None)}Ok(fix)
}
pub(crate) fn scan_one_for_fix_using<C:crate::key_policy_control::Control>(tracked:&Tracked,pats:&Pats,lists:&Tracked,lpats:Option<&ListPats>,f:&SourceFile,named_args:&BTreeSet<(usize,usize)>,control:&mut C,allowed:&mut impl FnMut(usize)->Result<bool,C::Error>,list_macro_fixes:bool)->Result<(Vec<Hit>,Vec<(String,String)>),C::Error>{
 scan_one_fix_scope_using(tracked,pats,lists,lpats,f,named_args,control,allowed,if list_macro_fixes{FixScanScope::ListMacros}else{FixScanScope::Lint},&mut|_,_,_|Ok(false))
}
#[derive(Clone,Copy,PartialEq,Eq)]pub(crate) enum FixScanScope{Lint,ListMacros,Tracked}
pub(crate) fn scan_one_tracked_fixes_using<C:crate::key_policy_control::Control>(tracked:&Tracked,pats:&Pats,lists:&Tracked,lpats:Option<&ListPats>,f:&SourceFile,named_args:&BTreeSet<(usize,usize)>,control:&mut C,allowed:&mut impl FnMut(usize)->Result<bool,C::Error>,setter_available:&mut impl FnMut(&str,&str,FixAction)->Result<bool,C::Error>)->Result<(Vec<Hit>,Vec<(String,String)>),C::Error>{
 scan_one_fix_scope_using(tracked,pats,lists,lpats,f,named_args,control,allowed,FixScanScope::Tracked,setter_available)
}
fn scan_one_fix_scope_using<C:crate::key_policy_control::Control>(tracked:&Tracked,pats:&Pats,lists:&Tracked,lpats:Option<&ListPats>,f:&SourceFile,named_args:&BTreeSet<(usize,usize)>,control:&mut C,allowed:&mut impl FnMut(usize)->Result<bool,C::Error>,scope:FixScanScope,setter_available:&mut impl FnMut(&str,&str,FixAction)->Result<bool,C::Error>)->Result<(Vec<Hit>,Vec<(String,String)>),C::Error>{
    use crate::key_policy_control as kc;control.checkpoint()?;let make_fixes=!C::CHECKED;let mut temporary_bytes=0;
    let mut hits = Vec::new();
    let mut setters = Vec::new();
    if !pats.any.is_match(f.text()) {
        return Ok((hits, setters));
    }
    let clean_lines=if make_fixes{f.clean().text.split('\n').collect()}else if scope==FixScanScope::Tracked{fix_lines(f.clean(),control)?}else{Vec::new()};
    let raw_lines=if make_fixes{f.raw().text.split('\n').collect()}else if scope==FixScanScope::Tracked{fix_lines(f.raw(),control)?}else{Vec::new()};
    for p in parse_procs_using(f.clean(),control)? {
        control.checkpoint()?;
        kc::reserve(control,||p.owner.len().checked_mul(8)?.checked_add(256))?;
        let owner = if p.owner != "/" { normalize_type(p.owner) } else { "/".to_string() };
        // Construction of the instance (see PRE_LIVE): its own tracked vars are written plainly there.
        let pre_live = PRE_LIVE.contains(&p.name) || pats.setup.iter().any(|(t, n)| n == p.name && is_subtype(&owner, t));
        let mut is_setter_of: Option<String> = None;
        if let Some(var) = p.name.strip_prefix("set_") {
            if tracked_base(tracked, var, &owner).map(|b| !b.is_empty()).unwrap_or(false) {
                is_setter_of = Some(kc::own(control,var)?);
                kc::row(control,&mut setters)?;setters.push((kc::own(control,&owner)?,kc::own(control,p.name)?));
            }
        }
        let mut locals: HashSet<String> = HashSet::new();
        let mut typed: HashMap<String, String> = HashMap::new();
        // Locals that walk one of the instance's own parts (`for(var/datum/omni_port/P in ports)`): parts the instance is still building.
        let mut own_parts: HashSet<String> = HashSet::new();
        let arg_typed = lexical_pattern_7();
        for m in arg_typed.captures_iter(p.args) {
            control.checkpoint()?;kc::reserve(control,||m.s(1).len().checked_mul(8)?.checked_add(4096))?;typed.insert(kc::own(control,m.s(2))?,normalize_type(m.s(1)));
            if !locals.contains(m.s(2)){kc::reserve(control,||Some(2048))?;locals.insert(kc::own(control,m.s(2))?);}
        }
        for (number, line) in &p.body {
            control.checkpoint()?;
            if py_lstrip(line).starts_with('#') {
                continue;
            }
            // A verb's `set name = "..."` / `set category = ...` is a declaration of the verb, not a write to a var.
            if lexical_pattern_8().is_match(line) {
                continue;
            }
            for m in lexical_pattern_9().captures_iter(line) {
                control.checkpoint()?;if !locals.contains(m.s(1)){kc::reserve(control,||Some(2048))?;locals.insert(kc::own(control,m.s(1))?);}
            }
            for m in lexical_pattern_10().captures_iter(line) {
                control.checkpoint()?;kc::reserve(control,||m.s(1).len().checked_mul(8)?.checked_add(4096))?;typed.insert(kc::own(control,m.s(2))?,normalize_type(m.s(1)));
            }
            if pre_live {
                for m in lexical_pattern_11().captures_iter(line) {
                    control.checkpoint()?;if !own_parts.contains(m.s(1)){kc::reserve(control,||Some(2048))?;own_parts.insert(kc::own(control,m.s(1))?);}
                }
            }
            for m in pats.bare.captures_iter(line) {
                control.checkpoint()?;
                if named_args.contains(&(*number, m.start(0) + 1)) || in_call_args_using(line,m.start(0),control,&mut temporary_bytes)? {
                    continue; // this exact AST expression names a call argument, not storage
                }
                let var = if m.s(1).is_empty() { m.s(2) } else { m.s(1) };
                if is_setter_of.as_deref() == Some(var) {
                    continue;
                }
                let written_via_src = m.whole().contains(&format!("src.{}", var));
                if pre_live {
                    continue;
                }
                if locals.contains(var) && !written_via_src {
                    continue;
                }
                if declares_local(line,var,control,&mut temporary_bytes)? {
                    continue;
                }
                let base = tracked_base(tracked, var, &owner).filter(|b| !b.is_empty());
                if let Some(base) = base {
                    if !allowed(*number)? {
                        let is_list = tracked_base(lists, var, &owner).is_some();
                        let fix = if make_fixes{setter_fix(&clean_lines, &raw_lines, *number, m.start(0), if written_via_src { "src" } else { "" }, var, is_list)}else if scope==FixScanScope::Tracked{let fix=admitted_setter_fix(&clean_lines,&raw_lines,*number,m.start(0),if written_via_src{"src"}else{""},var,is_list,control)?;match fix{Some(fix)if setter_available(&owner,var,fix.action)?=>Some(fix),_=>None}}else{None};
                        let msg=kc::format(control,format_args!("{} written outside {}/proc/set_{}()", var, base, var))?;kc::row(control,&mut hits)?;hits.push(Hit{line:*number,msg,rule:RULE_SETTER,fix,list_macro:false});
                    }
                }
            }
            for m in pats.dotted.captures_iter(line) {
                control.checkpoint()?;
                let holder = if m.s(1).is_empty() { m.s(3) } else { m.s(1) };
                let var = if m.s(2).is_empty() { m.s(4) } else { m.s(2) };
                if holder == "src" {
                    continue; // the bare pattern counts src.V
                }
                if own_parts.contains(holder) {
                    continue; // a part the instance is building (see PRE_LIVE)
                }
                let base = typed.get(holder).and_then(|t| tracked_base(tracked, var, t)).filter(|b| !b.is_empty());
                if let Some(base) = base {
                    if !allowed(*number)? {
                        let is_list = typed.get(holder).and_then(|t| tracked_base(lists, var, t)).is_some();
                        let fix = if make_fixes{setter_fix(&clean_lines, &raw_lines, *number, m.start(0), holder, var, is_list)}else if scope==FixScanScope::Tracked{let fix=admitted_setter_fix(&clean_lines,&raw_lines,*number,m.start(0),holder,var,is_list,control)?;match fix{Some(fix)if setter_available(typed.get(holder).map_or(owner.as_str(),String::as_str),var,fix.action)?=>Some(fix),_=>None}}else{None};
                        let msg=kc::format(control,format_args!("{}.{} written outside {}/proc/set_{}()", holder, var, base, var))?;kc::row(control,&mut hits)?;hits.push(Hit{line:*number,msg,rule:RULE_SETTER,fix,list_macro:false});
                    }
                }
            }
            if let Some(lp) = lpats {
                // In-place edits of a tracked list var: the same holder rules as a write, one pattern per form.
                let raw_line=if make_fixes||scope!=FixScanScope::Lint{f.raw().line(*number)}else{""};
                let forms: [(&Pat, &str, usize, usize, usize); 3] = [(&lp.r#macro, "macro", 2, 3, 1), (&lp.method, "method", 1, 2, 3), (&lp.index, "index", 1, 2, 0)];
                for (pat, kind, holder_group, var_group, form_group) in forms {
                    for m in pat.captures_iter(line) {
                        control.checkpoint()?;
                        let holder = m.s(holder_group);
                        let var = m.s(var_group);
                        let base = if holder.is_empty() || holder == "src" {
                            let written_via_src = holder == "src";
                            if pre_live {
                                continue;
                            }
                            if (locals.contains(var) && !written_via_src) || declares_local(line,var,control,&mut temporary_bytes)? {
                                continue;
                            }
                            tracked_base(lists, var, &owner)
                        } else {
                            typed.get(holder).and_then(|t| tracked_base(lists, var, t))
                        };
                        let Some(base) = base.filter(|b| !b.is_empty()) else { continue };
                        if allowed(*number)? {
                            continue;
                        }
                        let form = if form_group == 0 { "" } else { m.s(form_group) };
                        let list_macro=kind=="macro"&&matches!(form,"LAZYADD"|"LAZYREMOVE"|"LAZYOR"|"LAZYDISTINCTADD"|"LAZYSET"|"LAZYCLEARLIST"|"LAZYNULL");
                        let fix = if make_fixes{list_fix(line, raw_line, kind, m.start(0), holder, var, form)}else if (scope==FixScanScope::Tracked||scope==FixScanScope::ListMacros&&list_macro)&&statement_prefix_ok(&line[..m.start(0)]) {
                            // Explicit native edit collection only. Ordinary
                            // checked lint queries still allocate NO fix buffers.
                            kc::reserve(control,||kc::split_bound(raw_line.len())?.checked_add(raw_line.len().checked_mul(8)?)?.checked_add(holder.len().checked_mul(4)?)?.checked_add(var.len().checked_mul(4)?)?.checked_add(1024))?;
                            let fix=list_fix(line,raw_line,kind,m.start(0),holder,var,form).filter(|fix|line.get(fix.end as usize..).is_some_and(|tail|{let tail=tail.trim_start();tail.is_empty()||tail.starts_with(';')}));
                            control.checkpoint()?;
                            if scope==FixScanScope::Tracked{match fix{Some(fix)if setter_available(if holder.is_empty()||holder=="src"{&owner}else{typed.get(holder).map_or(owner.as_str(),String::as_str)},var,fix.action)?=>Some(fix),_=>None}}else{fix}
                        }else{None};
                        let who = if holder.is_empty(){kc::own(control,var)?}else{kc::format(control,format_args!("{}.{}",holder,var))?};
                        let msg=kc::format(control,format_args!("{} edited in place ({}) outside {}'s generated add_/remove_/set_{}_at/clear_ procs", who, if form.is_empty() { "[] =" } else { form }, base, var))?;kc::row(control,&mut hits)?;hits.push(Hit{line:*number,msg,rule:RULE_LIST,fix,list_macro});
                    }
                }
            }
        }
    }
    control.checkpoint()?;Ok((hits, setters))
}


fn lexical_pattern_0()->&'static Pat{pat_match!(r"/[\w/]+\s*$")}
fn lexical_pattern_1()->&'static Pat{pat_match!(r"(/[\w/]*?)/(?:(?:proc|verb)/)?(\w+)\s*\((.*)$")}
fn lexical_pattern_2()->&'static Pat{pat_match!(
                r"\s*(?:TRACKED\(\s*(/[\w/]+)\s*,\s*(\w+)\s*[,)]|SETTER\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\))"
            )}
fn lexical_pattern_3()->&'static Pat{pat!(r"\bderive\(\s*nameof\(\s*(?:/[\w/]+::)?(\w+)\s*\)")}
fn lexical_pattern_4()->&'static Pat{pat_match!(r"^\s*STAT\(\s*(/[\w/]+)\s*,\s*(\w+)\s*,")}
fn lexical_pattern_5()->&'static Pat{pat!(r"^CAPABILITIES(?:_PART)?\(\s*(/[\w/]+)\s*[,)]")}
fn lexical_pattern_6()->&'static Pat{pat!(r"\bsetup\(\s*PROC_REF\((\w+)\)")}
fn lexical_pattern_7()->&'static Pat{pat!(r"(?:^|[(,])\s*(?:var/)?((?:/?[\w]+/)*[\w]+)/(\w+)\s*(?==|,|\)|$|\bas\b)")}
fn lexical_pattern_8()->&'static Pat{pat!(r"^\s*set\s+(?:name|desc|category|hidden|src|popup_menu|instant|invisibility|background|waitfor)\s*=")}
fn lexical_pattern_9()->&'static Pat{pat!(r"\bvar/(?:[\w/]*/)?(\w+)\b")}
fn lexical_pattern_10()->&'static Pat{pat!(r"(?:\bvar)?(/[\w/]+)/(\w+)\b")}
fn lexical_pattern_11()->&'static Pat{pat!(r"\bfor\s*\(\s*var/(?:[\w/]*/)?(\w+)\s+in\s+(?:src\.)?(\w+)\s*\)")}
/// Admit one actual exposed Caps.groups peak before a file loan's scans.
/// Regex engine compiler/search scratch remains the existing shared baseline.
pub(crate) fn captures_admission<C:crate::key_policy_control::Control>(control:&mut C,pats:Option<&Pats>,lists:Option<&ListPats>)->Result<(),C::Error>{if !C::CHECKED{return Ok(())}let mut count=0usize;for pattern in [lexical_pattern_0(),lexical_pattern_1(),lexical_pattern_2(),lexical_pattern_3(),lexical_pattern_4(),lexical_pattern_5(),lexical_pattern_6(),lexical_pattern_7(),lexical_pattern_8(),lexical_pattern_9(),lexical_pattern_10(),lexical_pattern_11()]{count=count.max(pattern.capture_group_count());}if let Some(pats)=pats{for pattern in [&pats.any,&pats.bare,&pats.dotted]{count=count.max(pattern.capture_group_count());}}if let Some(lists)=lists{for pattern in [&lists.r#macro,&lists.method,&lists.index]{count=count.max(pattern.capture_group_count());}}crate::key_policy_control::reserve(control,||count.checked_mul(4*std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+64))}
pub fn metadata(tests:bool)->&'static Meta{if tests{&META_TESTS}else{&META}}

#[cfg(all(test,feature="native-policy"))]mod native_control_tests{
 use super::*;use crate::{captured_generator_budget::Budget,captured_allow_annotations::Operation,reactive_reads_native::Failure};use std::io;
 #[test]fn checked_scanner_real_growth_denial_precedes_late_poll_and_fresh_retry(){let text=format!("/obj/box\n    var/plain\nTRACKED(/obj/box, plain)\n/obj/box/proc/change()\n{}",(0..80).map(|_|"    plain = 2\n").collect::<String>());let source=SourceFile::from_text("code/probe.dm",&text);let mut tracked=Tracked::new();tracked_from_text(&source,&mut tracked);let pats=build_pats(&tracked).unwrap();let small=Budget::new(1024).unwrap();let late=||if small.denied(){Err(io::Error::new(io::ErrorKind::Interrupted,"late tracked control"))}else{Ok(())};let mut control=Operation{budget:&small,poll:&late};captures_admission(&mut control,Some(&pats),None).unwrap();let error=match scan_one_using(&tracked,&pats,&Tracked::new(),None,&source,&BTreeSet::new(),&mut control,&mut|_|Ok(false)){Ok(_)=>panic!("actual tracked row growth must deny"),Err(actual)=>actual};assert!(matches!(error,Failure::Operational(actual)if actual.kind()==io::ErrorKind::OutOfMemory));let fresh=Budget::new(1<<20).unwrap();let poll=||Ok(());let mut control=Operation{budget:&fresh,poll:&poll};captures_admission(&mut control,Some(&pats),None).unwrap();let(hits,_)=scan_one_using(&tracked,&pats,&Tracked::new(),None,&source,&BTreeSet::new(),&mut control,&mut|_|Ok(false)).unwrap();assert_eq!(hits.len(),80);assert!(hits.iter().all(|hit|hit.fix.is_none()),"native findings do not allocate unused rewrite buffers");}
 #[test]fn checked_scanner_returns_actual_first_io_without_reclassification(){let source=SourceFile::from_text("code/probe.dm","TRACKED(/obj/box, plain)\n/obj/box/proc/change()\n    plain = 2\n");let mut tracked=Tracked::new();tracked_from_text(&source,&mut tracked);let pats=build_pats(&tracked).unwrap();let root=Budget::new(1<<20).unwrap();let stop=||Err(io::Error::from_raw_os_error(1450));let result=scan_one_using(&tracked,&pats,&Tracked::new(),None,&source,&BTreeSet::new(),&mut Operation{budget:&root,poll:&stop},&mut|_|Ok(false));assert!(matches!(result,Err(Failure::Operational(ref actual))if actual.raw_os_error()==Some(1450)));}
}

#[cfg(all(test,feature="native-policy"))]mod native_list_macro_fix_control_tests {
 use super::*;use crate::{captured_generator_budget::Budget,captured_allow_annotations::Operation,captured_reactive_reads::Failure};
 fn fixture(body:&str)->(SourceFile,Tracked,Tracked,Pats,ListPats){
  let source=format!("/obj/box\n    var/list/items\nTRACKED(/obj/box, items)\n/obj/box/proc/change()\n    {body}\n");
  let file=SourceFile::from_text("code/fix.dm",&source);let mut tracked=Tracked::new();tracked_from_text(&file,&mut tracked);
  let lists=tracked.clone();let pats=build_pats(&tracked).unwrap();let lpats=build_list_pats(&lists).unwrap();(file,tracked,lists,pats,lpats)
 }
 #[test]fn explicit_checked_list_macro_fix_matches_same_legacy_kernel_but_ordinary_lint_still_allocates_no_fix(){
  for body in ["LAZYADD(items, value)","LAZYADD(src.items, make(a, b))","LAZYADD(items, list(a, b)) // keep","LAZYREMOVE(items, value)","LAZYOR(items, value)","LAZYDISTINCTADD(src.items, list(a, b))","LAZYSET(items, key, value)","LAZYCLEARLIST(items)","LAZYNULL(items)"]{
   let(file,tracked,lists,pats,lpats)=fixture(body);let old=scan_one(&tracked,&pats,&lists,Some(&lpats),&file,&mut Sink::new(),&BTreeSet::new()).0;
   let root=Budget::new(1<<20).unwrap();let poll=||Ok(());let mut control=Operation{budget:&root,poll:&poll};
   let now=scan_one_for_fix_using(&tracked,&pats,&lists,Some(&lpats),&file,&BTreeSet::new(),&mut control,&mut|_|Ok(false),true).unwrap().0;
   assert_eq!(old.len(),1);assert_eq!(now.len(),1);assert!(now[0].list_macro);let before=old[0].fix.as_ref().unwrap();let after=now[0].fix.as_ref().unwrap();assert_eq!((&before.was,&before.text,before.start,before.end),(&after.was,&after.text,after.start,after.end));
   let lint=scan_one_using(&tracked,&pats,&lists,Some(&lpats),&file,&BTreeSet::new(),&mut control,&mut|_|Ok(false)).unwrap().0;
   assert!(lint.iter().all(|hit|hit.fix.is_none()));
  }
 }
 #[test]fn checked_list_macro_fix_does_not_broaden_other_forms_strings_or_expression_contexts(){
  let(file,tracked,lists,pats,lpats)=fixture("items.Add(value)");let root=Budget::new(1<<20).unwrap();let poll=||Ok(());let mut c=Operation{budget:&root,poll:&poll};
  let hits=scan_one_for_fix_using(&tracked,&pats,&lists,Some(&lpats),&file,&BTreeSet::new(),&mut c,&mut|_|Ok(false),true).unwrap().0;
  assert_eq!(hits.len(),1);assert!(!hits[0].list_macro);assert!(hits[0].fix.is_none());
  let(file,tracked,lists,pats,lpats)=fixture("var/count = LAZYADD(items, value)");
  let hits=scan_one_for_fix_using(&tracked,&pats,&lists,Some(&lpats),&file,&BTreeSet::new(),&mut c,&mut|_|Ok(false),true).unwrap().0;
  assert_eq!(hits.len(),1);assert!(hits[0].list_macro);assert!(hits[0].fix.is_none());
  let(file,tracked,lists,pats,lpats)=fixture("LAZYADD(items, value) + 1");
  let hits=scan_one_for_fix_using(&tracked,&pats,&lists,Some(&lpats),&file,&BTreeSet::new(),&mut c,&mut|_|Ok(false),true).unwrap().0;assert_eq!(hits.len(),1);assert!(hits[0].fix.is_none());
  let(file,tracked,lists,pats,lpats)=fixture(r#"var/text = "LAZYADD(items, value)""#);
  let hits=scan_one_for_fix_using(&tracked,&pats,&lists,Some(&lpats),&file,&BTreeSet::new(),&mut c,&mut|_|Ok(false),true).unwrap().0;assert!(hits.is_empty());
 }
 #[test]fn checked_list_macro_fix_funds_malformed_argument_span_growth_before_legacy_arity_rejection(){
  let body=format!("LAZYADD(items,{})",",".repeat(1024));let(file,tracked,lists,pats,lpats)=fixture(&body);
  let root=Budget::new(32768).unwrap();let poll=||Ok(());let actual=scan_one_for_fix_using(&tracked,&pats,&lists,Some(&lpats),&file,&BTreeSet::new(),&mut Operation{budget:&root,poll:&poll},&mut|_|Ok(false),true).err().expect("span growth must be funded before list_fix allocates and rejects arity");
  assert!(matches!(actual,Failure::Operational(error)if error.kind()==std::io::ErrorKind::OutOfMemory));
  let root=Budget::new(1<<20).unwrap();let hits=scan_one_for_fix_using(&tracked,&pats,&lists,Some(&lpats),&file,&BTreeSet::new(),&mut Operation{budget:&root,poll:&poll},&mut|_|Ok(false),true).unwrap().0;assert_eq!(hits.len(),1);assert!(hits[0].list_macro);assert!(hits[0].fix.is_none());
 }
 #[test]fn checked_list_macro_fix_preserves_first_actual_io_and_denies_before_unfunded_rewrite(){
  let(file,tracked,lists,pats,lpats)=fixture("LAZYADD(items, value)");
  let budget=Budget::new(1<<20).unwrap();let first=||Err(std::io::Error::from_raw_os_error(1450));
  let actual=scan_one_for_fix_using(&tracked,&pats,&lists,Some(&lpats),&file,&BTreeSet::new(),&mut Operation{budget:&budget,poll:&first},&mut|_|Ok(false),true).err().expect("checked native fix must refuse");
  assert!(matches!(actual,Failure::Operational(error)if error.raw_os_error()==Some(1450)));
  let tiny=Budget::new(256).unwrap();let poll=||Ok(());
  let actual=scan_one_for_fix_using(&tracked,&pats,&lists,Some(&lpats),&file,&BTreeSet::new(),&mut Operation{budget:&tiny,poll:&poll},&mut|_|Ok(false),true).err().expect("checked native fix must refuse");
  assert!(matches!(actual,Failure::Operational(error)if error.kind()==std::io::ErrorKind::OutOfMemory));
 }
}

#[cfg(all(test,feature="native-policy"))]mod native_list_macro_additional_controls {
 use super::*;use crate::{captured_generator_budget::Budget,captured_allow_annotations::Operation};
 #[test]fn checked_list_macro_fix_denies_value_context_for_each_supported_form(){
  for call in ["LAZYADD(items, value)","LAZYREMOVE(items, value)","LAZYOR(items, value)","LAZYDISTINCTADD(items, value)","LAZYSET(items, key, value)","LAZYCLEARLIST(items)","LAZYNULL(items)"]{
   for body in [format!("return {call}"),format!("var/value = {call}"),format!("{call} + 1")]{
    let source=format!("/obj/box\n    var/list/items\nTRACKED(/obj/box, items)\n/obj/box/proc/change()\n    {body}\n");
    let file=SourceFile::from_text("code/fix.dm",&source);let mut tracked=Tracked::new();tracked_from_text(&file,&mut tracked);let lists=tracked.clone();let pats=build_pats(&tracked).unwrap();let lpats=build_list_pats(&lists).unwrap();let budget=Budget::new(1<<20).unwrap();let poll=||Ok(());
    let hits=scan_one_for_fix_using(&tracked,&pats,&lists,Some(&lpats),&file,&BTreeSet::new(),&mut Operation{budget:&budget,poll:&poll},&mut|_|Ok(false),true).unwrap().0;
    assert_eq!(hits.len(),1,"{body}");assert!(hits[0].list_macro,"{body}");assert!(hits[0].fix.is_none(),"must preserve value-used context: {body}");
   }
  }
 }
}

#[cfg(all(test,feature="native-policy"))]mod native_list_macro_raw_line_controls {
 use super::*;use crate::{captured_generator_budget::Budget,captured_allow_annotations::Operation};
 #[test]fn checked_list_macro_fix_preserves_normalized_crlf_kernel_and_exact_view_line_bytes(){
  let authored="/obj/box\r\n    var/list/items\r\nTRACKED(/obj/box, items)\r\n/obj/box/proc/change()\r\n    LAZYSET(items, key, value) // keep\r\n";
  let exact=crate::tree::View::new(authored.to_owned());
  for (number,split) in authored.split('\n').enumerate(){assert_eq!(exact.line(number+1),split,"indexed view must preserve CR exactly");}
  let file=SourceFile::from_text("code/fix.dm",authored);assert!(!file.raw().text.contains('\r'),"Analyze source view is universal-newline normalized, not physical byte authority");
  let mut tracked=Tracked::new();tracked_from_text(&file,&mut tracked);let lists=tracked.clone();let pats=build_pats(&tracked).unwrap();let lpats=build_list_pats(&lists).unwrap();
  let old=scan_one(&tracked,&pats,&lists,Some(&lpats),&file,&mut Sink::new(),&BTreeSet::new()).0;let budget=Budget::new(1<<20).unwrap();let poll=||Ok(());
  let actual=scan_one_for_fix_using(&tracked,&pats,&lists,Some(&lpats),&file,&BTreeSet::new(),&mut Operation{budget:&budget,poll:&poll},&mut|_|Ok(false),true).unwrap().0;
  assert_eq!(old.len(),1);assert_eq!(actual.len(),1);assert_eq!(old[0].fix,actual[0].fix);assert_eq!(actual[0].fix.as_ref().unwrap().text,"set_items_at(key, value)");
 }
}

#[cfg(all(test,feature="native-policy"))]mod native_full_tracked_fix_controls {
 use super::*;use crate::{captured_generator_budget::Budget,captured_allow_annotations::Operation};
 fn fixture(body:&str,list:bool)->(SourceFile,Tracked,Pats,Tracked,Option<ListPats>){
  let source=format!("/obj/box\n    var/{ty}value\nTRACKED(/obj/box, value)\n/obj/box/proc/change()\n{body}\n",ty=if list{"list/"}else{""});
  let file=SourceFile::from_text("code/fix.dm",&source);let mut tracked=Tracked::new();tracked_from_text(&file,&mut tracked);let pats=build_pats(&tracked).unwrap();let lists=if list{tracked.clone()}else{Tracked::new()};let lpats=build_list_pats(&lists);(file,tracked,pats,lists,lpats)
 }
 #[test]fn checked_full_tracked_fixes_use_same_scalar_method_index_and_multiline_kernels(){
  for(body,list,action)in[("    value = 42",false,FixAction::Set),("    value += text(\n        42)",false,FixAction::Set),("    ++value",false,FixAction::Set),("    value += 42",true,FixAction::Add),("    value -= 42",true,FixAction::Remove),("    value |= 42",true,FixAction::Include),("    value.Add(42)",true,FixAction::Add),("    value[1] = 42",true,FixAction::SetAt),("    value.Cut()",true,FixAction::Clear),("    value.Insert(1, 42)",true,FixAction::Insert),("    value.Swap(1, 2)",true,FixAction::Swap)]{
   let(f,t,p,l,lp)=fixture(body,list);let old=scan_one(&t,&p,&l,lp.as_ref(),&f,&mut Sink::new(),&BTreeSet::new()).0;
   let budget=Budget::new(8<<20).unwrap();let poll=||Ok(());let mut asked=Vec::new();let now=scan_one_tracked_fixes_using(&t,&p,&l,lp.as_ref(),&f,&BTreeSet::new(),&mut Operation{budget:&budget,poll:&poll},&mut|_|Ok(false),&mut|owner,var,which|{asked.push((owner.to_owned(),var.to_owned(),which));Ok(true)}).unwrap().0;
   assert_eq!(old.len(),1,"{body}");assert_eq!(now.len(),1,"{body}");assert_eq!(now[0].fix,old[0].fix,"{body}");assert_eq!(now[0].fix.as_ref().unwrap().action,action);assert_eq!(asked,[("/obj/box".into(),"value".into(),action)]);
  }
 }
 #[test]fn checked_full_tracked_fixes_require_actual_setter_and_refuse_semicolon_tail_loss(){
  let(f,t,p,l,lp)=fixture("    value = 42",false);let budget=Budget::new(1<<20).unwrap();let poll=||Ok(());
  let hits=scan_one_tracked_fixes_using(&t,&p,&l,lp.as_ref(),&f,&BTreeSet::new(),&mut Operation{budget:&budget,poll:&poll},&mut|_|Ok(false),&mut|_,_,_|Ok(false)).unwrap().0;assert_eq!(hits.len(),1);assert!(hits[0].fix.is_none());
  let(f,t,p,l,lp)=fixture("    value++; keep_effect()",false);let old=scan_one(&t,&p,&l,lp.as_ref(),&f,&mut Sink::new(),&BTreeSet::new()).0;assert!(old[0].fix.as_ref().unwrap().was.contains("keep_effect"),"actual old kernel safety regression");
  let hits=scan_one_tracked_fixes_using(&t,&p,&l,lp.as_ref(),&f,&BTreeSet::new(),&mut Operation{budget:&budget,poll:&poll},&mut|_|Ok(false),&mut|_,_,_|Ok(true)).unwrap().0;assert_eq!(hits.len(),1);assert!(hits[0].fix.is_none());
 }
 #[test]fn checked_full_tracked_fix_preserves_first_io_and_real_allocation_denial(){
  let(f,t,p,l,lp)=fixture("    value = text(42)",false);let root=Budget::new(1<<20).unwrap();let first=||Err(std::io::Error::from_raw_os_error(1450));
  let actual=scan_one_tracked_fixes_using(&t,&p,&l,lp.as_ref(),&f,&BTreeSet::new(),&mut Operation{budget:&root,poll:&first},&mut|_|panic!("no later allowance pull"),&mut|_,_,_|panic!("no later metadata pull")).err().unwrap();assert!(matches!(actual,crate::captured_reactive_reads::Failure::Operational(ref e)if e.raw_os_error()==Some(1450)));
  let tiny=Budget::new(1).unwrap();let poll=||Ok(());let actual=scan_one_tracked_fixes_using(&t,&p,&l,lp.as_ref(),&f,&BTreeSet::new(),&mut Operation{budget:&tiny,poll:&poll},&mut|_|Ok(false),&mut|_,_,_|Ok(true)).err().unwrap();assert!(matches!(actual,crate::captured_reactive_reads::Failure::Operational(ref e)if e.kind()==std::io::ErrorKind::OutOfMemory));
 }
}
