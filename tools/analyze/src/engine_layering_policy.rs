//! SAME original engine dependency judges; provenance supplied by actual selected model facts.
//! No scanner, parser, model, source authority or whole-source completion in this DATA kernel.
use std::collections::BTreeSet;use crate::key_policy_control::{self as kc,Control};
#[derive(Debug,Clone,PartialEq,Eq,PartialOrd,Ord)]pub struct Finding{pub rule:&'static str,pub file:String,pub line:u32,pub message:String}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Layer { Engine, Library }

impl Layer {
    pub fn name(self) -> &'static str {
        match self { Self::Engine => "engine_layering", Self::Library => "library_layering" }
    }

    pub fn selects(self, file: &str) -> bool {
        match self {
            Self::Engine => file.starts_with("code/engine/") || file.starts_with("code/host/"),
            Self::Library => file.starts_with("code/library/"),
        }
    }

    fn external(self, file: &str) -> bool {
        ["code/content/", "code/game/", "code/modules/", "code/datums/"]
            .iter().any(|root| file.starts_with(root))
            || self == Self::Engine && Self::Library.selects(file)
    }

    fn lawful(self, file: &str) -> bool {
        Self::Engine.selects(file)
            || self == Self::Library && (self.selects(file) || file.starts_with("code/domains/world_model/"))
    }

    pub fn metadata(self) -> &'static Meta {
        match self { Self::Engine => &META, Self::Library => &LIBRARY_META }
    }
}

fn generated(file: &str) -> bool { file.starts_with("code/engine/_generated/") }
/// Borrowed original selections. Native implementations must use compiler-selected
/// callable/field/parent facts and source-only provenance, never target-name prefixes.
pub trait Facts<C:Control>{type Call;fn type_exists(&self,path:&str,c:&mut C)->Result<bool,C::Error>;fn def_at(&self,file:&str,line:u32,c:&mut C)->Result<Option<(String,String)>,C::Error>;fn builtin_type(&self,path:&str,c:&mut C)->Result<bool,C::Error>;fn type_headers(&self,path:&str)->Option<&[String]>;fn owner_definitions(&self,path:&str)->Option<&[String]>;fn method(&self,owner:&str,name:&str,c:&mut C)->Result<Option<Self::Call>,C::Error>;fn global(&self,name:&str,c:&mut C)->Result<Option<Self::Call>,C::Error>;fn builtin_call(&self,call:&Self::Call,c:&mut C)->Result<bool,C::Error>;fn callable_file(&self,call:&Self::Call,c:&mut C)->Result<String,C::Error>;fn visit_method_declaration_files(&self,owner:&str,name:&str,c:&mut C,emit:&mut dyn FnMut(&str,&mut C)->Result<bool,C::Error>)->Result<(),C::Error>;}
fn temporary_copy<C:Control>(c:&mut C,slot:usize,text:&str)->Result<String,C::Error>{kc::temporary(c,slot,||text.len().checked_mul(4)?.checked_add(512))?;Ok(text.to_owned())}
fn put<C:Control>(found:&mut BTreeSet<Finding>,file:&str,line:u32,message:String,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;kc::reserve(c,||std::mem::size_of::<Finding>().checked_mul(4)?.checked_add(256))?;found.insert(Finding{rule:"external_dependency",file:kc::own(c,file)?,line,message});Ok(())}
pub fn provenance<C:Control>(layer:Layer,found:&mut BTreeSet<Finding>,file:&str,line:u32,symbol:&str,definition:&str,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;if layer.external(definition){let message=kc::format(c,format_args!("{} is defined in {}",symbol,definition))?;put(found,file,line,message,c)?;}Ok(())}
pub fn ty<C:Control,F:Facts<C>>(layer:Layer,facts:&F,found:&mut BTreeSet<Finding>,file:&str,line:u32,path:&str,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;let path=if let Some(element)=path.strip_prefix("/list/"){kc::temporary(c,1,||element.len().checked_mul(4)?.checked_add(512))?;format!("/{element}")}else{temporary_copy(c,1,path)?};if facts.builtin_type(&path,c)?{return Ok(())}let headers=facts.type_headers(&path).unwrap_or(&[]);let mut genuine=false;for header in headers{c.checkpoint()?;if !generated(header){genuine=true;break}}let definitions=if genuine{headers}else{facts.owner_definitions(&path).unwrap_or(&[])};for definition in definitions{c.checkpoint()?;if !generated(definition)&&layer.lawful(definition){return Ok(())}}for definition in definitions{c.checkpoint()?;if !generated(definition)&&layer.external(definition){provenance(layer,found,file,line,&path,definition,c)?;}}Ok(())}
pub fn method<C:Control,F:Facts<C>>(layer:Layer,facts:&F,found:&mut BTreeSet<Finding>,file:&str,line:u32,owner:&str,name:&str,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;if owner=="/"||owner.is_empty(){return global(layer,facts,found,file,line,name,c)}let Some(call)=facts.method(owner,name,c)?else{return Ok(())};if facts.builtin_call(&call,c)?{return Ok(())}let mut lawful=false;facts.visit_method_declaration_files(owner,name,c,&mut|definition,c|{c.checkpoint()?;if layer.lawful(definition)&&!generated(definition){lawful=true;Ok(false)}else{Ok(true)}})?;if lawful{return Ok(())}let definition=facts.callable_file(&call,c)?;kc::temporary(c,2,||owner.len().checked_add(name.len())?.checked_mul(4)?.checked_add(512))?;let symbol=format!("{owner}::{name}");provenance(layer,found,file,line,&symbol,&definition,c)}
pub fn global<C:Control,F:Facts<C>>(layer:Layer,facts:&F,found:&mut BTreeSet<Finding>,file:&str,line:u32,name:&str,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;let Some(call)=facts.global(name,c)?else{return Ok(())};if facts.builtin_call(&call,c)?{return Ok(())}let definition=facts.callable_file(&call,c)?;kc::temporary(c,2,||name.len().checked_mul(4)?.checked_add(512))?;let symbol=format!("/proc/{name}");provenance(layer,found,file,line,&symbol,&definition,c)}

/// SAME explicit path regex/truncation policy as original sem::layering.
pub fn source_paths<C:Control,F:Facts<C>>(layer:Layer,facts:&F,found:&mut BTreeSet<Finding>,file:&str,line:u32,text:&str,c:&mut C)->Result<(),C::Error>{
 if !text.contains('/'){return Ok(())}static RE:std::sync::OnceLock<regex::Regex>=std::sync::OnceLock::new();let re=RE.get_or_init(||regex::Regex::new(r"(?:^|[^\w])(/(?:[A-Za-z_]\w*/)*[A-Za-z_]\w*)").unwrap());
 for cap in re.captures_iter(text){c.checkpoint()?;let mut path=temporary_copy(c,1,&cap[1])?;if let Some((owner,name))=path.rsplit_once("/proc/"){if owner.is_empty(){global(layer,facts,found,file,line,name,c)?;}else{ty(layer,facts,found,file,line,owner,c)?;method(layer,facts,found,file,line,owner,name,c)?;}continue}while !facts.type_exists(&path,c)?{c.checkpoint()?;let Some(pos)=path.rfind('/')else{break};if pos==0{break}path.truncate(pos);}ty(layer,facts,found,file,line,&path,c)?;}Ok(())
}
pub fn marker_calls<C:Control,F:Facts<C>>(layer:Layer,facts:&F,found:&mut BTreeSet<Finding>,file:&str,line:u32,text:&str,c:&mut C)->Result<(),C::Error>{
 if !text.contains('('){return Ok(())}static RE:std::sync::OnceLock<regex::Regex>=std::sync::OnceLock::new();let re=RE.get_or_init(||regex::Regex::new(r"\b([A-Za-z_]\w*)\s*\(").unwrap());for cap in re.captures_iter(text){c.checkpoint()?;let token=cap.get(1).unwrap();if text[..token.start()].chars().next_back().is_some_and(|v|v=='.'||v=='/'){continue}let name=&cap[1];if let Some((owner,_))=facts.def_at(file,line,c)?{if facts.method(&owner,name,c)?.is_some(){method(layer,facts,found,file,line,&owner,name,c)?;continue}}global(layer,facts,found,file,line,name,c)?;}Ok(())
}
pub fn source_proc_refs<C:Control,F:Facts<C>>(layer:Layer,facts:&F,found:&mut BTreeSet<Finding>,file:&str,line:u32,text:&str,marker_owner:Option<&str>,c:&mut C)->Result<(),C::Error>{
 if !text.contains("PROC_REF"){return Ok(())}let owner=match marker_owner{Some(owner)=>temporary_copy(c,3,owner)?,None=>facts.def_at(file,line,c)?.map(|(owner,_)|owner).unwrap_or_else(||"/".to_owned())};static TYPED:std::sync::OnceLock<regex::Regex>=std::sync::OnceLock::new();let typed=TYPED.get_or_init(||regex::Regex::new(r"\bTYPE_PROC_REF\s*\(\s*(/[A-Za-z_][\w/]*)\s*,\s*([A-Za-z_]\w*)\s*\)").unwrap());for cap in typed.captures_iter(text){c.checkpoint()?;ty(layer,facts,found,file,line,&cap[1],c)?;method(layer,facts,found,file,line,&cap[1],&cap[2],c)?;}static OWN:std::sync::OnceLock<regex::Regex>=std::sync::OnceLock::new();let own=OWN.get_or_init(||regex::Regex::new(r"\bPROC_REF\s*\(\s*([A-Za-z_]\w*)\s*\)").unwrap());for cap in own.captures_iter(text){c.checkpoint()?;method(layer,facts,found,file,line,&owner,&cap[1],c)?;}Ok(())
}

use crate::lint::{Meta,Policy,RuleMeta,ScanKind};use crate::tree::CODE_DM;
const HINT: &str = "move the content-specific implementation downstream; call an actual engine-declared virtual interface, or move the foundational implementation into the engine";
static META: Meta = Meta {
    name: crate::allow_registry_fields::engine_layering::SCOPE_META_0.name, group: crate::allow_registry_fields::engine_layering::SCOPE_META_0.group, label: "engine_layering", legacy: "",
    select: CODE_DM, scan: ScanKind::Tree, policy: Policy::Hard,
    rules: &[RuleMeta { name: "external_dependency", hint: HINT }, RuleMeta { name: "semantic_model", hint: "repair the parsed environment; engine layering cannot pass without the semantic model" }],
    allow: crate::allow_registry_fields::engine_layering::ALLOW_0, lists: crate::allow_registry_fields::engine_layering::SCOPE_META_0.lists,
};

const LIBRARY_HINT: &str = "library code may not name content: move the content-specific implementation to code/content/, declare a virtual proc in the library and implement it there, or move the shared type into code/domains/world_model/";
static LIBRARY_META: Meta = Meta {
    name: crate::allow_registry_fields::library_layering::SCOPE_META_0.name,
    group: crate::allow_registry_fields::library_layering::SCOPE_META_0.group,
    label: "library_layering", legacy: "", select: CODE_DM, scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: "tools/ci/library_layering_baseline.txt",
        header: &[
            "Library files that name content (library may not reference content). rule<TAB>file<TAB>normalized line.",
            "`analyze check --lint library_layering` fails on a site not listed here.",
            "Shrink-only: after a sweep, `analyze baseline --update --lint library_layering`.",
        ],
        banned: &[],
    },
    rules: &[
        RuleMeta { name: "external_dependency", hint: LIBRARY_HINT },
        RuleMeta { name: "semantic_model", hint: "repair the parsed environment; library layering cannot pass without the semantic model" },
    ],
    allow: crate::allow_registry_fields::library_layering::ALLOW_0,
    lists: crate::allow_registry_fields::library_layering::SCOPE_META_0.lists,
};

pub fn metadata()->&'static Meta{&META}
