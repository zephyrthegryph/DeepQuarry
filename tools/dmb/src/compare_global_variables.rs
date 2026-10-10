use super::*;

pub(super) fn normalize(dmb: &Dmb, slot: u32) -> NormalVariable {
    // BuiltinGlobalVars is the VM's direct VarID exception, certified by its
    // complete record rather than by an incidental table position.
    if dmb.variables.get(slot as usize).is_some_and(|record| {
        record.kind == 82 && record.value == 0 && dmb.string(record.name) == Some(b"vars")
    }) {
        return NormalVariable::Named("builtin-global-vars");
    }
    let invalid = |reason, id| NormalVariable::InvalidGlobal(reason, slot, id);
    let Some(footer) = dmb.lists.get(dmb.variable_footer as usize) else {
        return invalid("missing-footer", None);
    };
    if footer.len() % 2 != 0 {
        return invalid("malformed-footer", None);
    }
    let Some(index) = (slot as usize).checked_mul(2) else {
        return invalid("slot-out-of-range", None);
    };
    let Some(&id) = footer.get(index) else {
        return invalid("slot-out-of-range", None);
    };
    let Some(record) = dmb.variables.get(id as usize) else {
        return invalid("variable-out-of-range", Some(id));
    };
    match bytes(dmb, record.name) {
        Some(name) => NormalVariable::Global(Some(name)),
        None => invalid("missing-variable-name", Some(id)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn model() -> Dmb {
        let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let name = dmb.strings.len() as u32;
        for text in [b"file".as_slice(), b"flat_template", b"vars"] {
            dmb.strings.push(crate::dmb::DmString {
                data: text.to_vec(),
                long_chunks: 0,
            });
        }
        dmb.variables.resize(
            180,
            crate::dmb::Variable {
                kind: 0,
                value: 0,
                name,
            },
        );
        dmb.variables[67].name = name;
        dmb.variables[179].name = name + 1;
        dmb.variables[178] = crate::dmb::Variable {
            kind: 82,
            value: 0,
            name: name + 2,
        };
        dmb.variable_footer = dmb.lists.len() as u32;
        let mut footer = vec![0; 136];
        footer[134] = 179;
        footer[135] = 1;
        dmb.lists.push(footer);
        dmb
    }

    #[test]
    fn footer_slots_resolve_names_in_each_compilers_binding_context() {
        let native = model();
        assert_eq!(
            native.string(native.variables[67].name),
            Some(b"file".as_slice())
        );
        assert_eq!(
            normalize(&native, 67),
            NormalVariable::Global(Some(b"flat_template".to_vec()))
        );
        let mut byond = native.clone();
        byond.variables[120] = byond.variables[179].clone();
        byond.lists[byond.variable_footer as usize][134] = 120;
        assert_eq!(normalize(&native, 67), normalize(&byond, 67));
        assert_eq!(
            normalize(&native, 178),
            NormalVariable::Named("builtin-global-vars")
        );
    }

    #[test]
    fn invalid_bindings_remain_distinct_and_do_not_fall_back_to_direct_ids() {
        let mut dmb = model();
        assert_eq!(
            normalize(&dmb, 179),
            NormalVariable::InvalidGlobal("slot-out-of-range", 179, None)
        );
        dmb.lists[dmb.variable_footer as usize][134] = 999;
        assert_eq!(
            normalize(&dmb, 67),
            NormalVariable::InvalidGlobal("variable-out-of-range", 67, Some(999))
        );
        dmb.lists[dmb.variable_footer as usize].push(0);
        assert_eq!(
            normalize(&dmb, 67),
            NormalVariable::InvalidGlobal("malformed-footer", 67, None)
        );
        dmb.variable_footer = u32::MAX;
        assert_eq!(
            normalize(&dmb, 67),
            NormalVariable::InvalidGlobal("missing-footer", 67, None)
        );
    }
}
