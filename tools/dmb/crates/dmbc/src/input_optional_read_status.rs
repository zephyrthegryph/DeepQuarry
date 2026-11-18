//! Exact optional-reader DATA on the existing immutable read-observation spine.
//! Optional outcomes never issue Original readability, payload, source or EOF.
use super::*;
#[derive(Clone,Copy,Debug,Eq,PartialEq,Serialize,Deserialize)]pub enum OptionalReadPhase{Open,Read}
#[derive(Clone,Copy,Debug,Eq,PartialEq,Serialize,Deserialize)]pub enum OptionalReadStatus{Readable,NoText{phase:OptionalReadPhase,raw:i32}}
impl OptionalReadStatus{
 pub(super) fn os_failure(phase:OptionalReadPhase,error:io::Error)->io::Result<Self>{match error.raw_os_error(){Some(raw)=>Ok(Self::NoText{phase,raw}),None=>Err(error)}}
}
impl super::path_presence::ImmutableFactValue for OptionalReadStatus{}
pub enum OptionalInputRead{NoText(OptionalReadStatus),Read(CapturedInputRead)}
