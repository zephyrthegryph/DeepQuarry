use super::*;
use serde_json::json;
fn fixture() -> (QueryReply, Vec<SourceQuery>, Value) {
    let root = std::env::current_dir().unwrap();
    let config = root.join("tools/ci/lint_scopes.toml");
    let questions = vec![SourceQuery::NativeWorkspaceRawPolicy {
        root: root.clone(),
        configuration: config.clone(),
        lints: vec!["scheduler".into()],
        cursor: None,
        limit: 128,
    }];
    let mut row = json!({"row":"source_native_workspace_raw_policy","schema":"dm-session-source-query-v1","source_revision":"s","policy_revision":"p","semantic_revision":"r","snapshot_as_of":"policy_revision","root":root,"configuration":config,"recursive_roots":[root.join("code")],"requested_lints":["scheduler"],"lint_whitelist":dq_analyze::captured_raw_policy::RAW_FILE_LINTS,"scope":"typed_discovery_raw_files","full_policy_parity":false,"baseline_applied":false,"admission":"raw_findings","configuration_scope":"proven_missing_configuration","aggregate_id":"11111111111111111111111111111111","offset":0,"count":1,"total_items":1,"next_cursor":null,"items":[{"lint":"scheduler","kind":"site","site":{"rule":"sleep","rel":"code/a.dm","line":2,"msg":"message","key":"","ident":""}}]});
    row["policy_scopes"]=json!([["scheduler","[[],[],[],{},{},{},[]]"]]);
    row["items"][0]["source_text"]=json!("sleep(1)");
    let reply = QueryReply {
        schema: "unused".into(),
        revision: "r".into(),
        complete: false,
        coverage: "partial".into(),
        query_count: 0,
        source_query_count: 1,
        source_revision: Some("s".into()),
        policy_revision: Some("p".into()),
        snapshot_outcome: "analyzed".into(),
        last_request_outcome: "analyzed".into(),
        publication_pair: None,
        jsonl: format!("{row}\n"),
    };
    (reply, questions, row)
}
#[test]
fn exact_workspace_pages_are_snapshot_as_of_not_live_disk_or_full_semantic_parity() {
    let (reply, questions, _) = fixture();
    validate_requested(&reply, &questions).unwrap();
}
#[test]
fn stale_foreign_extra_and_nonprogress_pages_are_refused() {
    for (key, value) in [
        ("policy_revision", json!("foreign")),
        ("snapshot_as_of", json!("live_disk")),
        ("offset", json!(1)),
        ("count", json!(0)),
        ("total_items", json!(0)),
        ("full_policy_parity", json!(true)),
        ("extra", json!(1)),
    ] {
        let (mut reply, questions, mut row) = fixture();
        row[key] = value;
        reply.jsonl = format!("{row}\n");
        assert!(validate_requested(&reply, &questions).is_err(), "{key}");
    }
    let (mut reply, questions, row) = fixture();
    reply.jsonl = format!("{row}\n{row}\n");
    assert!(validate_requested(&reply, &questions).is_err());
}
#[test]
fn record_kind_and_admitted_rule_shape_are_checked() {
    for change in 0..4 {
        let (mut reply, questions, mut row) = fixture();
        match change {
            0 => row["items"][0]["kind"] = json!("unknown"),
            1 => row["items"][0]["site"]["rule"] = json!("not_a_rule"),
            2 => row["items"][0]["site"]["line"] = json!(0),
            _ => row["items"][0]["lint"] = json!("player_link"),
        };
        reply.jsonl = format!("{row}\n");
        assert!(validate_requested(&reply, &questions).is_err());
    }
}

#[test]fn workspace_report_scope_and_digest_evidence_are_required_and_strictly_shaped(){
 for change in 0..9 {
  let(mut reply,questions,mut row)=fixture();
  match change {
   0=>{row.as_object_mut().unwrap().remove("policy_scopes");},
   1=>row["policy_scopes"]=json!([]),
   2=>row["policy_scopes"][0][0]=json!("player_link"),
   3=>row["policy_scopes"][0][1]=json!("not JSON"),
   4=>row["policy_scopes"][0][1]=json!("[[],[],[],{},{},{},[],9]"),
   5=>row["policy_scopes"][0][1]=json!("[[],[],[],{},{},{\"sleep\":true},[]]"),
   6=>{row["items"][0].as_object_mut().unwrap().remove("source_text");},
   7=>row["items"][0]["source_text"]=json!(7),
   _=>row["items"][0]["unrequested_evidence"]=json!("extra"),
  }
  reply.jsonl=format!("{row}\n");assert!(validate_requested(&reply,&questions).is_err(),"mutation {change}");
 }
 let(mut reply,questions,mut row)=fixture();row["items"][0]=json!({"lint":"scheduler","kind":"allow","allow":{"rel":"code/a.dm","line":2,"name":"scheduler","code":""},"source_digest":"000102030405060708090a0b0c0d0e0f101112ff"});reply.jsonl=format!("{row}\n");validate_requested(&reply,&questions).unwrap();
 for digest in [json!(null),json!(""),json!("00"),json!("000102030405060708090A0B0C0D0E0F101112FF"),json!("z00102030405060708090a0b0c0d0e0f101112ff")]{row["items"][0]["source_digest"]=digest;reply.jsonl=format!("{row}\n");assert!(validate_requested(&reply,&questions).is_err());}
}

#[test]fn workspace_scope_streaming_accepts_wide_empty_lists_and_escaped_tokens_without_owned_inner_dom(){
 let(mut reply,questions,mut row)=fixture();
 let mut wide=String::from("[[],[],[],{},{},{},[");for index in 0..100_000{if index!=0{wide.push(',')}wide.push_str("\"\"");}wide.push_str("]]");
 row["policy_scopes"][0][1]=json!(wide);reply.jsonl=format!("{row}\n");assert!(reply.jsonl.len()<super::super::MAX_OUTPUT);validate_requested(&reply,&questions).unwrap();
 let escaped="quote\" backslash\\ newline\n snow雪 emoji😺";
 let lists=std::collections::BTreeMap::from([(escaped,vec![escaped])]);let tables=std::collections::BTreeMap::from([(escaped,std::collections::BTreeMap::from([(escaped,escaped)]))]);
 let projection=json!([[escaped],[escaped],[escaped],lists,tables,{"minimum":i64::MIN,"maximum":i64::MAX},[escaped]]);
 row["policy_scopes"][0][1]=json!(serde_json::to_string(&projection).unwrap());reply.jsonl=format!("{row}\n");validate_requested(&reply,&questions).unwrap();
 // A long escaped token uses serde's reusable scratch, not a String per row.
 let token="\\\n\"".repeat(30_000);let projection=json!([[],[],[],{},{},{},[token]]);row["policy_scopes"][0][1]=json!(serde_json::to_string(&projection).unwrap());reply.jsonl=format!("{row}\n");assert!(reply.jsonl.len()<super::super::MAX_OUTPUT);validate_requested(&reply,&questions).unwrap();
}
#[test]fn workspace_scope_streaming_rejects_wrong_counts_types_trailing_json_and_nested_payloads(){
 let(mut reply,questions,mut row)=fixture();
 let malformed=["[]","[[],[],[],{},{},{}]","[[],[],[],{},{},{},[],0]","[[],[],[],{},{},{},[]] []","[[],[],[],{\"key\":[1]},{},{},[]]","[[],[],[],{},{\"table\":{\"key\":false}},{},[]]","[[],[],[],{},{},{\"rule\":9223372036854775808},[]]","[[],[],[],{},{},{\"rule\":1.0},[]]","[[],[],[],{},{},{},[\"\\uD800\"]]"];
 for text in malformed{row["policy_scopes"][0][1]=json!(text);reply.jsonl=format!("{row}\n");assert!(validate_requested(&reply,&questions).is_err(),"{text}");}
 let deep=format!("{}0{}","[".repeat(160),"]".repeat(160));for text in [format!("[[],[],[],{{}},{{}},{{}},[{deep}]]"),format!("[[],[],[],{{}},{{}},{{}},[],{deep}]")]{row["policy_scopes"][0][1]=json!(text);reply.jsonl=format!("{row}\n");assert!(validate_requested(&reply,&questions).is_err());}
}
#[test]fn workspace_scope_streaming_preadmits_token_scratch_from_same_unchanged_report_reservation(){
 let valid="[[],[],[],{},{},{},[]]";let reserve=crate::query_db::QueryDb::workspace_raw_report_reserve();assert_eq!(reserve,4*1024*1024);
 assert_eq!(scope_projection(valid,reserve).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);
 // Known resource refusal precedes JSON work, and healthy controls recover.
 assert_eq!(scope_projection("not JSON",reserve).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);scope_projection(valid,0).unwrap();assert_eq!(scope_projection("not JSON",0).unwrap_err().kind(),std::io::ErrorKind::InvalidData);
 let value=json!({"a":["quoted\"",{},[1,2]],"b":"other"});assert!(report_value_backing(&value).unwrap()>0);
}

#[test]fn existing_raw_policy_and_complete_raw_report_notes_remain_valid_after_check_grep_extension(){
 let(mut reply,questions,mut row)=fixture();row["items"][0]=json!({"lint":"scheduler","kind":"note","text":"existing authenticated raw producer note"});reply.jsonl=format!("{row}\n");validate_requested(&reply,&questions).unwrap();
 let SourceQuery::NativeWorkspaceRawPolicy{root,configuration,lints,cursor,limit}=&questions[0]else{unreachable!()};let complete=vec![SourceQuery::NativeWorkspaceRawReportPage{root:root.clone(),configuration:configuration.clone(),lints:lints.clone(),cursor:cursor.clone(),limit:*limit}];row["row"]="source_native_workspace_raw_report".into();row["admission"]="complete_selected_raw_policy_findings".into();reply.jsonl=format!("{row}\n");validate_requested(&reply,&complete).unwrap();
}
