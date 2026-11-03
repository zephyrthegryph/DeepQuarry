//! Unique original requirement-bool lexical and union policy. No source role.
use crate::{lint::{Meta,Policy,RuleMeta,ScanKind},tree::CODE_DM,key_policy_control::{self as kc,Control}};
use std::collections::{BTreeSet,HashSet};
pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::requirement_bool::SCOPE_META_0.name,
    group: crate::allow_registry_fields::requirement_bool::SCOPE_META_0.group,
    label: "requirement_bool",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: "tools/ci/requirement_bool_baseline.txt",
        header: &[
            "Transitional boolean requirement callbacks. rule<TAB>file<TAB>normalized line.",
            "Convert callbacks to null-or-reason req(); analyze baseline --update --lint requirement_bool only shrinks this list.",
        ],
        banned: &["boolean_callback", "legacy_macro"],
    },
    rules: &[RuleMeta {
        name: "boolean_callback",
        hint: "merge the callback and refusal into req(PROC_REF(x)): return null to allow or a reason to refuse",
    }, RuleMeta {
        name: "legacy_macro",
        hint: "the requirement macro compiler was retired: use native null-or-reason requirements in acceptance() or needs()",
    }],
    allow: crate::allow_registry_fields::requirement_bool::ALLOW_0,
    lists: crate::allow_registry_fields::requirement_bool::SCOPE_META_0.lists,
};

pub fn metadata()->&'static Meta{&META}
pub const CALL:&str=r"(?<![\w./])req_bool\s*\(";
pub const DECLARATION:&str=r"^\s*/(?:\w+/)*req_bool\s*\(";
pub fn matches(call:&crate::pat::Pat,declaration:&crate::pat::Pat,code:&str)->bool{call.is_match(code)||declaration.is_match(code)}
pub struct Scanner{call:crate::pat::Pat,declaration:crate::pat::Pat}
impl Scanner{
 pub fn new()->Self{Self{call:crate::pat::Pat::new(CALL),declaration:crate::pat::Pat::new(DECLARATION)}}
 pub fn matches(&self,code:&str)->bool{matches(&self.call,&self.declaration,code)}
}
pub fn retired_name_using<C:Control>(code:&str,name:&str,work:&mut C)->Result<bool,C::Error>{let word=|b:u8|b.is_ascii_alphanumeric()||b==b'_';for(at,_)in code.match_indices(name){work.checkpoint()?;let end=at+name.len();if(at==0||!word(code.as_bytes()[at-1]))&&(end==code.len()||!word(code.as_bytes()[end])){return Ok(true)}}Ok(false)}
pub fn retired_name_in(code:&str,name:&str)->bool{retired_name_using(code,name,&mut kc::Compatibility).expect("original unbounded requirement predicate")}
/// The exact original BTreeSet union/dedup shape. Selection is an adapter input;
/// it cannot grant access to a file, source text or completion receipt.
pub struct Calls{rows:BTreeSet<(String,usize)>}
impl Calls{
 pub fn new()->Self{Self{rows:BTreeSet::new()}}
 pub fn rows(&self)->&BTreeSet<(String,usize)>{&self.rows}
 pub fn into_rows(self)->BTreeSet<(String,usize)>{self.rows}
 pub fn insert<C:Control>(&mut self,relative:&str,line:usize,work:&mut C)->Result<(),C::Error>{work.checkpoint()?;if C::CHECKED{kc::reserve(work,||relative.len().checked_mul(4)?.checked_add(2048))?;}self.rows.insert((relative.to_owned(),line));Ok(())}
 pub fn typed<C:Control>(&mut self,relative:&str,line:usize,selected:&HashSet<String>,work:&mut C)->Result<(),C::Error>{work.checkpoint()?;if selected.contains(relative){self.insert(relative,line,work)?;}Ok(())}
}
