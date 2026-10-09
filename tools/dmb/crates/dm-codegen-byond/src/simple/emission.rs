//! Emission lowering over the shared compiler context.
use super::*;

impl Compiler<'_> {
    pub(super) fn emit(&mut self, opcode: u32, operands: Vec<Word>) {
        // Branch entries must establish their own source before executing.
        if opcode != 0x84
            && opcode != 0x85
            && (self.debug_last != self.debug_current
                || matches!(self.result.code.items.last(), Some(CodeItem::Label(_))))
        {
            if let Some(origin) = self.debug_current {
                self.result
                    .code
                    .items
                    .push(CodeItem::Instruction(Instruction {
                        opcode: 0x84,
                        operands: vec![Word::SourceFile(origin)],
                    }));
                self.result
                    .code
                    .items
                    .push(CodeItem::Instruction(Instruction {
                        opcode: 0x85,
                        operands: vec![Word::SourceLine(origin)],
                    }));
                self.debug_last = Some(origin);
            }
        }
        self.result
            .code
            .items
            .push(CodeItem::Instruction(Instruction { opcode, operands }));
    }

    pub(super) fn intern_string(&mut self, value: &str) -> SymbolId {
        self.intern_bytes(value.as_bytes())
    }

    pub(super) fn intern_format_template(&mut self, bytes: Vec<u8>) -> SymbolId {
        self.intern_bytes(&bytes)
    }

    fn intern_bytes(&mut self, bytes: &[u8]) -> SymbolId {
        match self.string_roster.intern_bytes(bytes) {
            Ok(id) => id,
            Err(collision) => {
                let mut failure = error("string payload", &collision.to_string());
                failure.kind = LowerErrorKind::Internal;
                self.resolver_failure.borrow_mut().get_or_insert(failure);
                SymbolId::of_bytes(bytes)
            }
        }
    }

    pub(super) fn label(&mut self) -> LabelId {
        let label = LabelId(self.next_label);
        self.next_label = self
            .next_label
            .checked_add(1)
            .expect("procedure label count exceeds u32");
        self.label_try_depths.insert(label, self.try_depth);
        label
    }

    pub(super) fn parameter_defaults(&mut self) -> Result<(), LowerError> {
        if !self.bindings.parameter_type_flags.is_empty()
            && self.bindings.parameter_type_flags.len() != self.bindings.parameters.len()
        {
            return Err(error(
                "parameters",
                "parameter type flag count differs from names",
            ));
        }
        if !self.bindings.parameter_defaults.is_empty()
            && self.bindings.parameter_defaults.len() != self.bindings.parameters.len()
        {
            return Err(error(
                "parameters",
                "parameter default count differs from names",
            ));
        }
        for (index, default) in self.bindings.parameter_defaults.iter().enumerate() {
            let Some(default) = default else {
                continue;
            };
            let slot = Word::Variable(VariableWord::Arg(index as u32));
            self.emit(opcode::GET_VAR, vec![slot.clone()]);
            self.emit(opcode::IS_NULL, vec![]);
            self.emit(opcode::TEST, vec![]);
            let skip = self.label();
            self.emit(opcode::JZ, vec![Word::Branch(skip)]);
            if let Some(path) = self
                .bindings
                .parameter_types
                .get(&self.bindings.parameters[index])
            {
                let parsed = parse_expression(default);
                if !parsed.diagnostics.is_empty() {
                    return Err(error(default, "invalid parameter default expression"));
                }
                let expr = parsed
                    .expr
                    .ok_or_else(|| error(default, "missing parameter default expression"))?;
                self.local_initializer(
                    &expr,
                    &format!("var{path}/{}", self.bindings.parameters[index]),
                    default,
                )?;
            } else {
                self.expression_text(default, default)?;
            }
            self.emit(opcode::SET_VAR, vec![slot]);
            self.result.code.items.push(CodeItem::Label(skip));
        }
        Ok(())
    }

    // Clause ordinals drive the frozen branch construction and labels.
}
