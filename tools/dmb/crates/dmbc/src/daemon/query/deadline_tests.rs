use super::*;

#[test]
fn legacy_query_budget_and_explicit_demand_limit() {
    let json = r#"{"project":"probe.dme","defines":{},"engine_template":null,"bootstrap_catalog":false,"expected_revision":null,"queries":[]}"#;
    let mut request: QueryRequest = serde_json::from_str(json).unwrap();
    assert_eq!(request.timeout().unwrap().as_secs(), 20);
    request.timeout_seconds = Some(300);
    assert_eq!(request.timeout().unwrap().as_secs(), 300);
    request.validate().unwrap();
    for invalid in [0, 301, u16::MAX] {
        request.timeout_seconds = Some(invalid);
        assert_eq!(
            request.validate().unwrap_err().kind(),
            io::ErrorKind::InvalidInput
        );
    }
}
