//! What `own_set` -> `rel_set` and `own_add` -> `rel_add` share: the var has to be declared before the new write verb can dispatch on it.
//!
//! `rel_set` / `rel_add` read the declared kind of the var (`rel_kind`, code/engine/declare/relations.dm): an `owns_one` / `owns_many`
//! var goes through `own_set` / `own_add`, a list var through the list state, an undeclared one becomes a plain view. The old verbs
//! learned an undeclared var as owned on first use, so a bare rename would turn an owned var into a view. Each converted site
//! therefore needs its var declared owned, and the codemod emits the declaration:
//!
//! * the var is already declared (a legacy `OWN`/`ownership()` entry, a `CAPABILITIES` relation entry on the type or an ancestor): the
//!   call is only renamed;
//! * otherwise `owns_one(nameof(var), /declared/type)` (one value) or `owns_many(nameof(var), /element/type)` (a list) is added to
//!   the `CAPABILITIES(T)` block of the type that DECLARES the var, not a subtype; the block is made, after the type's var block, when
//!   the type has none;
//! * a var it cannot type confidently (untyped, a value type, an unresolved receiver, a list written with `own_set`, a scalar written
//!   with `own_add`) keeps its `own_*` call as residue.
//!
//! The declared type is the var's own type, so `own_type_ok()` accepts what the code already stores.

use std::any::Any;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::Path;
use std::sync::Arc;

use super::helpers::rename_exact;
use super::{Ctx, Edit, KeyUse, Need, Outcome, Rewrite};
use crate::dm::ownership_index::{parents, proc_scopes, Index, ACCESSOR};
use crate::declaration_markers::Decls;
use crate::codemod_facts::FactSource;
use crate::tree::{Tree, CODE_DM};

/// One accessor call on a line: which verb, which var, and the static type of its receiver ("" when unknown).
struct Ev {
    func: String,
    var: String,
    rtype: String,
}

pub struct Prep {
    idx: IndexOwner,
    decls: DeclarationOwner,
    events: HashMap<(String, u32), Vec<Ev>>,
    /// Names of list vars something assigns a whole list to with `own_set`: `own_type_ok()` would refuse that list under an element
    /// type, so such a var is declared `owns_many` without one.
    list_set_vars: HashSet<String>,
}

impl Prep {
    pub fn build(tree: &Tree) -> Prep {
        let files = tree.select(&CODE_DM);
        let idx = Index::get(tree, &files);
        let decls = Decls::get(tree);
        let mut events: HashMap<(String, u32), Vec<Ev>> = HashMap::new();
        for f in &files {
            let raw = f.raw();
            let rel = f.rel.clone();
            proc_scopes(f.code(), |no, _line, owner, _proc, local_types| {
                let rl = raw.line(no);
                for m in ACCESSOR.captures_iter(rl) {
                    let (func, recv, name) = (m.s(1), m.s(2), m.s(3));
                    let mut rtype: Option<String> = if recv == "src" { Some(owner.to_string()) } else { local_types.get(recv).and_then(|t| t.clone()) };
                    if rtype.is_none() && recv != "src" {
                        rtype = idx.member(owner, recv).map(|g| g.vtype);
                    }
                    events.entry((rel.clone(), no as u32)).or_default().push(Ev { func: func.to_string(), var: name.to_string(), rtype: rtype.unwrap_or_default() });
                }
            });
        }
        let mut list_set_vars: HashSet<String> = HashSet::new();
        for evs in events.values() {
            for e in evs {
                if e.func == "own_set" && !e.rtype.is_empty() && idx.member(&e.rtype, &e.var).map(|m| m.is_list).unwrap_or(false) {
                    list_set_vars.insert(e.var.clone());
                }
            }
        }
        Prep { idx:IndexOwner::Legacy(idx), decls:DeclarationOwner::Legacy(decls), events, list_set_vars }
    }
}

pub fn prepare(tree: &Tree) -> Arc<dyn Any + Send + Sync> {
    Arc::new(Prep::build(tree))
}

/// The var an accessor call names (`nameof(x)`, `nameof(src.x)`, `nameof(/type::x)` or `"x"`) and, for the last form, the type it names.
fn var_name(arg: &str) -> Option<(String, Option<String>)> {
    let a = arg.trim();
    if let Some(s) = a.strip_prefix('"').and_then(|s| s.strip_suffix('"')) {
        return Some((s.to_string(), None));
    }
    let inner = a.strip_prefix("nameof(")?.strip_suffix(')')?.trim();
    let name = inner.rsplit(['.', ':']).next()?.trim();
    if name.is_empty() || !name.chars().all(|c| c.is_alphanumeric() || c == '_') {
        return None;
    }
    let ty = inner.strip_prefix('/').and_then(|r| r.split_once("::")).map(|(t, _)| format!("/{}", t.trim()));
    Some((name.to_string(), ty))
}

/// Splits a declared type path into (is_list, element or value type).
fn split_type(declared: &str) -> (bool, String) {
    match declared.strip_prefix("/list") {
        Some("") => (true, String::new()),
        Some(rest) if rest.starts_with('/') => (true, rest.to_string()),
        _ => (false, declared.to_string()),
    }
}

/// The rewrite of one `own_set` (`many = false`) or `own_add` (`many = true`) call.
pub fn rewrite(cx:&Ctx,new:&str,many:bool)->Outcome{match rewrite_using(cx,new,many){Ok(actual)=>actual,Err(first)=>Outcome::Operational(first)}}
fn rewrite_using(cx:&Ctx,new:&str,many:bool)->std::io::Result<Outcome>{
 let renamed=rename_exact(cx,new,3);
 let Outcome::Rewrite(Rewrite{edits,keys,..})=renamed else{return Ok(renamed)};
 let Some(prep)=cx.prep.downcast_ref::<Prep>()else{return Ok(renamed_without_prep(edits,keys))};
 let Some((var,named_type))=var_name_using(cx.arg_text(1),cx.work)?else{return Ok(Outcome::Residue("dynamic_var",cx.own_using("the var is not nameof(x) or a literal")?))};
 let src_holder=cx.arg_text(0).trim()=="src"&&cx.owner!="/";
 let rtype=if let Some(ty)=named_type{ty}else if src_holder{cx.own_using(cx.owner)?}else{
  let event=prep.events.iter().find(|((relative,line),_)|relative==cx.rel&&*line==cx.line).and_then(|(_,rows)|rows.iter().find(|event|event.func==cx.callee&&event.var==var));
  match event{Some(event)=>cx.own_using(&event.rtype)?,None=>String::new()}
 };
 if rtype.is_empty(){return Ok(Outcome::Residue("unresolved_receiver",cx.own_using("the static type of the holder is unknown: declare the var by hand")?))}
 let Some(owner)=cx.sem.var_owner(&rtype,&var)?else{return Ok(Outcome::Residue("unknown_var",cx.format_using(format_args!("{} has no var {}",rtype,var))?))};
 let declared=if let Some(work)=cx.work{
  let mut control=super::work::Operation(work);
  let mut declared=prep.idx.decl_using(&rtype,&var,&mut control)?.is_some();
  if !declared{crate::raw_ownership_policy::visit_parents_until_using(&rtype,&mut control,&mut|parent,_|{if prep.decls.is_relation(parent,&var){declared=true;Ok(false)}else{Ok(true)}})?;}
  declared||prep.decls.is_relation(&owner,&var)
 }else{prep.idx.decl(&rtype,&var).is_some()||parents(&rtype).iter().any(|parent|prep.decls.is_relation(parent,&var))||prep.decls.is_relation(&owner,&var)};
 if declared{return Ok(Outcome::Rewrite(Rewrite{edits,keys,..Default::default()}))}
 let Some(signature)=cx.sem.var_decl(&owner,&var)?else{return Ok(Outcome::Residue("unknown_var",cx.format_using(format_args!("{} has no declared var {}",owner,var))?))};
 if crate::scopes::is_defines(&signature.file)||signature.file.starts_with("code/world/tgs/"){return Ok(Outcome::Residue("untyped_var",cx.format_using(format_args!("{} is declared in {}, which takes no declarations",var,signature.file))?))}
 let(is_list,value)=match signature.declared.strip_prefix("/list"){Some("")=>(true,""),Some(rest)if rest.starts_with('/')=>(true,rest),_=>(false,signature.declared.as_str())};
 if many&&!is_list{return Ok(Outcome::Residue("scalar_var",cx.own_using("own_add on a var that is not a list")?))}
 if !many&&is_list{return Ok(Outcome::Residue("list_var",cx.own_using("own_set on a list var: rel_set goes through the list state; convert by hand")?))}
 if value.is_empty()&&!many{return Ok(Outcome::Residue("untyped_var",cx.own_using("the var has no declared type, so owns_one() has none to say")?))}
 let entity=if let Some(work)=cx.work{prep.idx.is_entity_using(value,&mut super::work::Operation(work))?}else{prep.idx.is_entity(value)};
 if !value.is_empty()&&!entity{return Ok(Outcome::Residue("untyped_var",cx.format_using(format_args!("{} is not an entity type: nothing to own",value))?))}
 let vtype=if many&&prep.list_set_vars.contains(&var){String::new()}else{cx.own_using(value)?};
 let origin=cx.origin_using()?;let needs=cx.singleton_using(Need{holder:owner,var,many,vtype,origin})?;
 Ok(Outcome::Rewrite(Rewrite{edits,keys,needs,..Default::default()}))
}
fn var_name_using(arg:&str,work:Option<&dyn crate::policy_finish::admitted::Work>)->std::io::Result<Option<(String,Option<String>)>>{
 let argument=arg.trim();
 if let Some(name)=argument.strip_prefix('"').and_then(|value|value.strip_suffix('"')){return Ok(Some((super::work::own(work,name)?,None)))}
 let Some(inner)=argument.strip_prefix("nameof(").and_then(|value|value.strip_suffix(')'))else{return Ok(None)};let inner=inner.trim();
 let name=inner.rsplit(['.',':']).next().unwrap_or("").trim();if name.is_empty()||!name.chars().all(|ch|ch.is_alphanumeric()||ch=='_'){return Ok(None)}
 let ty=inner.strip_prefix('/').and_then(|rest|rest.split_once("::")).map(|(ty,_)|super::work::format(work,format_args!("/{}",ty.trim()))).transpose()?;
 Ok(Some((super::work::own(work,name)?,ty)))
}

fn renamed_without_prep(edits: Vec<Edit>, keys: Vec<KeyUse>) -> Outcome {
    Outcome::Rewrite(Rewrite { edits, keys, ..Default::default() })
}

/// The newline a file uses.
fn nl_of(text: &str) -> &'static str {
    if text.contains("\r\n") {
        "\r\n"
    } else {
        "\n"
    }
}

fn entry_line(n: &Need) -> String {
    let verb = if n.many { "owns_many" } else { "owns_one" };
    if n.vtype.is_empty() {
        format!("{}(nameof({}))", verb, n.var)
    } else {
        format!("{}(nameof({}), {})", verb, n.var, n.vtype)
    }
}

/// The edits that declare `needs`: into each holder's existing `CAPABILITIES` block, else a new block after the type's var block.
pub fn declaration_edits(root:&Path,tree:&Tree,sem:&dyn FactSource,prep:&(dyn Any+Send+Sync),physical:&dyn super::PhysicalFiles,needs:&[Need])->std::io::Result<Vec<(String,Vec<Edit>)>>{declaration_edits_using(root,sem,prep,physical,needs,None)}
pub(crate) fn declaration_edits_using(_root:&Path,sem:&dyn FactSource,prep:&(dyn Any+Send+Sync),physical:&dyn super::PhysicalFiles,needs:&[Need],work:Option<&dyn crate::policy_finish::admitted::Work>)->std::io::Result<Vec<(String,Vec<Edit>)>>{
    let Some(prep) = prep.downcast_ref::<Prep>() else { return Ok(Vec::new()) };
    let mut by_holder:Vec<(&str,Vec<&Need>)>=Vec::new();
    for n in needs {
        if let Some(rows)=super::work::map_get_mut(&mut by_holder,n.holder.as_str()){super::work::row(work,rows)?;rows.push(n);}else{let mut rows=Vec::new();super::work::row(work,&mut rows)?;rows.push(n);super::work::map_insert(work,&mut by_holder,n.holder.as_str(),rows)?;}
    }
    let mut out:Vec<(String,Vec<Edit>)>=Vec::new();
    for (holder, ns) in by_holder {
        let existing = prep.decls.markers().iter().find(|m| m.name == "CAPABILITIES" && m.part.is_none() && m.args.first().map(|a| a == holder).unwrap_or(false));
        let (rel, offset, newline, prefix): (String, usize, &str, String) = if let Some(m) = existing {
            let Some(text) = super::physical_text_using(physical,&m.rel,work)? else { continue };
            let nl = nl_of(&text);
            // The end of the block: the end of its last entry line, or the header's closing parenthesis when it has no entries.
            let body_end = m.body_offset + m.body.len();
            let end = if m.args.len() >= 2 { body_end } else { body_end + 1 };
            // The marker's offsets are in the file with LF line ends; a CRLF file has one more byte per line before it.
            let end = if nl == "\r\n" {
                end+lf_newlines_before(&text,end)
            } else {
                end
            };
            (super::work::own(work,&m.rel)?,end,nl,String::new())
        } else {
            let Some(sig) = sem.var_decl(holder, &ns[0].var)? else { continue };
            let Some(text) = super::physical_text_using(physical,&sig.file,work)? else { continue };
            let nl = nl_of(&text);
            // After the type's block: the declaration line, and every indented or blank line that follows it up to the next top-level line.
            let mut lines=Vec::new();for line in text.split('\n'){super::work::row(work,&mut lines)?;lines.push(line);}
            let mut starts=super::work::vec_capacity(work,lines.len())?;
            let mut at = 0usize;
            for l in &lines {
                starts.push(at);
                at += l.len() + 1;
            }
            let decl_idx = (sig.line as usize).saturating_sub(1).min(lines.len().saturating_sub(1));
            let mut last = decl_idx;
            if lines[decl_idx].starts_with(|c: char| c.is_whitespace()) {
                let mut j = decl_idx + 1;
                while j < lines.len() {
                    let l = lines[j].trim_end_matches('\r');
                    // A block comment at column 0 (`/* ... */`) does not end the type's block either.
                    if l.starts_with("/*") {
                        while j < lines.len() && !lines[j].contains("*/") {
                            j += 1;
                        }
                        j += 1;
                        continue;
                    }
                    // A blank line, a comment or a preprocessor line at column 0 does not end the type's block: more vars may follow it.
                    if l.trim().is_empty() || l.starts_with("//") || l.starts_with('#') {
                        j += 1;
                        continue;
                    }
                    if !l.starts_with(|c: char| c.is_whitespace()) {
                        break;
                    }
                    last = j;
                    j += 1;
                }
            }
            let end = starts[last] + lines[last].trim_end_matches('\r').len();
            (super::work::own(work,&sig.file)?,end,nl,super::work::format(work,format_args!("{nl}{nl}CAPABILITIES({holder})"))?)
        };
        let mut text = prefix;
        for n in ns {
            super::work::push_str(work,&mut text,newline)?;
            super::work::push_str(work,&mut text,"\t")?;
            let verb=if n.many{"owns_many"}else{"owns_one"};
            let entry=if n.vtype.is_empty(){super::work::format(work,format_args!("{}(nameof({}))",verb,n.var))?}else{super::work::format(work,format_args!("{}(nameof({}), {})",verb,n.var,n.vtype))?};
            super::work::push_str(work,&mut text,&entry)?;
        }
        let edit=Edit::insert(offset,text);
        if let Some(rows)=super::work::map_get_mut(&mut out,rel.as_str()){super::work::row(work,rows)?;rows.push(edit);}else{let mut rows=Vec::new();super::work::row(work,&mut rows)?;rows.push(edit);super::work::map_insert(work,&mut out,rel,rows)?;}
    }
    Ok(out)
}
fn lf_newlines_before(text:&str,limit:usize)->usize{
 let bytes=text.as_bytes();let(mut at,mut logical,mut newlines)=(0usize,0usize,0usize);
 while at<bytes.len()&&logical<limit{if bytes[at]==b'\r'&&bytes.get(at+1)==Some(&b'\n'){at+=1;}if bytes[at]==b'\n'{newlines+=1;}logical+=1;at+=1;}newlines
}

#[cfg(feature="native-policy")]
enum IndexOwner{Legacy(Arc<Index>),Native(crate::captured_codemod_index::CapturedIndex)}
#[cfg(not(feature="native-policy"))]
enum IndexOwner{Legacy(Arc<Index>)}
impl std::ops::Deref for IndexOwner{type Target=Index;fn deref(&self)->&Index{match self{Self::Legacy(value)=>value,#[cfg(feature="native-policy")]Self::Native(value)=>value.actual()}}}
enum DeclarationOwner{Legacy(Arc<Decls>),#[cfg(feature="native-policy")]Native{markers:Vec<crate::declaration_markers::Marker>,relations:Vec<(String,String)>}}
impl DeclarationOwner{
 fn is_relation(&self,owner:&str,name:&str)->bool{match self{Self::Legacy(value)=>value.is_relation(owner,name),#[cfg(feature="native-policy")]Self::Native{relations,..}=>relations.binary_search_by(|(ty,var)|(ty.as_str(),var.as_str()).cmp(&(owner,name))).is_ok()}}
 fn markers(&self)->&[crate::declaration_markers::Marker]{match self{Self::Legacy(value)=>&value.markers,#[cfg(feature="native-policy")]Self::Native{markers,..}=>markers}}
}
#[cfg(feature="native-policy")]
pub(crate) fn prepare_native(lexical:&dyn super::LexicalFiles,manifest:Option<&str>,phase:&mut crate::captured_codemod_work::Phase<'_>,budget:&Arc<crate::captured_generator_budget::Budget>,source_work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,patterns:&dyn crate::native_pattern::Provider)->std::io::Result<Prep>{
 use crate::{key_policy_control as kc,key_policy_control::Control,policy_finish::admitted::Work};
 let failure=|error:crate::captured_reactive_reads::Failure|match error{crate::captured_reactive_reads::Failure::Operational(first)=>first,crate::captured_reactive_reads::Failure::Unsupported(message)=>std::io::Error::new(std::io::ErrorKind::Unsupported,message)};
 Work::checkpoint(phase)?;
 let mut index=crate::captured_codemod_index::Builder::new(source_work,patterns).map_err(failure)?;
 lexical.for_each(&mut|file|{if CODE_DM.matches(file){index.file(file).map_err(failure)?;}Ok(())})?;
 let idx=index.finish().map_err(failure)?;
 // The SAME original marker producer emits only the CAPABILITIES family;
 // entry-proc/runtime markers cannot contribute ownership declarations.
 let retained=crate::captured_generator_budget::Budget::scoped_temporaries(budget).map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))?;
 let temporary=crate::captured_generator_budget::Budget::scoped_temporaries(budget).map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))?;
 let mut raw=Vec::new();let mut count=0usize;
 lexical.for_each(&mut|file|{
  if !CODE_DM.matches(file){return Ok(())}
  Work::checkpoint(phase)?;let marker=file.marker();if let Some(error)=file.captured_budget_error(){return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,error))}
  let mut checkpoint=||Work::checkpoint(phase).map_err(crate::captured_reactive_reads::Failure::Operational);
  crate::captured_marker_rows::collect_file_funded(&file.rel,marker,&retained,&temporary,&["CAPABILITIES","CAPABILITIES_PART"],false,false,false,&mut raw,&mut count,&mut checkpoint).map_err(|actual|match actual{crate::captured_reactive_reads::Failure::Operational(first)=>first,other=>match budget.require(){Err(first)=>std::io::Error::new(std::io::ErrorKind::OutOfMemory,first),Ok(())=>failure(other)}})?;
  Ok(())
 })?;
 let mut markers=Vec::new();let mut last_lines=None;
 for marker in raw{
  let fixed=marker.name.capacity().checked_add(marker.rel.capacity()).and_then(|n|n.checked_add(marker.body.capacity())).and_then(|n|n.checked_add(marker.part.as_ref().map_or(0,String::capacity))).and_then(|n|n.checked_add(marker.args.capacity().checked_mul(std::mem::size_of::<String>())?)).ok_or(std::io::ErrorKind::OutOfMemory)?;
  let bytes=marker.args.iter().try_fold(fixed,|sum,arg|sum.checked_add(arg.capacity())).ok_or(std::io::ErrorKind::OutOfMemory)?;
  Work::reserve(phase,bytes)?;
  let address=Arc::as_ptr(&marker.line_starts)as usize;
  if last_lines!=Some(address){Work::reserve(phase,marker.line_starts.capacity().checked_mul(std::mem::size_of::<u32>()).and_then(|n|n.checked_add(std::mem::size_of::<Vec<u32>>()+2*std::mem::size_of::<usize>())).ok_or(std::io::ErrorKind::OutOfMemory)?)?;last_lines=Some(address);}
  super::work::row(Some(&*phase),&mut markers)?;
  markers.push(crate::declaration_markers::Marker{name:marker.name,part:marker.part,rel:marker.rel,line:marker.line,body:marker.body,args:marker.args,body_offset:marker.body_offset,line_starts:marker.line_starts});
 }
 drop(temporary);drop(retained);
 // Exact old manifest include order, with duplicate paths taking the first
 // ordinal. This table carries DATA only, no path-read authority.
 let mut order:Vec<(String,usize)>=Vec::new();
 for line in manifest.unwrap_or("").lines(){
  Work::checkpoint(phase)?;let Some(rest)=line.trim().strip_prefix("#include")else{continue};let Some(path)=rest.trim().strip_prefix('"').and_then(|rest|rest.split('"').next())else{continue};
  let mut relative=super::work::string_capacity(Some(&*phase),path.len())?;for ch in path.chars(){relative.push(if ch=='\\'{'/'}else{ch});}
  if order.binary_search_by(|(old,_)|old.cmp(&relative)).is_err(){let ordinal=order.len();super::work::map_insert(Some(&*phase),&mut order,relative,ordinal)?;}
 }
 let ordinal=|relative:&str|order.binary_search_by(|(old,_)|old.as_str().cmp(relative)).ok().map_or(usize::MAX,|at|order[at].1);
 super::work::stable_sort_by(Some(&*phase),&mut markers,|a,b|(ordinal(&a.rel),a.rel.as_str(),a.line).cmp(&(ordinal(&b.rel),b.rel.as_str(),b.line)))?;
 let mut relations=Vec::new();
 for marker in &markers{
  if let Some(owner)=marker.args.first(){
   for found in kc::captures_all_static(phase,r"\b(?:owns_one|owns_many|ref_one|ref_many|hud_element|profile)\(\s*nameof\((\w+)\)",&marker.body,||crate::pat!(r"\b(?:owns_one|owns_many|ref_one|ref_many|hud_element|profile)\(\s*nameof\((\w+)\)"))?{
    let row=(super::work::own(Some(&*phase),owner)?,super::work::own(Some(&*phase),found.s(1))?);super::work::set_insert(Some(&*phase),&mut relations,row)?;
   }
  }
  for found in kc::captures_all_static(phase,r"\blinks?\(\s*(/[\w/]+)::(\w+)\s*,\s*(/[\w/]+)::(\w+)",&marker.body,||crate::pat!(r"\blinks?\(\s*(/[\w/]+)::(\w+)\s*,\s*(/[\w/]+)::(\w+)"))?{
   for(a,b)in[(1,2),(3,4)]{let row=(super::work::own(Some(&*phase),found.s(a))?,super::work::own(Some(&*phase),found.s(b))?);super::work::set_insert(Some(&*phase),&mut relations,row)?;}
  }
 }
 let mut events:HashMap<(String,u32),Vec<Ev>>=HashMap::new();
 let mut scratch=crate::captured_codemod_work::Phase::new(source_work,budget,patterns)?;
 lexical.for_each(&mut|file|{
  if !CODE_DM.matches(file){return Ok(())}
  let raw=file.raw();let code=file.code();if let Some(error)=file.captured_budget_error(){return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,error))}
  crate::dm::ownership_index::proc_scopes_using(code,&mut scratch,&mut|line,_text,owner,_procedure,locals,scratch|{
   for found in kc::captures_all_static(scratch,crate::raw_ownership_policy::ACCESSOR_SOURCE,raw.line(line),||&ACCESSOR)?{
    let(func,receiver,name)=(found.s(1),found.s(2),found.s(3));
    let mut rtype=if receiver=="src"{Some(super::work::own(Some(&*phase),owner)?)}else{locals.get(receiver).and_then(|ty|ty.as_deref()).map(|ty|super::work::own(Some(&*phase),ty)).transpose()?};
    if rtype.is_none()&&receiver!="src"{rtype=idx.actual().member_using(owner,receiver,scratch)?.map(|row|row.vtype);if let Some(value)=&rtype{Work::reserve(phase,value.capacity())?;}}
    let key=(super::work::own(Some(&*phase),&file.rel)?,u32::try_from(line).map_err(|_|std::io::ErrorKind::InvalidData)?);
    if !events.contains_key(&key){kc::hash_room(phase,&mut events)?;let retained_key=(super::work::own(Some(&*phase),&key.0)?,key.1);events.insert(retained_key,Vec::new());}
    let rows=events.get_mut(&key).expect("inserted event row");super::work::row(Some(&*phase),rows)?;
    rows.push(Ev{func:super::work::own(Some(&*phase),func)?,var:super::work::own(Some(&*phase),name)?,rtype:rtype.unwrap_or_default()});
   }Ok(())
  })?;Ok(())
 })?;
 let mut list_set_vars=HashSet::new();
 for rows in events.values(){for event in rows{
  if event.func=="own_set"&&!event.rtype.is_empty()&&idx.actual().member_using(&event.rtype,&event.var,&mut scratch)?.is_some_and(|member|member.is_list)&&!list_set_vars.contains(&event.var){kc::set_room(phase,&mut list_set_vars)?;list_set_vars.insert(super::work::own(Some(&*phase),&event.var)?);}
 }}
 Work::checkpoint(phase)?;
 Ok(Prep{idx:IndexOwner::Native(idx),decls:DeclarationOwner::Native{markers,relations},events,list_set_vars})
}
