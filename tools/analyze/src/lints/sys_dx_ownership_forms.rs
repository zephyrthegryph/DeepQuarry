//! Port of `tools/ci/sys_rules/dx_ownership_forms.py`: the ownership declaration forms replaced
//! by the ownership() and relations() list overrides (doc/rewrite/ownership.md 1.2, 4.1), string
//! var names in accessors, and a var owned twice (by a capability's owned() entries and by the
//! type's own ownership()).

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::dm::sys::{register_module, SysModule};
use crate::incr;
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::{SourceFile, Tree};
use crate::util::{before_slashes, is_py_space};

use crate::allow_registry_fields::sys_dx_ownership_forms::RULES;

use crate::sys_ownership_forms_policy::{facts_of,related};

fn scan(_tree:&Tree,files:&[&SourceFile])->Vec<(&'static str,String,usize)>{let facts=incr::facts("sys-dx-ownership-forms",files,facts_of);let rows:Vec<_>=files.iter().zip(facts).map(|(file,facts)|(file.rel.as_str(),facts)).collect();let mut out=Vec::new();crate::sys_ownership_forms_policy::scan_using(&rows,&mut crate::key_policy_control::Compatibility,&mut|rule,relative,line,_|{out.push((rule,relative.to_owned(),line as usize));Ok(())}).unwrap_or_else(|never|match never{});out}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: crate::allow_registry_fields::sys_dx_ownership_forms::SCOPE_MODULE_NAME, rules: RULES, files_scan: Some(scan), ..SysModule::DEFAULT });
}
