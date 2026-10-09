//! Preserve the exact thread identity text without repeated formatting.
use std::cell::OnceCell;

thread_local! {
    static LABEL: OnceCell<String> = const { OnceCell::new() };
}

pub(crate) fn with_label<T>(visit: impl FnOnce(&str) -> T) -> T {
    LABEL.with(|label| visit(label.get_or_init(|| format!("{:?}", std::thread::current().id()))))
}

pub(crate) fn owned() -> String {
    with_label(str::to_owned)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exact_identity_reuses_the_same_thread_allocation() {
        let expected = format!("{:?}", std::thread::current().id());
        let first = with_label(|label| {
            assert_eq!(label, expected);
            label.as_ptr() as usize
        });
        assert_eq!(with_label(|label| label.as_ptr() as usize), first);
        assert_eq!(owned(), expected);
    }

    #[test]
    fn concurrent_workers_keep_distinct_exact_labels() {
        let workers: Vec<_> = (0..4)
            .map(|_| {
                std::thread::spawn(|| {
                    let expected = format!("{:?}", std::thread::current().id());
                    assert_eq!(owned(), expected);
                    owned()
                })
            })
            .collect();
        let labels: std::collections::BTreeSet<_> = workers
            .into_iter()
            .map(|worker| worker.join().unwrap())
            .collect();
        assert_eq!(labels.len(), 4);
        assert!(!labels.contains(&owned()));
    }
}
