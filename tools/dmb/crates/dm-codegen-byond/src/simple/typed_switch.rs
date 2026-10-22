//! Native constant switch tables; dynamic forms keep the existing fallback.
use super::*;

// Pure bounded bitwise constants use DM's 24-bit numeric domain. Broader
// expressions retain the runtime fallback; no resolver calls occur in preflight.
fn switch_number(expr: &Expr) -> Option<f32> {
    if let Some(number) = fold_number(expr) {
        return Some(number);
    }
    match &expr.kind {
        ExprKind::Group(inner) => switch_number(inner),
        ExprKind::Binary { op, lhs, rhs } if op == "|" => {
            let a = switch_number(lhs)?;
            let b = switch_number(rhs)?;
            let exact = |value: f32| {
                value.is_finite() && value.fract() == 0.0 && (0.0..=16_777_215.0).contains(&value)
            };
            if !exact(a) || !exact(b) {
                return None;
            }
            Some(((a as u32 | b as u32) & 0x00ff_ffff) as f32)
        }
        _ => None,
    }
}

fn eligible(expr: &Expr) -> bool {
    if switch_number(expr).is_some() {
        return true;
    }
    match &expr.kind {
        ExprKind::Group(inner) => eligible(inner),
        // `"name" || src.name` (NAMEOF) folds to the constant text, as in DreamMaker.
        ExprKind::Binary { op, lhs, .. } if op == "||" && super::expression::constant_text_truth(lhs) == Some(true) => eligible(lhs),
        // `nameof(x)` is the text of its argument.
        ExprKind::Call { callee, args } => {
            args.len() == 1 && matches!(&callee.kind, ExprKind::Ident(name) if name == "nameof")
        }
        ExprKind::TypePath(_) => true,
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
        if let Some(number) = switch_number(expr) {
            return Ok(ValueWord::Number(number.to_bits()));
        }
        let start = self.result.code.items.len();
        // Table values are compile-time data, not executed expressions. Keep
        // ordinary value production and interning, but do not issue debug
        // instructions or consume the current executable source transition.
        let current = self.debug_current.take();
        let last = self.debug_last.take();
        let produced = self.expression(expr, text);
        self.debug_current = current;
        self.debug_last = last;
        let emitted = self.result.code.items.split_off(start);
        produced?;
        match emitted.as_slice() {
            [
                CodeItem::Instruction(Instruction {
                    opcode: opcode::PUSH_INT,
                    operands,
                }),
            ] => match operands.as_slice() {
                [Word::Immediate(value)] => Ok(ValueWord::Number((*value as f32).to_bits())),
                _ => Err(error(text, "constant switch integer has invalid operands")),
            },
            [
                CodeItem::Instruction(Instruction {
                    opcode: opcode::PUSH_VAL,
                    operands,
                }),
            ] => match operands.as_slice() {
                [Word::Value(value)] => Ok(value.clone()),
                _ => Err(error(text, "constant switch value has invalid operands")),
            },
            [
                CodeItem::Instruction(Instruction {
                    opcode: opcode::GET_VAR,
                    operands,
                }),
            ] if matches!(operands.as_slice(), [Word::Variable(VariableWord::Null)]) => {
                Ok(ValueWord::Null)
            }
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
        // `const` variables in a case label are their values.
        let alternatives: Vec<Vec<SwitchAlternative>> = cases
            .iter()
            .map(|case| {
                case.alternatives
                    .iter()
                    .map(|alternative| match alternative {
                        SwitchAlternative::Exact(value) => SwitchAlternative::Exact(
                            self.constant_context_expression(value).unwrap_or_else(|| value.clone()),
                        ),
                        SwitchAlternative::Range(low, high) => SwitchAlternative::Range(
                            self.constant_context_expression(low).unwrap_or_else(|| low.clone()),
                            self.constant_context_expression(high).unwrap_or_else(|| high.clone()),
                        ),
                    })
                    .collect()
            })
            .collect();
        if cases.is_empty()
            || !alternatives.iter().all(|case| {
                case.iter().all(|alt| match alt {
                    SwitchAlternative::Exact(value) => eligible(value),
                    SwitchAlternative::Range(low, high) => {
                        switch_number(low).is_some() && switch_number(high).is_some()
                    }
                })
            })
        {
            return Ok(false);
        }
        // Overlapping ranges and exact cases are tabled as authored: DreamMaker lists every range in source order,
        // then every exact value in source order, whatever they cover (measured against dm.exe: `if(25 to 27)` then
        // `if(26)` and the reverse order both give `SwitchRange {25..27, 26}` in that table order).
        for case in &alternatives {
            for alternative in case {
                if let SwitchAlternative::Range(low, high) = alternative {
                    let (low, high) = (switch_number(low).unwrap(), switch_number(high).unwrap());
                    if low > high {
                        return Ok(false);
                    }
                }
            }
        }
        let end = self.label();
        let default = self.label();
        let labels: Vec<_> = cases.iter().map(|_| self.label()).collect();
        let mut exact = Vec::new();
        let mut ranges = Vec::new();
        for (case, label) in alternatives.iter().zip(&labels) {
            // DreamMaker tables the alternatives of one case last to first (`if(1, 2, 3)` is 3, 2, 1).
            for alternative in case.iter().rev() {
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
