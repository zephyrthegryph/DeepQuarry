//! Original registry adapter, one shared exact lexical UI policy.
use crate::{dm::sys::{register_module,SysModule},lint::Registry};
use crate::allow_registry_fields::sys_ui::RULES;
pub fn register(reg:&mut Registry){register_module(reg,SysModule{name:crate::allow_registry_fields::sys_ui::SCOPE_MODULE_NAME,rules:RULES,files_scan:Some(crate::sys_ui_policy::scan),..SysModule::DEFAULT});}
