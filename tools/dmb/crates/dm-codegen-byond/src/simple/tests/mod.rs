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

// Explicit identities for these small standalone fixture declaration tables.
// Production lowering receives resolver-issued references instead.
trait FixtureKey {
    fn id(&self) -> SymbolId;
    fn text(&self) -> Option<&str> {
        None
    }
}
impl FixtureKey for str {
    fn id(&self) -> SymbolId {
        SymbolId::of(self)
    }
    fn text(&self) -> Option<&str> {
        Some(self)
    }
}
impl FixtureKey for String {
    fn id(&self) -> SymbolId {
        SymbolId::of(self)
    }
    fn text(&self) -> Option<&str> {
        Some(self)
    }
}
impl FixtureKey for SymbolId {
    fn id(&self) -> SymbolId {
        *self
    }
}
impl FixtureKey for StringPayload {
    fn id(&self) -> SymbolId {
        self.id
    }
    fn text(&self) -> Option<&str> {
        std::str::from_utf8(&self.bytes).ok()
    }
}
impl<T: FixtureKey + ?Sized> FixtureKey for &T {
    fn id(&self) -> SymbolId {
        (*self).id()
    }
    fn text(&self) -> Option<&str> {
        (*self).text()
    }
}
fn reference(table: Table, key: impl FixtureKey) -> SymRef {
    match table {
        Table::String => SymRef::String(key.id()),
        Table::Class => SymRef::Type(key.id()),
        Table::Instance => SymRef::Instance(key.id()),
        Table::Variable => SymRef::Var {
            owner: SymbolId::of("/"),
            name: key.id(),
        },
        Table::Proc => {
            let path = key.text().expect("fixture proc spelling");
            let (owner, name, verb) = if let Some((owner, name)) = path.rsplit_once("/verb/") {
                (owner, name, true)
            } else {
                let (owner, name) = path.rsplit_once("/proc/").expect("fixture proc namespace");
                (owner, name, false)
            };
            let owner = SymbolId::of(if owner.is_empty() { "/" } else { owner });
            if verb {
                SymRef::Verb {
                    owner,
                    name: SymbolId::of(name),
                    occurrence: 0,
                }
            } else {
                SymRef::Proc {
                    owner,
                    name: SymbolId::of(name),
                    occurrence: 0,
                }
            }
        }
        Table::Resource => panic!("resource fixtures require an explicit identity"),
        Table::List => panic!("fixture lists require explicit captured identity"),
    }
}
fn string_texts(proc: &SimpleProc) -> Vec<String> {
    proc.strings
        .iter()
        .map(|payload| String::from_utf8(payload.bytes.to_vec()).unwrap())
        .collect()
}
fn compile_fixture_proc_with_bindings(
    body: &[Item],
    bindings: &LowerBindings,
) -> Result<SimpleProc, Vec<LowerError>> {
    let mut bindings = bindings.clone();
    for name in &bindings.globals {
        bindings
            .global_variables
            .entry(name.clone())
            .or_insert_with(|| reference(Table::Variable, name));
    }
    if let Some(path) = &bindings.current_proc_path {
        let captured = reference(Table::Proc, path);
        bindings.procedure_identity = Some(match captured {
            SymRef::Proc {
                owner,
                name,
                occurrence,
            } => dm_ir::ProcedureIdentity {
                owner,
                name,
                occurrence,
                verb: false,
            },
            SymRef::Verb {
                owner,
                name,
                occurrence,
            } => dm_ir::ProcedureIdentity {
                owner,
                name,
                occurrence,
                verb: true,
            },
            _ => unreachable!(),
        });
    }
    crate::compile_simple_proc_with_bindings(body, &bindings)
}

mod preparsed;
