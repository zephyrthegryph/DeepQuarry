//! Release finished lowering growth capacity without changing symbolic content.
use crate::{lower_resolver::ResolverProc, Item, SimpleProc, SymbolicProc};

fn compact<T>(values: &mut Vec<T>) {
    if values.capacity() > values.len() {
        values.shrink_to_fit();
    }
}
fn names(values: &mut Vec<String>) {
    for value in values.iter_mut() {
        if value.capacity() > value.len() {
            value.shrink_to_fit();
        }
    }
    compact(values);
}
impl SymbolicProc {
    /// Preserve labels, references and instruction order while releasing slack.
    pub fn compact_retained(&mut self) {
        for item in &mut self.items {
            if let Item::Instruction(instruction) = item {
                compact(&mut instruction.operands);
            }
        }
        compact(&mut self.items);
    }
}
impl SimpleProc {
    /// Immutable literal backing and every semantic field remain unchanged.
    pub fn compact_retained(&mut self) {
        self.code.compact_retained();
        compact(&mut self.strings);
        compact(&mut self.class_paths);
        compact(&mut self.instance_paths);
        compact(&mut self.resources);
        names(&mut self.local_names);
        names(&mut self.argument_names);
        compact(&mut self.argument_type_flags);
        compact(&mut self.argument_value_sources);
    }
}
impl ResolverProc {
    pub fn compact_retained(&mut self) {
        self.procedure.compact_retained();
        for instance in self.modified_instances.values_mut() {
            compact(&mut instance.field_origins);
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        freeze_proc, Instruction, Item, LabelId, SimpleProc, SymRef, SymbolId, SymbolicProc, Word,
    };

    #[test]
    fn capacity_compaction_preserves_exact_frozen_code_and_typed_references() {
        let reference = SymRef::Proc {
            owner: SymbolId::of("/datum/base"),
            name: SymbolId::of("callback"),
            occurrence: 7,
        };
        let mut operands = Vec::with_capacity(64);
        operands.push(Word::Reference(reference));
        let mut code = SymbolicProc {
            items: Vec::with_capacity(128),
        };
        code.items.push(Item::Instruction(Instruction {
            opcode: 0xcd, // CallGlobalArgList has one typed ProcID operand.
            operands,
        }));
        code.items.push(Item::Label(LabelId(0)));
        let mut procedure = SimpleProc {
            code,
            ..Default::default()
        };
        procedure.local_names.reserve(32);
        procedure.local_names.push("local".into());
        let original_capacity = procedure.code.items.capacity();
        let expected = procedure.clone();
        let frozen = freeze_proc(&procedure.code).unwrap();
        let mut before = Vec::new();
        procedure
            .code
            .for_each_reference(|reference| before.push(reference));
        procedure.compact_retained();
        assert_eq!(procedure, expected);
        let compacted = freeze_proc(&procedure.code).unwrap();
        assert_eq!(
            compacted.code().canonical_bytes(),
            frozen.code().canonical_bytes()
        );
        assert_eq!(
            compacted.sites().collect::<Vec<_>>(),
            frozen.sites().collect::<Vec<_>>()
        );
        assert_eq!(compacted.labels(), frozen.labels());
        let mut after = Vec::new();
        procedure
            .code
            .for_each_reference(|reference| after.push(reference));
        assert_eq!(before, [reference]);
        assert_eq!(after, before);
        assert!(procedure.code.items.capacity() < original_capacity);
    }
}
