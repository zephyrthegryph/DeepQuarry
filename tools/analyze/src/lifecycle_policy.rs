//! Unique original lifecycle judgment over borrowed lexical schema/source data.
//! No Tree/Sem, source receipt or completed-workspace authority is issued here.
use std::collections::HashSet;
use crate::{lint::{Meta,Policy,RuleMeta,ScanKind},tree::{View,CODE_DM},pat::Pat,util::py_strip,key_policy_control::{self as kc,Control},state_schema_data::{Schema,chain}};
const HINT: &str = "move it to on_materialize() and undo it in on_dematerialize()";

pub static META: Meta = Meta {
    name: crate::allow_registry_fields::lifecycle::SCOPE_META_0.name,
    group: crate::allow_registry_fields::lifecycle::SCOPE_META_0.group,
    label: "lifecycle",
    legacy: "tools/ci/lifecycle_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "global_list_write", hint: HINT },
        RuleMeta { name: "processing_start", hint: HINT },
        RuleMeta { name: "global_signal_registration", hint: HINT },
        RuleMeta { name: "radio_join", hint: HINT },
    ],
    allow: crate::allow_registry_fields::lifecycle::ALLOW_0,
    lists: crate::allow_registry_fields::lifecycle::SCOPE_META_0.lists,
};


const CLEAN_TYPES: &[&str] = &[
    "/obj/item/pda",
    "/obj/item/radio",
    "/obj/item/gps",
    "/obj/item/implant/tracking",
    "/obj/item/card/id",
    "/obj/item/card/id/guest",
];

pub(crate) fn row<C:Control,T>(c:&mut C,rows:&mut Vec<T>)->Result<(),C::Error>{if !C::CHECKED||rows.len()<rows.capacity(){return Ok(())}let wanted=rows.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||c.overflow())?;let bound=wanted.checked_mul(4).ok_or_else(||c.overflow())?;kc::reserve(c,||bound.checked_mul(std::mem::size_of::<T>())?.checked_add(128))?;rows.try_reserve_exact(wanted-rows.len()).map_err(|_|c.allocation_failed())?;if rows.capacity()>bound{return Err(c.allocation_failed())}Ok(())}
pub struct Body{pub owner:String,pub hits:Vec<(u32,u8)>}
pub struct FileFacts{pub relative:String,pub bodies:Vec<Body>}
pub struct Patterns{forbidden:Vec<(&'static str,&'static str,Pat)>,head:Pat}
impl Patterns{pub fn new()->Self{Self{forbidden:vec![("global_list_write","global list write",Pat::new(r"\bGLOB\.\w+\s*(?:\+=|-=|\|=|&=|\^=)|\bGLOB\.\w+\s*\[[^\]]*\]\s*=(?!=)|\bGLOB\.\w+\.(?:Add|Remove|Insert|Cut|Swap)\(")),("processing_start","processing start",Pat::new(r"\bSTART_PROCESSING\w*\(")),("global_signal_registration","global signal registration",Pat::new(r"\bRegisterSignal\(\s*SSdcs\b")),("radio_join","radio join",Pat::new(r"\bGLOB\.radio_service\.add_object\(|\bset_frequency\("))],head:Pat::new(r"^(/[\w/]+?)/(?:proc/)?Initialize\(")}}}
/// Same Initialize header/body boundary and pattern order. Temporary regex
/// capture backing belongs to the actual file loan, retained rows to the phase.
pub fn scan_using<C:Control,T:Control<Error=C::Error>>(code:&View,patterns:&Patterns,keep:&mut C,temporary:&mut T)->Result<Vec<Body>,C::Error>{let mut rows=Vec::new();if !code.text.contains("Initialize("){return Ok(rows)}kc::reserve(temporary,||patterns.head.capture_group_count().checked_mul(4*std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128))?;let mut i=1usize;while i<=code.num_lines(){temporary.checkpoint()?;let Some(m)=patterns.head.captures(code.line(i))else{i=i.checked_add(1).ok_or_else(||temporary.overflow())?;continue};let owner=kc::own(keep,m.s(1))?;let mut hits=Vec::new();i=i.checked_add(1).ok_or_else(||temporary.overflow())?;while i<=code.num_lines(){temporary.checkpoint()?;let line=code.line(i);if !py_strip(line).is_empty()&&!matches!(line.chars().next(),Some(' ')|Some('\t')){break}for(index,(_,_,pattern))in patterns.forbidden.iter().enumerate(){temporary.checkpoint()?;if pattern.is_match(line){row(keep,&mut hits)?;let number=if C::CHECKED{u32::try_from(i).map_err(|_|keep.overflow())?}else{i as u32};hits.push((number,index as u8));}}i=i.checked_add(1).ok_or_else(||temporary.overflow())?;}row(keep,&mut rows)?;rows.push(Body{owner,hits});}keep.checkpoint()?;Ok(rows)}
/// The original chain helper remains unique; this reusable positive-delta
/// temporary envelope covers its simultaneous prefix String/Vec allocations.
fn paths<C:Control>(owner:&str,c:&mut C,peak:&mut usize)->Result<Vec<String>,C::Error>{if C::CHECKED{let width=owner.len();let parts=owner.bytes().try_fold(4usize,|count,byte|{c.checkpoint()?;if byte==b'/'{count.checked_add(1).ok_or_else(||c.overflow())}else{Ok(count)}})?;let bound=parts.checked_mul(width.checked_mul(4).and_then(|n|n.checked_add(4*std::mem::size_of::<String>()+128)).ok_or_else(||c.overflow())?).and_then(|n|n.checked_add(1024)).ok_or_else(||c.overflow())?;if bound>*peak{c.reserve(bound-*peak)?;*peak=bound;}}Ok(chain(owner))}
pub fn judge_using<C:Control>(schema:&Schema,files:&[FileFacts],patterns:&Patterns,c:&mut C,emit:&mut dyn FnMut(&str,&str,u32,String,&mut C)->Result<(),C::Error>,note:&mut dyn FnMut(String,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{let mut ancestors=HashSet::new();let mut peak=0usize;for owner in schema.latent.keys(){c.checkpoint()?;let chain=paths(owner,c,&mut peak)?;let mut value=false;for parent in &chain{c.checkpoint()?;if let Some(current)=schema.latent.get(parent){value=*current}}if value{for parent in chain{c.checkpoint()?;if !ancestors.contains(&parent){kc::reserve(c,||Some(2048))?;if C::CHECKED{c.reserve(parent.capacity())?;}ancestors.insert(parent);}}}}for owner in CLEAN_TYPES{for parent in paths(owner,c,&mut peak)?{c.checkpoint()?;if !ancestors.contains(&parent){kc::reserve(c,||Some(2048))?;if C::CHECKED{c.reserve(parent.capacity())?;}ancestors.insert(parent);}}}let mut checked=0usize;let mut problems=0usize;for file in files{c.checkpoint()?;for body in &file.bodies{c.checkpoint()?;if !ancestors.contains(&body.owner){let mut value=false;for parent in paths(&body.owner,c,&mut peak)?{c.checkpoint()?;if let Some(current)=schema.latent.get(&parent){value=*current}}if !value{continue}}checked=checked.checked_add(1).ok_or_else(||c.overflow())?;for(number,index)in &body.hits{c.checkpoint()?;let(name,label,_)=&patterns.forbidden[*index as usize];problems=problems.checked_add(1).ok_or_else(||c.overflow())?;let message=kc::format(c,format_args!("{} in {}/Initialize()",label,body.owner))?;emit(name,&file.relative,*number,message,c)?;}}}let message=kc::format(c,format_args!("lifecycle lint: {} Initialize() procs on latent-safe types and their ancestors, {} problems",checked,problems))?;note(message,c)?;c.checkpoint()}

/// Pure membership DATA from the same actual registered Select.
pub fn selects_path(relative:&str)->bool{META.select.matches_path(relative)}
