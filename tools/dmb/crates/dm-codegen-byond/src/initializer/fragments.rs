//! Assignment continuations: no VM frame, return, or procedure epilogue.
//!
//! Construction is private to the initializer producer. A fragment's source
//! ordinals are local; assembly binds them to the current admitted assignment.
use super::*;
use crate::{Instruction, Item, LabelId, StringRoster, SymbolId, Word};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone)]
pub struct AssignmentFragment {
    code: ResolverProc,
    label_count: u32,
    modified_references: Vec<SymRef>,
}

impl AssignmentFragment {
    pub(super) fn certify(code: ResolverProc) -> Result<Self, InitializerError> {
        let frame = &code.procedure;
        if frame.local_count != 0
            || !frame.local_names.is_empty()
            || !frame.argument_names.is_empty()
            || !frame.argument_type_flags.is_empty()
            || !frame.argument_value_sources.is_empty()
        {
            return Err(invalid("assignment fragment requires a VM frame"));
        }
        let mut definitions = BTreeSet::new();
        let mut branches = Vec::new();
        for item in &frame.code.items {
            match item {
                Item::Label(label) => {
                    if !definitions.insert(label.0) {
                        return Err(invalid("assignment fragment repeats a label"));
                    }
                }
                Item::Instruction(instruction) => {
                    if matches!(instruction.opcode, opcode::END | opcode::RET) {
                        return Err(invalid("assignment fragment contains an epilogue"));
                    }
                    for word in &instruction.operands {
                        match word {
                            Word::Branch(label) => branches.push(label.0),
                            Word::SourceFile(origin) | Word::SourceLine(origin) if *origin != 0 => {
                                return Err(invalid("assignment fragment has nonlocal debug"));
                            }
                            _ => {}
                        }
                    }
                }
            }
        }
        let label_count = u32::try_from(definitions.len())
            .map_err(|_| invalid("assignment fragment label count exceeds u32"))?;
        if definitions.iter().copied().ne(0..label_count)
            || branches.iter().any(|label| !definitions.contains(label))
        {
            return Err(invalid(
                "assignment fragment labels are not a dense closed set",
            ));
        }
        let modified_references = code.modified_instances.keys().copied().collect();
        Ok(Self {
            code,
            label_count,
            modified_references,
        })
    }

    /// Recertify a source-neutral transported continuation using the SAME
    /// producer invariants. Semantic/current-source admission remains external.
    pub fn from_transport(code: ResolverProc) -> Result<Self, InitializerError> {
        Self::from_transport_with_references(code, Vec::new())
    }
    /// A stripped transport retains the complete original modified-reference
    /// roster; current descriptors must still be reissued before binding.
    pub fn from_transport_with_references(
        code: ResolverProc,
        references: Vec<SymRef>,
    ) -> Result<Self, InitializerError> {
        if !code.modified_instances.is_empty() {
            return Err(invalid(
                "transported fragment requires current modified recipes",
            ));
        }
        let expected = code
            .procedure
            .instance_paths
            .iter()
            .copied()
            .map(SymRef::Instance)
            .collect::<BTreeSet<_>>();
        let mut used = BTreeSet::new();
        code.procedure.code.for_each_reference(|reference| {
            if matches!(reference, SymRef::Instance(_)) {
                used.insert(reference);
            }
        });
        if expected.len() != code.procedure.instance_paths.len()
            || references.iter().copied().ne(expected.iter().copied())
        {
            return Err(invalid(
                "transported modified-reference roster differs from instance operands",
            ));
        }
        if !used.is_subset(&expected) {
            return Err(invalid(
                "transported instance operand has no declared instance",
            ));
        }
        let mut certified = Self::certify(code)?;
        certified.modified_references = references;
        Ok(certified)
    }

    /// The assembly producer appends exactly one End. Validate its frame,
    /// closed labels and current local source roster with the fragment validator.
    pub fn validate_assembly_transport(
        code: &ResolverProc,
        root_count: usize,
    ) -> Result<(), InitializerError> {
        Self::validate_assembly_transport_with_references(code, root_count, Vec::new())
    }
    pub fn validate_assembly_transport_with_references(
        code: &ResolverProc,
        root_count: usize,
        references: Vec<SymRef>,
    ) -> Result<(), InitializerError> {
        let mut continuation = code.clone();
        match continuation.procedure.code.items.pop() {
            Some(Item::Instruction(instruction))
                if instruction.opcode == opcode::END && instruction.operands.is_empty() => {}
            _ => return Err(invalid("transported assembly requires terminal End")),
        }
        for item in &mut continuation.procedure.code.items {
            if let Item::Instruction(instruction) = item {
                for word in &mut instruction.operands {
                    if let Word::SourceFile(index) | Word::SourceLine(index) = word {
                        if *index as usize >= root_count {
                            return Err(invalid(
                                "transported assembly has unissued source ordinal",
                            ));
                        }
                        *index = 0;
                    }
                }
            }
        }
        Self::from_transport_with_references(continuation, references).map(|_| ())
    }

    /// Modified descriptors still require a current typed-expression reissuer.
    /// Fresh continuations support them; retained continuations decline them.
    pub fn can_retain(&self) -> bool {
        self.code.modified_instances.is_empty()
    }
    pub fn code(&self) -> &ResolverProc {
        &self.code
    }
    pub fn modified_references(&self) -> &Vec<SymRef> {
        &self.modified_references
    }
    /// Remove current AST-bearing descriptors before retaining semantic code.
    pub fn split_modified(
        mut self,
    ) -> (
        Self,
        BTreeMap<SymRef, crate::lower_resolver::CapturedModifiedInstance>,
    ) {
        let captured = std::mem::take(&mut self.code.modified_instances);
        (self, captured)
    }
    /// Attach only the exact original descriptor roster, reissued by the caller
    /// against the current typed expression and current resolver meanings.
    pub fn bind_modified(
        mut self,
        captured: BTreeMap<SymRef, crate::lower_resolver::CapturedModifiedInstance>,
    ) -> Result<Self, InitializerError> {
        if captured
            .keys()
            .copied()
            .ne(self.modified_references.iter().copied())
            || captured.iter().any(|(reference, value)| {
                *reference != SymRef::Instance(SymbolId::of(&value.descriptor.alias()))
            })
        {
            return Err(invalid(
                "initializer current descriptor roster differs from fragment",
            ));
        }
        self.code.modified_instances = captured;
        Ok(self)
    }
}

pub(super) fn assemble_continuations(
    fragments: impl IntoIterator<Item = AssignmentFragment>,
    debug_enabled: bool,
) -> Result<ResolverProc, InitializerError> {
    let mut result = ResolverProc {
        modified_instances: BTreeMap::new(),
        procedure_values: BTreeMap::new(),
        procedure_statics: BTreeMap::new(),
        procedure: crate::SimpleProc::default(),
        slots: BTreeMap::new(),
        resources: BTreeMap::new(),
        instances: BTreeMap::new(),
    };
    let mut strings = StringRoster::default();
    let mut classes = BTreeSet::new();
    let mut instances = BTreeSet::new();
    let mut resources = BTreeSet::new();
    let mut next_label = 0u32;
    let mut debug_last = None;
    for (index, fragment) in fragments.into_iter().enumerate() {
        let origin = u32::try_from(index)
            .map_err(|_| invalid("initializer assignment count exceeds u32"))?;
        let label_base = next_label;
        next_label = next_label
            .checked_add(fragment.label_count)
            .ok_or_else(|| invalid("initializer assembled label count exceeds u32"))?;
        let mut code = fragment.code;
        strings
            .merge(code.procedure.strings)
            .map_err(|error| invalid(&format!("initializer string collision: {error}")))?;
        append_unique(
            &mut result.procedure.class_paths,
            code.procedure.class_paths,
            &mut classes,
        );
        append_unique(
            &mut result.procedure.instance_paths,
            code.procedure.instance_paths,
            &mut instances,
        );
        append_unique(
            &mut result.procedure.resources,
            code.procedure.resources,
            &mut resources,
        );
        merge_exact(&mut result.procedure_values, code.procedure_values)?;
        merge_exact(&mut result.procedure_statics, code.procedure_statics)?;
        merge_exact(&mut result.slots, code.slots)?;
        merge_exact(&mut result.resources, code.resources)?;
        merge_exact(&mut result.instances, code.instances)?;
        for (reference, mut captured) in code.modified_instances {
            captured.origin = captured.origin.map(|_| origin);
            for field in &mut captured.field_origins {
                *field = field.map(|_| origin);
            }
            if let Some(previous) = result.modified_instances.get(&reference) {
                if previous.descriptor.canonical_bytes() != captured.descriptor.canonical_bytes() {
                    return Err(invalid("initializer modified-instance identity collision"));
                }
            } else {
                // The shared producer preserves the first descriptor's origin.
                result.modified_instances.insert(reference, captured);
            }
        }
        for item in &mut code.procedure.code.items {
            match item {
                Item::Label(label) => label.0 += label_base,
                Item::Instruction(instruction) => {
                    for word in &mut instruction.operands {
                        match word {
                            Word::Branch(LabelId(label)) => *label += label_base,
                            Word::SourceFile(local) | Word::SourceLine(local) => *local = origin,
                            _ => {}
                        }
                    }
                    if instruction.opcode == 0x85 {
                        debug_last = Some(origin);
                    }
                }
            }
        }
        result
            .procedure
            .code
            .items
            .extend(code.procedure.code.items);
    }
    // typed_assignment restores the shared entry origin (zero). Reproduce
    // Compiler::emit's final END source transition, including a branch entry.
    if debug_enabled
        && (debug_last != Some(0)
            || matches!(result.procedure.code.items.last(), Some(Item::Label(_))))
    {
        result
            .procedure
            .code
            .items
            .push(Item::Instruction(Instruction {
                opcode: 0x84,
                operands: vec![Word::SourceFile(0)],
            }));
        result
            .procedure
            .code
            .items
            .push(Item::Instruction(Instruction {
                opcode: 0x85,
                operands: vec![Word::SourceLine(0)],
            }));
    }
    result
        .procedure
        .code
        .items
        .push(Item::Instruction(Instruction {
            opcode: opcode::END,
            operands: Vec::new(),
        }));
    result.procedure.strings = strings.into_payloads();
    Ok(result)
}

fn invalid(message: &str) -> InitializerError {
    InitializerError::Invalid(message.into())
}
fn append_unique<T: Copy + Ord>(output: &mut Vec<T>, incoming: Vec<T>, seen: &mut BTreeSet<T>) {
    for value in incoming {
        if seen.insert(value) {
            output.push(value);
        }
    }
}
fn merge_exact<K: Ord, V: PartialEq>(
    output: &mut BTreeMap<K, V>,
    incoming: BTreeMap<K, V>,
) -> Result<(), InitializerError> {
    for (key, value) in incoming {
        if let Some(previous) = output.get(&key) {
            if previous != &value {
                return Err(invalid("initializer resolver sidecar collision"));
            }
        } else {
            output.insert(key, value);
        }
    }
    Ok(())
}
#[cfg(test)]
#[path = "fragments_tests.rs"]
mod tests;
