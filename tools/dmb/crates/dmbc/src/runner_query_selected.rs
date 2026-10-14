//! Bounded current-source rows issued by the ordinary selected-reference producer.
use std::{
    collections::BTreeMap,
    io::{self, Write},
};
#[derive(Default)]
pub(super) struct SelectedRows {
    rows: BTreeMap<u32, Vec<u8>>,
    bytes: usize,
}
const LIMIT: usize = crate::daemon::query::MAX_OUTPUT;
const ROW_LIMIT: usize = (LIMIT - 4096) / 6;
struct Limited(Vec<u8>);
impl Write for Limited {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if bytes.len() > ROW_LIMIT.saturating_sub(self.0.len()) {
            return Err(io::Error::other("selected snapshot row exceeds limit"));
        }
        self.0.extend_from_slice(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}
impl SelectedRows {
    pub(super) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        census.observe_items("query_snapshot.selected_rows", self.rows.len());
        census.unknown(
            "query_snapshot.selected_rows",
            "BTreeMap node capacity and allocator overhead are not exposed",
        );
        for bytes in self.rows.values() {
            census.vec_payload("query_snapshot.selected_rows", bytes);
        }
    }
    pub(super) fn contains(&self, ordinal: u32) -> bool {
        self.rows.contains_key(&ordinal)
    }
    pub(super) fn capture(&mut self, current: &crate::selected_query::CurrentProcedureReferences) {
        if self.rows.len() >= 256 {
            return;
        }
        let mut row = Limited(Vec::new());
        if current.write_jsonl(&mut row).is_err() || row.0.len() > LIMIT.saturating_sub(self.bytes)
        {
            return;
        }
        let ordinal = current.occurrence().declaration.0;
        if self.rows.contains_key(&ordinal) {
            return;
        }
        self.bytes += row.0.len();
        self.rows.insert(ordinal, row.0);
    }
    pub(super) fn write_current(
        current: &crate::selected_query::CurrentProcedureReferences,
        revision: u128,
        output: &mut impl Write,
    ) -> io::Result<()> {
        let mut bytes = Limited(Vec::new());
        current.write_jsonl(&mut bytes).map_err(io::Error::other)?;
        Self::write_envelope(
            current.occurrence().declaration.0,
            revision,
            &bytes.0,
            output,
        )
    }
    pub(super) fn write(
        &self,
        ordinal: u32,
        revision: u128,
        output: &mut impl Write,
    ) -> io::Result<()> {
        let row = self.rows.get(&ordinal).ok_or_else(|| io::Error::new(io::ErrorKind::NotFound,
            "selected references were not captured for this procedure; analyze --resolved first (bounded snapshot may omit rows)"))?;
        Self::write_envelope(ordinal, revision, row, output)
    }
    fn write_envelope(
        ordinal: u32,
        revision: u128,
        row: &[u8],
        output: &mut impl Write,
    ) -> io::Result<()> {
        let captured = std::str::from_utf8(row).map_err(io::Error::other)?;
        serde_json::to_writer(
            &mut *output,
            &serde_json::json!({
                "schema":"dm-session-source-query-v1", "row":"source_selected_references",
                "source_revision":format!("{revision:032x}"), "occurrence":ordinal,
                "complete":false, "captured_jsonl":captured,
            }),
        )
        .map_err(io::Error::other)?;
        output.write_all(b"\n")
    }
}
