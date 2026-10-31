//! Parser-free registration adapter; legacy registration stays at Lifeforms.
pub fn register(reg:&mut crate::lint::Registry){crate::lifeform_source_policy::register_hatches(reg)}
