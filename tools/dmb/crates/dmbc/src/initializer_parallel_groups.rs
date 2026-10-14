//! Independent group jobs on the borrowed build pool, with canonical result order.
use dm_exec::BuildExecutor;
use std::sync::atomic::{AtomicUsize, Ordering};
type IndexedResults<T, E> = Vec<(usize, Result<T, E>)>;

pub(super) fn ordered_jobs<T: Send, E: Send>(
    count: usize,
    executor: &BuildExecutor,
    job: impl Fn(usize) -> Result<T, E> + Sync,
) -> Result<Vec<Result<T, E>>, &'static str> {
    let next = AtomicUsize::new(0);
    let workers = executor.workers().min(count);
    let mut outputs: Vec<Option<IndexedResults<T, E>>> = (0..workers).map(|_| None).collect();
    let completed = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        executor.scope(|scope| {
            for output in &mut outputs {
                let job = &job;
                let next = &next;
                scope.spawn(move |_| {
                    let mut results = Vec::new();
                    loop {
                        let index = next.fetch_add(1, Ordering::Relaxed);
                        if index >= count {
                            break;
                        }
                        results.push((index, job(index)));
                    }
                    *output = Some(results);
                });
            }
        });
    }));
    if completed.is_err() {
        return Err("initializer codegen worker panicked");
    }
    let mut ordered: Vec<Option<Result<T, E>>> = (0..count).map(|_| None).collect();
    for output in outputs {
        for (index, result) in output.ok_or("initializer codegen worker omitted its results")? {
            ordered[index] = Some(result);
        }
    }
    ordered
        .into_iter()
        .map(|result| result.ok_or("initializer codegen group result missing"))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn borrowed_jobs_preserve_ordinals_and_first_error() {
        let executor = BuildExecutor::new(3).unwrap();
        let values = [10, 20, 30, 40, 50];
        let results = ordered_jobs(values.len(), &executor, |index| {
            if index == 1 || index == 3 {
                Err(index)
            } else {
                Ok(values[index])
            }
        })
        .unwrap();
        assert_eq!(results, [Ok(10), Err(1), Ok(30), Err(3), Ok(50)]);
        assert_eq!(results.into_iter().collect::<Result<Vec<_>, _>>(), Err(1));
    }

    #[test]
    fn panic_joins_other_jobs_before_returning() {
        let executor = BuildExecutor::new(2).unwrap();
        let finished = AtomicUsize::new(0);
        let result = ordered_jobs(8, &executor, |index| {
            if index == 0 {
                panic!("intentional group panic");
            }
            finished.fetch_add(1, Ordering::Relaxed);
            Ok::<_, ()>(index)
        });
        assert_eq!(result.unwrap_err(), "initializer codegen worker panicked");
        assert_eq!(finished.load(Ordering::Relaxed), 7);
        assert_eq!(executor.install(|| 42), 42);
    }
}
