//! Exact request/response validation for explicitly admitted full generators.
use super::{QueryReply,QueryRequest,SourceQuery,encoded_bytes::{ByteCursor,Fragment,MAX_FRAGMENT}};
use serde_json::Value;
use std::io;
const MAX_ENCODED:u64=64*1024*1024;
pub(super) mod name {
 pub fn serialize<S:serde::Serializer>(name:&crate::GeneratorName,serializer:S)->Result<S::Ok,S::Error>{serializer.serialize_str(name.name())}
 pub fn deserialize<'de,D:serde::Deserializer<'de>>(deserializer:D)->Result<crate::GeneratorName,D::Error>{serde::Deserialize::deserialize(deserializer)}
}
fn invalid(message:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,message)}
pub(super) fn reads_policy(query:&SourceQuery)->bool{matches!(query,SourceQuery::NativeGeneratorBytes{..})}
pub(super) fn validate_request(request:&QueryRequest)->io::Result<()>{
 for query in &request.source_queries{if let SourceQuery::NativeGeneratorBytes{cursor,limit,..}=query{
  if request.expected_policy_revision.is_none()||*limit==0||*limit as usize>MAX_FRAGMENT{return Err(io::Error::new(io::ErrorKind::InvalidInput,"generator bytes need an exact policy pin and bounded fragment"))}
  if let Some(cursor)=cursor{cursor.validate(MAX_ENCODED)?;}
 }}Ok(())
}
pub(super) fn validate_requested(reply:&QueryReply,questions:&[SourceQuery])->io::Result<()>{
 let mut expected=questions.iter().filter(|query|reads_policy(query));
 for line in reply.jsonl.lines(){let row:Value=serde_json::from_str(line).map_err(io::Error::other)?;if row["row"]!="source_native_generator_bytes"{continue}
  let Some(SourceQuery::NativeGeneratorBytes{generator,cursor,limit})=expected.next()else{return Err(invalid("unrequested generator bytes"))};
  let keys=["row","schema","semantic_revision","source_revision","policy_revision","generator","full_generator_output","byte_fragment_only","output_format","requested_cursor","limit","fragment","bytes"];
  let object=row.as_object().ok_or_else(||invalid("generator byte row is not an object"))?;
  if object.len()!=keys.len()||keys.iter().any(|key|!object.contains_key(*key))||row["schema"]!="dm-session-source-query-v1"||row["semantic_revision"].as_str()!=Some(reply.revision.as_str())||reply.source_revision.is_none()||row["source_revision"].as_str()!=reply.source_revision.as_deref()||reply.policy_revision.is_none()||row["policy_revision"].as_str()!=reply.policy_revision.as_deref()||row["generator"]!=generator.name()||row["full_generator_output"]!=true||row["byte_fragment_only"]!=true||row["output_format"]!="native_generator_artifact_json"||row["requested_cursor"]!=serde_json::to_value(cursor).map_err(io::Error::other)?||row["limit"]!=*limit{return Err(invalid("generator reply differs from requested generator/frame"))}
  let fragment:Fragment=serde_json::from_value(row["fragment"].clone()).map_err(io::Error::other)?;
  let bytes=row["bytes"].as_array().ok_or_else(||invalid("generator fragment bytes missing"))?;
  let offset=cursor.map_or(0,|cursor|cursor.offset);
  let end=offset.checked_add(bytes.len()as u64).filter(|end|*end<=fragment.total).ok_or_else(||invalid("generator fragment extent differs"))?;
  if bytes.iter().any(|byte|byte.as_u64().is_none_or(|byte|byte>255))||bytes.len()>*limit as usize||fragment.length as usize!=bytes.len()||fragment.total==0||fragment.total>MAX_ENCODED||fragment.offset!=offset||fragment.end_of_output!=(end==fragment.total)||fragment.next!=(end<fragment.total).then_some(ByteCursor{output_id:fragment.output_id,total:fragment.total,offset:end})||!fragment.end_of_output&&bytes.len()!=*limit as usize||cursor.is_some_and(|cursor|cursor.output_id!=fragment.output_id||cursor.total!=fragment.total){return Err(invalid("generator byte identity/continuity differs"))}
 }
 if expected.next().is_some(){return Err(invalid("requested generator bytes missing"))}Ok(())
}
#[cfg(test)]mod tests{
 use super::*;
 #[test]fn generator_byte_request_canonical_wire_requires_pins_and_bounded_fragments(){
  let root=std::env::current_dir().unwrap();let mut request=QueryRequest{timeout_seconds:Some(300),project:root.join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some("1".repeat(32)),expected_source_revision:Some("2".repeat(32)),expected_policy_revision:Some("3".repeat(32)),queries:vec![],source_queries:vec![SourceQuery::NativeGeneratorBytes{generator:crate::GeneratorName::Deps,cursor:None,limit:97}]};
  let wire=serde_json::to_value(&request).unwrap();assert_eq!(wire["source_queries"][0]["NativeGeneratorBytes"]["generator"],"deps");let roundtrip:QueryRequest=serde_json::from_value(wire).unwrap();roundtrip.validate().unwrap();
  request.expected_policy_revision=None;assert!(request.validate().is_err());request.expected_policy_revision=Some("3".repeat(32));if let SourceQuery::NativeGeneratorBytes{limit,..}=&mut request.source_queries[0]{*limit=MAX_FRAGMENT as u32+1;}assert!(request.validate().is_err());
 }
}
