use super::*;
use serde::Serialize;
#[derive(Default, Serialize)]
pub struct OwnerReport {
    pub owner: String,
    pub unique_payload_bytes: u64,
    pub unique_known_capacity_bytes: u64,
    pub unique_file_backed_bytes: u64,
    pub unknown_capacity_payload_bytes: u64,
    pub unique_allocations: u64,
    pub shared_encounters: u64,
    pub observed_items: u64,
    pub unknown: BTreeSet<String>,
}
#[derive(Serialize)]
pub struct HeapCensusReport {
    pub schema: u32,
    pub stage: String,
    pub scope: &'static str,
    pub unique_known_capacity_bytes: u64,
    pub unique_file_backed_bytes: u64,
    pub unknown_capacity_payload_bytes: u64,
    pub rust_requested_live_bytes: Option<u64>,
    pub owners: Vec<OwnerReport>,
    pub limitations: Vec<&'static str>,
    pub frozen_code_metrics: relocation_metrics::RelocationMetrics,
}
