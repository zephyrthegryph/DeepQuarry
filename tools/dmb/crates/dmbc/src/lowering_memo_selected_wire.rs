//! Private coordinate wire. No syntax serde dependency or authored AST payload.
use dm_ir::{SelectedMeaning, SelectedReference, SelectedReferences, SymbolId};
use dm_syntax::NodeStep;
use serde::{Deserialize, Serialize};
#[cfg(test)]
#[path = "lowering_memo_selected_wire_tests.rs"]
mod tests;

#[derive(Serialize, Deserialize)]
pub(super) struct SelectedWire {
    complete: bool,
    unbound_selections: usize,
    references: Vec<ReferenceWire>,
}
#[derive(Serialize, Deserialize)]
struct ReferenceWire {
    path: Vec<(u8, usize)>,
    relative_span: Option<(usize, usize)>,
    name: SymbolId,
    meaning: SelectedMeaning,
}
impl SelectedWire {
    pub(super) fn capture(facts: &SelectedReferences) -> Option<Self> {
        if facts.complete {
            return None;
        }
        Some(Self {
            complete: false,
            unbound_selections: facts.unbound_selections,
            references: facts
                .references
                .iter()
                .map(|reference| ReferenceWire {
                    relative_span: reference.relative_span,
                    path: reference
                        .path
                        .iter()
                        .map(|step| match *step {
                            NodeStep::Statement(index) => (0, index),
                            NodeStep::Branch(index) => (1, index),
                            NodeStep::Expression(index) => (2, index),
                            NodeStep::Child(index) => (3, index),
                        })
                        .collect(),
                    name: reference.name,
                    meaning: reference.meaning.clone(),
                })
                .collect(),
        })
    }
    pub(super) fn valid(&self) -> bool {
        !self.complete
            && self.references.iter().all(|reference| {
                reference.path.first().is_some_and(|(tag, _)| *tag == 0)
                    && reference.path.iter().all(|(tag, _)| *tag <= 3)
                    && reference.meaning.structurally_valid()
                    && reference
                        .relative_span
                        .is_none_or(|(start, end)| start <= end)
            })
    }
    pub(super) fn rehydrate(self) -> Option<SelectedReferences> {
        if !self.valid() {
            return None;
        }
        Some(SelectedReferences {
            complete: false,
            unbound_selections: self.unbound_selections,
            references: self
                .references
                .into_iter()
                .map(|reference| SelectedReference {
                    relative_span: reference.relative_span,
                    path: reference
                        .path
                        .into_iter()
                        .map(|(tag, index)| match tag {
                            0 => NodeStep::Statement(index),
                            1 => NodeStep::Branch(index),
                            2 => NodeStep::Expression(index),
                            3 => NodeStep::Child(index),
                            _ => unreachable!("validated coordinate tag"),
                        })
                        .collect(),
                    name: reference.name,
                    meaning: reference.meaning,
                })
                .collect(),
        })
    }
}
