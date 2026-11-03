//! Unique original UI host/action/constructor tables and source-local facts.
//! These are data; no Tree/model/source authority is constructed here.
use std::{cell::RefCell,collections::{HashMap,HashSet,BTreeMap,BTreeSet},rc::Rc};
use serde::{Serialize,Deserialize};
use crate::{dm::dx::{Proc,procs_in,is_subtype,lineage},tree::SourceFile,util::{py_rstrip,py_strip},pat,pat_match};
use crate::ui_actions_normalizer::Normaliser;
use crate::ui_actions_js::RawCall;
use crate::key_policy_control::{self as kc,Control,Compatibility};
pub(crate) const INTERFACES:&str="tgui/packages/tgui/interfaces";
pub(crate) const CAP_ROOT:&str="/datum/capability";
pub(crate) const CAPS_DIR:&str="code/datums/capabilities/";
pub(crate) const BUILTIN_HOSTS:[&str;2]=["/datum","/atom"];
/// One act() of a source file, with the dispatcher's normalisation of its names precomputed.
pub(crate) struct Call {
    pub(crate) rel: String,
    pub(crate) line: usize,
    pub(crate) raw_action: String,
    pub(crate) raw_keys: Option<Vec<String>>,
    pub(crate) nkey: Option<String>,
    pub(crate) nkeys: Option<Vec<Option<String>>>,
}

impl Call {
    pub(crate) fn new(rel:&str,raw:&RawCall,norm:&Normaliser)->Call{compat(Self::new_using(rel,raw,norm,&mut Compatibility))}
    pub(crate) fn new_using<C:Control>(rel:&str,raw:&RawCall,norm:&Normaliser,c:&mut C)->Result<Call,C::Error>{let rel=crate::ui_actions_policy::own_using(c,rel)?;let raw_action=crate::ui_actions_policy::own_using(c,&raw.action)?;let raw_keys=match &raw.keys{Some(keys)=>{let mut out=Vec::new();for key in keys{kc::row(c,&mut out)?;out.push(crate::ui_actions_policy::own_using(c,key)?);}Some(out)},None=>None};let nkey=norm.key_using(&raw.action,c)?;let nkeys=match &raw.keys{Some(keys)=>{let mut out=Vec::new();for key in keys{kc::row(c,&mut out)?;out.push(norm.key_using(key,c)?);}Some(out)},None=>None};Ok(Call{rel,line:raw.line,raw_action,raw_keys,nkey,nkeys})}
}

/// `tsx_acts`: the act() calls of an interface's sources (`None`: every source under interfaces/).
pub(crate) struct Acts {
    /// Sorted by path.
    pub(crate) files: Vec<(String, Vec<Call>)>,
    /// The selftest's `{interface: calls}` table instead of files.
    pub(crate) fixed: bool,
    pub(crate) by_interface: RefCell<HashMap<Option<String>, Rc<Vec<usize>>>>,
}

impl Acts {
    pub(crate) fn real(files: Vec<(String, Vec<Call>)>) -> Acts {
        Acts { files, fixed: false, by_interface: RefCell::new(HashMap::new()) }
    }

    /// Selftest table: the key of each entry is the interface name.
    pub(crate) fn fixed(table: Vec<(String, Vec<Call>)>) -> Acts {
        Acts { files: table, fixed: true, by_interface: RefCell::new(HashMap::new()) }
    }

    pub(crate) fn selected(&self,interface:Option<&str>)->Rc<Vec<usize>>{compat(self.selected_using(interface,&mut Compatibility))}
    pub(crate) fn selected_using<C:Control>(&self,interface:Option<&str>,c:&mut C)->Result<Rc<Vec<usize>>,C::Error>{c.checkpoint()?;let key=match interface{Some(value)=>Some(crate::ui_actions_policy::own_using(c,value)?),None=>None};if let Some(found)=self.by_interface.borrow().get(&key){return Ok(Rc::clone(found))}let mut picked=Vec::new();for(n,(rel,_))in self.files.iter().enumerate(){c.checkpoint()?;let take=if self.fixed{match interface{None=>true,Some(value)=>rel==value}}else if rel.ends_with(".d.ts"){false}else{match interface{None=>rel.ends_with(".tsx")||rel.ends_with(".ts"),Some(value)=>{let mut exact=false;for extension in ["tsx","ts","jsx","js"]{c.checkpoint()?;if equal_parts(rel,&[INTERFACES,"/",value,".",extension],false,c)?{exact=true;break}}let under=equal_parts(rel,&[INTERFACES,"/",value,"/"],true,c)?&&[".tsx",".ts",".jsx",".js"].iter().any(|suffix|rel.ends_with(suffix));exact||under}}};if take{kc::row(c,&mut picked)?;picked.push(n);}}kc::reserve(c,||Some(std::mem::size_of::<Vec<usize>>()+2*std::mem::size_of::<usize>()))?;let value=Rc::new(picked);crate::ui_actions_policy::map_room_using(&mut *self.by_interface.borrow_mut(),c)?;self.by_interface.borrow_mut().insert(key,Rc::clone(&value));Ok(value)}
    pub(crate) fn for_interface(&self,interface:Option<&str>)->Vec<&Call>{compat(self.for_interface_using(interface,&mut Compatibility))}
    pub(crate) fn for_interface_using<C:Control>(&self,interface:Option<&str>,c:&mut C)->Result<Vec<&Call>,C::Error>{let picked=self.selected_using(interface,c)?;let mut out=Vec::new();for &n in picked.iter(){c.checkpoint()?;for call in &self.files[n].1{kc::row(c,&mut out)?;out.push(call);}}Ok(out)}
}

// ---- DM hosts ---------------------------------------------------------------------------------

/// Insertion-ordered map (a Python dict).
pub(crate) struct Om<V> {
    pub(crate) keys: Vec<String>,
    pub(crate) map: HashMap<String, V>,
}

impl<V> Om<V> {
    pub(crate) fn new() -> Om<V> {
        Om { keys: Vec::new(), map: HashMap::new() }
    }
    pub(crate) fn insert(&mut self,key:&str,value:V){compat(self.insert_using(key,value,&mut Compatibility))}
    pub(crate) fn insert_using<C:Control>(&mut self,key:&str,value:V,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;if !self.map.contains_key(key){kc::row(c,&mut self.keys)?;self.keys.push(crate::ui_actions_policy::own_using(c,key)?);crate::ui_actions_policy::map_room_using(&mut self.map,c)?;}let key=crate::ui_actions_policy::own_using(c,key)?;self.map.insert(key,value);Ok(())}
    pub(crate) fn get(&self, k: &str) -> Option<&V> {
        self.map.get(k)
    }
    pub(crate) fn iter(&self) -> impl Iterator<Item = (&String, &V)> {
        self.keys.iter().map(move |k| (k, &self.map[k]))
    }
    pub(crate) fn is_empty_at(&self, k: &str) -> bool {
        self.map.get(k).is_none()
    }
}

pub(crate) struct Hosts {
    /// The procs the analysis reads by index: every `act_` proc, every global `cap_*` /
    /// capabilities-directory proc and every `capabilities()` proc, in file order.
    pub(crate) procs: Vec<Proc>,
    /// Content hash of each of `procs`.
    pub(crate) hashes: Vec<u128>,
    pub(crate) ids: HashMap<String, String>,
    pub(crate) legacy: HashSet<String>,
    /// host type -> {action key: proc index}
    pub(crate) acts: Om<Om<usize>>,
    /// capability type -> {action key: proc index}
    pub(crate) cap_acts: Om<Om<usize>>,
    pub(crate) ctor_bodies: HashMap<String, String>,
    pub(crate) ctor_caps_cache: RefCell<HashMap<String, BTreeSet<String>>>,
    /// host type -> capability types its own capabilities() body adds (constructors resolved).
    pub(crate) type_caps: HashMap<String, BTreeSet<String>>,
    pub(crate) actions_cache: RefCell<HashMap<String, Rc<HashMap<String, usize>>>>,
}

/// `(tgui_id by type, DECLARE_UI types)` of one file (the head of the old `Hosts::new`).
pub(crate) fn host_scan(file:&SourceFile)->(Vec<(String,String)>,Vec<String>){compat(host_scan_using(file,&mut Compatibility))}
pub(crate) fn host_scan_using<C:Control>(file:&SourceFile,c:&mut C)->Result<(Vec<(String,String)>,Vec<String>),C::Error>{let mut ids=Vec::new();let mut legacy=Vec::new();let clean=file.clean();let raw=file.raw();let mut current=None;for number in 1..=clean.num_lines(){c.checkpoint()?;let code=clean.line(number);if let Some(head)=first_capture(pat!(r"^(/[\w/]+)\s*$"),py_rstrip(code),c)?{current=Some(crate::ui_actions_policy::own_using(c,head.s(1))?);continue}if !code.is_empty()&&!code.starts_with([' ','\t']){current=None;if let Some(found)=first_capture(pat!(r"^\s*DECLARE_UI\w*\(\s*(/[\w/]+)"),code,c)?{kc::row(c,&mut legacy)?;legacy.push(crate::ui_actions_policy::own_using(c,found.s(1))?);}if let Some(found)=first_capture(pat!(r#"^(/[\w/]+?)/tgui_id\s*=\s*"([^"\n]+)""#),raw.line(number),c)?{kc::row(c,&mut ids)?;ids.push((crate::ui_actions_policy::own_using(c,found.s(1))?,crate::ui_actions_policy::own_using(c,found.s(2))?));}continue}if let Some(owner)=&current{if code.contains("tgui_id"){if let Some(found)=first_capture(pat!(r#"^\s+tgui_id\s*=\s*"([^"\n]+)""#),raw.line(number),c)?{kc::row(c,&mut ids)?;ids.push((crate::ui_actions_policy::own_using(c,owner)?,crate::ui_actions_policy::own_using(c,found.s(1))?));}}}}Ok((ids,legacy))}

/// A proc the analysis reads by index, as cached per file (`kind` 0: act_, 1: global constructor,
/// 2: capabilities()). Constructors and capabilities() carry their sanitized body.
#[derive(Serialize, Deserialize, Clone, PartialEq)]
pub(crate) struct PInfo {
    pub(crate) kind: u8,
    pub(crate) line: u32,
    pub(crate) path: String,
    pub(crate) name: String,
    pub(crate) params: Vec<String>,
    pub(crate) body_start: u32,
    pub(crate) body_len: u32,
    pub(crate) hash: u128,
    pub(crate) body: Option<String>,
}

/// One dm file's contribution: hosts, the procs read by index, the identity hash of every proc
/// (`names`: name hash and content hash, in file order), and the lines an `ALLOW(ui_actions)` keeps.
#[derive(Serialize, Deserialize, Default, PartialEq)]
pub(crate) struct DmFacts {
    pub(crate) ids: Vec<(String, String)>,
    pub(crate) legacy: Vec<String>,
    pub(crate) procs: Vec<PInfo>,
    pub(crate) names: Vec<(u64, u128)>,
    /// `(asked line, annotation line, reason code)`.
    pub(crate) kept: Vec<(u32, u32, String)>,
}

pub(crate) fn name_hash(name: &str) -> u64 {
    u64::from_le_bytes(blake3::hash(name.as_bytes()).as_bytes()[..8].try_into().unwrap())
}

pub(crate) fn dm_facts(file:&SourceFile)->DmFacts{compat(dm_facts_using(file,&mut Compatibility))}
pub(crate) fn dm_facts_using<C:Control>(file:&SourceFile,c:&mut C)->Result<DmFacts,C::Error>{let(ids,legacy)=host_scan_using(file,c)?;let clean=file.clean();let mut out=DmFacts{ids,legacy,..DmFacts::default()};crate::dm::dx::visit_proc_headers_using(file,c,|p,c|{c.checkpoint()?;let params=crate::dm::dx::param_names_using(p.params,c)?;let mut hash=blake3::Hasher::new();for part in [p.path,p.name]{c.checkpoint()?;hash.update(part.as_bytes());hash.update(b"\0");}for(i,param)in params.iter().enumerate(){c.checkpoint()?;if i!=0{hash.update(b"\x01");}hash.update(param.as_bytes());}hash.update(b"\0");for k in 0..p.body_len{c.checkpoint()?;if k!=0{hash.update(b"\n");}hash.update(clean.line(p.body_start+k).as_bytes());}hash.update(b"\0");let hash=u128::from_le_bytes(hash.finalize().as_bytes()[..16].try_into().unwrap());kc::row(c,&mut out.names)?;out.names.push((name_hash(p.name),hash));let kind=if p.name.starts_with("act_")&&p.path!="/"{Some(0u8)}else if p.path=="/"&&(p.name.starts_with("cap_")||p.rel.starts_with(CAPS_DIR)){Some(1)}else if p.name=="capabilities"&&p.path!="/"{Some(2)}else{None};if let Some(kind)=kind{let body=if kind>0{let mut bytes=p.body_len.saturating_sub(1);for k in 0..p.body_len{c.checkpoint()?;bytes=bytes.checked_add(clean.line(p.body_start+k).len()).ok_or_else(||c.overflow())?;}kc::reserve(c,||bytes.checked_add(64))?;let mut body=String::with_capacity(bytes);for k in 0..p.body_len{c.checkpoint()?;if k!=0{body.push('\n');}body.push_str(clean.line(p.body_start+k));}Some(body)}else{None};let value=PInfo{kind,line:p.line as u32,path:crate::ui_actions_policy::own_using(c,p.path)?,name:crate::ui_actions_policy::own_using(c,p.name)?,params,body_start:p.body_start as u32,body_len:p.body_len as u32,hash,body};kc::row(c,&mut out.procs)?;out.procs.push(value);}Ok(())})?;c.checkpoint()?;if file.text().contains("ui_actions"){for number in 1..=file.raw().num_lines(){c.checkpoint()?;if let Some(kept)=crate::allow::kept_using(file,number,"ui_actions",c)?{kc::row(c,&mut out.kept)?;out.kept.push((number as u32,kept.line as u32,kept.code.unwrap_or_default()));}}}Ok(out)}

impl Hosts {
    pub(crate) fn new(files: &[&SourceFile], facts: &[DmFacts]) -> Hosts {Self::from_facts(files.iter().zip(facts).map(|(file,facts)|(file.rel.as_str(),facts)))}
    pub(crate) fn from_facts<'a>(rows:impl IntoIterator<Item=(&'a str,&'a DmFacts)>)->Hosts{compat(Self::from_facts_using(rows,&mut Compatibility))}
    pub(crate) fn from_facts_using<'a,C:Control>(rows:impl IntoIterator<Item=(&'a str,&'a DmFacts)>,c:&mut C)->Result<Hosts,C::Error>{
     let mut ids=HashMap::new();let mut legacy=HashSet::new();let mut procs:Vec<Proc>=Vec::new();let mut kinds:Vec<(u8,Option<String>)>=Vec::new();let mut hashes=Vec::new();
     for(rel,facts)in rows{c.checkpoint()?;for(ty,id)in &facts.ids{c.checkpoint()?;if !ids.contains_key(ty){crate::ui_actions_policy::map_room_using(&mut ids,c)?;}let key=crate::ui_actions_policy::own_using(c,ty)?;let value=crate::ui_actions_policy::own_using(c,id)?;ids.insert(key,value);}for ty in &facts.legacy{hash_add(&mut legacy,ty,c)?;}for p in &facts.procs{c.checkpoint()?;let mut params=Vec::new();for value in &p.params{kc::row(c,&mut params)?;params.push(crate::ui_actions_policy::own_using(c,value)?);}let proc=Proc{rel:crate::ui_actions_policy::own_using(c,rel)?,line:p.line as usize,path:crate::ui_actions_policy::own_using(c,&p.path)?,name:crate::ui_actions_policy::own_using(c,&p.name)?,params,body_start:p.body_start as usize,body_len:p.body_len as usize};kc::row(c,&mut procs)?;procs.push(proc);let body=match &p.body{Some(body)=>Some(crate::ui_actions_policy::own_using(c,body)?),None=>None};kc::row(c,&mut kinds)?;kinds.push((p.kind,body));kc::row(c,&mut hashes)?;hashes.push(p.hash);}}
     let mut acts:Om<Om<usize>>=Om::new();let mut cap_acts:Om<Om<usize>>=Om::new();let mut ctor_bodies=HashMap::new();let mut caps_bodies:Om<Vec<String>>=Om::new();
     for(n,proc)in procs.iter().enumerate(){c.checkpoint()?;let(kind,body)=&kinds[n];match kind{0=>{let table=if subtype(&proc.path,CAP_ROOT,c)?{&mut cap_acts}else{&mut acts};if table.is_empty_at(&proc.path){table.insert_using(&proc.path,Om::new(),c)?;}table.map.get_mut(&proc.path).unwrap().insert_using(&proc.name[4..],n,c)?;},1=>{if !ctor_bodies.contains_key(&proc.name){crate::ui_actions_policy::map_room_using(&mut ctor_bodies,c)?;}let key=crate::ui_actions_policy::own_using(c,&proc.name)?;let value=crate::ui_actions_policy::own_using(c,body.as_deref().unwrap_or(""))?;ctor_bodies.insert(key,value);},_=>{if caps_bodies.is_empty_at(&proc.path){caps_bodies.insert_using(&proc.path,Vec::new(),c)?;}let values=caps_bodies.map.get_mut(&proc.path).unwrap();kc::row(c,values)?;values.push(crate::ui_actions_policy::own_using(c,body.as_deref().unwrap_or(""))?);}}}
     let mut hosts=Hosts{procs,hashes,ids,legacy,acts,cap_acts,ctor_bodies,ctor_caps_cache:RefCell::new(HashMap::new()),type_caps:HashMap::new(),actions_cache:RefCell::new(HashMap::new())};let mut type_caps=HashMap::new();for(path,bodies)in caps_bodies.iter(){c.checkpoint()?;let mut set=BTreeSet::new();for body in bodies{let found=hosts.caps_in_using(body,&HashSet::new(),c)?;for value in found{tree_add_owned(&mut set,value,c)?;}}crate::ui_actions_policy::map_room_using(&mut type_caps,c)?;let key=crate::ui_actions_policy::own_using(c,path)?;type_caps.insert(key,set);}hosts.type_caps=type_caps;Ok(hosts)
    }

    /// The capability types a global cap_* constructor (or bundle) builds.
    pub(crate) fn ctor_caps(&self,name:&str,seen:&HashSet<String>)->BTreeSet<String>{compat(self.ctor_caps_using(name,seen,&mut Compatibility))}
    pub(crate) fn ctor_caps_using<C:Control>(&self,name:&str,seen:&HashSet<String>,c:&mut C)->Result<BTreeSet<String>,C::Error>{c.checkpoint()?;if let Some(value)=self.ctor_caps_cache.borrow().get(name){return copied_tree(value,c)}if seen.contains(name)||!self.ctor_bodies.contains_key(name){return Ok(BTreeSet::new())}let mut seen=copied_seen(seen,c)?;hash_add(&mut seen,name,c)?;let got=self.caps_in_using(&self.ctor_bodies[name],&seen,c)?;crate::ui_actions_policy::map_room_using(&mut *self.ctor_caps_cache.borrow_mut(),c)?;let key=crate::ui_actions_policy::own_using(c,name)?;let saved=copied_tree(&got,c)?;self.ctor_caps_cache.borrow_mut().insert(key,saved);Ok(got)}
    pub(crate) fn caps_in(&self,body:&str,seen:&HashSet<String>)->BTreeSet<String>{compat(self.caps_in_using(body,seen,&mut Compatibility))}
    pub(crate) fn caps_in_using<C:Control>(&self,body:&str,seen:&HashSet<String>,c:&mut C)->Result<BTreeSet<String>,C::Error>{let mut out=BTreeSet::new();
     pat!(r"\bnew\s+(/datum/capability[\w/]*)|\bvar/(/datum/capability[\w/]*)/\w+\s*=\s*new\b").try_for_each_capture(body,c,groups,|c,m|tree_add(&mut out,if m.matched(1){m.s(1)}else{m.s(2)},c))?;
     pat!(r"(?:[(,=]\s*)(/datum/capability/[\w/]+)").try_for_each_capture(body,c,groups,|c,m|tree_add(&mut out,m.s(1),c))?;
     pat!(r"(?<![\w./:])([A-Za-z_]\w*)\s*\(").try_for_each_capture(body,c,groups,|c,m|{let found=self.ctor_caps_using(m.s(1),seen,c)?;for value in found{c.checkpoint()?;tree_add_owned(&mut out,value,c)?;}Ok(())})?;Ok(out)
    }

    pub(crate) fn caps_of(&self,path:&str)->BTreeSet<String>{compat(self.caps_of_using(path,&mut Compatibility))}
    pub(crate) fn caps_of_using<C:Control>(&self,path:&str,c:&mut C)->Result<BTreeSet<String>,C::Error>{let mut out=BTreeSet::new();for ancestor in crate::dm::dx::lineage_using(path,c)?{c.checkpoint()?;if let Some(values)=self.type_caps.get(&ancestor){for value in values{tree_add(&mut out,value,c)?;}}}Ok(out)}
    pub(crate) fn interface_of(&self,path:&str)->Option<String>{compat(self.interface_of_using(path,&mut Compatibility))}
    pub(crate) fn interface_of_using<C:Control>(&self,path:&str,c:&mut C)->Result<Option<String>,C::Error>{for ancestor in crate::dm::dx::lineage_using(path,c)?{c.checkpoint()?;if let Some(value)=self.ids.get(&ancestor){return Ok(Some(crate::ui_actions_policy::own_using(c,value)?))}}Ok(None)}
    pub(crate) fn is_legacy(&self,path:&str)->bool{compat(self.is_legacy_using(path,&mut Compatibility))}
    pub(crate) fn is_legacy_using<C:Control>(&self,path:&str,c:&mut C)->Result<bool,C::Error>{for ancestor in crate::dm::dx::lineage_using(path,c)?{c.checkpoint()?;if self.legacy.contains(&ancestor){return Ok(true)}}Ok(false)}
    pub(crate) fn cap_actions(&self,path:&str)->HashMap<String,usize>{compat(self.cap_actions_using(path,&mut Compatibility))}
    pub(crate) fn cap_actions_using<C:Control>(&self,path:&str,c:&mut C)->Result<HashMap<String,usize>,C::Error>{let mut out=HashMap::new();for ancestor in crate::dm::dx::lineage_using(path,c)?.iter().rev(){c.checkpoint()?;if let Some(actions)=self.cap_acts.get(ancestor){for(key,value)in actions.iter(){map_put(&mut out,key,*value,c)?;}}}Ok(out)}
    pub(crate) fn actions_of(&self,path:&str)->Rc<HashMap<String,usize>>{compat(self.actions_of_using(path,&mut Compatibility))}
    pub(crate) fn actions_of_using<C:Control>(&self,path:&str,c:&mut C)->Result<Rc<HashMap<String,usize>>,C::Error>{c.checkpoint()?;if let Some(value)=self.actions_cache.borrow().get(path){return Ok(Rc::clone(value))}let mut out=HashMap::new();for capability in self.caps_of_using(path,c)?{c.checkpoint()?;for(action,proc)in self.cap_actions_using(&capability,c)?{c.checkpoint()?;if !out.contains_key(&action){crate::ui_actions_policy::map_room_using(&mut out,c)?;out.insert(action,proc);}}}for ancestor in crate::dm::dx::lineage_using(path,c)?.iter().rev(){c.checkpoint()?;if let Some(actions)=self.acts.get(ancestor){for(key,value)in actions.iter(){map_put(&mut out,key,*value,c)?;}}}kc::reserve(c,||Some(std::mem::size_of::<HashMap<String,usize>>()+2*std::mem::size_of::<usize>()))?;let value=Rc::new(out);crate::ui_actions_policy::map_room_using(&mut *self.actions_cache.borrow_mut(),c)?;let key=crate::ui_actions_policy::own_using(c,path)?;self.actions_cache.borrow_mut().insert(key,Rc::clone(&value));Ok(value)}
    pub(crate) fn is_migrated(&self,path:&str)->bool{compat(self.is_migrated_using(path,&mut Compatibility))}
    pub(crate) fn is_migrated_using<C:Control>(&self,path:&str,c:&mut C)->Result<bool,C::Error>{for ancestor in crate::dm::dx::lineage_using(path,c)?{c.checkpoint()?;if !BUILTIN_HOSTS.contains(&ancestor.as_str())&&self.acts.get(&ancestor).map(|m|!m.keys.is_empty()).unwrap_or(false){return Ok(true)}}for capability in self.caps_of_using(path,c)?{c.checkpoint()?;if !self.cap_actions_using(&capability,c)?.is_empty(){return Ok(true)}}Ok(false)}
    pub(crate) fn by_interface(&self)->BTreeMap<String,Vec<String>>{compat(self.by_interface_using(&mut Compatibility))}
    pub(crate) fn by_interface_using<C:Control>(&self,c:&mut C)->Result<BTreeMap<String,Vec<String>>,C::Error>{let mut paths:BTreeSet<&String>=BTreeSet::new();for path in self.ids.keys().chain(self.acts.keys.iter()).chain(self.type_caps.keys()){c.checkpoint()?;if !paths.contains(path){kc::reserve(c,||Some(1024))?;paths.insert(path);}}let mut out:BTreeMap<String,Vec<String>>=BTreeMap::new();for path in paths{c.checkpoint()?;if BUILTIN_HOSTS.contains(&path.as_str())||subtype(path,CAP_ROOT,c)?{continue}if let Some(interface)=self.interface_of_using(path,c)?{if !out.contains_key(&interface){kc::reserve(c,||Some(1024))?;}let values=out.entry(interface).or_insert_with(Vec::new);kc::row(c,values)?;values.push(crate::ui_actions_policy::own_using(c,path)?);}}Ok(out)}
    pub(crate) fn served_interfaces(&self,path:&str)->Option<BTreeSet<String>>{compat(self.served_interfaces_using(path,&mut Compatibility))}
    pub(crate) fn served_interfaces_using<C:Control>(&self,path:&str,c:&mut C)->Result<Option<BTreeSet<String>>,C::Error>{self.served_interfaces_inner(path,c,&mut Vec::new())}
    fn served_interfaces_inner<C:Control>(&self,path:&str,c:&mut C,stack:&mut Vec<String>)->Result<Option<BTreeSet<String>>,C::Error>{c.checkpoint()?;if BUILTIN_HOSTS.contains(&path){return Ok(None)}if C::CHECKED{for ancestor in stack.iter(){c.checkpoint()?;if ancestor==path{return Err(c.overflow())}}kc::row(c,stack)?;stack.push(crate::ui_actions_policy::own_using(c,path)?);}let mut out=BTreeSet::new();if subtype(path,CAP_ROOT,c)?{for(host,caps)in &self.type_caps{c.checkpoint()?;let mut reaches=false;for capability in caps{c.checkpoint()?;if subtype(capability,path,c)?{reaches=true;break}}if reaches{if let Some(values)=self.served_interfaces_inner(host,c,stack)?{for value in values{tree_add_owned(&mut out,value,c)?;}}}}if C::CHECKED{stack.pop();}return Ok(Some(out))}if let Some(interface)=self.interface_of_using(path,c)?{tree_add_owned(&mut out,interface,c)?;}for(ty,interface)in &self.ids{c.checkpoint()?;if subtype(ty,path,c)?{tree_add(&mut out,interface,c)?;}}if C::CHECKED{stack.pop();}Ok(Some(out))}
}


fn compat<T>(value:Result<T,std::convert::Infallible>)->T{match value{Ok(value)=>value,Err(never)=>match never{}}}
fn groups<C:Control>(c:&mut C,n:usize)->Result<(),C::Error>{kc::reserve(c,||n.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128))}
fn tree_add<C:Control>(set:&mut BTreeSet<String>,value:&str,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;if !set.contains(value){kc::reserve(c,||value.len().checked_add(1024))?;set.insert(value.to_owned());}Ok(())}
fn tree_add_owned<C:Control>(set:&mut BTreeSet<String>,value:String,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;if !set.contains(&value){kc::reserve(c,||Some(1024))?;set.insert(value);}Ok(())}
fn copied_tree<C:Control>(values:&BTreeSet<String>,c:&mut C)->Result<BTreeSet<String>,C::Error>{let mut out=BTreeSet::new();for value in values{tree_add(&mut out,value,c)?;}Ok(out)}
fn hash_add<C:Control>(set:&mut HashSet<String>,value:&str,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;if !set.contains(value){crate::ui_actions_policy::set_room_using(set,c)?;let value=crate::ui_actions_policy::own_using(c,value)?;set.insert(value);}Ok(())}

fn copied_seen<C:Control>(values:&HashSet<String>,c:&mut C)->Result<HashSet<String>,C::Error>{let mut out=HashSet::new();for value in values{hash_add(&mut out,value,c)?;}Ok(out)}

fn map_put<C:Control>(map:&mut HashMap<String,usize>,key:&str,value:usize,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;if !map.contains_key(key){crate::ui_actions_policy::map_room_using(map,c)?;}let key=crate::ui_actions_policy::own_using(c,key)?;map.insert(key,value);Ok(())}
fn subtype<C:Control>(path:&str,base:&str,c:&mut C)->Result<bool,C::Error>{for ancestor in crate::dm::dx::lineage_using(path,c)?{c.checkpoint()?;if ancestor==base{return Ok(true)}}Ok(false)}

/// Same literal format equality/prefix tests without allocating the old
/// temporary formatted path once per candidate file. No path normalization.
fn equal_parts<C:Control>(text:&str,parts:&[&str],prefix:bool,c:&mut C)->Result<bool,C::Error>{let mut bytes=text.bytes();for part in parts{for expected in part.bytes(){c.checkpoint()?;if bytes.next()!=Some(expected){return Ok(false)}}}Ok(prefix||bytes.next().is_none())}

fn first_capture<'a,C:Control>(pattern:&crate::pat::Pat,text:&'a str,c:&mut C)->Result<Option<crate::pat::Caps<'a>>,C::Error>{groups(c,pattern.capture_group_count())?;c.checkpoint()?;let found=pattern.captures(text);c.checkpoint()?;Ok(found)}
