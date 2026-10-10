use super::*;

pub(super) fn normalize(dmb: &memo::NormalizationContext<'_>, id: u32) -> NormalVariable {
    // Pinned DreamMaker static_icon_probe emits Global(178) for VarID178,
    // while its footer has only 68 declaration pairs. Global is never a slot.
    let Some(record) = dmb.variables.get(id as usize) else {
        return NormalVariable::InvalidGlobal("variable-out-of-range", id, None);
    };
    if record.kind == 82 && record.value == 0 && dmb.string(record.name) == Some(b"vars") {
        return NormalVariable::Named("builtin-global-vars");
    }
    match bytes(dmb, record.name) {
        Some(name) => NormalVariable::Global(Some(name)),
        None => NormalVariable::InvalidGlobal("missing-variable-name", id, Some(record.name)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn direct_variable_ids_do_not_follow_footer_ordinals() {
        let mut native =
            Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let name = native.strings.len() as u32;
        for text in [b"file".as_slice(), b"flat_template", b"vars"] {
            native.strings.push(crate::dmb::DmString {
                data: text.to_vec(),
                long_chunks: 0,
            });
        }
        native.variables.resize(
            180,
            crate::dmb::Variable {
                kind: 0,
                value: 0,
                name,
            },
        );
        native.variables[67].name = name;
        native.variables[179].name = name + 1;
        native.variables[177] = crate::dmb::Variable {
            kind: 82,
            value: 0,
            name: name + 2,
        };
        native.variable_footer = native.lists.len() as u32;
        let mut footer = vec![0; 136];
        footer[134] = 179;
        footer[135] = 1;
        native.lists.push(footer);
        let mut byond = native.clone();
        byond.variables[178] = native.variables[179].clone();
        byond.lists[byond.variable_footer as usize][134] = 178;
        assert_eq!(
            normalize(&memo::NormalizationContext::new(&native), 179),
            normalize(&memo::NormalizationContext::new(&byond), 178)
        );
        assert_ne!(
            normalize(&memo::NormalizationContext::new(&native), 67),
            normalize(&memo::NormalizationContext::new(&byond), 178)
        );
        assert_eq!(
            normalize(&memo::NormalizationContext::new(&native), 177),
            NormalVariable::Named("builtin-global-vars")
        );
        native.variable_footer = u32::MAX;
        assert_eq!(
            normalize(&memo::NormalizationContext::new(&native), 179),
            NormalVariable::Global(Some(b"flat_template".to_vec()))
        );
        assert_eq!(
            normalize(&memo::NormalizationContext::new(&native), 999),
            NormalVariable::InvalidGlobal("variable-out-of-range", 999, None)
        );
        native.variables[179].name = u32::MAX;
        assert_eq!(
            normalize(&memo::NormalizationContext::new(&native), 179),
            NormalVariable::InvalidGlobal("missing-variable-name", 179, Some(u32::MAX))
        );
    }
}
