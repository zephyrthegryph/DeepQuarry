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

    pub(super) fn intern_string(&mut self, value: &str) {
        if self.seen_strings.insert(value.to_owned()) {
            self.result.strings.push(value.to_owned());
        }
    }

    pub(super) fn intern_format_template(&mut self, bytes: Vec<u8>) -> String {
        if let Ok(text) = std::str::from_utf8(&bytes) {
            let key = text.to_owned();
            self.intern_string(&key);
            return key;
        }
        let mut key = String::from("\u{e000}format:");
        for byte in &bytes {
            key.push_str(&format!("{byte:02x}"));
        }
        if self.seen_strings.insert(key.clone()) {
            self.result.strings.push(key.clone());
        }
        self.result.format_templates.insert(key.clone(), bytes);
        key
    }

    pub(super) fn label(&mut self) -> String {
        let next = self.next_label;
        self.next_label += 1;
        let label = format!("block_{next}");
        self.label_try_depths.insert(label.clone(), self.try_depth);
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
            self.emit(opcode::JZ, vec![Word::Branch(skip.clone())]);
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
