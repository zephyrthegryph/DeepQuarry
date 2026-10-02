//! Ordered independent work with a bounded active-byte window. Publication and
//! mutation of shared compiler tables remain on the caller's thread.
use std::sync::{Condvar, Mutex};

struct Job<J> {
    ordinal: usize,
    bytes: usize,
    input: J,
}
struct Completion<R> {
    ordinal: usize,
    output: Result<R, Box<dyn std::any::Any + Send>>,
}
pub struct OrderedPool<J, R> {
    senders: Vec<std::sync::mpsc::SyncSender<Job<J>>>,
    completed: std::sync::mpsc::Receiver<Completion<R>>,
    next_worker: usize,
    budget: std::sync::Arc<(Mutex<usize>, Condvar)>,
    max_bytes: usize,
}
impl<J, R> OrderedPool<J, R> {
    pub fn submit(
        &mut self,
        ordinal: usize,
        estimated_bytes: usize,
        input: J,
    ) -> Result<(), WorkError> {
        if estimated_bytes > self.max_bytes {
            return Err(WorkError::BudgetExceeded {
                job: ordinal,
                estimate: estimated_bytes,
                budget: self.max_bytes,
            });
        }
        let (lock, available) = &*self.budget;
        let mut active = lock.lock().unwrap_or_else(|e| e.into_inner());
        while *active > self.max_bytes - estimated_bytes {
            active = available.wait(active).unwrap_or_else(|e| e.into_inner());
        }
        *active += estimated_bytes;
        drop(active);
        let worker = self.next_worker % self.senders.len();
        self.next_worker = self.next_worker.wrapping_add(1);
        if self.senders[worker]
            .send(Job {
                ordinal,
                bytes: estimated_bytes,
                input,
            })
            .is_err()
        {
            let mut active = lock.lock().unwrap_or_else(|e| e.into_inner());
            *active -= estimated_bytes;
            available.notify_all();
            return Err(WorkError::Panic {
                job: ordinal,
                message: "worker disconnected".into(),
            });
        }
        Ok(())
    }
    /// Drain a caller-bounded window. Typed panic payloads retain their outer
    /// infrastructure boundary; no compiler panic becomes a source diagnostic.
    pub fn receive_batch(&mut self, count: usize) -> Vec<R> {
        let mut results: Vec<_> = (0..count)
            .map(|_| self.completed.recv().expect("ordered worker stopped"))
            .collect();
        results.sort_by_key(|result| result.ordinal);
        results
            .into_iter()
            .map(|result| match result.output {
                Ok(output) => output,
                Err(payload) => std::panic::resume_unwind(payload),
            })
            .collect()
    }
}

/// Persistent worker-local state across every job window in a stage. Input and
/// completion channels are bounded; the caller drains at most `window` jobs.
pub fn with_ordered_pool<J: Send, R: Send, S: Send, F: Send, O>(
    limits: WorkLimits,
    window: usize,
    mut make_state: impl FnMut(usize) -> S,
    process: impl Fn(&mut S, J) -> R + Sync,
    finish: impl Fn(S, usize) -> F + Sync,
    consume: impl FnOnce(&mut OrderedPool<J, R>) -> O,
) -> (O, Vec<F>) {
    assert!(
        limits.workers > 0 && limits.max_active_bytes > 0 && window > 0,
        "invalid ordered pool limits"
    );
    std::thread::scope(|scope| {
        let (sender, completed) = std::sync::mpsc::sync_channel(window);
        let budget = std::sync::Arc::new((Mutex::new(0usize), Condvar::new()));
        let mut senders = Vec::new();
        let mut handles = Vec::new();
        for worker in 0..limits.workers.min(window).min(64) {
            let (jobs, receiver) = std::sync::mpsc::sync_channel::<Job<J>>(1);
            senders.push(jobs);
            let completed = sender.clone();
            let budget = budget.clone();
            let process = &process;
            let finish = &finish;
            let mut state = make_state(worker);
            handles.push(
                std::thread::Builder::new()
                    .name(format!("dm-stage-worker-{worker}"))
                    .stack_size(16 * 1024 * 1024)
                    .spawn_scoped(scope, move || {
                        while let Ok(job) = receiver.recv() {
                            let output =
                                std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                                    process(&mut state, job.input)
                                }));
                            let (lock, available) = &*budget;
                            let mut active = lock.lock().unwrap_or_else(|e| e.into_inner());
                            *active -= job.bytes;
                            drop(active);
                            available.notify_all();
                            if completed
                                .send(Completion {
                                    ordinal: job.ordinal,
                                    output,
                                })
                                .is_err()
                            {
                                break;
                            }
                        }
                        finish(state, worker)
                    })
                    .expect("cannot start ordered worker"),
            );
        }
        drop(sender);
        let mut pool = OrderedPool {
            senders,
            completed,
            next_worker: 0,
            budget,
            max_bytes: limits.max_active_bytes,
        };
        let result = consume(&mut pool);
        drop(pool);
        let finished = handles
            .into_iter()
            .map(|handle| match handle.join() {
                Ok(result) => result,
                Err(payload) => std::panic::resume_unwind(payload),
            })
            .collect();
        (result, finished)
    })
}

#[derive(Clone, Copy, Debug)]
pub struct WorkLimits {
    pub workers: usize,
    pub max_active_bytes: usize,
}
impl Default for WorkLimits {
    fn default() -> Self {
        Self {
            workers: 2,
            max_active_bytes: 64 * 1024 * 1024,
        }
    }
}
impl WorkLimits {
    /// Shared settings for source, resource, map and compiler work. The default
    /// is two workers and 64 MiB in-flight estimates; completed windows are
    /// independently bounded by each caller's stage window.
    pub fn configured() -> Self {
        let workers = std::env::var("DM_COMPILER_WORKERS")
            .ok()
            .or_else(|| std::env::var("DM_WORKERS").ok())
            .and_then(|value| value.parse::<usize>().ok())
            .unwrap_or(2)
            .clamp(1, 4);
        let megabytes = std::env::var("DM_WORK_ACTIVE_MIB")
            .ok()
            .and_then(|value| value.parse::<usize>().ok())
            .unwrap_or(64)
            .clamp(16, 256);
        Self {
            workers,
            max_active_bytes: megabytes * 1024 * 1024,
        }
    }
}
#[derive(Debug, Eq, PartialEq)]
pub enum WorkError {
    InvalidLimits,
    BudgetExceeded {
        job: usize,
        estimate: usize,
        budget: usize,
    },
    Panic {
        job: usize,
        message: String,
    },
}

pub fn map_ordered<T: Sync, R: Send>(
    inputs: &[T],
    limits: WorkLimits,
    estimate: impl Fn(&T) -> usize + Sync,
    job: impl Fn(&T) -> R + Sync,
) -> Result<Vec<R>, WorkError> {
    map_ordered_with_state(inputs, limits, estimate, |_| (), |_, input| job(input))
}

/// Worker-local state is initialized once and remains on its owning thread.
/// This lets parsing/lowering adapters share the same engine with local caches.
pub fn map_ordered_with_state<T: Sync, R: Send, S: Send>(
    inputs: &[T],
    limits: WorkLimits,
    estimate: impl Fn(&T) -> usize + Sync,
    initialize: impl Fn(usize) -> S + Sync,
    job: impl Fn(&mut S, &T) -> R + Sync,
) -> Result<Vec<R>, WorkError> {
    if limits.workers == 0 || limits.max_active_bytes == 0 {
        return Err(WorkError::InvalidLimits);
    }
    let costs: Vec<_> = inputs.iter().map(estimate).collect();
    if let Some((index, cost)) = costs
        .iter()
        .enumerate()
        .find(|(_, cost)| **cost > limits.max_active_bytes)
    {
        return Err(WorkError::BudgetExceeded {
            job: index,
            estimate: *cost,
            budget: limits.max_active_bytes,
        });
    }
    if inputs.len() <= 1 || limits.workers == 1 {
        // Tiny and explicitly serial stages use the same contracts without
        // allocating threads/channels or losing worker-local state reuse.
        let mut state = None;
        return inputs
            .iter()
            .enumerate()
            .map(|(index, input)| {
                std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    let state = state.get_or_insert_with(|| initialize(0));
                    job(state, input)
                }))
                .map_err(|payload| WorkError::Panic {
                    job: index,
                    message: payload
                        .downcast_ref::<String>()
                        .cloned()
                        .or_else(|| {
                            payload
                                .downcast_ref::<&str>()
                                .map(|message| message.to_string())
                        })
                        .unwrap_or_else(|| "non-string panic".into()),
                })
            })
            .collect();
    }
    let window = limits.workers.min(64).max(1) * 2;
    let (result, _) = with_ordered_pool(
        limits,
        window,
        |worker| (worker, None::<S>),
        |state, index: usize| {
            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                if state.1.is_none() {
                    state.1 = Some(initialize(state.0));
                }
                job(
                    state.1.as_mut().expect("initialized worker"),
                    &inputs[index],
                )
            }))
            .map_err(|payload| WorkError::Panic {
                job: index,
                message: payload
                    .downcast_ref::<String>()
                    .cloned()
                    .or_else(|| payload.downcast_ref::<&str>().map(|s| s.to_string()))
                    .unwrap_or_else(|| "non-string panic".into()),
            })
        },
        |_, _| (),
        |pool| {
            let mut output = Vec::with_capacity(inputs.len());
            for start in (0..inputs.len()).step_by(window) {
                let end = (start + window).min(inputs.len());
                for index in start..end {
                    pool.submit(index, costs[index], index)?;
                }
                for result in pool.receive_batch(end - start) {
                    output.push(result?);
                }
            }
            Ok(output)
        },
    );
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    #[test]
    fn byte_window_orders_results_and_reports_panics() {
        let active = AtomicUsize::new(0);
        let peak = AtomicUsize::new(0);
        let output = map_ordered(
            &[1, 2, 3, 4],
            WorkLimits {
                workers: 4,
                max_active_bytes: 8,
            },
            |_| 4,
            |value| {
                let bytes = active.fetch_add(4, Ordering::SeqCst) + 4;
                peak.fetch_max(bytes, Ordering::SeqCst);
                std::thread::yield_now();
                active.fetch_sub(4, Ordering::SeqCst);
                value * 2
            },
        )
        .unwrap();
        assert_eq!(output, vec![2, 4, 6, 8]);
        assert!(peak.load(Ordering::SeqCst) <= 8);
        let failure = map_ordered(
            &[0, 1, 2],
            WorkLimits::default(),
            |_| 1,
            |value| {
                if *value == 1 {
                    panic!("job failed");
                }
                *value
            },
        );
        assert_eq!(
            failure,
            Err(WorkError::Panic {
                job: 1,
                message: "job failed".into()
            })
        );
    }

    #[test]
    fn inline_work_preserves_state_panics_and_budget_preflight() {
        let initialized = AtomicUsize::new(0);
        let results = map_ordered_with_state(
            &[3, 4, 5],
            WorkLimits {
                workers: 1,
                max_active_bytes: 8,
            },
            |_| 4,
            |_| {
                initialized.fetch_add(1, Ordering::SeqCst);
                0
            },
            |state, value| {
                *state += value;
                *state
            },
        )
        .unwrap();
        assert_eq!(results, [3, 7, 12]);
        assert_eq!(initialized.load(Ordering::SeqCst), 1);
        let failure = map_ordered_with_state(
            &[1],
            WorkLimits {
                workers: 4,
                max_active_bytes: 8,
            },
            |_| 4,
            |_| panic!("inline initialization"),
            |_: &mut (), value| *value,
        );
        assert_eq!(
            failure,
            Err(WorkError::Panic {
                job: 0,
                message: "inline initialization".into()
            })
        );
        let rejected = map_ordered(
            &[1],
            WorkLimits {
                workers: 1,
                max_active_bytes: 8,
            },
            |_| 9,
            |_| -> () {
                panic!("preflight must reject before execution");
            },
        );
        assert_eq!(
            rejected,
            Err(WorkError::BudgetExceeded {
                job: 0,
                estimate: 9,
                budget: 8
            })
        );
    }
}
