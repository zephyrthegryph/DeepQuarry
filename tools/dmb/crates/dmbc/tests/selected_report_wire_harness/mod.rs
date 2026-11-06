pub use dmbc::daemon::{analyze, query};

mod selected_exclusions {
    pub type Request = serde_json::Value;
}

pub mod generation {
    // Unrelated frame variants are not exercised in this codec-only harness.
    pub type GenerationRequest = serde_json::Value;
    pub type GenerationTerminal = serde_json::Value;
    pub type GenerationAbort = serde_json::Value;
    pub use dmbc::daemon::generation::MAX_REPORT_BYTES;
}

#[path = "../../src/daemon/control.rs"]
pub(crate) mod control;
#[path = "../../src/daemon/retained_rejection.rs"]
mod retained_rejection;
#[path = "../../src/daemon/protocol.rs"]
mod protocol;
#[path = "../../src/daemon/selected_report_wire.rs"]
mod selected_report_wire;
