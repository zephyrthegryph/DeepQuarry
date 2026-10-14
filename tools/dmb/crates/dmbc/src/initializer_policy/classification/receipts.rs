//! Share exact repeated ancestry observations, retaining canonical replay order.
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning, SymbolId};
use dm_session::{Receipt, ReceiptGroupPool, ResolverRead};
use std::sync::Arc;

pub(crate) type ReceiptPool = ReceiptGroupPool<ResolveQuery, ResolvedMeaning, ReadDomain>;
pub(super) fn capture(
    reads: Vec<ResolverRead>,
    owner: SymbolId,
    pool: Option<&ReceiptPool>,
) -> Receipt<ResolveQuery, ResolvedMeaning, ReadDomain> {
    let Some(pool) = pool else {
        return reads.into();
    };
    let target = ResolveQuery::Ancestry(owner);
    let Some(start) = reads.iter().position(|read| read.query == target) else {
        return reads.into();
    };
    let end = start
        + reads[start..]
            .iter()
            .take_while(|read| read.query == target)
            .count();
    // RecordingResolver issues a canonical query-sorted ledger. Preserve equal
    // query ordering too: different answers/domain records may not be discarded.
    let mut before = reads;
    let after = before.split_off(end);
    let ancestry = before.split_off(start);
    let mut groups: Vec<Arc<[ResolverRead]>> = Vec::with_capacity(3);
    if !before.is_empty() {
        groups.push(before.into());
    }
    groups.push(pool.intern(ancestry));
    if !after.is_empty() {
        groups.push(after.into());
    }
    Receipt::from_groups(groups.into()).expect("recording resolver issues canonical reads")
}
