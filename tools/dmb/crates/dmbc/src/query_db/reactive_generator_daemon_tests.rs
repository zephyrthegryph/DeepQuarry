use super::*;
#[test]
fn actual_generator_requests_reassemble_final_original_output_without_second_frontend_or_io(){
 use crate::daemon::query::{self,SourceQuery,encoded_bytes::{Continuity,Fragment}};
 let f=Fixture::new_generator();let tree=Arc::clone(&f._front.snapshot.tree);
 let expected=f.queries.with_workspace_generator_guard(&f.workspace,&f._snapshot.workspace_native_read().unwrap(),&f.capture,generator_policy::GeneratorName::Deps,|artifact|serde_json::to_vec(&artifact.output_wire()).map_err(io::Error::other)).unwrap();
 let before_io=f.reads.load(Ordering::Relaxed);let before_body=f.queries.db().stats(dm_query::Kind(4)).computed;
 let mut request=query::QueryRequest{timeout_seconds:Some(300),project:f.root.join("deepquarry.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",dm_analysis::tree_export::source_revision(&f._front))),expected_policy_revision:Some(format!("{:032x}",f.workspace.policy_revision())),queries:vec![],source_queries:vec![]};
 let state=QueryState{snapshot:Some(f._snapshot),last_request_outcome:"analyzed",publication_pair:None};
 let mut continuity=Continuity::new(64*1024*1024);let mut staged=Vec::new();let mut cursor=None;
 loop{
  request.source_queries=vec![SourceQuery::NativeGeneratorBytes{generator:generator_policy::GeneratorName::Deps,cursor,limit:97}];
  let roundtrip:query::QueryRequest=serde_json::from_slice(&serde_json::to_vec(&request).unwrap()).unwrap();
  let reply=query::evaluate_snapshot(&roundtrip,&tree,&state).unwrap();query::validate_effect_batch_for_test(&roundtrip,&reply).unwrap();
  let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();let fragment:Fragment=serde_json::from_value(row["fragment"].clone()).unwrap();let bytes:Vec<u8>=serde_json::from_value(row["bytes"].clone()).unwrap();cursor=continuity.accept(fragment,&bytes,&mut staged).unwrap();if cursor.is_none(){break}
 }
 continuity.finish().unwrap();assert_eq!(staged,expected);assert_eq!(f.reads.load(Ordering::Relaxed),before_io);assert_eq!(f.queries.db().stats(dm_query::Kind(4)).computed,before_body);
 let mut stale=request.clone();stale.expected_policy_revision=Some("0".repeat(32));assert!(query::evaluate_snapshot(&stale,&tree,&state).is_err());
 let mut unrequested=request;unrequested.source_queries=vec![SourceQuery::NativeGeneratorBytes{generator:generator_policy::GeneratorName::Reads,cursor:None,limit:97}];assert!(query::evaluate_snapshot(&unrequested,&tree,&state).is_err());
}
