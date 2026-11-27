//! Order-preserving parallel maps for the front end's per-item passes (declaration origins, body indexing, body
//! terminations). Each pass visits every declaration or body of the program; split over the request's executor they cost a
//! fraction of the serial walk. The result is the serial result: chunks are contiguous, joined in order, and an error is the
//! first error in item order (each chunk stops at its own first error, and the chunks are read in order).

/// Items below this count are mapped on the calling thread.
const SERIAL_BELOW: usize = 8192;

/// `f(start, items[start..end])` for contiguous chunks of `items`, concatenated in order.
pub(crate) fn chunked_map<T, R, E>(
    executor: &dm_exec::BuildExecutor,
    items: &[T],
    f: impl Fn(usize, &[T]) -> Result<Vec<R>, E> + Sync,
) -> Result<Vec<R>, E>
where
    T: Sync,
    R: Send,
    E: Send,
{
    chunked_map_above(executor, items, SERIAL_BELOW, f)
}

/// [`chunked_map`] for items that each cost more (a whole owner): mapped on
/// the calling thread below `serial_below` items.
pub(crate) fn chunked_map_above<T, R, E>(
    executor: &dm_exec::BuildExecutor,
    items: &[T],
    serial_below: usize,
    f: impl Fn(usize, &[T]) -> Result<Vec<R>, E> + Sync,
) -> Result<Vec<R>, E>
where
    T: Sync,
    R: Send,
    E: Send,
{
    let workers = executor.workers().max(1);
    if workers == 1 || items.len() < serial_below {
        return f(0, items);
    }
    // A few chunks per worker, so one slow chunk (a large file's declarations) does not hold the pass.
    let chunk = items.len().div_ceil(workers * 4).max(1);
    let mut slots: Vec<Option<Result<Vec<R>, E>>> = (0..items.len().div_ceil(chunk)).map(|_| None).collect();
    executor.scope(|scope| {
        for (index, slot) in slots.iter_mut().enumerate() {
            let f = &f;
            let start = index * chunk;
            let part = &items[start..(start + chunk).min(items.len())];
            scope.spawn(move |_| *slot = Some(f(start, part)));
        }
    });
    let mut out = Vec::with_capacity(items.len());
    for slot in slots {
        out.extend(slot.expect("every chunk of a scoped map runs")?);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    #[test]
    fn chunked_map_equals_the_serial_map_and_reports_the_first_error() {
        let executor = dm_exec::BuildExecutor::new(4).unwrap();
        let items: Vec<usize> = (0..50_000).collect();
        let serial: Vec<usize> = items.iter().map(|x| x * 3).collect();
        let parallel = super::chunked_map(&executor, &items, |start, part| {
            Ok::<_, ()>(part.iter().enumerate().map(|(i, x)| {
                assert_eq!(start + i, *x);
                x * 3
            }).collect())
        })
        .unwrap();
        assert_eq!(parallel, serial);
        let first = super::chunked_map(&executor, &items, |_, part| {
            part.iter().map(|x| if x % 9000 == 8999 { Err(*x) } else { Ok(*x) }).collect::<Result<Vec<_>, _>>()
        });
        assert_eq!(first, Err(8999));
    }
}
