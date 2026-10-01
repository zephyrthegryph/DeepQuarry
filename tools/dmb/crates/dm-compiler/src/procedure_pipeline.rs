//! Bounded parallel symbolic lowering with deterministic ordered publication.
//!
//! Linking allocates shared table IDs and must retain source order. Parsing and
//! immutable syntax-cache reads have no such dependency. Workers own bounded
//! caches and symbolic bodies; the coordinator retains all DMB table mutation.
#[cfg(test)]
use crate::proc_parse_cache::ProcParseCache;
use dm_syntax::Item;
#[cfg(test)]
use dm_syntax::{Diagnostic, Span};
use std::path::Path;

use crate::lower_cache::{CacheStats, ProcLoweringCache};
use dm_codegen_byond::{LowerBindings, LowerError, SimpleProc};

struct LoweringJob {
    ordinal: usize,
    body: Vec<Item>,
    bindings: LowerBindings,
}

pub(crate) struct LoweringResult {
    pub ordinal: usize,
    pub bindings: LowerBindings,
    pub compiled: Result<SimpleProc, Vec<LowerError>>,
}

pub(crate) struct LoweringPool {
    senders: Vec<std::sync::mpsc::SyncSender<LoweringJob>>,
    completed: std::sync::mpsc::Receiver<LoweringResult>,
    next_worker: usize,
}

impl LoweringPool {
    pub fn submit(&mut self, ordinal: usize, body: Vec<Item>, bindings: LowerBindings) {
        let worker = self.next_worker % self.senders.len();
        self.next_worker = self.next_worker.wrapping_add(1);
        self.senders[worker]
            .send(LoweringJob {
                ordinal,
                body,
                bindings,
            })
            .expect("procedure lowering worker stopped");
    }

    /// The caller submits at most two jobs before draining them. A slow first
    /// job cannot make later completed syntax/code accumulate without bounds.
    pub fn receive_batch(&mut self, count: usize) -> Vec<LoweringResult> {
        let mut results: Vec<_> = (0..count)
            .map(|_| {
                self.completed
                    .recv()
                    .expect("procedure lowering worker stopped")
            })
            .collect();
        results.sort_by_key(|result| result.ordinal);
        results
    }
}

pub(crate) fn with_lowering_pool<R>(
    cache_root: Option<&Path>,
    workers: usize,
    consume: impl FnOnce(&mut LoweringPool) -> R,
) -> (R, CacheStats) {
    std::thread::scope(|scope| {
        let (completed_sender, completed) = std::sync::mpsc::channel();
        let mut senders = Vec::new();
        let mut handles = Vec::new();
        for ordinal in 0..workers.clamp(1, 2) {
            let (sender, receiver) = std::sync::mpsc::sync_channel::<LoweringJob>(1);
            senders.push(sender);
            let completed = completed_sender.clone();
            let handle = std::thread::Builder::new()
                .name(format!("dm-procedure-lower-{ordinal}"))
                .stack_size(16 * 1024 * 1024)
                .spawn_scoped(scope, move || {
                    let mut cache = cache_root
                        .map(|root| ProcLoweringCache::open(root.to_path_buf()))
                        .unwrap_or_else(ProcLoweringCache::disabled);
                    while let Ok(job) = receiver.recv() {
                        // A worker panic must report a failed job rather than
                        // leave the ordered coordinator waiting for its ordinal.
                        let compiled =
                            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                                cache.compile(&job.body, &job.bindings)
                            }))
                            .unwrap_or_else(|_| {
                                Err(vec![LowerError {
                                    statement: "<procedure lowering worker>".into(),
                                    reason: "procedure lowering panicked".into(),
                                }])
                            });
                        if completed
                            .send(LoweringResult {
                                ordinal: job.ordinal,
                                bindings: job.bindings,
                                compiled,
                            })
                            .is_err()
                        {
                            break;
                        }
                    }
                    cache.stats()
                })
                .expect("cannot start procedure lowering worker");
            handles.push(handle);
        }
        drop(completed_sender);
        let mut pool = LoweringPool {
            senders,
            completed,
            next_worker: 0,
        };
        let result = consume(&mut pool);
        // Disconnect jobs/results before joining, including early compile errors.
        drop(pool);
        let mut stats = CacheStats::default();
        for handle in handles {
            let worker = handle.join().expect("procedure lowering worker panicked");
            stats.hits += worker.hits;
            stats.misses += worker.misses;
            stats.corrupt_entries += worker.corrupt_entries;
        }
        (result, stats)
    })
}

pub(crate) fn worker_count() -> usize {
    std::env::var("DM_COMPILER_WORKERS")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(2)
        .clamp(1, 2)
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
