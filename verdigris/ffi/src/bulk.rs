//! Bulk registration straight into a domain's live store (Phase 4b).
//!
//! Round-start registration (`setup_allturfs()`: every turf's gas and heat)
//! used to queue one command and one overlay entry per cell, which held the
//! whole batch twice until the next frame and then made the first frames copy
//! every chunk: 180 MB of the Southern Cross boot and most of its 384 MB
//! peak. A bulk bind opens a [`Direct`] buffer per domain, the per-cell code
//! pushes into it instead of the port, and [`Direct::flush`] writes the rows
//! with [`Sim::write_direct`](vg_core::sim::Sim::write_direct). When the domain
//! is not quiescent (a frame in flight, DM writes pending) the rows go through
//! the port as before, so the result is the same either way.

use vg_core::owner::{Domain, DomainKey};
use vg_core::world::World;

/// Rows buffered for one domain during a bulk bind.
pub(crate) struct Direct<D: Domain> {
    key: DomainKey<D>,
    rows: Vec<(u32, D::Value)>,
}

impl<D: Domain> Direct<D> {
    pub(crate) fn new(key: DomainKey<D>) -> Self {
        Self {
            key,
            rows: Vec::new(),
        }
    }

    pub(crate) fn push(&mut self, cell: u32, value: D::Value) {
        self.rows.push((cell, value));
    }

    /// Writes every buffered row: into the live store when the domain is
    /// quiescent, else through the port. Returns whether the direct path ran.
    pub(crate) fn flush(self, w: &mut World) -> bool {
        let Self { key, rows } = self;
        if rows.is_empty() {
            return true;
        }
        let mut pending = Some(rows);
        let shared = w.sim_mut().write_direct(key, |store| {
            let layout = store.layout();
            let mut touched = Vec::new();
            for (cell, value) in pending.take().unwrap_or_default() {
                if let Some((chunk, _)) = layout.locate(cell) {
                    if touched.last() != Some(&chunk) {
                        touched.push(chunk);
                    }
                }
                store.set(cell, value);
            }
            touched.sort_unstable();
            touched.dedup();
            // Space is most of a station grid: its identical vacuum
            // chunks share one allocation instead of one each.
            store.share_uniform_chunks(&touched)
        });
        let metrics = crate::metrics::registry();
        if let Some(rows) = pending {
            // Not quiescent: the same rows through commands and the overlay.
            metrics.counter("bulk.port_fallback_flushes").inc();
            metrics
                .counter("bulk.port_fallback_rows")
                .add(rows.len() as u64);
            let port = w.sim_mut().port(key);
            for (cell, value) in rows {
                let _ = port.put(cell, value);
            }
        } else {
            metrics.counter("bulk.direct_flushes").inc();
        }
        if let Some(n) = shared {
            metrics.counter("bulk.shared_uniform_chunks").add(n as u64);
        }
        shared.is_some()
    }
}
