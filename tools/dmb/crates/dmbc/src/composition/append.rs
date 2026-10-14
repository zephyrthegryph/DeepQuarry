//! Stable-numbering append of new procedures into the retained composed model
//! (doc/structural_change_set.md, addendum). Indices come from append-only
//! link-table extension; nothing already numbered moves.
use super::*;
use crate::symbolic::FrozenUnit;

pub(crate) struct NewProcedure {
    pub unit: FrozenUnit,
    pub words: std::sync::Arc<Vec<u32>>,
    /// Index the extended link tables assigned to this unit's key.
    pub index: u32,
    /// Formal declaration (`proc/x`) rather than an override.
    pub declared: bool,
}

/// Table strings bound by the extension, in index order (as composition does).
pub(crate) fn append_table_strings(
    dmb: &mut Dmb,
    strings: &[(u32, Vec<u8>)],
) -> Result<(), CompositionError> {
    for (index, data) in strings {
        while dmb.strings.len() < *index as usize
            && dm_link::is_reserved_string_index(dmb.strings.len() as u32)
        {
            dmb.strings.push(DmString {
                data: Vec::new(),
                long_chunks: 0,
            });
        }
        if *index as usize != dmb.strings.len() {
            return Err(CompositionError::NonContiguous("appended string indexes".into()));
        }
        let chunks =
            u16::try_from(data.len() / 65535).map_err(|_| unsupported("string too large"))?;
        dmb.strings.push(DmString {
            data: data.clone(),
            long_chunks: chunks,
        });
    }
    Ok(())
}

/// Emit each new procedure record exactly as composition's procedure loop.
pub(crate) fn emit_procedures(
    dmb: &mut Dmb,
    string_index: &mut StringIndex,
    tables: &dm_link::LinkTables,
    symbols: &SymbolTable,
    procedures: Vec<NewProcedure>,
) -> Result<(), CompositionError> {
    let references = dm_link::ArgumentSourceReferences::none();
    let _ = tables;
    for procedure in procedures {
        reserve_procedure_sentinel(dmb);
        if procedure.index as usize != dmb.procs.len() {
            return Err(CompositionError::NonContiguous("appended procedure index".into()));
        }
        let mut metadata = procedure_plan::metadata(&procedure.unit, None, symbols, &references)?;
        metadata.declared = Some(procedure.declared);
        metadata.path = procedure
            .unit
            .metadata_recipe
            .path(symbols, procedure.declared);
        frame_contribution::emit(
            dmb,
            string_index,
            &procedure.unit,
            procedure.words,
            metadata,
            true,
        )?;
    }
    Ok(())
}
