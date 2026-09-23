//! The metrics registry (`rust_core.md` §11): counters, gauges and
//! histograms registered by name, read all at once with
//! [`MetricsRegistry::snapshot`] / [`MetricsRegistry::to_json`].
//!
//! Handles ([`Counter`], [`Gauge`], [`Histogram`]) are cheap `Arc` clones of
//! atomics: updating one never locks or allocates, so frame tasks, jobs and
//! binds can all record. Only registration and snapshots take the
//! registry's lock, and both are rare (setup, and one metrics call per
//! benchmark mark or profiler sample).
//!
//! Core has no statics: the DLL owns one registry (vg-ffi `metrics`).

use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, PoisonError, RwLock};

use crate::alloc::{AllocTag, TagCounters};
use crate::sim::SimMetrics;

/// A monotonically increasing count.
#[derive(Clone, Debug, Default)]
pub struct Counter(Arc<AtomicU64>);

impl Counter {
    pub fn inc(&self) {
        self.add(1);
    }
    pub fn add(&self, n: u64) {
        self.0.fetch_add(n, Ordering::Relaxed);
    }
    /// Sets the count (for mirroring a count kept elsewhere).
    pub fn set(&self, n: u64) {
        self.0.store(n, Ordering::Relaxed);
    }
    #[must_use]
    pub fn get(&self) -> u64 {
        self.0.load(Ordering::Relaxed)
    }
}

/// A value that goes up and down (stored as `f64` bits).
#[derive(Clone, Debug, Default)]
pub struct Gauge(Arc<AtomicU64>);

impl Gauge {
    pub fn set(&self, v: f64) {
        self.0.store(v.to_bits(), Ordering::Relaxed);
    }
    #[must_use]
    pub fn get(&self) -> f64 {
        f64::from_bits(self.0.load(Ordering::Relaxed))
    }
}

#[derive(Debug)]
struct HistInner {
    /// Upper bounds, ascending; one extra overflow bucket follows.
    bounds: Vec<f64>,
    buckets: Vec<AtomicU64>,
    count: AtomicU64,
    /// Sum as `f64` bits, updated with a CAS loop.
    sum: AtomicU64,
    max: AtomicU64,
}

/// A distribution over fixed buckets.
#[derive(Clone, Debug)]
pub struct Histogram(Arc<HistInner>);

/// A histogram's contents at snapshot time.
#[derive(Clone, Debug, PartialEq)]
pub struct HistogramSample {
    pub bounds: Vec<f64>,
    /// `bounds.len() + 1` counts; the last is overflow.
    pub buckets: Vec<u64>,
    pub count: u64,
    pub sum: f64,
    pub max: f64,
}

impl Histogram {
    fn new(bounds: &[f64]) -> Self {
        let mut bounds = bounds.to_vec();
        bounds.sort_by(f64::total_cmp);
        let buckets = (0..=bounds.len()).map(|_| AtomicU64::new(0)).collect();
        Self(Arc::new(HistInner {
            bounds,
            buckets,
            count: AtomicU64::new(0),
            sum: AtomicU64::new(0f64.to_bits()),
            max: AtomicU64::new(0f64.to_bits()),
        }))
    }

    pub fn observe(&self, v: f64) {
        let h = &self.0;
        let i = h.bounds.partition_point(|b| *b < v);
        h.buckets[i].fetch_add(1, Ordering::Relaxed);
        h.count.fetch_add(1, Ordering::Relaxed);
        let _ = h
            .sum
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |s| {
                Some((f64::from_bits(s) + v).to_bits())
            });
        let _ = h
            .max
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |m| {
                (v > f64::from_bits(m)).then(|| v.to_bits())
            });
    }

    #[must_use]
    pub fn sample(&self) -> HistogramSample {
        let h = &self.0;
        HistogramSample {
            bounds: h.bounds.clone(),
            buckets: h
                .buckets
                .iter()
                .map(|b| b.load(Ordering::Relaxed))
                .collect(),
            count: h.count.load(Ordering::Relaxed),
            sum: f64::from_bits(h.sum.load(Ordering::Relaxed)),
            max: f64::from_bits(h.max.load(Ordering::Relaxed)),
        }
    }
}

/// One metric's value at snapshot time.
#[derive(Clone, Debug, PartialEq)]
pub enum MetricValue {
    Counter(u64),
    Gauge(f64),
    Histogram(HistogramSample),
}

#[derive(Clone, Debug)]
enum Metric {
    Counter(Counter),
    Gauge(Gauge),
    Histogram(Histogram),
}

/// Named metrics. Names are dotted paths by convention
/// (`sim.frame_ms`, `alloc.gas.current_bytes`, `jobs.station_layout.completed`).
#[derive(Default)]
pub struct MetricsRegistry {
    metrics: RwLock<BTreeMap<String, Metric>>,
}

impl MetricsRegistry {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// The counter called `name`, registering it on first use.
    ///
    /// # Panics
    /// If `name` is already registered as another kind.
    pub fn counter(&self, name: &str) -> Counter {
        match self.get_or_insert(name, || Metric::Counter(Counter::default())) {
            Metric::Counter(c) => c,
            other => panic!("metric {name} is a {other:?}, not a counter"),
        }
    }

    /// The gauge called `name`, registering it on first use.
    ///
    /// # Panics
    /// If `name` is already registered as another kind.
    pub fn gauge(&self, name: &str) -> Gauge {
        match self.get_or_insert(name, || Metric::Gauge(Gauge::default())) {
            Metric::Gauge(g) => g,
            other => panic!("metric {name} is a {other:?}, not a gauge"),
        }
    }

    /// The histogram called `name`, registering it with `bounds` on first
    /// use (later calls keep the first bounds).
    ///
    /// # Panics
    /// If `name` is already registered as another kind.
    pub fn histogram(&self, name: &str, bounds: &[f64]) -> Histogram {
        match self.get_or_insert(name, || Metric::Histogram(Histogram::new(bounds))) {
            Metric::Histogram(h) => h,
            other => panic!("metric {name} is a {other:?}, not a histogram"),
        }
    }

    fn get_or_insert(&self, name: &str, make: impl FnOnce() -> Metric) -> Metric {
        if let Some(m) = self
            .metrics
            .read()
            .unwrap_or_else(PoisonError::into_inner)
            .get(name)
        {
            return m.clone();
        }
        self.metrics
            .write()
            .unwrap_or_else(PoisonError::into_inner)
            .entry(name.to_owned())
            .or_insert_with(make)
            .clone()
    }

    /// Every metric, sorted by name.
    #[must_use]
    pub fn snapshot(&self) -> Vec<(String, MetricValue)> {
        self.metrics
            .read()
            .unwrap_or_else(PoisonError::into_inner)
            .iter()
            .map(|(name, m)| {
                let v = match m {
                    Metric::Counter(c) => MetricValue::Counter(c.get()),
                    Metric::Gauge(g) => MetricValue::Gauge(g.get()),
                    Metric::Histogram(h) => MetricValue::Histogram(h.sample()),
                };
                (name.clone(), v)
            })
            .collect()
    }

    /// Every metric as one flat JSON object: counters and gauges map to
    /// numbers; a histogram maps to
    /// `{"count","sum","max","bounds":[..],"buckets":[..]}`.
    #[must_use]
    pub fn to_json(&self) -> String {
        let mut out = String::from("{");
        for (i, (name, value)) in self.snapshot().iter().enumerate() {
            if i > 0 {
                out.push(',');
            }
            write_json_str(&mut out, name);
            out.push(':');
            match value {
                MetricValue::Counter(c) => {
                    let _ = write!(out, "{c}");
                }
                MetricValue::Gauge(g) => write_json_f64(&mut out, *g),
                MetricValue::Histogram(h) => {
                    let _ = write!(out, "{{\"count\":{},\"sum\":", h.count);
                    write_json_f64(&mut out, h.sum);
                    out.push_str(",\"max\":");
                    write_json_f64(&mut out, h.max);
                    out.push_str(",\"bounds\":[");
                    for (j, b) in h.bounds.iter().enumerate() {
                        if j > 0 {
                            out.push(',');
                        }
                        write_json_f64(&mut out, *b);
                    }
                    out.push_str("],\"buckets\":[");
                    for (j, b) in h.buckets.iter().enumerate() {
                        if j > 0 {
                            out.push(',');
                        }
                        let _ = write!(out, "{b}");
                    }
                    out.push_str("]}");
                }
            }
        }
        out.push('}');
        out
    }

    /// Mirrors allocator tag counters into `alloc.<tag>.current_bytes` /
    /// `alloc.<tag>.peak_bytes` gauges, plus `alloc.total.*`.
    pub fn record_alloc_tags(&self, tags: &TagCounters) {
        let mut total = 0u64;
        for tag in AllocTag::ALL {
            let usage = tags.usage(tag);
            total += usage.current;
            #[allow(clippy::cast_precision_loss)]
            {
                self.gauge(&format!("alloc.{}.current_bytes", tag.name()))
                    .set(usage.current as f64);
                self.gauge(&format!("alloc.{}.peak_bytes", tag.name()))
                    .set(usage.peak as f64);
            }
        }
        #[allow(clippy::cast_precision_loss)]
        self.gauge("alloc.total.current_bytes").set(total as f64);
    }

    /// Mirrors a sim's backpressure metrics under `prefix` (e.g. `sim`).
    #[allow(clippy::cast_precision_loss)]
    pub fn record_sim(&self, prefix: &str, m: &SimMetrics) {
        let c = |n: &str, v: u64| self.counter(&format!("{prefix}.{n}")).set(v);
        let g = |n: &str, v: f64| self.gauge(&format!("{prefix}.{n}")).set(v);
        c("ticks", m.ticks);
        c("frames_dispatched", m.frames_dispatched);
        c("frames_completed", m.frames_completed);
        c("dispatches_skipped", m.dispatches_skipped);
        c("view_age_over_budget", m.view_age_over_budget);
        c("frame_panics", m.frame_panics);
        g("last_frame_ms", m.last_frame.as_secs_f64() * 1000.0);
        g("max_frame_ms", m.max_frame.as_secs_f64() * 1000.0);
        g("command_backlog", m.command_backlog as f64);
        g("view_age_ticks", f64::from(m.view_age_ticks));
        g("overlay_entries", m.overlay_entries as f64);
    }
}

fn write_json_f64(out: &mut String, v: f64) {
    if v.is_finite() {
        let _ = write!(out, "{v}");
    } else {
        out.push_str("null");
    }
}

fn write_json_str(out: &mut String, s: &str) {
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

/// Default bucket bounds for millisecond timings.
pub const MS_BUCKETS: &[f64] = &[
    0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 1000.0,
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registers_by_name_and_snapshots_all() {
        let r = MetricsRegistry::new();
        r.counter("a.calls").inc();
        r.counter("a.calls").add(2);
        r.gauge("b.level").set(1.5);
        let h = r.histogram("c.ms", &[1.0, 10.0]);
        h.observe(0.5);
        h.observe(5.0);
        h.observe(50.0);
        let snap = r.snapshot();
        assert_eq!(snap[0], ("a.calls".into(), MetricValue::Counter(3)));
        assert_eq!(snap[1], ("b.level".into(), MetricValue::Gauge(1.5)));
        let MetricValue::Histogram(hs) = &snap[2].1 else {
            panic!()
        };
        assert_eq!(hs.buckets, vec![1, 1, 1]);
        assert_eq!(hs.count, 3);
        assert!((hs.sum - 55.5).abs() < 1e-9);
        assert!((hs.max - 50.0).abs() < 1e-9);
        assert_eq!(
            r.to_json(),
            "{\"a.calls\":3,\"b.level\":1.5,\"c.ms\":{\"count\":3,\"sum\":55.5,\"max\":50,\"bounds\":[1,10],\"buckets\":[1,1,1]}}"
        );
    }

    #[test]
    #[should_panic(expected = "not a gauge")]
    fn kind_mismatch_panics() {
        let r = MetricsRegistry::new();
        r.counter("x");
        r.gauge("x");
    }

    #[test]
    fn mirrors_alloc_tags() {
        use crate::alloc::AllocCounter;
        let tags = TagCounters::new();
        tags.record_alloc(AllocTag::Gas, 64);
        let r = MetricsRegistry::new();
        r.record_alloc_tags(&tags);
        assert!((r.gauge("alloc.gas.current_bytes").get() - 64.0).abs() < 1e-9);
        assert!((r.gauge("alloc.total.current_bytes").get() - 64.0).abs() < 1e-9);
    }
}
