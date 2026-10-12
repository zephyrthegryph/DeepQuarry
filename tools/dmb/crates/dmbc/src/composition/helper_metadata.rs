//! Argument-source metadata bound from the SAME current owning frame.
//! Pinned paired capture f59634645b3046708722d69420335a30 establishes:
//! helper at argument N has preceding names [0..N], extended through any
//! directly referenced formal; all flags/selectors are zero.
//! Executable Arg operands still use the full owning lexical frame.
use super::*;

pub(super) fn prefix<'a>(
    batch: &'a FrozenBatch,
    procedures: &[procedure_plan::Slot<crate::lowering::UnitIdentity>],
    owner: crate::lowering::UnitIdentity,
    argument: u32,
    referenced_prefix: u32,
) -> Result<&'a [String], CompositionError> {
    let table_index = batch
        .tables
        .index(crate::symbolic::unit_key(owner))
        .ok_or_else(|| unsupported("helper owning procedure is not linked"))?;
    let position = procedures
        .binary_search_by_key(&table_index, |slot| slot.table_index)
        .map_err(|_| unsupported("helper owning procedure is not current"))?;
    let slot = &procedures[position];
    if slot.identity != owner {
        return Err(unsupported("helper owning procedure identity differs"));
    }
    let unit = slot
        .artifact
        .and_then(|index| batch.units.get(index))
        .ok_or_else(|| unsupported("helper owning frame absent"))?;
    if unit.lowered.identity != owner {
        return Err(unsupported("helper owning artifact identity differs"));
    }
    let argument = usize::try_from(argument)
        .map_err(|_| unsupported("helper parameter index exceeds usize"))?;
    let count = argument.max(
        usize::try_from(referenced_prefix)
            .map_err(|_| unsupported("helper referenced parameter extent exceeds usize"))?,
    );
    if argument >= unit.lowered.frame.argument_names.len()
        || count > unit.lowered.frame.argument_names.len()
    {
        return Err(unsupported("helper parameter is outside current frame"));
    }
    Ok(&unit.lowered.frame.argument_names[..count])
}

pub(super) fn emit(
    dmb: &mut Dmb,
    strings: &mut StringIndex,
    words: impl Into<std::sync::Arc<Vec<u32>>>,
    names: &[String],
    prefix: &[String],
) -> Result<(), CompositionError> {
    let code = append_list(dmb, words)?;
    let mut locals = Vec::with_capacity(names.len());
    for name in names {
        let name = strings.intern(dmb, name.as_bytes())?;
        let id = u32::try_from(dmb.variables.len())
            .map_err(|_| unsupported("anonymous local overflow"))?;
        dmb.variables.push(Variable {
            kind: 0,
            value: 0,
            name,
        });
        locals.push(id);
    }
    let locals = append_list(dmb, locals)?;
    let mut arguments = Vec::with_capacity(prefix.len().saturating_mul(4));
    for name in prefix {
        let name = strings.intern(dmb, name.as_bytes())?;
        let id = u32::try_from(dmb.variables.len())
            .map_err(|_| unsupported("helper formal overflow"))?;
        dmb.variables.push(Variable {
            kind: 0,
            value: 0,
            name,
        });
        // Actual 516.1687 helper formals include preceding and referenced names. The
        // owner's declared types/defaults/value sources are intentionally absent.
        arguments.extend_from_slice(&[0, 0, id, 0]);
    }
    let args = append_list(dmb, arguments)?;
    dmb.procs.push(Proc {
        strings: [NONE; 4],
        source_parameter: 255,
        source_kind: 0,
        flags: 4,
        extended_flags: None,
        code_locals_args: [code, locals, args],
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn current_helper_emission_uses_only_preceding_names_with_zero_metadata() {
        let (mut batch, _) = super::super::tests::ownership_fixture_source(
            "/proc/helper_prefix_owner()\n    return 7\n",
        );
        let identity = batch.units[0].lowered.identity;
        let frame = std::sync::Arc::make_mut(&mut batch.units[0].lowered.frame);
        frame.argument_names = vec!["first".into(), "second".into(), "third".into()];
        frame.argument_type_flags = vec![8, 2, 4];
        let slots = [procedure_plan::Slot {
            table_index: batch
                .tables
                .index(crate::symbolic::unit_key(identity))
                .unwrap(),
            identity,
            artifact: Some(0),
        }];
        for argument in 0..3 {
            let names = prefix(&batch, &slots, identity, argument, 0).unwrap();
            assert_eq!(names.len(), argument as usize);
            let mut dmb =
                Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin"))
                    .unwrap();
            let mut strings = StringIndex::build(&dmb).unwrap();
            let code = vec![0x50, 7, 0x12, 0];
            let proc_id = dmb.procs.len();
            emit(&mut dmb, &mut strings, code.clone(), &[], names).unwrap();
            assert_eq!(dmb.proc_code_words(proc_id).unwrap(), code);
            let rows = dmb.proc_arguments(proc_id).unwrap();
            assert_eq!(rows.len(), argument as usize);
            for (index, row) in rows.iter().enumerate() {
                assert_eq!((row.type_flags, row.value_source, row.reserved), (0, 0, 0));
                assert_eq!(
                    dmb.string(dmb.variables[row.variable_id as usize].name),
                    Some(names[index].as_bytes())
                );
            }
            dmb.validate_references().unwrap();
        }
        assert!(prefix(&batch, &slots, identity, 3, 0).is_err());
        assert_eq!(prefix(&batch, &slots, identity, 0, 1).unwrap(), &["first"]);
        assert_eq!(
            prefix(&batch, &slots, identity, 2, 3).unwrap(),
            &["first", "second", "third"]
        );
        assert!(prefix(&batch, &slots, identity, 0, 4).is_err());
        let mut foreign = identity;
        foreign.name = SymbolId::of("foreign_helper_owner");
        assert!(prefix(&batch, &slots, foreign, 1, 0).is_err());
        let bad_slots = [procedure_plan::Slot {
            identity: foreign,
            ..slots[0]
        }];
        assert!(prefix(&batch, &bad_slots, identity, 1, 0).is_err());
    }
}
