//! Native constant switch tables; dynamic forms keep the existing fallback.
use super::*;
#[path = "typed_switch_overlap.rs"]
mod overlap;

fn eligible(expr: &Expr) -> bool {
    if fold_number(expr).is_some() {
        return true;
    }
    match &expr.kind {
        ExprKind::Group(inner) => eligible(inner),
        ExprKind::Literal(raw) if raw == "null" || raw == "TRUE" || raw == "FALSE" => true,
        ExprKind::Literal(raw) if !raw.starts_with("@'") => {
            matches!(decode_constant_string_literal(raw), Ok(Some(_)))
        }
        _ => false,
    }
}

impl Compiler<'_> {
    // Use the ordinary expression producer, including string interning and
    // constant folding. Preflight limits it to one immutable value instruction.
    fn switch_value(&mut self, expr: &Expr, text: &str) -> Result<ValueWord, LowerError> {
        let start = self.result.code.items.len();
        self.expression(expr, text)?;
        let emitted = self.result.code.items.split_off(start);
        match emitted.as_slice() {
            [CodeItem::Instruction(Instruction {
                opcode: opcode::PUSH_INT,
                operands,
            })] => match operands.as_slice() {
                [Word::Immediate(value)] => Ok(ValueWord::Number((*value as f32).to_bits())),
                _ => Err(error(text, "constant switch integer has invalid operands")),
            },
            [CodeItem::Instruction(Instruction {
                opcode: opcode::PUSH_VAL,
                operands,
            })] => match operands.as_slice() {
                [Word::Value(value)] => Ok(value.clone()),
                _ => Err(error(text, "constant switch value has invalid operands")),
            },
            _ => Err(error(
                text,
                "constant switch value requires runtime evaluation",
            )),
        }
    }

    pub(super) fn native_switch(
        &mut self,
        selector: &Expr,
        cases: &[dm_syntax::SwitchCase],
        else_branch: &[Statement],
        text: &str,
    ) -> Result<bool, LowerError> {
        if cases.is_empty()
            || !cases.iter().all(|case| {
                case.alternatives.iter().all(|alt| match alt {
                    SwitchAlternative::Exact(value) => eligible(value),
                    SwitchAlternative::Range(low, high) => {
                        fold_number(low).is_some() && fold_number(high).is_some()
                    }
                })
            })
        {
            return Ok(false);
        }
        // The existing native corpus proves disjoint ranges and exact cases.
        // Preserve the old path where regrouping could change authored priority.
        let mut numeric_exact = Vec::new();
        let mut numeric_ranges = Vec::new();
        for case in cases {
            for alternative in &case.alternatives {
                match alternative {
                    SwitchAlternative::Exact(value) => {
                        if let Some(number) = fold_number(value) {
                            numeric_exact.push(number);
                        }
                    }
                    SwitchAlternative::Range(low, high) => {
                        let (low, high) = (fold_number(low).unwrap(), fold_number(high).unwrap());
                        if !low.is_finite() || !high.is_finite() || low > high {
                            return Ok(false);
                        }
                        numeric_ranges.push((low, high));
                    }
                }
            }
        }
        if overlap::overlaps(&numeric_exact, &numeric_ranges) {
            return Ok(false);
        }
        let end = self.label();
        let default = self.label();
        let labels: Vec<_> = cases.iter().map(|_| self.label()).collect();
        let mut exact = Vec::new();
        let mut ranges = Vec::new();
        for (case, label) in cases.iter().zip(&labels) {
            for alternative in &case.alternatives {
                match alternative {
                    SwitchAlternative::Exact(value) => {
                        exact.push((self.switch_value(value, text)?, *label));
                    }
                    SwitchAlternative::Range(low, high) => {
                        ranges.push((
                            self.switch_value(low, text)?,
                            self.switch_value(high, text)?,
                            *label,
                        ));
                    }
                }
            }
        }
        let count =
            |len| u32::try_from(len).map_err(|_| error(text, "switch table exceeds wire count"));
        let mut words = Vec::new();
        let opcode = if ranges.is_empty() { 0x78 } else { 0x7a };
        if !ranges.is_empty() {
            words.push(Word::Immediate(count(ranges.len())?));
            for (low, high, label) in ranges {
                words.extend([Word::Value(low), Word::Value(high), Word::Branch(label)]);
            }
        }
        words.push(Word::Immediate(count(exact.len())?));
        for (value, label) in exact {
            words.extend([Word::Value(value), Word::Branch(label)]);
        }
        words.push(Word::Branch(default));
        self.expression(selector, text)?;
        self.emit(opcode, words);
        for (case, label) in cases.iter().zip(labels) {
            self.result.code.items.push(CodeItem::Label(label));
            self.typed_statements(&case.body)?;
            self.emit(opcode::JMP, vec![Word::Branch(end)]);
        }
        self.result.code.items.push(CodeItem::Label(default));
        self.typed_statements(else_branch)?;
        self.result.code.items.push(CodeItem::Label(end));
        Ok(true)
    }
}

#[cfg(test)]
#[path = "typed_switch_tests.rs"]
mod tests;
