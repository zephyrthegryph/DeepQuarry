//! Order-preserving parallel maps for the front end's per-item passes (declaration origins, body indexing, body
//! terminations). Each pass visits every declaration or body of the program; split over the request's executor they cost a
//! fraction of the serial walk. The result is the serial result: chunks are contiguous, joined in order, and an error is the
//! first error in item order (each chunk stops at its own first error, and the chunks are read in order).

/// Items below this count are mapped on the calling thread.
const SERIAL_BELOW: usize = 8192;

/// `f(start, items[start..end])` for contiguous chunks of `items`, concatenated in order.
pub(super) fn chunked_map<T, R, E>(
    executor: &dm_exec::BuildExecutor,
    items: &[T],
    f: impl Fn(usize, &[T]) -> Result<Vec<R>, E> + Sync,
) -> Result<Vec<R>, E>
where
    T: Sync,
    R: Send,
    E: Send,
{
    let workers = executor.workers().max(1);
    if workers == 1 || items.len() < SERIAL_BELOW {
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

/// Several output vectors filled side by side (one value per item in each), appended chunk by chunk.
pub(super) trait Columns: Send {
    fn with_capacity(capacity: usize) -> Self;
    fn append(&mut self, other: Self);
}
impl<A: Send, B: Send> Columns for (Vec<A>, Vec<B>) {
    fn with_capacity(capacity: usize) -> Self {
        (Vec::with_capacity(capacity), Vec::with_capacity(capacity))
    }
    fn append(&mut self, other: Self) {
        self.0.extend(other.0);
        self.1.extend(other.1);
    }
}
impl<A: Send, B: Send, C: Send, D: Send> Columns for (Vec<A>, Vec<B>, Vec<C>, Vec<D>) {
    fn with_capacity(capacity: usize) -> Self {
        (Vec::with_capacity(capacity), Vec::with_capacity(capacity), Vec::with_capacity(capacity), Vec::with_capacity(capacity))
    }
    fn append(&mut self, other: Self) {
        self.0.extend(other.0);
        self.1.extend(other.1);
        self.2.extend(other.2);
        self.3.extend(other.3);
    }
}

/// `chunked_map` for a map that yields several values per item, returned as columns (no vector of tuples to split again).
pub(super) fn chunked_columns<T, C, E>(
    executor: &dm_exec::BuildExecutor,
    items: &[T],
    f: impl Fn(usize, &[T]) -> Result<C, E> + Sync,
) -> Result<C, E>
where
    T: Sync,
    C: Columns,
    E: Send,
{
    let workers = executor.workers().max(1);
    if workers == 1 || items.len() < SERIAL_BELOW {
        return f(0, items);
    }
    let chunk = items.len().div_ceil(workers * 4).max(1);
    let mut slots: Vec<Option<Result<C, E>>> = (0..items.len().div_ceil(chunk)).map(|_| None).collect();
    executor.scope(|scope| {
        for (index, slot) in slots.iter_mut().enumerate() {
            let f = &f;
            let start = index * chunk;
            let part = &items[start..(start + chunk).min(items.len())];
            scope.spawn(move |_| *slot = Some(f(start, part)));
        }
    });
    let mut out = C::with_capacity(items.len());
    for slot in slots {
        out.append(slot.expect("every chunk of a scoped map runs")?);
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
        let (doubled, tripled): (Vec<_>, Vec<_>) = super::chunked_columns(&executor, &items, |_, part| {
            Ok::<_, ()>((part.iter().map(|x| x * 2).collect(), part.iter().map(|x| x * 3).collect()))
        })
        .unwrap();
        assert_eq!(doubled, items.iter().map(|x| x * 2).collect::<Vec<_>>());
        assert_eq!(tripled, serial);
    }
}
