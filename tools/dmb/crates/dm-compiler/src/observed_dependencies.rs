//! Stage-independent dependency recording and replay. Both positive and negative
//! observations are values; callers supply typed stage keys and portable values.
//! Persistence stores the ordered pairs, while Salsa consumes the same pairs as
//! input edges. No second dependency discovery pass is permitted.
use std::collections::BTreeMap;

pub(crate) fn record<K: Ord, V>(observations: &mut BTreeMap<K, V>, key: K, value: V) {
    observations.insert(key, value);
}

/// Replay only the recorded reads. A missing symbol is represented by the
/// stage's portable absent value, so adding a previously missing declaration
/// invalidates its readers without scanning the declaration inventory.
pub(crate) fn validate<'a, K: 'a, V: PartialEq + 'a>(
    observations: impl IntoIterator<Item = (&'a K, &'a V)>,
    mut resolve: impl FnMut(&K) -> V,
) -> bool {
    observations.into_iter().all(|(key, expected)| resolve(key) == *expected)
}
