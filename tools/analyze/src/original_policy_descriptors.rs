//! Canonical descriptor DATA for immutable external oracle modules.
//! No registration/completeness factory, collection helper, or source role is exported.
pub mod api{pub use crate::allow_registry_fields::api::{ALLOW_0,SCOPE_META_0};}
pub mod sys_fields{pub use crate::allow_registry_fields::sys_fields::{RULES,SCOPE_MODULE_NAME};}
pub mod sys_appearance{pub use crate::allow_registry_fields::sys_appearance::{RULES,ALLOW_EXTRA,SCOPE_MODULE_NAME};}
pub mod cooldown{pub use crate::allow_registry_fields::cooldown::{ALLOW_0,SCOPE_META_0};}
pub mod declaration_block{pub use crate::allow_registry_fields::declaration_block::{ALLOW_0,SCOPE_META_0};}
pub mod duplicate_input_key{pub use crate::allow_registry_fields::duplicate_input_key::{ALLOW_0,SCOPE_META_0};}
pub mod interactions{pub use crate::allow_registry_fields::interactions::{ALLOW_0,SCOPE_META_0};}
pub mod latent{pub use crate::allow_registry_fields::latent::{ALLOW_0,SCOPE_META_0};}
pub mod pollers{pub use crate::allow_registry_fields::pollers::{ALLOW_0,SCOPE_META_0};}
pub mod read_back{pub use crate::allow_registry_fields::read_back::{ALLOW_0,SCOPE_META_0};}
pub mod cap_bits{pub use crate::allow_registry_fields::cap_bits::{ALLOW_0,SCOPE_META_0};}
pub mod pool{pub use crate::allow_registry_fields::pool::SCOPE_META_0;}

pub mod sys_dx_constructor_shadow{pub use crate::allow_registry_fields::sys_dx_constructor_shadow::{RULES,SCOPE_MODULE_NAME};}
pub mod sys_dx_look_side_effects{pub use crate::allow_registry_fields::sys_dx_look_side_effects::{RULES,SCOPE_MODULE_NAME};}

pub mod sys_expiry{pub use crate::allow_registry_fields::sys_expiry::{RULES,SCOPE_MODULE_NAME};}

pub mod sys_ui{pub use crate::allow_registry_fields::sys_ui::{RULES,SCOPE_MODULE_NAME};}

pub mod doc_snippets{pub use crate::allow_registry_fields::doc_snippets::{ALLOW_0,SCOPE_META_0};}

pub mod ownership{pub use crate::allow_registry_fields::ownership::{ALLOW_0,SCOPE_META_0};}

pub mod ui_actions{pub use crate::allow_registry_fields::ui_actions::{ALLOW_0,SCOPE_META_0};}

pub mod setter_publishes{pub use crate::allow_registry_fields::setter_publishes::{ALLOW_0,SCOPE_META_0};}

pub mod op_order{pub use crate::allow_registry_fields::op_order::{ALLOW_0,SCOPE_META_0};}

pub mod sys_dx_reactive{pub use crate::allow_registry_fields::sys_dx_reactive::{RULES,SCOPE_MODULE_NAME};}

pub mod lifeforms{pub use crate::allow_registry_fields::lifeforms::{ALLOW_0,SCOPE_META_0};}
pub mod lifeform_allows{pub use crate::allow_registry_fields::lifeform_allows::{SCOPE_META_0};}
pub mod escape_hatches{pub use crate::allow_registry_fields::escape_hatches::{SCOPE_META_0};}

pub mod sem_handlers{pub use crate::allow_registry_fields::sem_handlers::{ALLOW_0,SCOPE_META_0};}

pub mod sem_reads{pub use crate::allow_registry_fields::sem_reads::ALLOW_0;}
pub mod untracked_inputs{pub use crate::allow_registry_fields::untracked_inputs::ALLOW_0;}
