//! Render authentic Original notices directly from their resource-held owner.
//! No intermediate diagnostic Vec, expanded-span invention, sorting or dedup.
use dm_tree::frontend::{OriginalDiagnosticPoint,OriginalPreprocessNotices};
use dm_preprocess::regions::OriginalNoticeSeverity;
use std::io::{self,Write};
fn invalid(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,message)}
fn at(out:&mut impl Write,point:OriginalDiagnosticPoint<'_>)->io::Result<()>{match point{
 OriginalDiagnosticPoint::Default=>write!(out,"(builtins):0:0"),
 OriginalDiagnosticPoint::Builtins=>write!(out,"(builtins):1:1"),
 OriginalDiagnosticPoint::Acquired{reported_path,line,byte_column,..}=>write!(out,"{}:{line}:{byte_column}",reported_path.display()),
}}
/// The caller keeps the same authentic preparation alive for the entire write.
/// Write errors propagate unchanged, including the first operational OS error.
pub fn write_original_preprocess_notices(out:&mut impl Write,notices:&OriginalPreprocessNotices<'_>)->io::Result<()>{
 for notice in notices.iter(){let notice=notice.map_err(invalid)?;
  at(out,notice.point)?;
  let severity=match notice.severity{OriginalNoticeSeverity::Error=>{super::count_error();"error"},OriginalNoticeSeverity::Warning=>{super::count_warning(notice.error_type);"warning"},OriginalNoticeSeverity::Hint=>"hint"};
  write!(out,":{severity}")?;if let Some(kind)=notice.error_type{write!(out," ({kind})")?;}writeln!(out,": {}",notice.message)?;
  for note in notice.notes{let(point,message)=note.map_err(invalid)?;at(out,point)?;writeln!(out,":note: {message}")?;}
 }
 Ok(())
}
