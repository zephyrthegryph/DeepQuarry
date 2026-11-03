//! Actual old HasLocation over the SAME interleaved source/expansion state.
//! Default is explicitly nonphysical; a macro invocation point is not forged
//! into a physical CODE/EOF receipt. Publisher validates its current plan owner.
use super::{original_macro_source::OriginalBorrowedMacroSource,original_raw_points::OriginalRawPoint,original_lexical_frame::OriginalLexicalFrameIdentity};
use crate::macro_expansion::{OriginalMacroCursor as Cursor,OriginalMacroOrigin as Origin};
use dm_syntax::SettingAdmission;use std::io;
pub(super) enum OriginalCurrentLocation{
 Expansion(Origin),
 Physical{frame:OriginalLexicalFrameIdentity,occurrence:usize,point:OriginalRawPoint},
 /// Pinned IncludeStack empty location is Location::default(), not EOF on the
 /// most recently popped file and not an invented empty physical source.
 Default,
 /// Pinned Location::builtins(), distinct from the empty source stack default.
 Builtins,
}
pub(super) fn current_using(cursor:&Cursor<'static>,source:&mut OriginalBorrowedMacroSource<'_>,a:&SettingAdmission<'_>)->io::Result<OriginalCurrentLocation>{
 a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
 if let Some(origin)=cursor.current_expansion_origin(source){if origin.byte_column.is_none(){return Err(io::Error::new(io::ErrorKind::Unsupported,"actual expansion invocation point is unissued"))}return Ok(OriginalCurrentLocation::Expansion(origin))}
 source.inputs.with_current_read_point(source.provider,a,|frame,occurrence,point|Ok(OriginalCurrentLocation::Physical{frame:frame.clone(),occurrence,point})).map(|point|point.unwrap_or(OriginalCurrentLocation::Default))
}
