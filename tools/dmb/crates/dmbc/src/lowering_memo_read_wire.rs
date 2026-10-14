//! One canonical dependency-answer wire view shared by compact and failure records.
use dm_ir::ResolveQuery;
use serde::{Deserialize, Serialize};
use std::borrow::Cow;
#[derive(Serialize, Deserialize)]
pub(crate) struct ReadWire<'a> {
    pub(crate) query: ResolveQuery,
    #[serde(borrow)]
    pub(crate) answer: Cow<'a, [u8]>,
}
pub(super) trait CanonicalRead {
    fn query(&self) -> ResolveQuery;
    fn answer(&self) -> &[u8];
}
impl CanonicalRead for ReadWire<'_> {
    fn query(&self) -> ResolveQuery {
        self.query
    }
    fn answer(&self) -> &[u8] {
        &self.answer
    }
}
impl CanonicalRead for (ResolveQuery, Vec<u8>) {
    fn query(&self) -> ResolveQuery {
        self.0
    }
    fn answer(&self) -> &[u8] {
        &self.1
    }
}
