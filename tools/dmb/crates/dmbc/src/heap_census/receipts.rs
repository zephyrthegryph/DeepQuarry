//! Inspect physical receipt owners without materializing their canonical stream.
use super::HeapCensus;
use dm_session::{Receipt, ReceiptStorageView};

impl HeapCensus {
    pub(crate) fn receipt<Q, A, D>(&mut self, owner: &str, reads: &Receipt<Q, A, D>) -> bool {
        let mut fresh = false;
        reads.visit_storage(|storage| {
            fresh |= match storage {
                ReceiptStorageView::Flat(values) => self.slice(owner, values, true),
                ReceiptStorageView::Groups(groups) => self.slice(owner, groups, true),
            };
        });
        fresh
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_session::Observation;
    use std::{mem::size_of, sync::Arc};

    #[test]
    fn grouped_receipts_charge_shared_leaves_once_without_flattening() {
        type Read = Observation<u32, u32, ()>;
        let shared: Arc<[Read]> = Arc::from([Read {
            query: 1,
            answer: 9,
            domain: (),
        }]);
        let left: Receipt<_, _, _> =
            Receipt::from_groups(Arc::from([Arc::clone(&shared)])).unwrap();
        let right: Receipt<_, _, _> =
            Receipt::from_groups(Arc::from([Arc::clone(&shared)])).unwrap();
        assert!(left.flat().is_none());
        let mut census = HeapCensus::new("receipt");
        assert!(census.receipt("left", &left));
        assert!(census.receipt("right", &right));
        assert!(!census.receipt("alias", &left.clone()));
        let report = census.finish();
        assert_eq!(
            report.unique_known_capacity_bytes,
            (size_of::<Read>() + 2 * size_of::<Arc<[Read]>>()) as u64
        );
        assert_eq!(
            left.iter().map(|read| read.answer).collect::<Vec<_>>(),
            vec![9]
        );
        assert!(left.flat().is_none());
    }
}
