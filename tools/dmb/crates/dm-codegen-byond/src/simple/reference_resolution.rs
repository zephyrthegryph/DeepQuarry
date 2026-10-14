//! Adapter to the shared selection core; all existing resolver calls stay here.
use super::*;
use dm_ir::reference_resolution::{VariableContext, VariableResolutionError};
use dm_ir::{SelectedBuiltin as B, SelectedMeaning as M};
struct Context<'a, 'compiler>(&'a Compiler<'compiler>);
impl VariableContext for Context<'_, '_> {
    type Error = LowerError;
    fn local(&self, name: &str) -> Option<u32> {
        self.0.local_slots.get(name).copied()
    }
    fn argument(&self, name: &str) -> Option<u32> {
        self.0
            .bindings
            .parameters
            .iter()
            .rposition(|value| value == name)
            .map(|index| index as u32)
    }
    fn procedure_static(&self, name: &str) -> Result<Option<SymRef>, LowerError> {
        match self.0.lookup {
            Some(lookup) => self
                .0
                .semantic(lookup.procedure_static_slot(self.0.bindings.procedure_identity, name)),
            None => Ok(None),
        }
    }
    fn member_shared(&self, name: &str) -> Result<Option<SymRef>, LowerError> {
        if self.0.lookup.is_some() {
            if let Some(owner) = self.0.bindings.current_type_path.as_deref() {
                return self.0.member_global(owner, name);
            }
        }
        Ok(None)
    }
    fn has_instance_field(&self, name: &str) -> Result<bool, LowerError> {
        self.0.has_field(name)
    }
    fn has_global(&self, name: &str) -> Result<bool, LowerError> {
        self.0.has_global(name)
    }
    fn global_storage(&self, name: &str) -> Result<Option<SymRef>, LowerError> {
        match self.0.lookup {
            Some(lookup) => self
                .0
                .semantic(lookup.slot(dm_ir::ResolveQuery::VarStorage {
                    owner: SymbolId::of("/"),
                    name: SymbolId::of(name),
                })),
            None => self.0.global_variable(name).map(Some),
        }
    }
    fn receiver_owner(&self) -> Option<SymbolId> {
        self.0
            .bindings
            .current_type_path
            .as_deref()
            .map(SymbolId::of)
    }
}
impl Compiler<'_> {
    pub(super) fn variable_meaning(&self, name: &str, statement: &str) -> Result<M, LowerError> {
        let meaning = dm_ir::reference_resolution::resolve_variable(&Context(self), name).map_err(
            |failure| {
                match failure {
                    VariableResolutionError::Host(error) => error,
                    VariableResolutionError::MissingGlobalStorage => {
                        error(statement, "global variable has no shared storage")
                    }
                    VariableResolutionError::Unresolved => {
                        if self.lookup.is_some() {
                            // Every namespace probe above completed authoritatively.
                            // Unsupported/failed host answers exit through Host instead.
                            LowerError {
                                primary_anchor: None,
                                related: Vec::new(),
                                kind: LowerErrorKind::SourceError,
                                ..error(
                                    statement,
                                    &crate::lower_diagnostics::undefined_variable_message(
                                        statement, name,
                                    ),
                                )
                            }
                        } else {
                            error(statement, &format!("unresolved variable name: {name}"))
                        }
                    }
                }
            },
        )?;
        self.validate_variable_type(&meaning, name, statement)?;
        Ok(meaning)
    }
    /// Validate the selected declaration, never another namespace with the same name.
    /// Runtime aliases remain licensed by the ordinary current resolver.
    pub(super) fn validate_variable_type(
        &self,
        meaning: &M,
        name: &str,
        statement: &str,
    ) -> Result<(), LowerError> {
        use dm_ir::ResolveQuery as Q;
        let Some(lookup) = self.lookup else {
            return Ok(());
        };
        let query = match meaning {
            M::InstanceField {
                owner: Some(owner),
                name,
            } => Q::DeclaredVarType {
                owner: *owner,
                name: *name,
            },
            M::SharedStorage(SymRef::VariableSlot(slot)) => {
                let slots = lookup.slots.borrow();
                let Some(slot) = slots.get(&SymRef::VariableSlot(*slot)) else {
                    return Ok(());
                };
                Q::DeclaredVarType {
                    owner: slot.owner,
                    name: slot.name,
                }
            }
            // Locals/arguments and procedure statics use separate declaration issuers.
            // Do not infer their validity from an unrelated global declaration.
            _ => return Ok(()),
        };
        // Storage selection already succeeded. Opaque declared-type knowledge
        // cannot invalidate a value read that needs no receiver type. Record
        // the ordinary query through the same host, but do not promote this
        // exact optional absence of authority into a lowering failure.
        let declared = match lookup.resolver.resolve(query) {
            dm_ir::ResolvedMeaning::Unsupported(opaque) if opaque == query => return Ok(()),
            dm_ir::ResolvedMeaning::DeclaredType(path) => path,
            dm_ir::ResolvedMeaning::Missing => None,
            dm_ir::ResolvedMeaning::Member { data, .. } => data.declared_type,
            other => {
                return self.semantic(Err(lookup.error(
                    query,
                    &format!("invalid selected declaration type answer: {other:?}"),
                )))
            }
        };
        let Some(path) = declared else {
            return Ok(());
        };
        let path = self.semantic(lookup.text(query, path))?;
        let query = Q::RuntimeType(SymbolId::of(&path));
        // A value read needs declaration validity, not an output class/instance
        // operand. Native value types can have an opaque runtime mapping.
        // Keep this optional observation in the ordinary recording ledger;
        // receiver/constructor operations still require runtime_type authority.
        match lookup.resolver.resolve(query) {
            dm_ir::ResolvedMeaning::Symbol(_) => Ok(()),
            dm_ir::ResolvedMeaning::Unsupported(opaque) if opaque == query => Ok(()),
            dm_ir::ResolvedMeaning::Missing => {
                let mut failure = lookup.error(query, "declared type is absent");
                failure.kind = LowerErrorKind::SourceError;
                failure.reason =
                    crate::lower_diagnostics::undefined_type_message(statement, name, &path);
                self.semantic(Err(failure))
            }
            other => self.semantic(Err(lookup.error(
                query,
                &format!("invalid selected declaration runtime type answer: {other:?}"),
            ))),
        }
    }
    pub(super) fn variable_operand(
        &mut self,
        meaning: &M,
        name: &str,
        statement: &str,
    ) -> Result<VariableWord, LowerError> {
        Ok(match meaning {
            M::Local(index) => VariableWord::Local(*index),
            M::Argument(index) => VariableWord::Arg(*index),
            M::SharedStorage(reference) => VariableWord::Global(*reference),
            M::InstanceField { name: field, .. } => {
                self.intern_string(name);
                VariableWord::SetCache(
                    Box::new(VariableWord::Src),
                    Box::new(VariableWord::Field(*field)),
                )
            }
            M::Builtin(builtin) => match builtin {
                B::Src => VariableWord::Src,
                B::Usr => VariableWord::Usr,
                B::World => VariableWord::World,
                B::Args => VariableWord::Args,
                B::Caller => VariableWord::Caller,
                B::Callee => VariableWord::Callee,
                B::ReturnValue => VariableWord::Dot,
            },
            _ => {
                return Err(error(
                    statement,
                    "variable selection returned a non-variable meaning",
                ))
            }
        })
    }
}

#[cfg(test)]
#[path = "reference_resolution_tests.rs"]
mod tests;
