//! Common anonymous executable input. Declaration coverage and map assignment
//! coverage are separate domains; map initialization is never a class default.
use crate::{debug_sources::DebugOrigins, initializer_lowering::LoweredInitializerUnit};
use dm_codegen_byond::lower_resolver::ResolverProc;
use dm_link::InitializerIdentity;
use std::sync::Arc;

#[derive(Clone)]
pub enum InitializationCoverage {
    ModifiedAssignments {
        count: u32,
        canonical_body: Arc<[u8]>,
    },
    DeclarationWrites(Vec<usize>),
    DeclarationPresence(crate::initializer_lowering::DeclarationPresence),
    /// Canonical authored atom block, including empty-block presence and
    /// ordered repeated assignments. Absolute source spans stay outside it.
    MapAssignments {
        count: u32,
        canonical_body: Arc<[u8]>,
    },
}
#[derive(Clone)]
pub struct InitializationArtifact {
    pub identity: InitializerIdentity,
    pub code: Arc<ResolverProc>,
    pub debug_origins: Arc<DebugOrigins>,
    pub coverage: InitializationCoverage,
    pub(crate) encoding: Option<Arc<crate::symbolic::InitializerEncoding>>,
}
impl From<LoweredInitializerUnit> for InitializationArtifact {
    fn from(unit: LoweredInitializerUnit) -> Self {
        Self {
            identity: match unit.scope {
                dm_ir::InitializerScope::Global => InitializerIdentity::Global,
                dm_ir::InitializerScope::Instance(owner) => InitializerIdentity::Class(owner),
            },
            code: Arc::new(unit.code),
            debug_origins: Arc::new(unit.debug_origins),
            encoding: unit.encoding,
            coverage: match unit.declaration_presence {
                Some(presence) if unit.write_ordinals.is_empty() => {
                    InitializationCoverage::DeclarationPresence(presence)
                }
                _ => InitializationCoverage::DeclarationWrites(unit.write_ordinals),
            },
        }
    }
}
impl InitializationArtifact {
    pub fn validate(&self) -> Result<(), String> {
        match (&self.identity, &self.coverage) {
            (
                InitializerIdentity::Modified(_),
                InitializationCoverage::ModifiedAssignments { canonical_body, .. },
            ) if !canonical_body.is_empty() => (),
            (
                InitializerIdentity::Map { .. },
                InitializationCoverage::MapAssignments { canonical_body, .. },
            ) if !canonical_body.is_empty() => (),
            (
                InitializerIdentity::Global | InitializerIdentity::Class(_),
                InitializationCoverage::DeclarationWrites(writes),
            ) if !writes.is_empty() => {
                let distinct: std::collections::HashSet<_> = writes.iter().collect();
                if distinct.len() != writes.len() {
                    return Err("duplicated declaration initializer coverage".into());
                }
            }
            (
                InitializerIdentity::Class(owner),
                InitializationCoverage::DeclarationPresence(presence),
            ) if *owner == presence.owner() => {
                let items = &self.code.procedure.code.items;
                if items.len() != 1
                    || !matches!(&items[0], dm_codegen_byond::Item::Instruction(instruction)
                    if instruction.opcode == byond_dmb::bytecode::opcode::END && instruction.operands.is_empty())
                    || !self.debug_origins.entries.is_empty()
                    || !self.code.slots.is_empty()
                    || !self.code.modified_instances.is_empty()
                    || !self.code.procedure_values.is_empty()
                    || !self.code.procedure_statics.is_empty()
                    || !self.code.resources.is_empty()
                    || !self.code.instances.is_empty()
                    || !self.code.procedure.local_names.is_empty()
                {
                    return Err("declaration presence initializer emits executable work".into());
                }
            }
            _ => return Err("initializer identity differs from its coverage domain".into()),
        }
        if !self.code.procedure.argument_names.is_empty()
            || !self.code.procedure.argument_type_flags.is_empty()
            || !self.code.procedure.argument_value_sources.is_empty()
        {
            return Err("anonymous initializer unexpectedly declares formal parameters".into());
        }
        Ok(())
    }
}
