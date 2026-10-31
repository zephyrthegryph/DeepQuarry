//! Whole original ui_types raw marker/bundle/schema policy. No semantic model.
use crate::{
    captured_generator_budget::{Budget, BudgetedText},
    declare_policy::Marker,
    sparse_slots_policy::Output,
};
use std::{collections::BTreeMap, sync::Arc};
pub const UI_TYPES_OUT: &str = "tgui/packages/tgui/interfaces/generated";
pub const MARKERS: &[&str] = &["CAPABILITIES", "SCHEMA", "TRACKED_SCHEMA"];
pub struct Input<'a> {
    pub markers: &'a [Marker<'a>],
    pub(crate) budget: Option<Arc<Budget>>,
    pub(crate) poll: Option<&'a dyn Fn() -> bool>,
}
impl<'a> Input<'a> {
    fn markers<'b>(&'b self, name: &'b str) -> impl Iterator<Item = &'b Marker<'a>> + 'b {
        self.markers
            .iter()
            .take_while(|_| self.poll.map_or(true, |f| f()))
            .filter(move |m| m.name == name)
    }
    fn charge(&self, n: usize) -> bool {
        self.poll.map_or(true, |f| f())
            && self.budget.as_ref().map_or(true, |b| b.charge(n).is_ok())
    }
    fn row<T>(&self,rows:&mut Vec<T>)->bool{self.budget.as_ref().map_or(true,|budget|budget.row(rows))}
    fn node<T>(&self)->bool{std::mem::size_of::<T>().checked_mul(16).and_then(|n|n.checked_add(2048)).is_some_and(|bytes|self.charge(bytes))}
    fn own(&self,text:&str)->Option<String>{text.len().checked_mul(2).and_then(|n|n.checked_add(64)).filter(|&bytes|self.charge(bytes)).map(|_|text.to_owned())}

}
pub struct Files {
    pub files: Vec<(String, String)>,
    pub diags: Vec<crate::sparse_slots_policy::Diagnostic>,
}
pub fn generate(cx:&Input<'_>)->Result<Files,String>{generate_with(cx,&mut||Ok(()))}
/// SAME ordered policy with direct operational checkpoints, never an error latch.
pub fn generate_with<E:From<String>+for<'error>From<&'error str>>(cx:&Input<'_>,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<Files,E>{
    let mut guarded=||{if let Some(budget)=&cx.budget{budget.require()?;}checkpoint()};
    generate_core(cx,&mut guarded)
}
fn generate_core<E:From<String>+for<'error>From<&'error str>>(cx:&Input<'_>,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<Files,E>{
    checkpoint()?;
    let mut out = match &cx.budget {
        Some(b) => Output::captured(b.clone()),
        None => Output::default(),
    };
    // The schemas: (type, var) -> the schema expression as written.
    let mut schemas: BTreeMap<(&str,&str),&str> = BTreeMap::new();
    for name in ["TRACKED_SCHEMA", "SCHEMA"] {
        for m in cx.markers(name) {
            checkpoint()?;
            if let (Some(t), Some(v), Some(s)) = (m.args.first(), m.args.get(1), m.args.get(2)) {
                if !schemas.contains_key(&(t.as_str(),v.as_str()))&&!cx.node::<((&str,&str),&str)>(){return Err("ui schema directory allocation denied".into())}
                schemas.insert((t.as_str(),v.as_str()),s.as_str());
            }
        }
    }
    // Entry procs (a global proc returning a list of entries): a CAPABILITIES entry `name()` stands for them.
    let mut bundles:BTreeMap<&str,&[String]>=BTreeMap::new();
    for marker in cx.markers(crate::raw_entry_proc_policy::ENTRY_PROC){checkpoint()?;if let Some(name)=marker.args.first(){if !bundles.contains_key(name.trim())&&!cx.node::<(&str,&[String])>(){return Err("ui bundle directory allocation denied".into())}bundles.insert(name.trim(),&marker.args[1..]);}}
    let mut windows: BTreeMap<String, Window> = BTreeMap::new();
    let mut empty: Vec<(String, u32, String, String)> = Vec::new();
    for m in cx.markers("CAPABILITIES") {
            checkpoint()?;
        let Some(owner) = m.args.first() else {
            continue;
        };
        let mut window_name: Option<String> = None;
        let mut forwards = false;
        let mut fields: Vec<(String, Option<String>)> = Vec::new();
        let mut acts: Vec<Act> = Vec::new();
        let mut list: Vec<&str> = Vec::new();
        visit_bundles(&m.args[1..],&bundles,0,cx,checkpoint,&mut|raw|{if !cx.row(&mut list){return Err("ui expanded entry directory allocation denied".into())}list.push(raw);Ok(())})?;
        for raw in list.iter() {
            checkpoint()?;
            if !clean_work(raw,cx){return Err("ui entry work allocation denied".into())}
            let entry = clean(raw);
            let Some((fname, body)) = call_of(&entry) else {
                continue;
            };
            if matches!(fname,"interface"|"ui_shape"|"op")&&!cx.charge(entry.len().checked_mul(128).and_then(|n|n.checked_add(2048)).ok_or("ui entry projection overflow")?){return Err("ui entry projection allocation denied".into())}
            match fname {
                "interface" => {
                    let parts = split_top(body);
                    // A window named by a var of the host (window_var =, each subtype its own) has no name to type here.
                    if let Some(first) = parts.first().filter(|f| f.trim().starts_with('"')) {
                        window_name = Some(cx.own(first.trim().trim_matches('"')).ok_or("ui window name allocation denied")?);
                    }
                    forwards = parts
                        .iter()
                        .skip(1)
                        .any(|p| p.trim_start().starts_with("forwards"));
                }
                "ui_shape" => {
                    for part in split_top(body) {
            checkpoint()?;
                        if let Some((name, schema)) =
                            part.split_once('=').filter(|(n, _)| is_ident(n.trim()))
                        {
                            if !cx.row(&mut fields){return Err("ui field directory allocation denied".into())}
                            fields.push((cx.own(name.trim()).ok_or("ui field name allocation denied")?,Some(cx.own(schema.trim()).ok_or("ui field schema allocation denied")?)));
                        } else if is_ident(part.trim()) {
                            if !cx.row(&mut fields){return Err("ui field directory allocation denied".into())}
                            fields.push((cx.own(part.trim()).ok_or("ui field name allocation denied")?,None));
                        }
                    }
                }
                "op" => {
                    let parts = split_top(body);
                    let Some(key) = parts
                        .first()
                        .map(|k| k.trim().trim_matches('"').to_string())
                    else {
                        continue;
                    };
                    for p in parts.iter().skip(1) {
            checkpoint()?;
                        let action=if cx.budget.is_some(){let mut control:ActionControl<'_,'_,E,_>=ActionControl{cx,checkpoint:&mut *checkpoint,_error:std::marker::PhantomData};ui_act_with(p,&key,0,&mut control)?}else{ui_act_of(p,&key)};
                        if let Some(act) = action {
                            if !cx.row(&mut acts){return Err("ui action directory allocation denied".into())}
                            acts.push(act);
                        }
                    }
                }
                _ => {}
            }
        }
        let Some(name) = window_name else { continue };
        if fields.is_empty() && acts.is_empty() {
            // A window that forwards its buttons and declares nothing of its own (the sleeper console) shows its target's window, typed there.
            if forwards {
                continue;
            }
            // A subtype that declares an inherited window again (its own tgui state) is typed where the window's buttons are; judged after
            // every block is read.
            if !cx.row(&mut empty){return Err("ui empty directory allocation denied".into())}
            empty.push((cx.own(m.rel).ok_or("ui empty path allocation denied")?,m.line,name,cx.own(owner).ok_or("ui empty owner allocation denied")?));
            continue;
        }
        if !cx.charge(name.len().checked_mul(2).and_then(|n|n.checked_add(64)).ok_or("ui window key overflow")?){return Err("ui window key allocation denied".into())}
        if !windows.contains_key(&name)&&(!cx.node::<(String,Window)>()||!cx.charge(owner.len().checked_add(m.rel.len()).and_then(|n|n.checked_mul(2)).and_then(|n|n.checked_add(128)).ok_or("ui window ownership overflow")?)){return Err("ui window directory allocation denied".into())}
        let w = windows.entry(name.clone()).or_insert_with(|| Window {
            owner: owner.clone(),
            rel: m.rel.to_owned(),
            line: m.line,
            fields: Vec::new(),
            acts: Vec::new(),
        });
        for (fname, explicit) in fields {
            checkpoint()?;
            if w.fields.iter().any(|f| f.name == fname) {
                continue;
            }
            let schema = explicit.or_else(|| {
                schemas
                    .get(&(owner.as_str(),fname.as_str()))
                    .and_then(|s| clone_schema(cx, s))
            });
            if schema.is_none() {
                out.diag(&m.rel, m.line, format_args!("ui_shape({}) of {}: `{}` has no schema (TRACKED_SCHEMA or SCHEMA) to type it from", fname, owner, fname));
            }
            if !cx.row(&mut w.fields){return Err("ui retained field directory allocation denied".into())}
            w.fields.push(Field {
                name: fname,
                schema,
            });
        }
        for act in acts {
            checkpoint()?;
            if w.acts.iter().any(|a| a.name == act.name) {
                continue;
            }
            if !cx.row(&mut w.acts){return Err("ui retained action directory allocation denied".into())}
            w.acts.push(act);
        }
        // Resolve each action argument's `from = nameof(v)` against the owner's schemas.
        for act in &mut w.acts {
            checkpoint()?;
            for arg in &mut act.args {
            checkpoint()?;
                if let Some(from) = arg.from.as_deref() {
                    arg.schema = schemas
                        .get(&(owner.as_str(),from))
                        .and_then(|s| clone_schema(cx, s));
                    if arg.schema.is_none() {
                        out.diag(
                            &m.rel,
                            m.line,
                            format_args!(
                                "arg(\"{}\", from = nameof({})) of {}: `{}` has no schema",
                                arg.name, from, owner, from
                            ),
                        );
                    }
                }
            }
        }
    }
    for (rel, line, name, owner) in empty {
            checkpoint()?;
        if !windows.contains_key(&name) {
            out.diag(&rel, line, format_args!("interface(\"{}\") of {} declares no ui_shape() and no ui_act() op: nothing to type", name, owner));
        }
    }
    let mut files = Vec::new();
    for (name, w) in &windows {
            checkpoint()?;
        if !cx.poll.map_or(true, |f| f()) {
            return Err("ui generator operation stopped".into());
        }
        if let Some(b) = &cx.budget {
            if !b.row(&mut files) {
                return Err("ui file roster allocation denied".into());
            }
        }
        let (path, text) = if let Some(b) = &cx.budget {
            let mut path = BudgetedText::new(b);
            use std::fmt::Write;
            write!(path, "{}/{}.d.ts", UI_TYPES_OUT, name)
                .map_err(|_| "ui output path allocation denied")?;
            let mut text = BudgetedText::new(b);
            write_window_with(name,w,&mut text,cx,checkpoint)?;
            (path.finish()?, text.finish()?)
        } else {
            let mut text = String::new();
            write_window_with(name,w,&mut text,cx,checkpoint)?;
            (format!("{}/{}.d.ts", UI_TYPES_OUT, name), text)
        };
        files.push((path, text));
    }
    if let Some(b) = &cx.budget {
        b.require()?;
    }
    if !cx.poll.map_or(true, |f| f()) {
        return Err("ui generator operation stopped".into());
    }
    checkpoint()?;
    Ok(Files {
        files,
        diags: out.diags,
    })
}
/// The entries with each `name()` of an entry proc replaced by the proc's entries (nested ones too).
trait Bundles{fn entries(&self,name:&str)->Option<&[String]>;}
impl Bundles for BTreeMap<String,Vec<String>>{fn entries(&self,name:&str)->Option<&[String]>{self.get(name).map(Vec::as_slice)}}
impl Bundles for BTreeMap<&str,&[String]>{fn entries(&self,name:&str)->Option<&[String]>{self.get(name).copied()}}
pub(crate) fn expand_bundles(entries:&[String],bundles:&BTreeMap<String,Vec<String>>,out:&mut Vec<String>,depth:usize,cx:&Input<'_>){visit_bundles(entries,bundles,depth,cx,&mut||Ok::<(),std::convert::Infallible>(()),&mut|raw|{if cx.row(out){if let Some(value)=cx.own(raw){out.push(value)}}Ok(())}).unwrap_or_else(|never|match never{})}
fn visit_bundles<'source,E>(entries:&'source[String],bundles:&'source impl Bundles,depth:usize,cx:&Input<'_>,checkpoint:&mut impl FnMut()->Result<(),E>,emit:&mut impl FnMut(&'source str)->Result<(),E>)->Result<(),E>{
 for raw in entries{checkpoint()?;if !clean_work(raw,cx){return Ok(())}let entry=clean(raw);if depth<8{if let Some((name,body))=call_of(&entry){if body.trim().is_empty(){if let Some(inner)=bundles.entries(name){visit_bundles(inner,bundles,depth+1,cx,checkpoint,emit)?;continue}}}}emit(raw)?;}checkpoint()?;Ok(())
}

struct Field {
    name: String,
    schema: Option<String>,
}

struct Arg {
    name: String,
    schema: Option<String>,
    from: Option<String>,
}

struct Act {
    name: String,
    args: Vec<Arg>,
}

struct Window {
    owner: String,
    rel: String,
    line: u32,
    fields: Vec<Field>,
    acts: Vec<Act>,
}

fn write_window_with<E:From<String>+for<'error>From<&'error str>>(
    name: &str,
    w: &Window,
    s: &mut impl std::fmt::Write,
    cx: &Input<'_>,
    checkpoint:&mut impl FnMut()->Result<(),E>,
) -> Result<(),E> {
    checkpoint()?;
    s.write_str("// GENERATED by tools/analyze: `analyze gen ui_types`. Do not edit by hand; edit the declarations it reads.\n").map_err(|_|"ui output allocation denied")?;
    write!(s,"// Window {}: the ui_shape() and ui_act() ops of {} ({}:{}); not committed: every build regenerates it (`analyze gen`).\n\n", name, w.owner, w.rel, w.line).map_err(|_|"ui output allocation denied")?;
    write!(s, "export type {}Data = {{\n", name).map_err(|_|"ui output allocation denied")?;
    for f in &w.fields {
        checkpoint()?;
        if let Some(schema) = &f.schema {
            schema_work(schema, cx).map_err(|_|"ui output allocation denied")?;
        }
        match &f.schema {
            Some(schema) => {
                write!(s, "  /** {} */\n", describe(schema)).map_err(|_|"ui output allocation denied")?;
                write!(s, "  {}: {};\n", f.name, ts_type(schema)).map_err(|_|"ui output allocation denied")?;
            }
            None => write!(s, "  {}: unknown;\n", f.name).map_err(|_|"ui output allocation denied")?,
        }
    }
    s.write_str("};\n\n").map_err(|_|"ui output allocation denied")?;
    write!(s, "export type {}Actions = {{\n", name).map_err(|_|"ui output allocation denied")?;
    for a in &w.acts {
        checkpoint()?;
        if a.args.is_empty() {
            write!(s, "  {}: Record<string, never>;\n", quote_key(&a.name)).map_err(|_|"ui output allocation denied")?;
            continue;
        }
        write!(s, "  {}: {{\n", quote_key(&a.name)).map_err(|_|"ui output allocation denied")?;
        for arg in &a.args {
            checkpoint()?;
            if let Some(schema) = &arg.schema {
                schema_work(schema, cx).map_err(|_|"ui output allocation denied")?;
            }
            match &arg.schema {
                Some(schema) => {
                    write!(s, "    /** {} */\n", describe(schema)).map_err(|_|"ui output allocation denied")?;
                    write!(s, "    {}: {};\n", arg.name, ts_type(schema)).map_err(|_|"ui output allocation denied")?;
                }
                None => write!(s, "    {}: unknown;\n", arg.name).map_err(|_|"ui output allocation denied")?,
            }
        }
        s.write_str("  };\n").map_err(|_|"ui output allocation denied")?;
    }
    s.write_str("};\n").map_err(|_|"ui output allocation denied")?;
    checkpoint()?;
    Ok(())
}

pub(crate) fn quote_key(k: &str) -> String {
    if is_ident(k) {
        k.to_string()
    } else {
        format!("'{}'", k)
    }
}

/// A marker argument as one line: the backslash that continued the previous line and the line breaks inside it are not part of the expression.
pub(crate) // The exact clean algorithm below holds joined/output Strings and a geometric
// Vec<&str>. Count actual whitespace runs first; unused long entries therefore
// remain linear in bytes without charging one reference per source character.
fn clean_work(s:&str,cx:&Input<'_>)->bool{
 if cx.budget.is_none(){return true}
 let mut words=0usize;let mut gap=true;
 for ch in s.chars(){let whitespace=ch=='\\'||ch.is_whitespace();if !whitespace&&gap{let Some(next)=words.checked_add(1)else{return false};words=next;}gap=whitespace;}
 s.len().checked_mul(8).and_then(|n|words.checked_mul(3*std::mem::size_of::<&str>()).and_then(|w|n.checked_add(w))).and_then(|n|n.checked_add(1024)).is_some_and(|bytes|cx.charge(bytes))
}
fn clean(s: &str) -> String {
    let joined: String = s.chars().map(|c| if c == '\\' { ' ' } else { c }).collect();
    joined.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// The `ui_act(...)` an op part is, if it is one: the window action's name (the first argument when it is text, else the op key) and its args.
pub(crate) fn ui_act_of(part:&str,key:&str)->Option<Act>{ui_act_with(part,key,0,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}
struct ActionControl<'a,'cx,E,F>{cx:&'a Input<'cx>,checkpoint:&'a mut F,_error:std::marker::PhantomData<fn()->E>}
impl<E:From<String>+for<'error>From<&'error str>,F:FnMut()->Result<(),E>>crate::key_policy_control::Control for ActionControl<'_,'_,E,F>{
 type Error=E;const CHECKED:bool=true;
 fn checkpoint(&mut self)->Result<(),E>{if let Some(budget)=&self.cx.budget{budget.require()?;}(self.checkpoint)()}
 fn reserve(&mut self,bytes:usize)->Result<(),E>{if let Some(budget)=&self.cx.budget{budget.charge(bytes)?;}Ok(())}
 fn overflow(&mut self)->E{if let Some(budget)=&self.cx.budget{budget.deny();}E::from("ui action work admission overflow")}
 fn allocation_failed(&mut self)->E{self.overflow()}
}
fn ui_act_with<C:crate::key_policy_control::Control>(part:&str,key:&str,depth:usize,c:&mut C)->Result<Option<Act>,C::Error>{
 use crate::key_policy_control as kc;
 c.checkpoint()?;
 if C::CHECKED&&depth>=128{return Err(c.overflow())}
 let Some((name,body))=call_of(part)else{return Ok(None)};
 let parts=if name=="ui_act"{split_top_with(body,c)?}else if name=="inputs"||name=="binds"{
  kc::reserve(c,||Some(512))?;
  for inner in split_top_with(body,c)?{c.checkpoint()?;if let Some(action)=ui_act_with(&inner,key,depth+1,c)?{return Ok(Some(action))}}
  return Ok(None)
 }else{return Ok(None)};
 let mut action=kc::own(c,key)?;let mut args=Vec::new();
 for(i,p)in parts.iter().enumerate(){c.checkpoint()?;let p=p.trim();if i==0&&p.starts_with('"'){action=kc::own(c,p.trim_matches('"'))?;continue}
  let Some(("arg",abody))=call_of(p)else{continue};let aparts=split_top_with(abody,c)?;let Some(first)=aparts.first()else{continue};let aname=kc::own(c,first.trim().trim_matches('"'))?;
  let mut schema=None;let mut from=None;
  for rest in aparts.iter().skip(1){c.checkpoint()?;let rest=rest.trim();if let Some(value)=rest.strip_prefix("from"){let value=value.trim_start().trim_start_matches('=').trim();from=match value.strip_prefix("nameof(").and_then(|x|x.strip_suffix(')')){Some(value)=>Some(kc::own(c,value.trim())?),None=>None};}else{schema=Some(kc::own(c,rest)?);}}
  kc::row(c,&mut args)?;args.push(Arg{name:aname,schema,from});
 }
 c.checkpoint()?;Ok(Some(Act{name:action,args}))
}

/// "name(body)" -> (name, body), when the whole text is one call.
pub(crate) fn call_of(s: &str) -> Option<(&str, &str)> {
    let s = s.trim();
    let open = s.find('(')?;
    if !s.ends_with(')') {
        return None;
    }
    let name = s[..open].trim();
    if !is_ident(name) {
        return None;
    }
    Some((name, &s[open + 1..s.len() - 1]))
}

pub(crate) fn is_ident(s: &str) -> bool {
    !s.is_empty()
        && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
        && !s.chars().next().unwrap().is_ascii_digit()
}

/// Splits at top-level commas (not inside (), [] or a string).
pub(crate) fn split_top(s:&str)->Vec<String>{split_top_with(s,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}
fn split_top_with<C:crate::key_policy_control::Control>(s:&str,c:&mut C)->Result<Vec<String>,C::Error>{
    use crate::key_policy_control as kc;
    c.checkpoint()?;kc::split(c,s.len())?;
    let mut out = Vec::new();
    let mut depth = 0i32;
    let mut in_str = false;
    let bytes: Vec<char> = s.chars().collect();
    let mut cur = String::new();
    for (i, current) in bytes.iter().enumerate() {
        c.checkpoint()?;
        match current {
            '"' if i == 0 || bytes[i - 1] != '\\' => {
                in_str = !in_str;
                cur.push(*current);
            }
            '(' | '[' if !in_str => {
                depth += 1;
                cur.push(*current);
            }
            ')' | ']' if !in_str => {
                depth -= 1;
                cur.push(*current);
            }
            ',' if !in_str && depth == 0 => {
                kc::row(c,&mut out)?;out.push(kc::own(c,cur.trim())?);
                cur.clear();
            }
            _ => cur.push(*current),
        }
    }
    let last=kc::own(c,cur.trim())?;
    if !last.is_empty() {
        kc::row(c,&mut out)?;out.push(last);
    }
    c.checkpoint()?;Ok(out)
}

/// The kind of a schema expression ("num", "int", "schema_text" -> "text", ...) and its top-level arguments.
pub(crate) fn schema_parts(expr: &str) -> (String, Vec<String>) {
    match call_of(expr) {
        Some((name, body)) => {
            let kind = match name {
                "schema_text" => "text",
                "schema_ref" => "ref",
                "schema_path" => "path",
                other => other,
            };
            (kind.to_string(), split_top(body))
        }
        None => (expr.trim().to_string(), Vec::new()),
    }
}

/// The range text of a schema, as `schema_describe()` prints it at runtime ("num 0..MAX_PUMP_PRESSURE step 1").
pub fn describe(expr: &str) -> String {
    let (kind, args) = schema_parts(expr);
    match kind.as_str() {
        "int" | "num" => {
            let mut min = String::new();
            let mut max = String::new();
            let mut step = String::new();
            let mut positional = 0;
            for a in &args {
                if let Some((n, v)) = a.split_once('=').filter(|(n, _)| is_ident(n.trim())) {
                    match n.trim() {
                        "min" => min = v.trim().to_string(),
                        "max" => max = v.trim().to_string(),
                        "step" => step = v.trim().to_string(),
                        _ => {}
                    }
                } else {
                    positional += 1;
                    match positional {
                        1 => min = a.trim().to_string(),
                        2 => max = a.trim().to_string(),
                        3 if kind == "num" => step = a.trim().to_string(),
                        _ => {}
                    }
                }
            }
            let range = if min.is_empty() && max.is_empty() {
                String::new()
            } else {
                format!(" {}..{}", min, max)
            };
            let step = if step.is_empty() {
                String::new()
            } else {
                format!(" step {}", step)
            };
            format!("{}{}{}", kind, range, step)
        }
        "text" => {
            let max = args
                .iter()
                .find(|a| !a.contains('=') && !a.trim().is_empty())
                .map(|a| a.trim().to_string());
            match max {
                Some(m) => format!("text max {}", m),
                None => "text".to_string(),
            }
        }
        _ => kind,
    }
}

/// The TypeScript type of a schema.
pub(crate) fn ts_type(expr: &str) -> String {
    let (kind, args) = schema_parts(expr);
    match kind.as_str() {
        "bool" => "boolean".into(),
        "int" | "num" | "flags" => "number".into(),
        "text" | "path" | "ref" => "string".into(),
        "enum" => {
            // enum(list("a", "b")): a union of the literals; anything else is a string.
            let lits: Vec<String> = args
                .first()
                .and_then(|a| call_of(a))
                .filter(|(n, _)| *n == "list")
                .map(|(_, body)| {
                    split_top(body)
                        .into_iter()
                        .filter(|x| x.trim().starts_with('"'))
                        .map(|x| format!("'{}'", x.trim().trim_matches('"')))
                        .collect()
                })
                .unwrap_or_default();
            if lits.is_empty() {
                "string".into()
            } else {
                lits.join(" | ")
            }
        }
        "list_of" => match args.first() {
            Some(inner) => format!("{}[]", paren_union(&ts_type(inner))),
            None => "unknown[]".into(),
        },
        "map_of" => match (args.first(), args.get(1)) {
            (Some(_), Some(v)) => format!("Record<string, {}>", ts_type(v)),
            _ => "Record<string, unknown>".into(),
        },
        "row" => "Record<string, unknown>".into(),
        _ => "unknown".into(),
    }
}

pub(crate) fn paren_union(t: &str) -> String {
    if t.contains(" | ") {
        format!("({})", t)
    } else {
        t.to_string()
    }
}

fn schema_work(expr: &str, cx: &Input<'_>) -> std::fmt::Result {
    if cx.budget.is_none() {
        return Ok(());
    }
    let mut depth = 0usize;
    let mut peak = 0usize;
    for c in expr.chars() {
        match c {
            '(' | '[' | '{' => {
                depth = depth.checked_add(1).ok_or(std::fmt::Error)?;
                peak = peak.max(depth)
            }
            ')' | ']' | '}' => depth = depth.saturating_sub(1),
            _ => {}
        }
    }
    if peak > 128 {
        cx.budget.as_ref().unwrap().deny();
        return Err(std::fmt::Error);
    }
    let bytes = expr
        .len()
        .checked_add(1)
        .and_then(|n| n.checked_mul(peak + 1))
        .and_then(|n| n.checked_mul(64))
        .and_then(|n| n.checked_add(4096))
        .ok_or(std::fmt::Error)?;
    if !cx.charge(bytes) {
        return Err(std::fmt::Error);
    }
    Ok(())
}

// A single original schema can feed MANY independently retained action arguments.
// Admit each actual retained clone before allocation, not merely its source once.
fn clone_schema(cx: &Input<'_>, schema: &str) -> Option<String> {
    if !cx.charge(schema.len().saturating_mul(2).saturating_add(64)) {
        return None;
    }
    Some(schema.to_owned())
}

#[cfg(test)]
mod captured_tests {
    use super::*;
    #[test]
    fn schema_clone_and_recursive_work_are_admitted_before_materialization() {
        let budget = Budget::new(128).unwrap();
        let cx = Input {
            markers: &[],
            budget: Some(budget.clone()),
            poll: None,
        };
        assert!(clone_schema(&cx, &"x".repeat(4096)).is_none());
        assert!(budget.denied());
        let fresh = Budget::new(1024 * 1024).unwrap();
        let cx = Input {
            markers: &[],
            budget: Some(fresh.clone()),
            poll: None,
        };
        let deep = format!("{}bool(){}", "list_of(".repeat(129), ")".repeat(129));
        assert!(schema_work(&deep, &cx).is_err());
        assert!(fresh.denied());
    }
    #[test]
    fn bundle_fanout_refuses_without_silent_empty_file_success() {
        let budget = Budget::new(128).unwrap();
        let args = vec![
            "/datum/x".into(),
            "interface(\"X\")".into(),
            "ui_shape(value=bool())".into(),
        ];
        let rows = [Marker {
            name: "CAPABILITIES",
            rel: "code/x.dm",
            line: 1,
            body: "",
            args: &args,
            body_offset: 0,
            line_starts: &[0],
        }];
        let cx = Input {
            markers: &rows,
            budget: Some(budget.clone()),
            poll: None,
        };
        assert!(generate(&cx).is_err());
        assert!(budget.denied());
    }
    #[test]
    fn bounded_writer_denies_actual_header_chunk_without_allocating() {
        use std::fmt::Write;
        let budget = Budget::new(64).unwrap();
        let mut text = BudgetedText::new(&budget);
        assert!(text
            .write_str("// GENERATED by tools/analyze: a header longer than the remaining headroom")
            .is_err());
        assert!(text.finish().is_err());
    }
}

#[cfg(test)]#[path="ui_types_policy_frozen_original.rs"]mod frozen_original;
#[cfg(test)]mod typed_policy_tests{
 use super::*;use super::frozen_original as original;
 #[derive(Debug)]enum Failure{Source(String),Operational(std::io::Error)}impl From<String>for Failure{fn from(message:String)->Self{Self::Source(message)}}impl<'a>From<&'a str>for Failure{fn from(message:&str)->Self{Self::Source(message.to_owned())}}
 fn fixture()->Vec<(&'static str,Vec<String>)>{vec![
 ("TRACKED_SCHEMA",vec!["/datum/probe","charge","integer(min = 0)"]),
 ("SCHEMA",vec!["/datum/probe","charge","number(min = 0, max = 100)"]),
 (crate::raw_entry_proc_policy::ENTRY_PROC,vec!["buttons","op(\"set\", ui_act(\"set\", arg(\"value\", from = nameof(charge))))"]),
 ("CAPABILITIES",vec!["/datum/probe","interface(\"Probe\")","ui_shape(charge, missing, mode = one_of(\"a\", \"b\"))","buttons()"]),
 ("CAPABILITIES",vec!["/datum/other","interface(\"Probe\")","ui_shape(other = bool())"]),
 ("CAPABILITIES",vec!["/datum/forward","interface(\"Forward\", forwards = src)"]),
 ("CAPABILITIES",vec!["/datum/empty","interface(\"Empty\")"]),
 ("CAPABILITIES",vec!["/datum/probe","interface(\"Probe\")","op(\"extra\", ui_act(\"extra\"))"])
 ].into_iter().map(|(name,args)|(name,args.into_iter().map(str::to_owned).collect())).collect()}
 fn views<'a>(rows:&'a [(&'static str,Vec<String>)])->Vec<Marker<'a>>{rows.iter().enumerate().map(|(at,(name,args))|Marker{name,rel:"code/ui.dm",line:at as u32+1,body:"",args,body_offset:0,line_starts:&[0]}).collect()}
 #[test]fn whole_original_ui_output_preserves_long_action_keys_and_nested_inputs(){
  let mut rows=fixture();let key="long_".repeat(800);let nested=format!("{}ui_act(){}","inputs(".repeat(16),")".repeat(16));rows.push(("CAPABILITIES",vec!["/datum/long".into(),"interface(\"Long\")".into(),format!("op(\"{key}\", {nested})")]));let markers=views(&rows);let expected=original::generate(&original::Input{markers:&markers,budget:None,poll:None}).unwrap();let current=generate_with(&Input{markers:&markers,budget:Some(Budget::new(32*1024*1024).unwrap()),poll:None},&mut||Ok::<(),Failure>(())).unwrap();assert_eq!(current.files,expected.files);assert_eq!(current.diags,expected.diags);assert!(current.files.iter().any(|(_,text)|text.contains(&key)),"full original comparison must contain the long action rather than silently skipping it");
 }
 #[test]fn typed_ui_policy_preserves_all_original_files_and_ordered_diagnostics(){let rows=fixture();let markers=views(&rows);let expected=original::generate(&original::Input{markers:&markers,budget:None,poll:None}).unwrap();let legacy=generate(&Input{markers:&markers,budget:None,poll:None}).unwrap();assert_eq!(legacy.files,expected.files);assert_eq!(legacy.diags,expected.diags);let budget=Budget::new(16*1024*1024).unwrap();let mut polls=0usize;let current=generate_with(&Input{markers:&markers,budget:Some(budget),poll:None},&mut||{polls+=1;Ok::<(),Failure>(())}).unwrap();assert_eq!(current.files,expected.files);assert_eq!(current.diags,expected.diags);assert!(polls>10);assert!(!current.diags.is_empty());assert_eq!(current.files.len(),1);}
 #[test]fn typed_ui_operational_checkpoint_never_uses_string_latch_and_retry_preserves_output(){let rows=fixture();let markers=views(&rows);let mut polls=0usize;let expected=generate_with(&Input{markers:&markers,budget:Some(Budget::new(16*1024*1024).unwrap()),poll:None},&mut||{polls+=1;Ok::<(),Failure>(())}).unwrap();let fail_at=polls.saturating_sub(2).max(1);let mut seen=0;let error=generate_with(&Input{markers:&markers,budget:Some(Budget::new(16*1024*1024).unwrap()),poll:None},&mut||{seen+=1;if seen==fail_at{Err(Failure::Operational(std::io::Error::from_raw_os_error(1450)))}else{Ok(())}}).err().unwrap();assert!(matches!(error,Failure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));assert_eq!(seen,fail_at);let retry=generate_with(&Input{markers:&markers,budget:Some(Budget::new(16*1024*1024).unwrap()),poll:None},&mut||Ok::<(),Failure>(())).unwrap();assert_eq!(retry.files,expected.files);assert_eq!(retry.diags,expected.diags);}
 #[test]fn typed_ui_unused_capability_padding_is_linear_work_instead_of_global_512_multiplier(){let padded=format!("unrelated({})","x".repeat(100_000));let rows=vec![("CAPABILITIES",vec!["/datum/padded".to_owned(),padded])];let markers=views(&rows);let expected=original::generate(&original::Input{markers:&markers,budget:None,poll:None}).unwrap();let budget=Budget::new(3*1024*1024).unwrap();let current=generate_with(&Input{markers:&markers,budget:Some(budget.clone()),poll:None},&mut||Ok::<(),Failure>(())).unwrap();assert_eq!(current.files,expected.files);assert_eq!(current.diags,expected.diags);assert!(budget.used()<2*1024*1024);assert!(!budget.denied());}
 struct Admitted<'a>{budget:&'a std::sync::Arc<Budget>,polls:usize,fail_at:usize}
 impl crate::key_policy_control::Control for Admitted<'_>{type Error=std::io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;if self.polls==self.fail_at{return Err(std::io::Error::from_raw_os_error(1450))}self.budget.require().map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))}fn reserve(&mut self,bytes:usize)->Result<(),Self::Error>{self.budget.charge(bytes).map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))}fn overflow(&mut self)->Self::Error{self.budget.deny();std::io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->Self::Error{self.overflow()}}
 #[test]fn admitted_ui_split_keeps_exact_original_quote_depth_empty_and_unicode_quirks(){let budget=Budget::new(4*1024*1024).unwrap();for text in ["a, [b,c], \"d,e\", {f,g}, trailing,",",,last",",","",r#"odd(\"quoted\\\"comma,x\"), λ"#]{let expected=original::split_top(text);let mut c=Admitted{budget:&budget,polls:0,fail_at:usize::MAX};assert_eq!(split_top_with(text,&mut c).unwrap(),expected);}}
 #[test]fn actual_repeated_ui_action_key_clones_are_funded_before_each_materialization(){use crate::key_policy_control as kc;let key="k".repeat(4096);let budget=Budget::new(1024*1024).unwrap();let mut c=Admitted{budget:&budget,polls:0,fail_at:usize::MAX};let mut kept=Vec::new();let result=(||{for _ in 0..600{let action=ui_act_with("ui_act()",&key,0,&mut c)?.unwrap();kc::row(&mut c,&mut kept)?;kept.push(action);}Ok::<(),std::io::Error>(())})();assert_eq!(result.unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);assert!(budget.denied());assert!(kept.len()<600);assert!(kept.iter().all(|action|action.name==key));let root=Budget::new(16*1024*1024).unwrap();let mut healthy=Admitted{budget:&root,polls:0,fail_at:usize::MAX};let action=ui_act_with("ui_act()",&key,0,&mut healthy).unwrap().unwrap();assert_eq!(action.name,key);}
 #[test]fn nested_ui_inputs_use_control_before_split_and_descent_then_retry_same_policy(){let nested=format!("{}ui_act(){}","inputs(".repeat(129),")".repeat(129));let budget=Budget::new(32*1024*1024).unwrap();let mut c=Admitted{budget:&budget,polls:0,fail_at:usize::MAX};assert_eq!(ui_act_with(&nested,"deep",0,&mut c).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert!(budget.denied());let nested=format!("{}ui_act(){}","binds(".repeat(16),")".repeat(16));let root=Budget::new(8*1024*1024).unwrap();let mut c=Admitted{budget:&root,polls:0,fail_at:5};assert_eq!(ui_act_with(&nested,"deep",0,&mut c).err().unwrap().raw_os_error(),Some(1450));assert_eq!(c.polls,5);assert!(!root.denied());let mut c=Admitted{budget:&root,polls:0,fail_at:usize::MAX};let actual=ui_act_with(&nested,"deep",0,&mut c).unwrap().unwrap();assert_eq!(actual.name,"deep");assert_eq!(actual.args.len(),0);}

 #[test]fn admitted_ui_clean_counts_actual_whitespace_reference_rows_before_old_projection(){let text="x ".repeat(20000);let tiny=Budget::new(4096).unwrap();let cx=Input{markers:&[],budget:Some(tiny.clone()),poll:None};assert!(!clean_work(&text,&cx));assert!(tiny.denied());let root=Budget::new(4*1024*1024).unwrap();let cx=Input{markers:&[],budget:Some(root),poll:None};assert!(clean_work(&text,&cx));assert_eq!(clean(&text),text.split_whitespace().collect::<Vec<_>>().join(" "));}

}
