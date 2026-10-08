//! Lowering tests grouped by semantic concern.
use super::*;
use crate::{link_proc, Ledger, Table};

mod bindings;
mod builtins_and_diagnostics_1;
mod builtins_and_diagnostics_2;
mod calls_1;
mod calls_2;
mod control_flow_1;
mod control_flow_2;
mod expressions;
mod objects_1;
mod objects_2;
mod strings;
