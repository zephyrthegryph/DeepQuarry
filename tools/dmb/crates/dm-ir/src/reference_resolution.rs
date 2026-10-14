//! Target-independent variable precedence over the current contextual query host.
//! Hosts keep query receipts and storage licensing; this core selects no table IDs.
use crate::{SelectedBuiltin, SelectedMeaning, SymRef, SymbolId};
#[cfg(test)]
#[path = "reference_resolution_tests.rs"]
mod tests;

pub trait VariableContext {
    type Error;
    fn local(&self, name: &str) -> Option<u32>;
    fn argument(&self, name: &str) -> Option<u32>;
    fn procedure_static(&self, name: &str) -> Result<Option<SymRef>, Self::Error>;
    fn member_shared(&self, name: &str) -> Result<Option<SymRef>, Self::Error>;
    fn has_instance_field(&self, name: &str) -> Result<bool, Self::Error>;
    fn has_global(&self, name: &str) -> Result<bool, Self::Error>;
    fn global_storage(&self, name: &str) -> Result<Option<SymRef>, Self::Error>;
    fn receiver_owner(&self) -> Option<SymbolId>;
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum VariableResolutionError<E> {
    Host(E),
    MissingGlobalStorage,
    Unresolved,
}
pub fn variable_builtin(name: &str) -> Option<SelectedBuiltin> {
    use SelectedBuiltin as B;
    match name {
        "src" => Some(B::Src),
        "usr" => Some(B::Usr),
        "world" => Some(B::World),
        "args" => Some(B::Args),
        "caller" => Some(B::Caller),
        "callee" => Some(B::Callee),
        "." => Some(B::ReturnValue),
        _ => None,
    }
}
pub fn resolve_variable<C: VariableContext>(
    context: &C,
    name: &str,
) -> Result<SelectedMeaning, VariableResolutionError<C::Error>> {
    use VariableResolutionError as E;
    if let Some(index) = context.local(name) {
        return Ok(SelectedMeaning::Local(index));
    }
    if let Some(index) = context.argument(name) {
        return Ok(SelectedMeaning::Argument(index));
    }
    if let Some(reference) = context.procedure_static(name).map_err(E::Host)? {
        return Ok(SelectedMeaning::SharedStorage(reference));
    }
    let builtin = variable_builtin(name);
    if builtin.is_none() {
        if let Some(reference) = context.member_shared(name).map_err(E::Host)? {
            return Ok(SelectedMeaning::SharedStorage(reference));
        }
    }
    if let Some(builtin) = builtin {
        return Ok(SelectedMeaning::Builtin(builtin));
    }
    if context.has_instance_field(name).map_err(E::Host)? {
        return Ok(SelectedMeaning::InstanceField {
            owner: context.receiver_owner(),
            name: SymbolId::of(name),
        });
    }
    if context.has_global(name).map_err(E::Host)? {
        return context
            .global_storage(name)
            .map_err(E::Host)?
            .map(SelectedMeaning::SharedStorage)
            .ok_or(E::MissingGlobalStorage);
    }
    Err(E::Unresolved)
}
