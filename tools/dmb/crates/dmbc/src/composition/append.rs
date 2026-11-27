//! Append-only string table extension for a relowered body's new literals (`crate::retained_output`,
//! body patches). Nothing already numbered moves; literal string ids are not observable.
use super::*;

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
