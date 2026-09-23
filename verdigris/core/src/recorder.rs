//! The flight recorder (`rust_core.md` §11): a ring buffer of the last N
//! frames' command batches and the sim metrics at each, dumped on a frame
//! panic or on demand.
//!
//! It sits on top of a recording [`Sim`] (`SimConfig::record`): call
//! [`capture`](FlightRecorder::capture) once per tick after
//! `dispatch_frame`. It moves the sim's log into the ring, so memory stays
//! bounded at `capacity` frames. While the ring still holds frame 0 its
//! dump is a complete log that the replay tool can verify; after it wraps,
//! the dump is diagnostic only (no base state to replay from).

use std::collections::VecDeque;
use std::fmt::Write as _;

use crate::replay::{DomainCodec, encode_log};
use crate::sim::{FrameRecord, Sim, SimMetrics};

/// A bounded log of recent frames.
pub struct FlightRecorder {
    capacity: usize,
    seed: u64,
    frames: VecDeque<(FrameRecord, SimMetrics)>,
    evicted: u64,
    panics_seen: u64,
}

impl FlightRecorder {
    #[must_use]
    pub fn new(capacity: usize, seed: u64) -> Self {
        Self {
            capacity: capacity.max(1),
            seed,
            frames: VecDeque::new(),
            evicted: 0,
            panics_seen: 0,
        }
    }

    /// Moves the frames `sim` recorded since the last call into the ring,
    /// each with the current metrics. Returns `true` if a frame panicked
    /// since the last call: the caller should dump.
    pub fn capture(&mut self, sim: &mut Sim) -> bool {
        let metrics = sim.metrics().clone();
        if let Some(log) = sim.take_log() {
            for record in log.frames {
                if self.frames.len() == self.capacity {
                    self.frames.pop_front();
                    self.evicted += 1;
                }
                self.frames.push_back((record, metrics.clone()));
            }
        }
        let panicked = metrics.frame_panics > self.panics_seen;
        self.panics_seen = metrics.frame_panics;
        panicked
    }

    #[must_use]
    pub fn len(&self) -> usize {
        self.frames.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.frames.is_empty()
    }

    /// Whether the ring still starts at the session's first frame, so its
    /// dump replays from an empty world.
    #[must_use]
    pub fn complete(&self) -> bool {
        self.evicted == 0
    }

    /// A binary `.vglog` of the buffered frames (see [`crate::replay`]),
    /// with `hashes` from [`crate::replay::state_hashes`] if the caller has
    /// settled the sim, else empty.
    #[must_use]
    pub fn dump_log(
        &self,
        scenario: &str,
        codecs: &[Box<dyn DomainCodec>],
        hashes: &[u64],
    ) -> Vec<u8> {
        encode_log(
            scenario,
            self.seed,
            self.frames.iter().map(|(r, _)| r),
            codecs,
            hashes,
        )
    }

    /// A human-readable dump: per frame, the metrics and every command.
    #[must_use]
    pub fn dump_text(&self, codecs: &[Box<dyn DomainCodec>]) -> String {
        let mut out = format!(
            "flight recorder: {} frames (evicted {}, complete: {})\n",
            self.frames.len(),
            self.evicted,
            self.complete()
        );
        for (record, m) in &self.frames {
            let _ = writeln!(
                out,
                "frame {}: last_frame={:?} backlog={} view_age={} skipped={} panics={}{}",
                record.frame,
                m.last_frame,
                m.command_backlog,
                m.view_age_ticks,
                m.dispatches_skipped,
                m.frame_panics,
                m.last_panic
                    .as_ref()
                    .map(|p| format!(" last_panic={p:?}"))
                    .unwrap_or_default(),
            );
            for (codec, batch) in codecs.iter().zip(record.batches()) {
                if let Some(batch) = batch {
                    for line in codec.describe_batch(batch.as_ref()) {
                        let _ = writeln!(out, "  {}: {line}", codec.name());
                    }
                }
            }
        }
        out
    }
}
