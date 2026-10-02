//! Bounded parallel symbolic lowering with deterministic ordered publication.
//!
//! Linking allocates shared table IDs and must retain source order. Parsing and
//! immutable syntax-cache reads have no such dependency. Workers own bounded
//! caches and symbolic bodies; the coordinator retains all DMB table mutation.
use crate::proc_parse_cache::ProcParseCache;
use dm_syntax::Item;
#[cfg(test)]
use dm_syntax::{Diagnostic, Span};
use std::path::Path;
use std::time::Duration;

use crate::lower_cache::{CacheStats, ProcLoweringCache, StageTimer};
use dm_codegen_byond::{LowerBindings, LowerError, SimpleProc};

/// Fixed independently of worker count so table allocation is reproducible.
/// Bounds completed code and syntax while overlapping more than two bodies.
pub(crate) const LOWERING_WINDOW: usize = 4;

struct LoweringJob {
    ordinal: usize,
    body: LoweringInput,
    bindings: LowerBindings,
    phase: LoweringPhase,
}
enum LoweringInput {
    Parsed(Vec<Item>),
    Source {
        raw: std::sync::Arc<str>,
        base: usize,
        metadata: super::ProcMetadata,
        modified: std::sync::Arc<super::ModifiedTypes>,
    },
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum LoweringPhase {
    Procedure,
    ArgumentSource,
    Initializer,
}
impl LoweringPhase {
    fn index(self) -> usize {
        match self {
            Self::Procedure => 0,
            Self::ArgumentSource => 1,
            Self::Initializer => 2,
        }
    }
}

// CPU counters are sampled at job boundaries, not around every tiny cache step.
// Unsupported hosts report unavailable CPU; elapsed timers remain supported.
#[cfg(windows)]
fn thread_cpu() -> Option<Duration> {
    #[repr(C)]
    #[derive(Default)]
    struct FileTime {
        low: u32,
        high: u32,
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetCurrentThread() -> *mut std::ffi::c_void;
        fn GetThreadTimes(
            thread: *mut std::ffi::c_void,
            creation: *mut FileTime,
            exit: *mut FileTime,
            kernel: *mut FileTime,
            user: *mut FileTime,
        ) -> i32;
    }
    let mut creation = FileTime::default();
    let mut exit = FileTime::default();
    let mut kernel = FileTime::default();
    let mut user = FileTime::default();
    let success = unsafe {
        GetThreadTimes(
            GetCurrentThread(),
            &mut creation,
            &mut exit,
            &mut kernel,
            &mut user,
        )
    };
    if success == 0 {
        return None;
    }
    let ticks = ((u64::from(kernel.high) << 32) | u64::from(kernel.low))
        .saturating_add((u64::from(user.high) << 32) | u64::from(user.low));
    Some(Duration::new(
        ticks / 10_000_000,
        ((ticks % 10_000_000) * 100) as u32,
    ))
}
#[cfg(not(windows))]
fn thread_cpu() -> Option<Duration> {
    None
}

pub(crate) struct LoweringResult {
    pub ordinal: usize,
    pub bindings: LowerBindings,
    pub compiled: Result<SimpleProc, Vec<LowerError>>,
    pub memo: Option<std::sync::Arc<crate::ProcedureMemo>>,
    pub lowering_cache_hit: bool,
    pub body_base: Option<usize>,
    pub source_error: Option<String>,
    pub(crate) internal_panic: Option<Box<dyn std::any::Any + Send>>,
}

pub(crate) struct LoweringPool<'a> {
    inner: &'a mut crate::work::OrderedPool<LoweringJob, LoweringResult>,
    profiling: bool,
    submit_elapsed: Duration,
    receive_elapsed: Duration,
}

impl LoweringPool<'_> {
    pub fn submit(&mut self, ordinal: usize, body: Vec<Item>, bindings: LowerBindings) {
        self.submit_for_phase(LoweringPhase::Procedure, ordinal, body, bindings);
    }
    pub fn submit_for_phase(
        &mut self,
        phase: LoweringPhase,
        ordinal: usize,
        body: Vec<Item>,
        bindings: LowerBindings,
    ) {
        fn body_bytes(items: &[Item]) -> usize {
            items
                .iter()
                .map(|item| {
                    std::mem::size_of::<Item>() + item.header.len() + body_bytes(&item.children)
                })
                .sum()
        }
        let bytes = body_bytes(&body).saturating_mul(4).saturating_add(4096);
        let timer = StageTimer::start(self.profiling);
        self.inner
            .submit(
                ordinal,
                bytes,
                LoweringJob {
                    ordinal,
                    body: LoweringInput::Parsed(body),
                    bindings,
                    phase,
                },
            )
            .expect("procedure lowering job exceeds bounded stage budget");
        timer.record(&mut self.submit_elapsed);
    }
    pub(super) fn submit_source(
        &mut self,
        ordinal: usize,
        raw: std::sync::Arc<str>,
        base: usize,
        metadata: super::ProcMetadata,
        modified: std::sync::Arc<super::ModifiedTypes>,
        bindings: LowerBindings,
    ) {
        let bytes = raw.len().saturating_mul(6).saturating_add(4096);
        let timer = StageTimer::start(self.profiling);
        self.inner
            .submit(
                ordinal,
                bytes,
                LoweringJob {
                    ordinal,
                    body: LoweringInput::Source {
                        raw,
                        base,
                        metadata,
                        modified,
                    },
                    bindings,
                    phase: LoweringPhase::Procedure,
                },
            )
            .expect("procedure source job exceeds bounded stage budget");
        timer.record(&mut self.submit_elapsed);
    }
    pub fn receive_batch(&mut self, count: usize) -> Vec<LoweringResult> {
        let timer = StageTimer::start(self.profiling);
        let results = self.inner.receive_batch(count);
        // Keep compatibility with diagnostic worker adapters carrying a typed panic.
        let results = results
            .into_iter()
            .map(|mut result| {
                if let Some(payload) = result.internal_panic.take() {
                    std::panic::resume_unwind(payload);
                }
                result
            })
            .collect();
        timer.record(&mut self.receive_elapsed);
        results
    }
}

struct LoweringWorker {
    cache: ProcLoweringCache,
    parser: Option<ProcParseCache>,
    cpu_start: Option<Duration>,
    phases: [CacheStats; 3],
    phase_cpu: [Duration; 3],
    phase_samples: [usize; 3],
}

pub(crate) fn with_lowering_pool<R>(
    cache_root: Option<&Path>,
    workers: usize,
    consume: impl FnOnce(&mut LoweringPool) -> R,
) -> (R, CacheStats) {
    let cache = cache_root
        .map(|root| ProcLoweringCache::open(root.to_path_buf()))
        .unwrap_or_else(ProcLoweringCache::disabled);
    with_lowering_cache(&cache, workers, consume)
}

pub(crate) fn with_lowering_cache<R>(
    parent: &ProcLoweringCache,
    workers: usize,
    consume: impl FnOnce(&mut LoweringPool) -> R,
) -> (R, CacheStats) {
    let semantic_model = super::semantic_declarations::capture_active();
    let parser = std::sync::OnceLock::<ProcParseCache>::new();
    let parse_root = parent.cache_root().map(Path::to_path_buf);
    let (result, workers) = crate::work::with_ordered_pool(
        crate::work::WorkLimits {
            workers: workers.clamp(1, LOWERING_WINDOW),
            max_active_bytes: crate::work::WorkLimits::configured().max_active_bytes,
        },
        LOWERING_WINDOW,
        |_| LoweringWorker {
            cache: parent.fork(),
            parser: None,
            cpu_start: parent.profiling_enabled().then(thread_cpu).flatten(),
            phases: [CacheStats::default(); 3],
            phase_cpu: [Duration::ZERO; 3],
            phase_samples: [0; 3],
        },
        |worker, job: LoweringJob| {
            let _semantic_model = super::semantic_declarations::activate_optional(semantic_model.clone());
            let profiling = worker.cache.profiling_enabled();
            let before = profiling.then(|| worker.cache.stats());
            let cpu = profiling.then(thread_cpu).flatten();
            let hits_before = worker.cache.hits_count();
            fn rebase(items: &mut [Item], base: usize) {
                for item in items {
                    item.span.start += base;
                    item.span.end += base;
                    item.header_span.start += base;
                    item.header_span.end += base;
                    rebase(&mut item.children, base);
                }
            }
            let parsed: Result<(Vec<Item>, Option<usize>), String> = match job.body {
                LoweringInput::Parsed(body) => Ok((body, None)),
                LoweringInput::Source {
                    raw,
                    base,
                    metadata,
                    modified,
                } => worker
                    .parser
                    .get_or_insert_with(|| {
                        parser
                            .get_or_init(|| ProcParseCache::open(parse_root.as_deref()))
                            .fork()
                    })
                    .parse(&raw, dm_syntax::Span::new(0, raw.len()))
                    .map_err(|mut diagnostic| {
                        diagnostic.span.start += base;
                        diagnostic.span.end += base;
                        format!("procedure syntax: {diagnostic:?}")
                    })
                    .and_then(|mut item| {
                        rebase(std::slice::from_mut(&mut item), base);
                        super::rewrite_modified_items(std::slice::from_mut(&mut item), &modified);
                        let (_, mut body) =
                            super::proc_metadata_from_base(&item.children, metadata)?;
                        super::extract_static_declarations(&mut body, &mut Vec::new());
                        let body_base = dm_codegen_byond::debug::body_span_base(&body);
                        Ok((body, Some(body_base)))
                    }),
            };
            let (body, body_base) = match parsed {
                Ok(parsed) => parsed,
                Err(error) => {
                    return LoweringResult {
                        ordinal: job.ordinal,
                        bindings: job.bindings,
                        compiled: Err(Vec::new()),
                        memo: None,
                        lowering_cache_hit: false,
                        body_base: None,
                        source_error: Some(error),
                        internal_panic: None,
                    }
                }
            };
            let outcome = worker.cache.compile_memo(&body, &job.bindings);
            let lowering_cache_hit = worker.cache.hits_count() > hits_before;
            let (compiled, memo) = match outcome {
                Ok(memo) => {
                    let memo = std::sync::Arc::new(memo);
                    (Ok(memo.procedure.clone()), Some(memo))
                }
                Err(errors) => (Err(errors), None),
            };
            if let Some(before) = before {
                let index = job.phase.index();
                worker.phases[index].merge(worker.cache.stats().since(before));
                if let Some((start, end)) = cpu.zip(thread_cpu()) {
                    worker.phase_cpu[index] += end.saturating_sub(start);
                    worker.phase_samples[index] += 1;
                }
            }
            LoweringResult {
                ordinal: job.ordinal,
                bindings: job.bindings,
                compiled,
                memo,
                lowering_cache_hit,
                body_base,
                source_error: None,
                internal_panic: None,
            }
        },
        |mut worker, ordinal| {
            let profiling = worker.cache.profiling_enabled();
            if let Err(error) = worker.cache.flush() {
                if profiling {
                    eprintln!("DM_BUILD_TRACE worker {ordinal} final flush failed: {error}");
                }
            }
            if profiling {
                let parser = worker
                    .parser
                    .as_ref()
                    .map(ProcParseCache::stats)
                    .unwrap_or_default();
                eprintln!("DM_BUILD_TRACE worker {ordinal} parser: {} hits, {} misses, read/decode {:.3}s, parse {:.3}s",parser.hits,parser.misses,parser.read_time.as_secs_f64(),parser.parse_time.as_secs_f64());
                let cpu = worker
                    .cpu_start
                    .zip(thread_cpu())
                    .map(|(start, end)| end.saturating_sub(start));
                eprintln!("DM_BUILD_TRACE worker {ordinal} total CPU {cpu:?}; phase job CPU {:?}, observed jobs {:?}; CPU job totals exclude final flush/channel gaps",worker.phase_cpu,worker.phase_samples);
                for (phase, stats) in ["procedure", "argument-source", "initializer"]
                    .into_iter()
                    .zip(worker.phases)
                {
                    stats.trace(&format!("worker {ordinal} {phase}"));
                }
                worker
                    .cache
                    .stats()
                    .trace(&format!("worker {ordinal} complete, including final flush"));
            }
            worker.cache.stats()
        },
        |inner| {
            let mut pool = LoweringPool {
                inner,
                profiling: parent.profiling_enabled(),
                submit_elapsed: Duration::ZERO,
                receive_elapsed: Duration::ZERO,
            };
            let result = consume(&mut pool);
            if pool.profiling {
                eprintln!("DM_BUILD_TRACE parent pipeline send elapsed {:.3}s; receive/sort elapsed {:.3}s (waits overlap worker work)",pool.submit_elapsed.as_secs_f64(),pool.receive_elapsed.as_secs_f64());
            }
            result
        },
    );
    let mut stats = CacheStats::default();
    for worker in workers {
        stats.merge(worker);
    }
    (result, stats)
}

pub(crate) fn worker_count() -> usize {
    crate::work::WorkLimits::configured()
        .workers
        .min(LOWERING_WINDOW)
}

#[cfg(test)]
pub(crate) fn with_parsed_procedures<R>(
    source: &str,
    spans: &[Span],
    cache_root: Option<&Path>,
    workers: usize,
    consume: impl FnOnce(&mut dyn Iterator<Item = Result<Item, Diagnostic>>) -> R,
) -> R {
    if workers <= 1 || spans.len() < 2 {
        let mut cache = ProcParseCache::open(cache_root);
        return consume(&mut spans.iter().map(|&span| cache.parse(source, span)));
    }
    std::thread::scope(|scope| {
        // A rendezvous keeps at most one completed AST plus one in-flight AST
        // beyond the AST currently being lowered, regardless of project size.
        let (sender, receiver) = std::sync::mpsc::sync_channel(0);
        let worker = std::thread::Builder::new()
            .name("dm-procedure-parser".into())
            .stack_size(16 * 1024 * 1024)
            .spawn_scoped(scope, move || {
            let mut cache = ProcParseCache::open(cache_root);
            for &span in spans {
                if sender.send(cache.parse(source, span)).is_err() {
                    break;
                }
            }
            if std::env::var_os("DM_BUILD_TRACE").is_some() {
                let stats = cache.stats();
                eprintln!("DM_BUILD_TRACE parallel procedure parser: {} hits, {} misses, {} corrupt; read/decode {:.3}s, parse {:.3}s", stats.hits, stats.misses, stats.corrupt, stats.read_time.as_secs_f64(), stats.parse_time.as_secs_f64());
            }
        }).expect("cannot start procedure parsing worker");
        let mut items = receiver.into_iter();
        let result = consume(&mut items);
        // Errors or early returns must disconnect the blocked producer before
        // joining it. Scope also guarantees it cannot outlive borrowed source.
        drop(items);
        worker.join().expect("procedure parsing worker panicked");
        result
    })
}

#[cfg(test)]
mod tests {
    #[test]
    fn source_jobs_parse_on_workers_and_preserve_current_body_anchor() {
        let raw: std::sync::Arc<str> = std::sync::Arc::from("/proc/probe()\n    return 7\n");
        let base = 1000;
        let expected = base + raw.find("return 7").unwrap();
        let (metadata, _) = super::super::proc_metadata(&[], None).unwrap();
        let modified = std::sync::Arc::new(super::super::ModifiedTypes::default());
        let (result, _) = super::with_lowering_pool(None, 2, |pool| {
            pool.submit_source(
                0,
                raw,
                base,
                metadata,
                modified,
                dm_codegen_byond::LowerBindings::default(),
            );
            pool.receive_batch(1).remove(0)
        });
        assert_eq!(result.body_base, Some(expected));
        assert!(result.source_error.is_none());
        assert!(result.compiled.is_ok());
    }
    #[test]
    fn worker_panic_retains_internal_failure_boundary() {
        let panic = std::panic::catch_unwind(|| {
            crate::work::with_ordered_pool(
                crate::work::WorkLimits::default(),
                4,
                |_| (),
                |_, _: ()| -> () { std::panic::panic_any(761u32) },
                |_, _| (),
                |pool| {
                    pool.submit(0, 1, ()).unwrap();
                    pool.receive_batch(1)
                },
            )
        })
        .err()
        .expect("worker panic must reach infrastructure boundary");
        assert_eq!(*panic.downcast::<u32>().unwrap(), 761);
    }
    use super::*;

    #[test]
    fn real_lowering_pool_reuses_disk_cache_and_orders_results() {
        let root = std::env::temp_dir().join(format!(
            "dm-lowering-pool-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let run = |workers| {
            with_lowering_pool(Some(&root), workers, |pool| {
                for ordinal in 0..2 {
                    let ast = dm_syntax::parse(&format!(
                        "/proc/p{ordinal}()\n    return {}\n",
                        ordinal + 1
                    ));
                    pool.submit(
                        ordinal,
                        ast.items[0].children.clone(),
                        LowerBindings::default(),
                    );
                }
                pool.receive_batch(2)
                    .into_iter()
                    .map(|result| (result.ordinal, result.compiled.unwrap()))
                    .collect::<Vec<_>>()
            })
        };
        let (cold, cold_stats) = run(2);
        assert_eq!(cold_stats.misses, 2);
        let (serial, serial_stats) = run(1);
        assert_eq!(serial_stats.hits, 2);
        let (parallel, parallel_stats) = run(2);
        assert_eq!(parallel_stats.hits, 2);
        assert_eq!(cold, serial);
        assert_eq!(serial, parallel);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn real_lowering_pool_joins_on_early_consumer_return() {
        let (result, _) = with_lowering_pool(None, 2, |pool| {
            let ast = dm_syntax::parse("/proc/p()\n    return 1\n");
            pool.submit(0, ast.items[0].children.clone(), LowerBindings::default());
            Err::<(), _>("stop before receiving")
        });
        assert_eq!(result, Err("stop before receiving"));
    }

    fn fixture() -> (&'static str, Vec<Span>) {
        let source = "/proc/first()\n    return 1\n/proc/second()\n    return 2\n/proc/third()\n    return 3\n";
        let spans = dm_syntax::parse(source)
            .items
            .iter()
            .map(|item| item.span)
            .collect();
        (source, spans)
    }

    #[test]
    fn parallel_parser_preserves_serial_order_spans_and_bodies() {
        let (source, spans) = fixture();
        let collect = |items: &mut dyn Iterator<Item = Result<Item, Diagnostic>>| {
            items
                .map(|item| format!("{:?}", item.unwrap()))
                .collect::<Vec<_>>()
        };
        let serial = with_parsed_procedures(source, &spans, None, 1, collect);
        let parallel = with_parsed_procedures(source, &spans, None, 2, collect);
        assert_eq!(serial, parallel);
        assert_eq!(parallel.len(), 3);
    }

    #[test]
    fn early_consumer_failure_disconnects_and_joins_worker() {
        let (source, spans) = fixture();
        let result = with_parsed_procedures(source, &spans, None, 2, |items| {
            assert!(items.next().unwrap().is_ok());
            Err::<(), _>("linking failed")
        });
        assert_eq!(result, Err("linking failed"));
    }

    #[test]
    fn empty_parallel_input_completes() {
        with_parsed_procedures("", &[], None, 2, |items| assert!(items.next().is_none()));
    }
}
