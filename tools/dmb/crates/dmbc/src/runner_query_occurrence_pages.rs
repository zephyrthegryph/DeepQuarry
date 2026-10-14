//! Bounded enumeration over the existing current occurrence issuer.
use super::SourceSnapshot;
use std::io::{self, Write};
impl SourceSnapshot {
    pub(crate) fn write_occurrences_page(
        &self,
        start: u32,
        limit: u32,
        tree: &dm_tree::SemanticTree,
        output: &mut impl Write,
    ) -> io::Result<()> {
        self.write_source_page(start, limit, tree, output, false)
    }
    pub(crate) fn write_body_contexts_page(
        &self,
        start: u32,
        limit: u32,
        tree: &dm_tree::SemanticTree,
        output: &mut impl Write,
    ) -> io::Result<()> {
        self.write_source_page(start, limit, tree, output, true)
    }
    fn write_source_page(
        &self,
        start: u32,
        limit: u32,
        tree: &dm_tree::SemanticTree,
        output: &mut impl Write,
        body_contexts: bool,
    ) -> io::Result<()> {
        if !self.matches_tree(tree) {
            return Err(io::Error::other(
                "source page tree differs from admitted snapshot",
            ));
        }
        if !(1..=128).contains(&limit) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "occurrence page limit must be 1..128",
            ));
        }
        let bodies = if body_contexts {
            Some(self.bodies.as_ref().ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::NotFound,
                    "current issued body contexts unavailable",
                )
            })?)
        } else {
            None
        };
        let total = u32::try_from(bodies.map_or_else(
            || self.occurrences.source_order().len(),
            |bodies| bodies.len(),
        ))
        .map_err(|_| io::Error::other("occurrence roster exceeds ordinal range"))?;
        if start > total {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "occurrence page cursor exceeds current roster",
            ));
        }
        let end = start.saturating_add(limit).min(total);
        let next = (end < total).then_some(end);
        let mut header = serde_json::to_vec(&serde_json::json!({"schema":"dm-session-source-query-v1", "row":if body_contexts {"source_body_contexts_page"} else {"source_occurrences_page"}, "source_revision":format!("{:032x}",self.source_revision), "start":start,"limit":limit,"total":total,"returned":end-start,"next_cursor":next,"page_complete":true,"complete":false})).map_err(io::Error::other)?;
        assert_eq!(header.pop(), Some(b'}'));
        output.write_all(&header)?;
        output.write_all(b",\"items\":[")?;
        for ordinal in start..end {
            crate::daemon::control::checkpoint()?;
            if ordinal != start {
                output.write_all(b",")?;
            }
            let row = if let Some(bodies) = bodies {
                let mut row =
                    dm_analysis::tree_export::source_body_row(tree, &bodies[ordinal as usize])
                        .map_err(io::Error::other)?;
                row["schema"] = "dm-session-source-query-v1".into();
                row["source_revision"] = format!("{:032x}", self.source_revision).into();
                row["ordinal"] = ordinal.into();
                row["executable_facts_included"] = false.into();
                row
            } else {
                self.occurrence(ordinal, tree)?
            };
            serde_json::to_writer(&mut *output, &row).map_err(io::Error::other)?;
        }
        output.write_all(b"]}\n")
    }
}
