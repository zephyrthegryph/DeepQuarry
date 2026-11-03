//! Existing registration delegates the unchanged cache/facts/judge to one shared producer.
use crate::{dm::sys::{register_module,SysModule},lint::Registry};
use crate::allow_registry_fields::sys_requirements::RULES;
pub fn register(reg:&mut Registry){register_module(reg,SysModule{name:crate::allow_registry_fields::sys_requirements::SCOPE_MODULE_NAME,rules:RULES,files_scan:Some(crate::sys_requirements_policy::scan),..SysModule::DEFAULT});}
