use super::*;

pub(super) fn finish_initializer(
    code: &mut ResolverProc,
    _instance: bool,
) -> Result<(), InitializerError> {
    let items = &mut code.procedure.code.items;
    if items.len() >= 3
        && matches!(&items[items.len()-3], crate::Item::Instruction(ins)
            if ins.opcode == opcode::PUSH_VAL && ins.operands == [crate::Word::Value(crate::ValueWord::Null)])
        && matches!(&items[items.len()-2], crate::Item::Instruction(ins)
            if ins.opcode == opcode::RET && ins.operands.is_empty())
        && matches!(&items[items.len()-1], crate::Item::Instruction(ins)
            if ins.opcode == opcode::END && ins.operands.is_empty())
    {
        items.truncate(items.len() - 3);
        items.push(crate::Item::Instruction(crate::Instruction {
            opcode: opcode::END,
            operands: Vec::new(),
        }));
    }
    if !matches!(items.last(),Some(crate::Item::Instruction(ins))
        if ins.opcode == opcode::END && ins.operands.is_empty())
        || items
            .iter()
            .any(|item| matches!(item,crate::Item::Instruction(ins) if ins.opcode == opcode::RET))
    {
        return Err(InitializerError::Unsupported(
            "initializer has an unsupported value-return epilogue".into(),
        ));
    }
    Ok(())
}

fn instance_field(variable: &crate::VariableWord) -> Option<dm_ir::SymbolId> {
    use crate::VariableWord::{Field, SetCache, Src};
    match variable {
        Field(field) => Some(*field),
        SetCache(receiver, field) if matches!(receiver.as_ref(), Src) => match field.as_ref() {
            Field(field) => Some(*field),
            _ => None,
        },
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::VariableWord::{Field, SetCache, Src, Usr};
    #[test]
    fn receiver_normalization_preserves_unproved_and_already_doubled_shapes() {
        let field = dm_ir::SymbolId::of("field");
        let cache = |left, right| SetCache(Box::new(left), Box::new(right));
        assert_eq!(instance_field(&Field(field)), Some(field));
        assert_eq!(instance_field(&cache(Src, Field(field))), Some(field));
        assert_eq!(instance_field(&cache(Usr, Field(field))), None);
        assert_eq!(instance_field(&cache(Src, cache(Src, Field(field)))), None);
        assert_eq!(instance_field(&cache(Src, cache(Usr, Field(field)))), None);
    }
}

/// Only the final target store belongs to this admitted assignment. Expression
/// side effects and writes in other assignments retain their own receiver.
pub(crate) fn double_assignment_receiver(items: &mut [crate::Item]) -> bool {
    let Some(crate::Item::Instruction(instruction)) = items.last_mut() else {
        return false;
    };
    if instruction.opcode != opcode::SET_VAR {
        return false;
    }
    let [crate::Word::Variable(variable)] = instruction.operands.as_slice() else {
        return false;
    };
    let Some(field) = instance_field(variable) else {
        return false;
    };
    use crate::VariableWord::{Field, SetCache, Src};
    instruction.operands = vec![crate::Word::Variable(SetCache(
        Box::new(Src),
        Box::new(SetCache(Box::new(Src), Box::new(Field(field)))),
    ))];
    true
}
