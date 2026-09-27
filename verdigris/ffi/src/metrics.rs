//! The DLL's metrics registry (`rust_core.md` §11) and its one read bind.
use std::sync::{Arc, OnceLock};

use byondapi::prelude::*;
use eyre::Result;
use vg_core::metrics::MetricsRegistry;

static METRICS: OnceLock<Arc<MetricsRegistry>> = OnceLock::new();

/// The process-wide registry every Rust domain records into.
pub fn registry() -> &'static Arc<MetricsRegistry> {
    METRICS.get_or_init(|| Arc::new(MetricsRegistry::new()))
}

/// Refreshes the sampled gauges (allocator, jobs) and returns every metric
/// as one JSON object.
pub fn snapshot_json() -> String {
    let metrics = registry();
    metrics.record_alloc_tags(crate::allocator::tag_counters());
    let (current, peak) = crate::allocator::diagnostics();
    #[allow(clippy::cast_precision_loss)]
    {
        metrics
            .gauge("alloc.heap.current_bytes")
            .set(current as f64);
        metrics.gauge("alloc.heap.peak_bytes").set(peak as f64);
        metrics
            .gauge("jobs.pending")
            .set(crate::jobs::registry().pending() as f64);
    }
    // The world's scheduler (the OM world step's Rust side), sampled like the rest.
    let _ = crate::world::with_world(|w| {
        let r = w.sched_metrics();
        let (received, merged, delivered, deferred, _) = w.sched_lanes();
        #[allow(clippy::cast_precision_loss)]
        for (name, v) in [
            ("world_sched.timers_pending", r.timers_pending as f64),
            ("world_sched.timers_fired", r.timers_fired as f64),
            ("world_sched.crossings_fired", r.crossings_fired as f64),
            ("world_sched.publications", r.publications as f64),
            ("world_sched.models", r.models as f64),
            ("world_sched.subscriptions", w.subscriptions(None) as f64),
            ("world_sched.wakes_received", received as f64),
            ("world_sched.wakes_merged", merged as f64),
            ("world_sched.wakes_delivered", delivered as f64),
            ("world_sched.wakes_deferred", deferred as f64),
        ] {
            metrics.gauge(name).set(v);
        }
        Ok(())
    });
    metrics.to_json()
}

/// Every Rust metric in one call: a JSON object mapping each name to a
/// number (counters, gauges) or `{count,sum,max,bounds,buckets}`
/// (histograms). Includes `alloc.<tag>.current_bytes` / `peak_bytes` per
/// allocator tag and `alloc.heap.*` for the whole Rust heap.
#[auxmacros::bind("/proc/verdigris_metrics")]
fn verdigris_metrics() -> Result<ByondValue> {
    Ok(ByondValue::new_str(snapshot_json())?)
}
