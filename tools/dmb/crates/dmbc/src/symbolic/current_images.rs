//! Immutable image linking on the existing request executor, in canonical order.
use super::*;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Mutex,
};

struct Job<'a> {
    frozen: &'a Arc<FrozenProc>,
    origins: &'a crate::debug_sources::DebugOrigins,
    features: BytecodeFeatures,
}
fn image(job: &Job<'_>, tables: &LinkTables) -> Result<CurrentImage, IntegrationError> {
    CurrentImage::issue(job.frozen, job.origins, tables, job.features)
}
fn images(
    jobs: &[Job<'_>],
    tables: &LinkTables,
    executor: Option<&dm_exec::BuildExecutor>,
) -> Result<Vec<CurrentImage>, IntegrationError> {
    let Some(executor) = executor.filter(|executor| executor.workers() > 1 && jobs.len() > 1)
    else {
        return jobs.iter().map(|job| image(job, tables)).collect();
    };
    let next = AtomicUsize::new(0);
    let results: Vec<_> = (0..jobs.len()).map(|_| Mutex::new(None)).collect();
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        executor.scope(|scope| {
            for _ in 0..executor.workers().min(jobs.len()) {
                let next = &next;
                let results = &results;
                scope.spawn(move |_| {
                    let _profile = dm_profile::stage("linking.current_images");
                    loop {
                        let index = next.fetch_add(1, Ordering::Relaxed);
                        let Some(job) = jobs.get(index) else {
                            break;
                        };
                        *results[index]
                            .lock()
                            .expect("current image result lock poisoned") =
                            Some(image(job, tables));
                    }
                });
            }
        })
    }))
    .map_err(|_| IntegrationError::CurrentImageWorker("worker panicked".into()))?;
    results
        .into_iter()
        .map(|result| {
            result
                .into_inner()
                .map_err(|_| IntegrationError::CurrentImageWorker("result lock poisoned".into()))?
                .ok_or_else(|| {
                    IntegrationError::CurrentImageWorker("worker omitted image".into())
                })?
        })
        .collect()
}

pub(super) fn issue(
    units: &mut [FrozenUnit],
    helpers: &mut [FrozenHelper],
    initializers: &mut [FrozenInitializer],
    tables: &LinkTables,
    executor: Option<&dm_exec::BuildExecutor>,
) -> Result<(), IntegrationError> {
    let jobs: Vec<_> = units
        .iter()
        .map(|unit| Job {
            frozen: &unit.frozen,
            origins: &unit.lowered.debug_origins,
            features: unit.features,
        })
        .chain(helpers.iter().map(|unit| Job {
            frozen: &unit.frozen,
            origins: &unit.debug_origins,
            features: unit.features,
        }))
        .chain(initializers.iter().map(|unit| Job {
            frozen: &unit.frozen,
            origins: &unit.debug_origins,
            features: unit.features,
        }))
        .collect();
    // Scope joins all workers. Ordered collect returns the same first error as
    // the serial units -> helpers -> initializers traversal, without publishing
    // any partial certificate set to the caller.
    let images = images(&jobs, tables, executor)?;
    drop(jobs);
    let slots = units
        .iter_mut()
        .map(|unit| &mut unit.current_image)
        .chain(helpers.iter_mut().map(|unit| &mut unit.current_image))
        .chain(initializers.iter_mut().map(|unit| &mut unit.current_image));
    for (slot, image) in slots.zip(images) {
        *slot = Some(image);
    }
    Ok(())
}
