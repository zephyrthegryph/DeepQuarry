//! String table slots a body patch gives other content (`crate::retained_output`): a relowered body's replaced literals
//! take the slots of the strings they replace, as a fresh link of the patched program numbers them
//! (`dm_link::LinkTables::replaced_unit_strings`). No other slot moves.
use super::*;

/// Give each `(index, bytes)` slot of the table its new content.
pub(crate) fn replace_table_strings(
    dmb: &mut Dmb,
    strings: &[(u32, Vec<u8>)],
) -> Result<(), CompositionError> {
    for (index, data) in strings {
        let chunks =
            u16::try_from(data.len() / 65535).map_err(|_| unsupported("string too large"))?;
        let slot = dmb
            .strings
            .get_mut(*index as usize)
            .ok_or_else(|| CompositionError::NonContiguous("replaced string index".into()))?;
        *slot = DmString {
            data: data.clone(),
            long_chunks: chunks,
        };
    }
    Ok(())
}
