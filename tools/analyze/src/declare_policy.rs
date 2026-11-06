//! Whole unchanged declaration marker/emitter policy shared by legacy and native.
//! Raw declaration marker projection only: no Decls/Sem/ObjectTree or DM parser.
use crate::{
    declare_ids_policy::{split_opt, Cap},
    raw_marker_policy::{matching_paren, split_args},
    sparse_slots_policy::Output,
};
use std::collections::{BTreeMap, BTreeSet};
pub const MARKERS: &[&str] = &[
    "CAPABILITIES",
    "CAPABILITY_TYPE",
    "CAPABILITY_DEF",
    "cap_keys",
    "STAGE_DEF",
    "SOURCE_DEF",
    "STATE_GRAPH",
    "STATIC_ENTRY",
];
pub struct Marker<'a> {
    pub name: &'a str,
    pub rel: &'a str,
    pub line: u32,
    pub body: &'a str,
    pub args: &'a [String],
    pub body_offset: usize,
    pub line_starts: &'a [u32],
}
impl Marker<'_> {
    pub fn line_at(&self, body_off: usize) -> u32 {
        let abs = (self.body_offset + body_off) as u32;
        match self.line_starts.binary_search(&abs) {
            Ok(i) => i as u32 + 1,
            Err(i) => i as u32,
        }
    }
}
pub struct Input<'a> {
    pub markers: &'a [Marker<'a>],
    // Positional metadata from the already ordered source marker index.
    pub(crate) part_features: &'a [Option<&'a str>],
    pub engine_sources: &'a [(&'a str, &'a str)],
    pub(crate) poll: Option<&'a dyn Fn() -> bool>,
    pub(crate) budget: Option<std::sync::Arc<crate::captured_generator_budget::Budget>>,
}
impl<'a> Input<'a> {
    fn markers<'b>(&'b self, name: &'b str) -> impl Iterator<Item = &'b Marker<'a>> + 'b {
        self.markers
            .iter()
            .take_while(|_| self.poll.map_or(true, |f| f()))
            .filter(move |m| m.name == name)
    }
    fn output(&self) -> Output {
        match &self.budget {
            Some(b) => Output::captured(b.clone()),
            None => Output::default(),
        }
    }
}
pub(crate) fn up(s: &str) -> String {
    s.to_uppercase()
}

/// `name = value` at the top level of an argument (an identifier, then `=` that is not `==`).
/// Collapses a multi-line expression onto one line (comments are already blanked in marker text).
fn lower_controlled<C:crate::key_policy_control::Control>(control:&mut C,value:&str)->Result<String,C::Error>{crate::key_policy_control::reserve(control,||value.len().checked_mul(6)?.checked_add(64))?;Ok(value.to_lowercase())}
pub(crate) fn one_line(text:&str)->String{match one_line_controlled(&mut crate::key_policy_control::Compatibility,text){Ok(value)=>value,Err(never)=>match never{}}}
fn one_line_controlled<C:crate::key_policy_control::Control>(control:&mut C,text:&str)->Result<String,C::Error>{
    let mut out=String::new();let mut offset=0;let mut space=false;
    while offset<text.len(){
        control.checkpoint()?;let rest=&text[offset..];
        let (ch,width)=if rest.starts_with("\\\r\n"){(' ',3)}else if rest.starts_with("\\\n"){(' ',2)}else{let ch=rest.chars().next().unwrap();(ch,ch.len_utf8())};
        offset+=width;
        if ch.is_whitespace(){space=!out.is_empty();continue}
        if space{append_controlled(control,&mut out," ")?;space=false;}
        let mut encoded=[0u8;4];append_controlled(control,&mut out,ch.encode_utf8(&mut encoded))?;
    }
    Ok(out)
}

pub(crate) fn quote(text:&str)->String{match quote_controlled(&mut crate::key_policy_control::Compatibility,text){Ok(value)=>value,Err(never)=>match never{}}}
fn quote_controlled<C:crate::key_policy_control::Control>(control:&mut C,text:&str)->Result<String,C::Error>{
    let mut out=String::new();append_controlled(control,&mut out,"\"")?;
    for ch in text.chars(){control.checkpoint()?;match ch{'\\'=>append_controlled(control,&mut out,"\\\\")?,'"'=>append_controlled(control,&mut out,"\\\"")?,_=>{let mut encoded=[0u8;4];append_controlled(control,&mut out,ch.encode_utf8(&mut encoded))?;}}}
    append_controlled(control,&mut out,"\"")?;Ok(out)
}

/// The key option as a DM expression: a bare identifier names a param (a text), NONE stays NONE.
pub(crate) fn key_expr(key:&Option<String>)->String{match key_expr_controlled(&mut crate::key_policy_control::Compatibility,key){Ok(value)=>value,Err(never)=>match never{}}}
fn key_expr_controlled<C:crate::key_policy_control::Control>(control:&mut C,key:&Option<String>)->Result<String,C::Error>{
    use crate::key_policy_control as kc;match key{
        None=>kc::own(control,"NONE"),
        Some(key)if key=="NONE"=>kc::own(control,"NONE"),
        Some(key)if key.starts_with('"')=>kc::own(control,key),
        Some(key)if key.chars().all(|ch|ch.is_alphanumeric()||ch=='_')=>quote_controlled(control,key),
        Some(key)=>kc::own(control,key),
    }
}

fn capabilities(cx:&Input<'_>,out:&mut Output)->Vec<Cap>{
    match capabilities_controlled(&mut crate::key_policy_control::Compatibility,cx,out){Ok(value)=>value,Err(never)=>match never{}}
}
fn capabilities_controlled<C:crate::key_policy_control::Control>(control:&mut C,cx:&Input<'_>,out:&mut Output)->Result<Vec<Cap>,C::Error>{
    use crate::key_policy_control as kc;let mut caps=Vec::new();let mut diagnostics=cx.output();
    for marker in cx.markers.iter().take_while(|_|cx.poll.map_or(true,|poll|poll())).filter(|marker|marker.name=="CAPABILITY_TYPE"||marker.name=="CAPABILITY_DEF"){
        control.checkpoint()?;
        if let Some(cap)=crate::declare_ids_policy::parse_capability_controlled(control,marker.name,marker.rel,marker.line,marker.args,&mut diagnostics)?{kc::row(control,&mut caps)?;caps.push(cap);}
    }
    for diagnostic in diagnostics.diags{out.diag(&diagnostic.rel,diagnostic.line,diagnostic.msg);}
    kc::reserve(control,||caps.len().checked_mul(std::mem::size_of::<Cap>())?.checked_mul(4)?.checked_add(64))?;
    caps.sort_by(|a,b|a.name.cmp(&b.name));control.checkpoint()?;Ok(caps)
}

/// Replaces every call `name(...)` (not a member or a longer name) in `text` by `f(args)`.
pub(crate) fn rewrite_calls(text:&str,name:&str,f:&dyn Fn(&[String])->String)->String {
    let result=rewrite_calls_controlled(&mut crate::key_policy_control::Compatibility,text,name,&mut|_,args|Ok(f(args)));
    match result{Ok(value)=>value,Err(never)=>match never{}}
}
fn append_controlled<C:crate::key_policy_control::Control>(control:&mut C,out:&mut String,text:&str)->Result<(),C::Error>{
    if C::CHECKED{
        control.checkpoint()?;
        let need=out.len().checked_add(text.len()).ok_or_else(||control.overflow())?;
        if need>out.capacity(){
            let requested=need.max(out.capacity().checked_mul(2).ok_or_else(||control.overflow())?).max(64);
            crate::key_policy_control::reserve(control,||requested.checked_mul(4)?.checked_add(64))?;
            out.try_reserve_exact(requested-out.len()).map_err(|_|control.allocation_failed())?;
            if out.capacity()>requested.checked_mul(4).ok_or_else(||control.overflow())?{return Err(control.allocation_failed())}
        }
    }
    out.push_str(text);Ok(())
}
fn split_args_controlled<C:crate::key_policy_control::Control>(control:&mut C,text:&str)->Result<Vec<String>,C::Error>{
    if !C::CHECKED{return Ok(split_args(text))}
    let mut args=Vec::new();for value in crate::raw_marker_policy::argument_slices(text){control.checkpoint()?;crate::key_policy_control::row(control,&mut args)?;args.push(crate::key_policy_control::own(control,value)?);}
    Ok(args)
}
/// The original scanner/order with actual argument and output growth admission.
/// Callback output must be materialized through this same control by native
/// callers; the compatibility callback remains the original unchecked route.
// SAME scanner dispatches original UTF-8 pieces and matched argument owners.
// Observers consume only matches, avoiding discarded full-text copies.
fn scan_calls_controlled<C:crate::key_policy_control::Control>(control:&mut C,text:&str,name:&str,emit:&mut dyn FnMut(&mut C,&str,Option<Vec<String>>)->Result<(),C::Error>)->Result<(),C::Error>{
 let bytes=text.as_bytes();let mut offset=0;
 while offset<text.len(){control.checkpoint()?;let rest=&text[offset..];
  if rest.starts_with(name)&&rest[name.len()..].trim_start().starts_with('('){
   let before=offset==0||!(bytes[offset-1].is_ascii_alphanumeric()||bytes[offset-1]==b'_'||bytes[offset-1]==b'.'||bytes[offset-1]==b'/');
   if before{let open=offset+name.len()+rest[name.len()..].find('(').unwrap();if let Some(close)=matching_paren(text,open){
    let args=split_args_controlled(control,&text[open+1..close])?;emit(control,&text[offset..close+1],Some(args))?;offset=close+1;continue;
   }}
  }
  let next=offset+rest.chars().next().unwrap().len_utf8();emit(control,&text[offset..next],None)?;offset=next;
 }
 Ok(())
}
fn rewrite_calls_controlled<C:crate::key_policy_control::Control>(control:&mut C,text:&str,name:&str,f:&mut dyn FnMut(&mut C,&[String])->Result<String,C::Error>)->Result<String,C::Error>{
 let mut output=String::new();scan_calls_controlled(control,text,name,&mut|control,original,args|{
  if let Some(args)=args{let replacement=f(control,&args)?;append_controlled(control,&mut output,&replacement)}else{append_controlled(control,&mut output,original)}
 })?;Ok(output)
}
fn observe_calls_controlled<C:crate::key_policy_control::Control>(control:&mut C,text:&str,name:&str,f:&mut dyn FnMut(&mut C,&[String])->Result<String,C::Error>)->Result<(),C::Error>{
 scan_calls_controlled(control,text,name,&mut|control,_,args|{if let Some(args)=args{let _=f(control,&args)?;}Ok(())})
}

/// Names of the global procs the declaration forms are: every `/proc/name(` of the engine (code/engine/), with the capability constructors
/// the markers declare. A declaration is written in a type's own `declared_entries()`, where an unqualified `cooldown(...)` would resolve to
/// the type's own `cooldown` proc (an `/obj/item/telecube/proc/cooldown()` captures the part constructor): the generator therefore writes
/// each call as `global.name(...)`, which only the global proc can answer.
fn set_name<C:crate::key_policy_control::Control>(control:&mut C,set:&mut BTreeSet<String>,name:&str)->Result<(),C::Error>{
    if C::CHECKED&&set.contains(name){return Ok(())}
    crate::key_policy_control::reserve(control,||std::mem::size_of::<String>().checked_mul(16)?.checked_add(2048))?;
    set.insert(crate::key_policy_control::own(control,name)?);Ok(())
}
pub(crate) fn global_constructors(cx:&Input<'_>,caps:&[Cap])->BTreeSet<String>{
    match global_constructors_controlled(&mut crate::key_policy_control::Compatibility,cx,caps){Ok(value)=>value,Err(never)=>match never{}}
}
/// Callback-local original constructor spellings; no raw source leaves this
/// helper. Its same Unicode/name/column-zero policy serves legacy and pages.
pub(crate) fn visit_engine_constructors<C:crate::key_policy_control::Control>(control:&mut C,relative:&str,text:&str,visit:&mut dyn FnMut(&mut C,&str)->Result<(),C::Error>)->Result<(),C::Error>{
    if !relative.starts_with("code/engine/"){return Ok(())}
    for line in text.lines(){
        control.checkpoint()?;
        if let Some(rest)=line.strip_prefix("/proc/"){
            let end=rest.char_indices().take_while(|(_,ch)|ch.is_alphanumeric()||*ch=='_').last().map_or(0,|(offset,ch)|offset+ch.len_utf8());
            if end!=0&&rest[end..].trim_start().starts_with('('){visit(control,&rest[..end])?;}
        }
    }
    Ok(())
}
fn global_constructors_controlled<C:crate::key_policy_control::Control>(control:&mut C,cx:&Input<'_>,caps:&[Cap])->Result<BTreeSet<String>,C::Error>{global_constructor_names_controlled(control,cx,caps,None)}
fn global_constructor_names_controlled<C:crate::key_policy_control::Control>(control:&mut C,cx:&Input<'_>,caps:&[Cap],engine_names:Option<BTreeSet<String>>)->Result<BTreeSet<String>,C::Error>{
    let provided=engine_names.is_some();
    let mut set=engine_names.unwrap_or_default();
    for cap in caps{control.checkpoint()?;set_name(control,&mut set,&cap.name)?;}
    for marker in cx.markers("STATIC_ENTRY"){control.checkpoint()?;if let Some(name)=marker.args.first().map(|arg|arg.trim()).filter(|name|!name.is_empty()){set_name(control,&mut set,name)?;}}
    set_name(control,&mut set,"every")?;
    if !provided{
    for &(relative,text)in cx.engine_sources{if cx.poll.is_some_and(|poll|!poll()){break}
        visit_engine_constructors(control,relative,text,&mut|control,name|set_name(control,&mut set,name))?;
    }
    }
    Ok(set)
}

/// The entry kinds that are read without an instance: `STATIC_ENTRY(loot)` in DM names a constructor `loot(...)` whose entries a
/// CAPABILITIES block may carry, but which are not part of the type's instance table (the library reads them at world setup,
/// before the first map load, from `declared_static_blocks()`).
pub(crate) fn static_kinds(cx:&Input<'_>)->BTreeSet<String>{match static_kinds_controlled(&mut crate::key_policy_control::Compatibility,cx){Ok(value)=>value,Err(never)=>match never{}}}
fn static_kinds_controlled<C:crate::key_policy_control::Control>(control:&mut C,cx:&Input<'_>)->Result<BTreeSet<String>,C::Error>{let mut names=BTreeSet::new();for marker in cx.markers("STATIC_ENTRY"){control.checkpoint()?;if let Some(name)=marker.args.first().map(|value|value.trim()).filter(|value|!value.is_empty()){set_name(control,&mut names,name)?;}}Ok(names)}

/// The name of the call a text opens with (`loot(...)` is `loot`), or None.
pub(crate) fn leading_call(t: &str) -> Option<&str> {
    let t = t.trim_start();
    let end = t.find(|c: char| !(c.is_alphanumeric() || c == '_'))?;
    if end == 0 || !t[end..].trim_start().starts_with('(') {
        return None;
    }
    Some(&t[..end])
}

/// Whether a CAPABILITIES entry is of a static kind: `loot(...)`, or `configure(loot(...))` changing what a supertype declared.
pub(crate) fn is_static_entry(raw:&str,kinds:&BTreeSet<String>)->bool{match is_static_entry_controlled(&mut crate::key_policy_control::Compatibility,raw,kinds){Ok(value)=>value,Err(never)=>match never{}}}
fn is_static_entry_controlled<C:crate::key_policy_control::Control>(control:&mut C,raw:&str,kinds:&BTreeSet<String>)->Result<bool,C::Error>{
    if kinds.is_empty() {
        return Ok(false);
    }
    let t=one_line_controlled(control,raw)?;
    Ok(match leading_call(&t) {
        Some("configure") => {
            let open = t.find('(').unwrap_or(0);
            leading_call(&t[open + 1..])
                .map(|n| kinds.contains(n))
                .unwrap_or(false)
        }
        Some(name) => kinds.contains(name),
        None => false,
    })
}
/// Writes every call of a global constructor in `text` as `global.name(...)` (not a member call, not a longer name, not inside a string).
pub(crate) fn qualify_globals(text:&str,names:&BTreeSet<String>)->String{
    match qualify_globals_controlled(&mut crate::key_policy_control::Compatibility,text,names){Ok(value)=>value,Err(never)=>match never{}}
}
fn qualify_globals_controlled<C:crate::key_policy_control::Control>(control:&mut C,text:&str,names:&BTreeSet<String>)->Result<String,C::Error>{
    let b = text.as_bytes();
    let mut out=if C::CHECKED{String::new()}else{String::with_capacity(text.len()+16)};
    let mut i = 0;
    while i < text.len() {
        control.checkpoint()?;
        let c = b[i];
        if c == b'"' {
            // a string literal: copied whole, escapes included
            let mut j = i + 1;
            while j < text.len() && b[j] != b'"' {
                if b[j] == b'\\' {
                    j += 1;
                }
                j += 1;
            }
            let end = (j + 1).min(text.len());
            append_controlled(control,&mut out,&text[i..end])?;
            i = end;
            continue;
        }
        if c.is_ascii_alphabetic() || c == b'_' {
            let mut j = i;
            while j < text.len() && (b[j].is_ascii_alphanumeric() || b[j] == b'_') {
                j += 1;
            }
            let ident = &text[i..j];
            let prev_ok = i == 0
                || !(b[i - 1].is_ascii_alphanumeric()
                    || b[i - 1] == b'_'
                    || b[i - 1] == b'.'
                    || b[i - 1] == b'/');
            let called = text[j..].trim_start().starts_with('(');
            if prev_ok && called && names.contains(ident) {
                append_controlled(control,&mut out,"global.")?;
            }
            append_controlled(control,&mut out,ident)?;
            i = j;
            continue;
        }
        let ch = text[i..].chars().next().unwrap();
        let mut encoded=[0u8;4];append_controlled(control,&mut out,ch.encode_utf8(&mut encoded))?;
        i += ch.len_utf8();
    }
    Ok(out)
}
/// One entry of a CAPABILITIES list, as DM.
struct Joined<'a,T>(&'a[T]);
impl<T:AsRef<str>> std::fmt::Display for Joined<'_,T>{fn fmt(&self,formatter:&mut std::fmt::Formatter<'_>)->std::fmt::Result{for(index,value)in self.0.iter().enumerate(){if index!=0{formatter.write_str(", ")?;}formatter.write_str(value.as_ref())?;}Ok(())}}
pub(crate) fn entry_text(raw:&str,caps:&[Cap],globals:&BTreeSet<String>)->String{match entry_text_controlled(&mut crate::key_policy_control::Compatibility,raw,caps,globals){Ok(value)=>value,Err(never)=>match never{}}}
fn entry_text_controlled<C:crate::key_policy_control::Control>(control:&mut C,raw:&str,caps:&[Cap],globals:&BTreeSet<String>)->Result<String,C::Error>{
    use crate::key_policy_control as kc;let mut text=one_line_controlled(control,raw)?;
    for call in["link","links"]{text=rewrite_calls_controlled(control,&text,call,&mut|control,args|{
        let mut parts=Vec::new();for index in 0..2{let value=args.get(index).map(String::as_str).unwrap_or("");kc::row(control,&mut parts)?;parts.push(if value.is_empty()||value.contains("::"){quote_controlled(control,value)?}else{kc::own(control,value)?});}
        for arg in args.iter().skip(2){kc::row(control,&mut parts)?;parts.push(kc::own(control,arg)?);}
        kc::format(control,format_args!("entry_link({})",Joined(&parts)))
    })?;}
    text=rewrite_calls_controlled(control,&text,"adjusts",&mut|control,args|{
        let Some(first)=args.first()else{return kc::own(control,"adjusts()")};
        let mut parts=Vec::new();kc::row(control,&mut parts)?;parts.push(if first.starts_with('"'){kc::own(control,first)?}else{quote_controlled(control,first)?});
        for arg in args.iter().skip(1){kc::row(control,&mut parts)?;parts.push(kc::own(control,arg)?);}
        kc::format(control,format_args!("adjusts({})",Joined(&parts)))
    })?;
    text=rewrite_calls_controlled(control,&text,"on_change",&mut|control,args|{
        let Some(first)=args.first()else{return kc::own(control,"on_change()")};
        let mut parts=Vec::new();for arg in args{kc::row(control,&mut parts)?;parts.push(kc::own(control,arg)?);}
        if let Some(inner)=first.strip_prefix("nameof(").and_then(|value|value.strip_suffix(')')){if inner.contains('.'){parts[0]=quote_controlled(control,inner.trim())?;}}
        kc::format(control,format_args!("on_change({})",Joined(&parts)))
    })?;
    text=rewrite_calls_controlled(control,&text,"configure",&mut|control,args|{
        let Some(first)=args.first()else{return kc::own(control,"configure()")};
        match caps.iter().find(|cap|&cap.id==first){
            Some(cap)=>kc::format(control,format_args!("configure({}({}))",cap.name,Joined(&args[1..]))),
            None=>kc::format(control,format_args!("configure({})",Joined(args))),
        }
    })?;
    qualify_globals_controlled(control,&text,globals)
}

/// Byte offset of each top-level argument of a marker body, in order (the args are `split_args(body)`).
pub(crate) fn arg_offsets(body:&str,args:&[String])->Vec<usize>{match arg_offsets_controlled(&mut crate::key_policy_control::Compatibility,body,args){Ok(value)=>value,Err(never)=>match never{}}}
fn arg_offsets_controlled<C:crate::key_policy_control::Control>(control:&mut C,body:&str,args:&[String])->Result<Vec<usize>,C::Error>{
    let mut at = 0;
    let mut out = Vec::new();
    for a in args {
        control.checkpoint()?;
        let mut pos = body[at..].find(a.as_str()).map(|p| at + p).unwrap_or(at);
        at = pos + a.len();
        // The text of an argument may open with the backslash that continued the previous line.
        let bytes = body.as_bytes();
        while pos < at && (bytes[pos].is_ascii_whitespace() || bytes[pos] == b'\\') {
            pos += 1;
        }
        crate::key_policy_control::row(control,&mut out)?;out.push(pos);
    }
    Ok(out)
}
#[derive(Clone, Copy)]
struct CapabilityBlock<'a> {
    marker: &'a Marker<'a>,
    feature: Option<&'a str>,
}

type CapabilityGroups<'a> = BTreeMap<&'a str, Vec<CapabilityBlock<'a>>>;

/// The same three scopes as master: one per dynamic half and one for the
/// whole static table. Retain references into the source-ordered marker index.
fn capability_groups<'a, C: crate::key_policy_control::Control>(
    control: &mut C,
    cx: &'a Input<'_>,
    in_scope: impl Fn(&str) -> bool,
    mut diagnostics: Option<&mut Output>,
) -> Result<CapabilityGroups<'a>, C::Error> {
    use crate::key_policy_control as kc;
    let mut ordered = Vec::new();
    for (index, marker) in cx.markers.iter().enumerate().take_while(|_| cx.poll.map_or(true, |poll| poll())) {
        control.checkpoint()?;
        if marker.name != "CAPABILITIES" || !in_scope(marker.rel) {
            continue;
        }
        let Some(ty) = marker.args.first().map(String::as_str) else {
            if let Some(out) = diagnostics.as_deref_mut() {
                out.diag(marker.rel, marker.line, "CAPABILITIES(T, entries...) needs a type");
            }
            continue;
        };
        let feature = cx.part_features.get(index).copied().flatten();
        kc::row(control, &mut ordered)?;
        ordered.push((ty, CapabilityBlock { marker, feature }));
    }
    // Equal keys keep the input order, just as master's stable per-type sort.
    kc::reserve(control, || ordered.len().checked_mul(std::mem::size_of::<(&str, CapabilityBlock<'_>)>())?.checked_mul(4))?;
    ordered.sort_by(|(ta, a), (tb, b)| {
        (ta, a.feature, a.marker.rel, a.marker.line).cmp(&(tb, b.feature, b.marker.rel, b.marker.line))
    });
    let mut groups = BTreeMap::new();
    let mut features: BTreeMap<&str, (&str, &str, u32)> = BTreeMap::new();
    for chunk in ordered.chunk_by(|(a, _), (b, _)| a == b) {
        control.checkpoint()?;
        let ty = chunk[0].0;
        let root_count = chunk.partition_point(|(_, row)| row.feature.is_none());
        let roots = &chunk[..root_count];
        for pair in roots.windows(2) {
            control.checkpoint()?;
            let first = pair[0].1.marker;
            let later = pair[1].1.marker;
            if let Some(out) = diagnostics.as_deref_mut() {
                out.diag(later.rel, later.line, format_args!("a second CAPABILITIES list for {} (the first is at {}:{}): one composition root per type; another file adds entries with CAPABILITIES_PART({}, feature)", ty, first.rel, first.line, ty));
            }
        }
        let mut accepted = Vec::new();
        if let Some((_, root)) = roots.first() {
            kc::row(control, &mut accepted)?;
            accepted.push(*root);
        }
        let mut seen: BTreeMap<&str, (&str, u32)> = BTreeMap::new();
        for (_, block) in &chunk[root_count..] {
            control.checkpoint()?;
            let feature = block.feature.expect("parts follow roots in composition order");
            let marker = block.marker;
            let valid = !feature.is_empty() && feature.chars().all(|c| c.is_alphanumeric() || c == '_')
                && !feature.starts_with(|c: char| c.is_ascii_digit());
            if !valid {
                if let Some(out) = diagnostics.as_deref_mut() {
                    out.diag(marker.rel, marker.line, format_args!("CAPABILITIES_PART({}, `{}`): the feature is an identifier, CAPABILITIES_PART(T, feature)", ty, feature));
                }
                continue;
            }
            if roots.is_empty() {
                if let Some(out) = diagnostics.as_deref_mut() {
                    out.diag(marker.rel, marker.line, format_args!("CAPABILITIES_PART({}, {}) has no root: the type's CAPABILITIES({}) block (in its home file) must exist", ty, feature, ty));
                }
                continue;
            }
            if let Some((rel, line)) = seen.get(feature) {
                if let Some(out) = diagnostics.as_deref_mut() {
                    out.diag(marker.rel, marker.line, format_args!("CAPABILITIES_PART({}, {}) is declared twice (the first is at {}:{}): one part per feature and type", ty, feature, rel, line));
                }
                continue;
            }
            // `seen` checks the same type first. Any already accepted owner
            // in the global table must therefore be a different type here.
            if let Some((other_ty, rel, line)) = features.get(feature) {
                if let Some(out) = diagnostics.as_deref_mut() {
                    out.diag(marker.rel, marker.line, format_args!("CAPABILITIES_PART({}, {}): the feature is already used for {} at {}:{}; a feature name is unique across all types (the DM proc __capabilities_part_{} is declared on the type, and a subtype may not declare it again): name it for its type", ty, feature, other_ty, rel, line, feature));
                }
                continue;
            }
            map_node::<C, (&str, (&str, &str, u32))>(control)?;
            features.insert(feature, (ty, marker.rel, marker.line));
            map_node::<C, (&str, (&str, u32))>(control)?;
            seen.insert(feature, (marker.rel, marker.line));
            kc::row(control, &mut accepted)?;
            accepted.push(*block);
        }
        if !accepted.is_empty() {
            map_node::<C, (&str, Vec<CapabilityBlock<'_>>)>(control)?;
            groups.insert(ty, accepted);
        }
    }
    control.checkpoint()?;
    Ok(groups)
}

/// The entries of the static kinds (`STATIC_ENTRY`), by type: the library reads them at world setup without making an instance of the type
/// (a map-time resolver and a loot table belong to a type that is never made). Each row is the block's file, the line of the block, and its
/// static entries with their own lines, in order; a type that declares none has no row.
pub(crate) fn static_blocks(cx:&Input<'_>,out:&mut Output,caps:&[Cap],globals:&BTreeSet<String>,statics:&BTreeSet<String>){match static_blocks_controlled(&mut crate::key_policy_control::Compatibility,cx,out,caps,globals,statics){Ok(())=>(),Err(never)=>match never{}}}
fn static_blocks_controlled<C:crate::key_policy_control::Control>(control:&mut C,cx:&Input<'_>,out:&mut Output,caps:&[Cap],globals:&BTreeSet<String>,statics:&BTreeSet<String>)->Result<(),C::Error>{
    use crate::key_policy_control as kc;control.checkpoint()?;
    out.doc("declared_static_blocks(): type -> list(file, line, entries) for the entries of the static kinds (STATIC_ENTRY), read without an instance.");
    let mut rows:Vec<Vec<String>>=Vec::new();
    if !statics.is_empty(){
        for (ty, blocks) in capability_groups(control, cx, |_| true, None)? {
            let marker = blocks[0].marker;
            let mut parts = Vec::new();
            for block in blocks {
                control.checkpoint()?;
                let origin = block.marker;
                let offsets = arg_offsets_controlled(control, origin.body, origin.args)?;
                for (index, arg) in origin.args.iter().enumerate().skip(1) {
                    control.checkpoint()?;
                    if arg.is_empty() || !is_static_entry_controlled(control, arg, statics)? {
                        continue;
                    }
                    let line = origin.line_at(offsets[index]);
                    let location = if block.feature.is_some() {
                        let file = quote_controlled(control, origin.rel)?;
                        kc::format(control, format_args!("entry_line({}, null, {})", line, file))?
                    } else {
                        kc::format(control, format_args!("entry_line({})", line))?
                    };
                    kc::row(control, &mut parts)?;
                    parts.push(location);
                    kc::row(control, &mut parts)?;
                    parts.push(entry_text_controlled(control, arg, caps, globals)?);
                }
            }
            if parts.is_empty(){continue}
            let test_only=crate::generator_test_scope::test_only(marker.rel);let mut row=Vec::new();
            if test_only{kc::row(control,&mut row)?;row.push(kc::own(control,crate::generator_test_scope::TEST_GUARD)?);}
            kc::row(control,&mut row)?;row.push(kc::format(control,format_args!("	// CAPABILITIES({}) at {}:{}",ty,marker.rel,marker.line))?);
            let quoted=quote_controlled(control,marker.rel)?;kc::row(control,&mut row)?;row.push(kc::format(control,format_args!("	into[{}] = list({}, {}, list({}))",ty.trim(),quoted,marker.line,Joined(&parts)))?);
            if test_only{kc::row(control,&mut row)?;row.push(kc::own(control,"#endif")?);}
            kc::row(control,&mut rows)?;rows.push(row);
        }
    }
    let chunks=rows.chunks(150).len();out.line("/proc/declared_static_blocks()");out.line("	. = list()");
    for index in 0..chunks{control.checkpoint()?;out.line_fmt(format_args!("	declared_static_blocks_part{}(.)",index+1));}out.blank();
    for(index,chunk)in rows.chunks(150).enumerate(){control.checkpoint()?;out.line_fmt(format_args!("/proc/declared_static_blocks_part{}(list/into)",index+1));for row in chunk{for line in row{control.checkpoint()?;out.line(line);}}out.blank();}
    control.checkpoint()?;Ok(())
}

struct LazyOwned<'a> {
    state_type: String,
    holders: Vec<&'a str>,
    var: String,
    test_only: bool,
}

struct LazyTable {
    state_type: String,
    test_only: bool,
}

/// Both declared storage forms use the same original marker/entry order.
fn lazy_accessors_controlled<C: crate::key_policy_control::Control>(
    control: &mut C,
    cx: &Input<'_>,
    out: &mut Output,
) -> Result<(), C::Error> {
    use crate::{declare_ids_policy::split_opt_borrowed, key_policy_control as kc};
    let mut owned: BTreeMap<String, LazyOwned<'_>> = BTreeMap::new();
    let mut tables: BTreeMap<String, LazyTable> = BTreeMap::new();
    let mut table_holders = Vec::new();
    for marker in cx.markers("CAPABILITIES") {
        control.checkpoint()?;
        let Some(holder) = marker.args.first().map(|arg| arg.trim()) else { continue };
        let test_only = crate::generator_test_scope::test_only(marker.rel);
        for entry in marker.args.iter().skip(1) {
            if entry.contains("owns_one") {
                scan_calls_controlled(control, entry, "owns_one", &mut |control, _, args| {
                    let Some(args) = args else { return Ok(()) };
                    if !args.iter().filter_map(|arg| split_opt_borrowed(arg)).any(|(key, value)| key == "lazy" && value.trim() == "TRUE") {
                        return Ok(());
                    }
                    let Some(var) = args.first().and_then(|arg| arg.trim().strip_prefix("nameof(")).and_then(|arg| arg.strip_suffix(')')).map(str::trim) else { return Ok(()) };
                    let ty = args.get(1).and_then(|arg| match split_opt_borrowed(arg) {
                        Some(("type", value)) => Some(value),
                        Some(_) => None,
                        None => Some(arg.trim()),
                    }).filter(|arg| arg.starts_with('/'));
                    let Some(ty) = ty else {
                        out.diag_fmt(marker.rel, marker.line, format_args!("owns_one(nameof({}), lazy = TRUE) on {}: name the state type as the second argument", var, holder));
                        return Ok(());
                    };
                    let valid = ty.rsplit('/').next().and_then(|leaf| leaf.strip_suffix("_state")) == Some(var);
                    if !ty.starts_with("/datum/") || !valid {
                        out.diag_fmt(marker.rel, marker.line, format_args!("owns_one(nameof({}), lazy = TRUE) on {}: the state type is /datum/{}_state, not {}", var, holder, var, ty));
                        return Ok(());
                    }
                    let name = kc::format(control, format_args!("{}_of", var))?;
                    if let Some(row) = owned.get_mut(&name) {
                        if row.state_type != ty {
                            out.diag_fmt(marker.rel, marker.line, format_args!("lazy state `{}`: {} names {}, another holder names {}; the accessor {}() is global, so name the vars apart", var, holder, ty, row.state_type, name));
                        } else if row.test_only != test_only {
                            out.diag_fmt(marker.rel, marker.line, format_args!("lazy state `{}`: declared by both test and game types; name the test var apart", var));
                        } else if !row.holders.contains(&holder) {
                            kc::row(control, &mut row.holders)?;
                            row.holders.push(holder);
                        }
                    } else {
                        map_node::<C, (String, LazyOwned<'_>)>(control)?;
                        let mut holders = Vec::new();
                        kc::row(control, &mut holders)?;
                        holders.push(holder);
                        let state_type = kc::own(control, ty)?;
                        let var = kc::own(control, var)?;
                        owned.insert(name, LazyOwned { state_type, holders, var, test_only });
                    }
                    Ok(())
                })?;
            }
            if entry.contains("lazy_state") {
                scan_calls_controlled(control, entry, "lazy_state", &mut |control, _, args| {
                    let Some(args) = args else { return Ok(()) };
                    let (Some(feature), Some(ty)) = (args.first().map(|arg| arg.trim()), args.get(1).map(|arg| arg.trim())) else {
                        out.diag_fmt(marker.rel, marker.line, format_args!("lazy_state() on {} needs (feature, /datum/feature_state)", holder));
                        return Ok(());
                    };
                    if ty.strip_prefix("/datum/").and_then(|leaf| leaf.strip_suffix("_state")) != Some(feature) {
                        out.diag_fmt(marker.rel, marker.line, format_args!("lazy_state({}, ..) on {}: the state type is /datum/{}_state, not {}", feature, holder, feature, ty));
                        return Ok(());
                    }
                    if !test_only {
                        kc::row(control, &mut table_holders)?;
                        table_holders.push((holder, kc::own(control, feature)?));
                    }
                    if let Some(row) = tables.get(feature) {
                        if row.test_only != test_only {
                            out.diag_fmt(marker.rel, marker.line, format_args!("lazy state `{}`: declared by both test and game types; name the test feature apart", feature));
                        }
                    } else {
                        map_node::<C, (String, LazyTable)>(control)?;
                        tables.insert(kc::own(control, feature)?, LazyTable { state_type: kc::own(control, ty)?, test_only });
                    }
                    Ok(())
                })?;
            }
        }
    }
    if owned.is_empty() && tables.is_empty() {
        return Ok(());
    }
    out.doc("Every lazy state declaration: list(holder type, feature, state type, \"table\" or \"var\", write proc, clear proc, weak-reference write proc). Read by code/engine/declare/lazy_state.dm (View Variables, SDQL, the state serializer).");
    out.line("/proc/lazy_feature_rows()");
    out.line("\tvar/static/list/rows = list(");
    let mut entries = Vec::new();
    for (holder, feature) in &table_holders {
        control.checkpoint()?;
        if let Some(row) = tables.get(feature) {
            let quoted = quote_controlled(control, feature)?;
            kc::row(control, &mut entries)?;
            entries.push(kc::format(control, format_args!("\t\tlist({}, {}, {}, \"table\", GLOBAL_PROC_REF({}_write), GLOBAL_PROC_REF({}_clear), GLOBAL_PROC_REF({}_ref_write))", holder, quoted, row.state_type, feature, feature, feature))?);
        }
    }
    for (name, row) in &owned {
        if row.test_only {
            continue;
        }
        let var = name.trim_end_matches("_of");
        let quoted = quote_controlled(control, var)?;
        for holder in &row.holders {
            control.checkpoint()?;
            kc::row(control, &mut entries)?;
            entries.push(kc::format(control, format_args!("\t\tlist({}, {}, {}, \"var\", GLOBAL_PROC_REF({}_write), GLOBAL_PROC_REF({}_clear), GLOBAL_PROC_REF({}_ref_write))", holder, quoted, row.state_type, var, var, var))?);
        }
    }
    if entries.is_empty() {
        out.blank();
    }
    for (index, entry) in entries.iter().enumerate() {
        control.checkpoint()?;
        out.line_fmt(format_args!("{}{}", entry, if index + 1 == entries.len() { "" } else { "," }));
    }
    out.line("\t)");
    out.line("\treturn rows");
    out.doc("The lazy states' accessors (owns_one(lazy = TRUE) and lazy_state()): x_of(holder) is the holder's state datum, made on the first call; x_peek() is the state or null;");
    out.doc("x_clear() ends it; x_write() is STATE_SET(): no state for a default value, a state dropped when every field is default again.");
    for (feature, row) in &tables {
        control.checkpoint()?;
        let ty = &row.state_type;
        let quoted = quote_controlled(control, feature)?;
        if row.test_only {
            out.line(crate::generator_test_scope::TEST_GUARD);
        }
        out.line_fmt(format_args!("/proc/{}_peek(datum/H)", feature));
        out.line_fmt(format_args!("\tRETURN_TYPE({})", ty));
        out.line_fmt(format_args!("\treturn lazy_state_peek(H, {})", quoted));
        out.line_fmt(format_args!("/proc/{}_of(datum/H)", feature));
        out.line_fmt(format_args!("\tRETURN_TYPE({})", ty));
        out.line_fmt(format_args!("\treturn lazy_state_peek(H, {}) || lazy_table_make(H, {}, {})", quoted, quoted, ty));
        out.line_fmt(format_args!("/proc/{}_view(datum/H)", feature));
        out.line_fmt(format_args!("\tRETURN_TYPE({})", ty));
        out.line_fmt(format_args!("\treturn {}_peek(H) || lazy_state_default_row({}, {})", feature, quoted, ty));
        out.line_fmt(format_args!("/proc/{}_clear(datum/H)", feature));
        out.line_fmt(format_args!("\tlazy_table_clear(H, {})", quoted));
        lazy_write_proc(out, feature);
        if row.test_only {
            out.line("#endif");
        }
    }
    for (name, row) in &owned {
        control.checkpoint()?;
        let ty = &row.state_type;
        let var = name.trim_end_matches("_of");
        let quoted = quote_controlled(control, var)?;
        if row.test_only {
            out.line(crate::generator_test_scope::TEST_GUARD);
        }
        out.line_fmt(format_args!("/proc/{}(datum/H)", name));
        lazy_holder_lookup(control, out, row)?;
        out.line_fmt(format_args!("\treturn S || lazy_state_make(H, {}, {})", quoted, ty));
        out.line_fmt(format_args!("/proc/{}_peek(datum/H)", var));
        lazy_holder_lookup(control, out, row)?;
        out.line("\treturn S");
        out.line_fmt(format_args!("/proc/{}_view(datum/H)", var));
        out.line_fmt(format_args!("\tRETURN_TYPE({})", ty));
        out.line_fmt(format_args!("\treturn {}_peek(H) || lazy_state_default_row({}, {})", var, quoted, ty));
        out.line_fmt(format_args!("/proc/{}_clear(datum/H)", var));
        out.line_fmt(format_args!("\tlazy_state_clear(H, {})", quoted));
        lazy_write_proc(out, var);
        if row.test_only {
            out.line("#endif");
        }
    }
    out.blank();
    control.checkpoint()
}

fn lazy_holder_lookup<C: crate::key_policy_control::Control>(control: &mut C, out: &mut Output, row: &LazyOwned<'_>) -> Result<(), C::Error> {
    out.line_fmt(format_args!("\tRETURN_TYPE({})", row.state_type));
    out.line_fmt(format_args!("\tvar/{}/S", row.state_type.trim_start_matches('/')));
    for (i, holder) in row.holders.iter().enumerate() {
        control.checkpoint()?;
        out.line_fmt(format_args!("\t{}if(istype(H, {}))", if i == 0 { "" } else { "else " }, holder));
        out.line_fmt(format_args!("\t\tvar/{}/X{} = H", holder.trim_start_matches('/'), i));
        out.line_fmt(format_args!("\t\tS = X{}.{}", i, row.var));
    }
    Ok(())
}

fn lazy_write_proc(out: &mut Output, feature: &str) {
    out.line_fmt(format_args!("/proc/{}_write(datum/H, value, default, setter)", feature));
    // A null write is a write of the default, as a null write cleared an old sparse slot.
    out.line("\tif(isnull(value))");
    out.line("\t\tvalue = default");
    out.line("\tvar/is_default = value == default && isnull(value) == isnull(default)");
    out.line_fmt(format_args!("\tvar/datum/S = {}_peek(H)", feature));
    out.line("\tif(!S)");
    out.line("\t\tif(is_default)");
    out.line("\t\t\treturn");
    out.line_fmt(format_args!("\t\tS = {}_of(H)", feature));
    out.line("\tcall(S, setter)(value)");
    out.line("\tif(is_default && lazy_state_all_default(S))");
    out.line_fmt(format_args!("\t\t{}_clear(H)", feature));
    // x_ref_write(H, field, target): STATE_REF_SET(), the write of a weak reference field (ref_one(weak = TRUE) on the state type): no state for a null target when
    // there is none, and the state goes when that was its last non-default field.
    out.line_fmt(format_args!("/proc/{}_ref_write(datum/H, field, datum/target)", feature));
    out.line_fmt(format_args!("\tvar/datum/S = {}_peek(H)", feature));
    out.line("\tif(!S)");
    out.line("\t\tif(isnull(target))");
    out.line("\t\t\treturn");
    out.line_fmt(format_args!("\t\tS = {}_of(H)", feature));
    out.line("\trel_set(S, field, target)");
    out.line("\tif(isnull(target) && lazy_state_all_default(S))");
    out.line_fmt(format_args!("\t\t{}_clear(H)", feature));
}

/// The keyed relations the CAPABILITIES lists declare (`ref_one(nameof(v), /type, by = nameof(id))`): the type the holder finds and the id var both
/// sides carry. A type is a keyed target whichever side builds its table first, so the table of a target built before any holder's (a door
/// placed before its button) must already know its key: the engine reads this list once, ahead of the first table.
fn map_node<C:crate::key_policy_control::Control,T>(control:&mut C)->Result<(),C::Error>{crate::key_policy_control::reserve(control,||std::mem::size_of::<T>().checked_mul(16)?.checked_add(2048))}
pub(crate) fn keyed_targets(cx:&Input<'_>,out:&mut Output){match keyed_targets_controlled(&mut crate::key_policy_control::Compatibility,cx,out){Ok(())=>(),Err(never)=>match never{}}}
fn keyed_targets_controlled<C:crate::key_policy_control::Control>(control:&mut C,cx:&Input<'_>,out:&mut Output)->Result<(),C::Error>{
    use crate::{key_policy_control as kc,declare_ids_policy::split_opt_borrowed};
    let mut rows:BTreeMap<String,(String,bool)>=BTreeMap::new();
    for marker in cx.markers("CAPABILITIES"){control.checkpoint()?;let test_only=crate::generator_test_scope::test_only(marker.rel);
        for arg in marker.args.iter().skip(1){for name in["ref_one","ref_many"]{
            let _=observe_calls_controlled(control,arg,name,&mut|control,args|{
                let ty=args.get(1).filter(|value|split_opt_borrowed(value).is_none());
                let named=|name:&str|args.iter().filter_map(|arg|split_opt_borrowed(arg)).find(|(key,_)|*key==name).map(|(_,value)|value);
                let by=named("target_key").or_else(||named("by"));
                if let(Some(ty),Some(by))=(ty,by){let var=by.trim().strip_prefix("nameof(").and_then(|value|value.strip_suffix(')')).unwrap_or(by.trim()).trim();let var=var.rsplit("::").next().unwrap_or(var);
                    let var=kc::own(control,var)?;if !C::CHECKED||!rows.contains_key(ty.trim()){map_node::<C,(String,(String,bool))>(control)?;}
                    let ty=kc::own(control,ty.trim())?;rows.insert(ty,(var,test_only));
                }
                Ok(String::new())
            })?;
        }}
    }
    out.doc("declared_keyed_targets(): target type -> the id var a keyed relation (by =) matches it on, read once before the first ownership table.");
    out.line("/proc/declared_keyed_targets()");out.line("\t. = list()");
    for(ty,(var,test_only))in &rows{control.checkpoint()?;if *test_only{out.line(crate::generator_test_scope::TEST_GUARD);}
        let quoted=quote_controlled(control,var)?;out.line_fmt(format_args!("\t.[{}] = {}",ty,quoted));
        if *test_only{out.line("#endif");}
    }
    out.blank();control.checkpoint()?;Ok(())
}

/// The accessors of the weak references (`ref_one/ref_many(nameof(v), /type, weak = TRUE)`, relations proposal D5): the var holds a handle, so
/// `v()` on the holder type resolves it (weak_get(): the datum or null, or the live members of a many). Generated, so no site writes its own.
pub(crate) fn weak_accessors(cx:&Input<'_>,out:&mut Output){match weak_accessors_controlled(&mut crate::key_policy_control::Compatibility,cx,out){Ok(())=>(),Err(never)=>match never{}}}
fn weak_accessors_controlled<C:crate::key_policy_control::Control>(control:&mut C,cx:&Input<'_>,out:&mut Output)->Result<(),C::Error>{
 use crate::{key_policy_control as kc,declare_ids_policy::split_opt_borrowed};
 let mut rows:BTreeMap<(String,String),(Option<String>,bool,bool)>=BTreeMap::new();
 for marker in cx.markers("CAPABILITIES"){control.checkpoint()?;let Some(holder)=marker.args.first().map(|value|value.trim())else{continue};let test_only=crate::generator_test_scope::test_only(marker.rel);
  for arg in marker.args.iter().skip(1){for name in["ref_one","ref_many"]{
   let _=observe_calls_controlled(control,arg,name,&mut|control,args|{
    let weak=args.iter().filter_map(|arg|split_opt_borrowed(arg)).any(|(key,value)|key=="weak"&&value.trim()=="TRUE");if !weak{return Ok(String::new())}
    let Some(first)=args.first()else{return Ok(String::new())};let Some(var)=nameof_inner_controlled(control,first.trim())?else{return Ok(String::new())};
    let ty=match args.get(1).filter(|arg|split_opt_borrowed(arg).is_none()).map(|value|value.trim()).filter(|value|value.starts_with('/')){Some(value)=>Some(kc::own(control,value)?),None=>None};
    map_node::<C,((String,String),(Option<String>,bool,bool))>(control)?;let holder=kc::own(control,holder)?;rows.insert((holder,var),(ty,name=="ref_many",test_only));Ok(String::new())
   })?;
  }}
 }
 if rows.is_empty(){control.checkpoint()?;return Ok(())}
 out.doc("The weak references' accessors (ref_one/ref_many(weak = TRUE)): the var holds a handle; v() reads the live target, or null.");
 for((holder,var),(ty,many,test_only))in &rows{control.checkpoint()?;if *test_only{out.line(crate::generator_test_scope::TEST_GUARD);}
  match(many,ty){(false,Some(ty))=>out.line_fmt(format_args!("{}/proc/{}() as {}",holder,var,ty)),(true,_)=>out.line_fmt(format_args!("{}/proc/{}() as /list",holder,var)),_=>out.line_fmt(format_args!("{}/proc/{}()",holder,var))};
  let quoted=quote_controlled(control,var)?;out.line_fmt(format_args!("	return weak_get(src, {})",quoted));if *test_only{out.line("#endif");}
 }out.blank();control.checkpoint()?;Ok(())
}

/// The declarations of the files in one half of the tree: the engine and the game (`test_only` false), or the test fixtures.
pub(crate) fn section(cx:&Input<'_>,out:&mut Output,caps:&[Cap],globals:&BTreeSet<String>,statics:&BTreeSet<String>,test_only:bool){match section_controlled(&mut crate::key_policy_control::Compatibility,cx,out,caps,globals,statics,test_only){Ok(())=>(),Err(never)=>match never{}}}
fn section_controlled<C:crate::key_policy_control::Control>(control:&mut C,
    cx: &Input<'_>,
    out: &mut Output,
    caps: &[Cap],
    globals: &BTreeSet<String>,
    statics: &BTreeSet<String>,
    test_only: bool,
)->Result<(),C::Error> {
    use crate::key_policy_control as kc;
    let in_half = |rel: &str| crate::generator_test_scope::test_only(&rel) == test_only;
    // Capabilities: the datum's param vars, the constructor, the registration row.
    for cap in caps.iter().filter(|c| in_half(&c.rel)) {
        control.checkpoint()?;
        out.doc_fmt(format_args!(
            "{}({}, {}) at {}:{}",
            if cap.is_def {
                "CAPABILITY_DEF"
            } else {
                "CAPABILITY_TYPE"
            },
            cap.name,
            cap.id,
            cap.rel,
            cap.line
        ));
        if !cap.params.is_empty() {
            out.line(&cap.ty);
            for (p, d) in &cap.params {
                if let Some(d) = d {
                    out.line_fmt(format_args!("\tvar/{} = {}", p, one_line_controlled(control,d)?));
                }
            }
        }
        let mut names=Vec::new();for(name,_)in &cap.params{kc::row(control,&mut names)?;names.push(name.as_str());}
        let joined=kc::format(control,format_args!("{}",Joined(&names)))?;
        let quoted_names=quote_controlled(control,&joined)?;
        out.line_fmt(format_args!("/proc/{}({})", cap.name, joined));
        out.line_fmt(format_args!("\tRETURN_TYPE({})", cap.ty));
        out.line_fmt(format_args!(
            "\treturn cap_construct({}, {}, list({}), {})",
            cap.id,
            cap.ty,
            joined,
            quoted_names
        ));
        out.line_fmt(format_args!("/datum/capdef_decl/c_{}/spec()", cap.name));
        out.line_fmt(format_args!(
            "\treturn list({}, {}, {}, {}, {}, {})",
            cap.id,
            cap.ty,
            key_expr_controlled(control,&cap.key)?,
            cap.stacks.as_deref().unwrap_or("STACK"),
            quote_controlled(control,cap.prefix.as_deref().unwrap_or(&cap.name))?,
            quoted_names
        ));
        out.blank();
    }
    // State keys.
    let mut by_id:BTreeMap<&String,&String>=BTreeMap::new();for cap in caps{control.checkpoint()?;if !by_id.contains_key(&cap.id){map_node::<C,(&String,&String)>(control)?;}by_id.insert(&cap.id,&cap.name);}
    for m in cx.markers("cap_keys").filter(|m| in_half(&m.rel)) {
        let Some(cap_id) = m.args.first() else {
            continue;
        };
        let cap_name=if let Some(name)=by_id.get(cap_id){kc::own(control,name)?}else{lower_controlled(control,cap_id.trim_start_matches("CAP_"))?};
        let mut rows = Vec::new();
        let mut accessors = Vec::new();
        for a in m.args.iter().skip(1) {
            if let Some((k,v))=crate::declare_ids_policy::split_opt_borrowed(a){
                let value=one_line_controlled(control,v)?;kc::row(control,&mut rows)?;rows.push(kc::format(control,format_args!("{} = {}",k,value))?);
                kc::row(control,&mut accessors)?;accessors.push(k);
            }
        }
        out.doc_fmt(format_args!("cap_keys({}) at {}:{}", cap_id, m.rel, m.line));
        out.line_fmt(format_args!("/datum/cap_keys_decl/k_{}/spec()", cap_name));
        out.line_fmt(format_args!(
            "\treturn list({}, list({}))",
            cap_id,
            Joined(&rows)
        ));
        for k in accessors {
            out.line_fmt(format_args!("/// The state key {} of {}, read on a holder (a granted capability with several selectors names the selector).", k, cap_name));
            out.line_fmt(format_args!(
                "/proc/{}_{}(datum/holder, selector)",
                cap_name,
                lower_controlled(control,k)?
            ));
            out.line_fmt(format_args!(
                "\treturn cap_key_get(holder, {}_{}, selector)",
                kc::upper(control,&cap_name)?,
                kc::upper(control,k)?
            ));
        }
        out.blank();
    }
    // Stages, sources, graphs.
    for m in cx.markers("STAGE_DEF").filter(|m| in_half(&m.rel)) {
        if let (Some(g), Some(n)) = (m.args.first(), m.args.get(1)) {
            out.line_fmt(format_args!("/datum/stage_def/{}_{}/spec()", g, n));
            out.line_fmt(format_args!(
                "\treturn list(STAGE_{}_{}, {}, {})",
                kc::upper(control,g)?,
                kc::upper(control,n)?,
                quote_controlled(control,g)?,
                quote_controlled(control,n)?
            ));
        }
    }
    for m in cx.markers("SOURCE_DEF").filter(|m| in_half(&m.rel)) {
        if let Some(n) = m.args.first() {
            out.line_fmt(format_args!("/datum/source_def/{}/spec()", n));
            out.line_fmt(format_args!("\treturn list(SRC_{}, {})", kc::upper(control,n)?, quote_controlled(control,n)?));
        }
    }
    for m in cx.markers("STATE_GRAPH").filter(|m| in_half(&m.rel)) {
        let Some(g) = m.args.first() else { continue };
        let mut entries=Vec::new();for arg in m.args.iter().skip(1){let line=one_line_controlled(control,arg)?;let value=qualify_globals_controlled(control,&line,globals)?;kc::row(control,&mut entries)?;entries.push(value);}
        out.doc_fmt(format_args!("STATE_GRAPH({}) at {}:{}", g, m.rel, m.line));
        out.line_fmt(format_args!(
            "/datum/graph_decl/g_{}/spec()",
            lower_controlled(control,g)?
        ));
        out.line_fmt(format_args!("\treturn list({}, {})", g, Joined(&entries)));
    }
    out.blank();
    let groups = capability_groups(control, cx, in_half, Some(&mut *out))?;
    for (ty, blocks) in &groups {
        control.checkpoint()?;
        let m = blocks[0].marker;
        out.doc_fmt(format_args!("CAPABILITIES({}) at {}:{}", ty, m.rel, m.line));
        out.line_fmt(format_args!("{}/declared_entries(list/into)", ty));
        out.line("\t..(into)");
        out.line_fmt(format_args!(
            "\tinto += entry_block({}, {}, {})",
            quote_controlled(control,&m.rel)?,
            m.line,
            ty
        ));
        // table_build() marks the chain it asks for: a block whose table is already compiled is not read, so its constructors are not run again.
        out.line_fmt(format_args!("\tif(declare_block_skipped(into, {}))", ty));
        out.line("\t\treturn");
        for block in blocks {
            control.checkpoint()?;
            if let Some(feature) = block.feature {
                out.line_fmt(format_args!("\t// part {} at {}:{}", feature, block.marker.rel, block.marker.line));
            }
            emit_capability_entries(control, out, *block, ty, caps, globals, statics)?;
        }
        out.blank();
    }
    lifeform_type_extras_controlled(control, out, &groups)?;
    control.checkpoint()?;
    Ok(())
}

fn emit_capability_entries<C: crate::key_policy_control::Control>(
    control: &mut C,
    out: &mut Output,
    block: CapabilityBlock<'_>,
    ty: &str,
    caps: &[Cap],
    globals: &BTreeSet<String>,
    statics: &BTreeSet<String>,
) -> Result<(), C::Error> {
    use crate::key_policy_control as kc;
    let m = block.marker;
    // section(name, "doc") opens a section: the entries after it, to the next section or the block's end, are the type's own
    // entries like any other, and each carries the section's name with its file:line (Explain Type and Interaction print both).
    let offsets = arg_offsets_controlled(control, m.body, m.args)?;
    let mut current: Option<(String, u32, usize)> = None; // name, line, entries so far
    let mut seen_sections: BTreeMap<String, u32> = BTreeMap::new();
    let close_section = |cur: &Option<(String, u32, usize)>, out: &mut Output| {
        if let Some((name, line, 0)) = cur {
            out.diag(
                &m.rel,
                *line,
                format_args!("section({}) of {} has no entries", name, ty),
            );
        }
    };
    for (i, a) in m.args.iter().enumerate().skip(1) {
        control.checkpoint()?;
        if a.is_empty() || is_static_entry_controlled(control,a,statics)? {
            continue;
        }
        let line = m.line_at(offsets[i]);
        if is_var_assignment(a) {
            out.diag(&m.rel, line, format_args!("`{}` is a var assignment inside the CAPABILITIES block of {}: the block holds entries only, so the type's vars would be lost; put the CAPABILITIES block after the type's var lines", one_line_controlled(control,a)?, ty));
            continue;
        }
        if let Some(parts) = section_parts_controlled(control,a)? {
            close_section(&current, out);
            let name=kc::own(control,parts.first().map(|part|part.trim()).unwrap_or(""))?;
            let ok_name = !name.is_empty()
                && name.chars().all(|c| c.is_alphanumeric() || c == '_')
                && !name.starts_with(|c: char| c.is_ascii_digit());
            let ok_doc = parts.len() <= 2
                && parts
                    .get(1)
                    .map(|d| d.trim().starts_with('"'))
                    .unwrap_or(true);
            if !(ok_name && ok_doc) {
                out.diag(&m.rel, line, format_args!("`{}`: a section header is section(name) or section(name, \"doc\") with name an identifier", one_line_controlled(control,a)?));
                current = None;
                continue;
            }
            if !seen_sections.contains_key(&name){map_node::<C,(String,u32)>(control)?;}
            let seen_name=kc::own(control,&name)?;
            if let Some(first) = seen_sections.insert(seen_name,line) {
                out.diag(
                    &m.rel,
                    line,
                    format_args!(
                        "section({}) of {} is declared twice (first at line {})",
                        name, ty, first
                    ),
                );
            }
            let doc=if let Some(value)=parts.get(1){let value=one_line_controlled(control,value.trim().trim_matches('"'))?;kc::format(control,format_args!(": {}",value))?}else{String::new()};
            out.line_fmt(format_args!("\t// section {}{}", name, doc));
            current = Some((name, line, 0));
            continue;
        }
        let section = current.as_mut().map(|(name, _, n)| {
            *n += 1;
            name.as_str()
        });
        match (block.feature, section) {
            (None, None) => out.line_fmt(format_args!("\tinto += entry_line({})", line)),
            (None, Some(name)) => out.line_fmt(format_args!("\tinto += entry_line({}, {})", line, quote_controlled(control, name)?)),
            (Some(_), section) => {
                let file = quote_controlled(control, m.rel)?;
                let name = section.map(|name| quote_controlled(control, name)).transpose()?;
                out.line_fmt(format_args!("\tinto += entry_line({}, {}, {})", line, name.as_deref().unwrap_or("null"), file));
            }
        }
        out.line_fmt(format_args!(
            "\tinto += list({})",
            entry_text_controlled(control,a,caps,globals)?
        ));
    }
    close_section(&current, out);
    Ok(())
}

/// Whether a block line is `name = value` (a var override that fell into a CAPABILITIES block) and not an entry call.
pub(crate) fn is_var_assignment(arg: &str) -> bool {
    let t = arg.trim_start();
    let end = t
        .find(|c: char| !(c.is_alphanumeric() || c == '_'))
        .unwrap_or(t.len());
    if end == 0 {
        return false;
    }
    let rest = t[end..].trim_start();
    rest.starts_with('=') && !rest.starts_with("==")
}

/// The first argument of a `nameof(x)` text: `x`.
pub(crate) fn nameof_inner(arg:&str)->Option<String>{match nameof_inner_controlled(&mut crate::key_policy_control::Compatibility,arg){Ok(value)=>value,Err(never)=>match never{}}}
fn nameof_inner_controlled<C:crate::key_policy_control::Control>(control:&mut C,arg:&str)->Result<Option<String>,C::Error>{let text=arg.trim();match text.strip_prefix("nameof(").and_then(|value|value.strip_suffix(')')){Some(inner)=>crate::key_policy_control::own(control,inner.trim()).map(Some),None=>Ok(None)}}

/// Whether a type path names an atom (its instances initialize through Initialize(), not New()).
pub(crate) fn is_atom_path(ty: &str) -> bool {
    ["/atom", "/obj", "/mob", "/turf", "/area"]
        .iter()
        .any(|p| ty == *p || ty.strip_prefix(*p).is_some_and(|rest|rest.starts_with('/')))
}

/// The calls a block names, by constructor name (a quick scan: a name followed by `(`, outside strings).
pub(crate) fn block_calls(args:&[String],name:&str)->Vec<Vec<String>> { match block_calls_controlled(&mut crate::key_policy_control::Compatibility,args,name){Ok(value)=>value,Err(never)=>match never{}} }
fn block_calls_controlled<C:crate::key_policy_control::Control>(control:&mut C,args:&[String],name:&str)->Result<Vec<Vec<String>>,C::Error>{
 let mut found=Vec::new();for arg in args.iter().skip(1){scan_calls_controlled(control,arg,name,&mut|control,_,inner|{if let Some(inner)=inner{crate::key_policy_control::row(control,&mut found)?;found.push(inner);}Ok(())})?;}Ok(found)
}

/// The lifecycle forms (code/engine/lifeforms/) a type's block needs the generator for:
/// - a non-atom type whose block names a form (a type-level every() is one: lifeform_datum_new() arms it; so is factors(), whose table lifeform_datum_new() puts on the entity its relation names; after_init() is one too: lifeform_datum_new() takes the make() record that arms it), or an owns_one/owns_many with starts =, gets `lifeform_declared = TRUE`, so /datum/New() runs it;
///
/// A type whose block names click_on(), double_click_on(), drag_onto(), drag_over(), hover() or tooltip() gets NO native override: BYOND's mouse
/// callbacks are overridden only in code/engine/kernel/entry.dm, and the input resolver finds the declared entry in the type tables when the event
/// resolves (the `mouse_override` lint rejects any other definition).
fn lifeform_type_extras_controlled<C: crate::key_policy_control::Control>(
    control: &mut C,
    out: &mut Output,
    groups: &CapabilityGroups<'_>,
) -> Result<(), C::Error> {
    const FORMS: &[&str] = &[
        "rolls",
        "preset",
        "param",
        "built_from",
        "registry",
        "radio_listen",
        "per_type",
        "variants",
        "initial_contents",
        "knows",
        "starts_as",
        "derives",
        "lives_while",
        "on_ending",
        "modes",
        "every",
        "keeps_if",
        "setup",
        "name_prefix",
        "factors",
        "after_init",
    ];
    for (ty, blocks) in groups {
        control.checkpoint()?;
        let ty = ty.trim();
        if is_atom_path(ty) || !ty.starts_with("/datum") {
            continue;
        }
        for block in blocks {
            control.checkpoint()?;
            let marker = block.marker;
            let mut declared = false;
            for form in FORMS {
                if !block_calls_controlled(control, marker.args, form)?.is_empty() {
                    declared = true;
                    break;
                }
            }
            // hud_element(..., when = X) is an owns_one with starts = when(X, T).
            for (owns, key) in [("owns_one", "starts"), ("owns_many", "starts"), ("hud_element", "when")] {
                if declared {
                    break;
                }
                declared = block_calls_controlled(control, marker.args, owns)?.iter().any(|args| {
                    args.iter().any(|arg| crate::declare_ids_policy::split_opt_borrowed(arg).is_some_and(|(name, _)| name == key))
                });
            }
            if declared {
                out.doc_fmt(format_args!("{} declares a lifecycle form ({}:{}): /datum/New() runs it.", ty, marker.rel, marker.line));
                out.line(ty);
                out.line("\tlifeform_declared = TRUE");
                break;
            }
        }
    }
    control.checkpoint()?;Ok(())
}

/// make(type, at =, by =, parts =, name = value...) and make_args(name = value...): their named parameters are every name a param() declares,
/// so DM checks a call's names; the bodies are the engine's (code/engine/lifeforms/params.dm). `analyze` checks each call against the made type.
pub(crate) fn make_procs(cx:&Input<'_>,out:&mut Output){match make_procs_controlled(&mut crate::key_policy_control::Compatibility,cx,out){Ok(())=>(),Err(never)=>match never{}}}
fn make_procs_controlled<C:crate::key_policy_control::Control>(control:&mut C,cx:&Input<'_>,out:&mut Output)->Result<(),C::Error>{
 use crate::key_policy_control as kc;
    const RESERVED: &[&str] = &["type", "at", "by", "parts", "given", "src", "usr", "args"];
    let mut names: BTreeSet<String> = BTreeSet::new();
    for m in cx.markers("CAPABILITIES") {
        control.checkpoint()?;
        for call in block_calls_controlled(control,&m.args, "param")? {
            let Some(first) = call.first() else { continue };
            let Some(name) = nameof_inner_controlled(control,first)? else {
                out.diag(
                    &m.rel,
                    m.line,
                    format_args!("param({}): the var is nameof(var)", first),
                );
                continue;
            };
            if RESERVED.contains(&name.as_str()) {
                out.diag(
                    &m.rel,
                    m.line,
                    format_args!(
                        "param(nameof({})): `{}` is one of make()'s own parameters; rename the var",
                        name, name
                    ),
                );
                continue;
            }
            if !names.contains(&name){map_node::<C,String>(control)?;}
            names.insert(name);
        }
    }
    let mut params=Vec::new();
    for name in &names{kc::row(control,&mut params)?;params.push(kc::format(control,format_args!("{} = MAKE_UNSET",name))?);}
    let tail=if params.is_empty(){String::new()}else{kc::format(control,format_args!(", {}",Joined(&params)))?};
    out.doc("make(type, at =, by =, parts =, name = value...): a new instance with its params set before init (code/engine/lifeforms/params.dm).");
    out.line_fmt(format_args!(
        "/proc/make(type, at = null, by = null, parts = null{})",
        tail
    ));
    out.line("\tvar/list/given = list()");
    for n in &names {
        out.line_fmt(format_args!("\tif({} != MAKE_UNSET)", n));
        out.line_fmt(format_args!("\t\tgiven[{}] = {}", quote_controlled(control,n)?, n));
    }
    out.line("\treturn make_build(type, at, by, parts, given)");
    out.doc(
        "make_args(name = value...): the params of what a starts = makes (OWNER is the holder).",
    );
    out.line_fmt(format_args!("/proc/make_args({})", Joined(&params)));
    out.line("\tvar/list/given = list()");
    for n in &names {
        out.line_fmt(format_args!("\tif({} != MAKE_UNSET)", n));
        out.line_fmt(format_args!("\t\tgiven[{}] = {}", quote_controlled(control,n)?, n));
    }
    out.line("\treturn make_args_build(given)");
    out.blank();
    control.checkpoint()?;Ok(())
}

/// The arguments of a `section(...)` header entry, or None when the entry is not one.
pub(crate) fn section_parts(entry:&str)->Option<Vec<String>>{match section_parts_controlled(&mut crate::key_policy_control::Compatibility,entry){Ok(value)=>value,Err(never)=>match never{}}}
fn section_parts_controlled<C:crate::key_policy_control::Control>(control:&mut C,entry:&str)->Result<Option<Vec<String>>,C::Error>{
 let text=entry.trim();let Some(rest)=text.strip_prefix("section").map(str::trim_start)else{return Ok(None)};
 if !rest.starts_with('('){return Ok(None)}
 let open=text.len()-rest.len();let Some(close)=matching_paren(text,open)else{return Ok(None)};
 if !text[close+1..].trim().is_empty(){return Ok(None)}
 Ok(Some(split_args_controlled(control,&text[open+1..close])?))
}

/// Admit the finite legacy temporary/retained overlap BEFORE policy transforms.
/// W sums original body/argument/path/raw-engine widths; C bounds configure
/// occurrences and D the largest actual constructor spelling. Each rewrite
/// consumes disjoint matched ranges. Link/adjusts/on_change quote expansion,
/// fixed call spelling and final global qualification conservatively fit
/// 1024*(W+C*D). At most eight simultaneous row/parts/text contexts retain a
/// transformed entry; the final factor2 covers old/new geometric String growth.
/// The original delimiter count separately bounds split_args String slots
/// (<=72W for its three-vector-capacity overlap), one_line words and small
/// BTree coordination; these fit the same conservative envelope, plus16KiB
/// per marker for empty arguments/fixed rows. Output itself remains separately
/// admitted for EVERY actual fmt chunk. This is no RSS/CPU or whole-tree claim.
fn admit_temporaries(cx: &Input<'_>) -> Result<(), String> {
    let Some(b) = &cx.budget else { return Ok(()) };
    let result = (|| -> Result<(), String> {
        let mut width = 1usize;
        let mut replaces = 0usize;
        let mut constructor = 1usize;
        for m in cx.markers {
            width = width
                .checked_add(m.name.len())
                .and_then(|n| n.checked_add(m.rel.len()))
                .and_then(|n| n.checked_add(m.body.len()))
                .ok_or("declare temporary width overflow")?;
            if matches!(m.name, "CAPABILITY_TYPE" | "CAPABILITY_DEF") {
                constructor = constructor.max(m.args.first().map_or(0, String::len));
            }
            for a in m.args {
                width = width
                    .checked_add(a.len())
                    .ok_or("declare argument width overflow")?;
                replaces = replaces
                    .checked_add(a.match_indices("configure").count())
                    .ok_or("declare replacement count overflow")?;
            }
        }
        for &(rel, text) in cx.engine_sources {
            width = width
                .checked_add(rel.len())
                .and_then(|n| n.checked_add(text.len()))
                .ok_or("declare engine width overflow")?;
        }
        let expanded = replaces
            .checked_mul(constructor)
            .and_then(|n| n.checked_add(width))
            .ok_or("declare expansion width overflow")?;
        b.charge(
            expanded
                .checked_mul(16384)
                .and_then(|n| {
                    cx.markers
                        .len()
                        .checked_mul(16384)
                        .and_then(|m| n.checked_add(m))
                })
                .ok_or("declare temporary admission overflow")?,
        )
    })();
    if result.is_err() {
        b.deny();
    }
    result
}
pub(crate) const REL_VAR_TYPES_UNAVAILABLE: &str =
    "native Declare needs original variable declarations for implicitly typed relations";

pub(crate) fn visit_rel_var_type_candidates<C: crate::key_policy_control::Control>(
    control: &mut C,
    cx: &Input<'_>,
    mut visit: impl FnMut(&mut C, &str, &str) -> Result<(), C::Error>,
) -> Result<(), C::Error> {
    use crate::declare_ids_policy::split_opt_borrowed;
    for marker in cx.markers("CAPABILITIES") {
        control.checkpoint()?;
        let Some(owner) = marker.args.first().map(|arg| arg.trim()) else { continue };
        for entry in marker.args.iter().skip(1) {
            for name in ["ref_one", "owns_one"] {
                if !entry.contains(name) {
                    continue;
                }
                scan_calls_controlled(control, entry, name, &mut |control, _, args| {
                    let Some(args) = args else { return Ok(()) };
                    if args.get(1).is_some_and(|arg| split_opt_borrowed(arg).is_none()) {
                        return Ok(());
                    }
                    if let Some(var) = args.first().and_then(|arg| arg.trim().strip_prefix("nameof(")).and_then(|arg| arg.strip_suffix(')')).map(str::trim) {
                        visit(control, owner, var)?;
                    }
                    Ok(())
                })?;
            }
        }
    }
    control.checkpoint()
}

pub fn generate(
    cx: &Input<'_>,
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Output, String> {
    checkpoint()?;
    admit_temporaries(cx)?;
    if let Some(b) = &cx.budget {
        b.require()?;
    }
    let mut out = cx.output();
    let caps = capabilities(cx, &mut out);
    checkpoint()?;
    let globals = global_constructors(cx, &caps);
    let statics = static_kinds(cx);
    checkpoint()?;
    section(cx, &mut out, &caps, &globals, &statics, false);
    checkpoint()?;
    let mut tests = cx.output();
    section(cx, &mut tests, &caps, &globals, &statics, true);
    checkpoint()?;
    if !tests.body.trim().is_empty() {
        out.line(crate::generator_test_scope::TEST_GUARD);
        out.blank();
        out.line(tests.body.trim_end());
        out.blank();
        out.line("#endif");
    }
    keyed_targets(cx, &mut out);
    checkpoint()?;
    weak_accessors(cx, &mut out);
    checkpoint()?;
    match lazy_accessors_controlled(&mut crate::key_policy_control::Compatibility, cx, &mut out) {
        Ok(()) => (),
        Err(never) => match never {},
    }
    checkpoint()?;
    static_blocks(cx, &mut out, &caps, &globals, &statics);
    checkpoint()?;
    make_procs(cx, &mut out);
    checkpoint()?;
    for d in std::mem::take(&mut tests.diags) {
        out.diag(&d.rel, d.line, d.msg);
    }
    if let Some(b) = &cx.budget {
        b.require()?;
    }
    checkpoint()?;
    Ok(out)
}

/// Typed native entry. Every policy temporary is admitted at its real growth site;
/// the caller supplies the SAME captured Output budget and no bool polling latch.
pub fn generate_controlled<C:crate::key_policy_control::Control>(cx:&Input<'_>,control:&mut C)->Result<Output,C::Error>{generate_with_constructors(cx,control,None)}
/// The names are source-neutral policy data collected during file-local loans.
/// They carry no completeness or current-source authority.
pub(crate) fn generate_with_constructors<C:crate::key_policy_control::Control>(cx:&Input<'_>,control:&mut C,engine_names:Option<BTreeSet<String>>)->Result<Output,C::Error>{
 control.checkpoint()?;
 let mut out=cx.output();
 let caps=capabilities_controlled(control,cx,&mut out)?;
 let globals=global_constructor_names_controlled(control,cx,&caps,engine_names)?;
 let statics=static_kinds_controlled(control,cx)?;
 section_controlled(control,cx,&mut out,&caps,&globals,&statics,false)?;
 let mut tests=cx.output();
 section_controlled(control,cx,&mut tests,&caps,&globals,&statics,true)?;
 if !tests.body.trim().is_empty(){out.line(crate::generator_test_scope::TEST_GUARD);out.blank();out.line(tests.body.trim_end());out.blank();out.line("#endif");}
 keyed_targets_controlled(control,cx,&mut out)?;
 weak_accessors_controlled(control,cx,&mut out)?;
 lazy_accessors_controlled(control,cx,&mut out)?;
 static_blocks_controlled(control,cx,&mut out,&caps,&globals,&statics)?;
 make_procs_controlled(control,cx,&mut out)?;
 for diagnostic in std::mem::take(&mut tests.diags){out.diag(&diagnostic.rel,diagnostic.line,diagnostic.msg);}
 control.checkpoint()?;Ok(out)
}

#[cfg(test)]
mod captured_tests {
    use super::*;
    #[test]
    fn denied_policy_temporary_work_never_starts_output_or_capability_clones() {
        let budget = crate::captured_generator_budget::Budget::new(64).unwrap();
        let args = vec!["cover".to_owned(), "CAP_COVER".to_owned()];
        let marker = Marker {
            name: "CAPABILITY_DEF",
            rel: "code/probe.dm",
            line: 1,
            body: "cover,CAP_COVER",
            args: &args,
            body_offset: 0,
            line_starts: &[0],
        };
        let rows = [marker];
        let input = Input {
            markers: &rows,
            part_features: &[],
            engine_sources: &[],
            budget: Some(budget.clone()),
            poll: None,
        };
        assert!(generate(&input, || Ok(())).is_err());
        assert!(budget.denied());
    }
    #[test]
    fn actual_output_growth_denial_after_temporary_admission_is_not_empty_success() {
        let probe = crate::captured_generator_budget::Budget::new(1024 * 1024).unwrap();
        let input = Input {
            markers: &[],
            part_features: &[],
            engine_sources: &[],
            budget: Some(probe.clone()),
            poll: None,
        };
        admit_temporaries(&input).unwrap();
        let exact = crate::captured_generator_budget::Budget::new(probe.used() + 1).unwrap();
        let denied = Input {
            markers: &[],
            part_features: &[],
            engine_sources: &[],
            budget: Some(exact.clone()),
            poll: None,
        };
        assert!(generate(&denied, || Ok(())).is_err());
        assert!(exact.denied());
    }
    #[test]
    fn marker_poll_failure_cannot_publish_partial_generated_text() {
        let args = vec!["cover".to_owned(), "CAP_COVER".to_owned()];
        let rows = [Marker {
            name: "CAPABILITY_DEF",
            rel: "code/x.dm",
            line: 1,
            body: "cover,CAP_COVER",
            args: &args,
            body_offset: 0,
            line_starts: &[0],
        }];
        let called = std::cell::Cell::new(0usize);
        let stopped = std::cell::Cell::new(false);
        let poll = || {
            let n = called.get() + 1;
            called.set(n);
            if n >= 5 {
                stopped.set(true);
                false
            } else {
                true
            }
        };
        let input = Input {
            markers: &rows,
            part_features: &[],
            engine_sources: &[],
            budget: None,
            poll: Some(&poll),
        };
        let outcome = generate(&input, || {
            if stopped.get() {
                Err("actual original operation refused".into())
            } else {
                Ok(())
            }
        });
        assert_eq!(outcome.unwrap_err(), "actual original operation refused");
        assert!(called.get() >= 5);
    }
    #[test]
    fn original_argument_line_mapping_keeps_block_replacement_coordinates() {
        let args = vec!["/datum/x".to_owned(), "op()".to_owned()];
        let m = Marker {
            name: "CAPABILITIES",
            rel: "code/x.dm",
            line: 1,
            body: "/datum/x,\n op()",
            args: &args,
            body_offset: 13,
            line_starts: &[0, 24],
        };
        assert_eq!(m.line_at(12), 2);
    }
}
