//! Existing Sys registration delegates its original facts/cache/judge to the unique shared producer.
use crate::{dm::sys::{register_module,SysModule},lint::Registry};
use crate::allow_registry_fields::sys_sfx::RULES;
pub fn register(reg:&mut Registry){register_module(reg,SysModule{name:crate::allow_registry_fields::sys_sfx::SCOPE_MODULE_NAME,rules:RULES,files_scan:Some(crate::sfx_policy::scan),..SysModule::DEFAULT});}
