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
    // Per-bind FFI call and error counts (always on; two relaxed adds a call).
    let (mut calls_total, mut errors_total) = (0_u64, 0_u64);
    for (name, calls, errors) in auxcallback::panic_guard::snapshot() {
        metrics.counter(&format!("ffi.calls.{name}")).set(calls);
        calls_total += calls;
        errors_total += errors;
        if errors > 0 {
            metrics.counter(&format!("ffi.errors.{name}")).set(errors);
        }
    }
    metrics.counter("ffi.calls_total").set(calls_total);
    metrics.counter("ffi.errors_total").set(errors_total);
    // The world's scheduler (the OM world step's Rust side), sampled like the rest.
    let _ = crate::world::with_world(|w| {
        let r = w.sched_metrics();
        let (received, merged, delivered, deferred, _) = w.sched_lanes();
        #[allow(clippy::cast_precision_loss)]
        for (name, v) in [
            ("world_sched.timers_pending", r.timers_pending as f64),
            ("world_sched.crossings_fired", r.crossings_fired as f64),
            ("world_sched.models", r.models as f64),
            ("world_sched.subscriptions", w.subscriptions(None) as f64),
            ("world_sched.wakes_received", received as f64),
            ("world_sched.wakes_merged", merged as f64),
            ("world_sched.wakes_delivered", delivered as f64),
            ("world_sched.wakes_deferred", deferred as f64),
        ] {
            metrics.gauge(name).set(v);
        }
        // Which pool the frames ran on: the light pool (frames under LIGHT_FRAME) or the whole frame pool, and how many were skipped.
        let sim = w.sim().metrics();
        #[allow(clippy::cast_precision_loss)]
        for (name, v) in [
            ("sim.frames_dispatched", sim.frames_dispatched as f64),
            ("sim.frames_completed", sim.frames_completed as f64),
            ("sim.light_frames", sim.light_frames as f64),
            ("sim.dispatches_skipped", sim.dispatches_skipped as f64),
            ("sim.last_frame_us", sim.last_frame.as_micros() as f64),
            ("sim.max_frame_us", sim.max_frame.as_micros() as f64),
        ] {
            metrics.gauge(name).set(v);
        }
        // What each task of the frame has cost so far (wall microseconds and runs, summed over the frame pool's threads).
        #[allow(clippy::cast_precision_loss)]
        for (name, micros, runs) in vg_core::frame::task_times() {
            metrics.gauge(&format!("task.us.{name}")).set(micros as f64);
            metrics.gauge(&format!("task.runs.{name}")).set(runs as f64);
        }
        // Each law's awake items and the items its last run stepped: what the world step does at idle.
        for s in w.law_stats() {
            metrics
                .gauge(&format!("world.awake.{}", s.name))
                .set(f64::from(s.awake));
            metrics
                .gauge(&format!("world.stepped.{}", s.name))
                .set(f64::from(s.stepped));
        }
        // Each per-turf field's awake chunks and live edges after its last step (a settled map steps none).
        let gas = crate::gas::turf_key()
            .ok()
            .and_then(|k| w.sim_mut().with_idle_world(|r| r.get_mut(k.state).stats_and_times()));
        let heat = crate::heat::field()
            .ok()
            .and_then(|k| w.sim_mut().with_idle_world(|r| r.get_mut(k.state).stats_and_times()));
        for (name, stats) in [("turf_gas", gas), ("solid_heat", heat)] {
            if let Some((st, times)) = stats {
                metrics
                    .gauge(&format!("world.awake.field_{name}_chunks"))
                    .set(f64::from(st.active_chunks));
                metrics
                    .gauge(&format!("world.stepped.field_{name}_edges"))
                    .set(f64::from(st.live_edges));
                metrics
                    .gauge(&format!("world.stepped.field_{name}_touched"))
                    .set(f64::from(st.touched_chunks));
                for (what, v) in [
                    ("woke_cells", st.woke_cells),
                    ("woke_geom", st.woke_geom),
                    ("woke_grid", st.woke_grid),
                    ("kept_edges", st.kept_edges),
                    ("kept_local", st.kept_local),
                    ("substeps", st.substeps),
                    ("stride", st.stride),
                    ("rate_ppm", st.rate_ppm),
                ] {
                    metrics.gauge(&format!("world.awake.field_{name}_{what}")).set(f64::from(v));
                }
                #[allow(clippy::cast_precision_loss)]
                for (what, v) in [
                    ("us_setup", times.setup),
                    ("us_flux", times.flux),
                    ("us_apply", times.apply),
                    ("us_quiet", times.quiet),
                    ("us_local", times.local),
                    ("steps", st.steps),
                    ("skipped_steps", st.skipped_steps),
                    ("stride_changes", st.stride_changes),
                ] {
                    metrics.gauge(&format!("world.awake.field_{name}_{what}")).set(v as f64);
                }
            }
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
