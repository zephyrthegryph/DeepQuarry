use super::*;

#[test]
fn coverage_counts_omissions_independently_of_unowned_diagnostics() {
    let mut totals = CoverageTotals {
        requested: 5,
        ..Default::default()
    };
    totals.returned(2, 1).unwrap();
    totals.returned(3, 4).unwrap();
    let mut bytes = Vec::new();
    // One diagnostic need not identify any particular omitted procedure.
    coverage(&mut bytes, &totals, 1, "partial").unwrap();
    let row: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(row["procedures"], 2);
    assert_eq!(row["requested_procedures"], 5);
    assert_eq!(row["returned_procedures"], 2);
    assert_eq!(row["omitted_procedures"], 3);
    assert_eq!(row["diagnostics"], 1);
    assert_eq!(row["unbound_selections"], 5);
    assert_eq!(row["unavailable_coordinate_markers"], 5);
    assert_eq!(row["semantic_resolution_complete"], false);
}

#[test]
fn coverage_rejects_impossible_counts_before_writing_a_summary() {
    let totals = CoverageTotals {
        requested: 1,
        returned: 2,
        ..Default::default()
    };
    let mut bytes = Vec::new();
    assert!(coverage(&mut bytes, &totals, 0, "partial").is_err());
    assert!(bytes.is_empty());
}
