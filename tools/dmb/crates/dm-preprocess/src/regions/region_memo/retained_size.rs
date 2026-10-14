//! Allocation-layout accounting; shared Arcs are conservatively charged per occurrence.
use crate::Macro;
use std::mem::{align_of, size_of};

pub(in crate::regions) fn arc_bytes(bytes: usize, alignment: usize) -> usize {
    bytes
        .saturating_add(2usize.saturating_mul(size_of::<usize>()))
        .saturating_add(alignment.max(align_of::<usize>()).saturating_sub(1))
}
pub(in crate::regions) fn record<T>() -> usize {
    arc_bytes(size_of::<T>(), align_of::<T>())
}
pub(in crate::regions) fn slice<T>(length: usize) -> usize {
    arc_bytes(length.saturating_mul(size_of::<T>()), align_of::<T>())
}
pub(in crate::regions) fn vector<T>(values: &Vec<T>, nested: impl Fn(&T) -> usize) -> usize {
    values.iter().fold(
        values.capacity().saturating_mul(size_of::<T>()),
        |total, value| total.saturating_add(nested(value)),
    )
}
pub(in crate::regions) fn macro_heap(value: &Macro) -> usize {
    value.replacement.capacity().saturating_add(
        value
            .parameters
            .as_ref()
            .map_or(0, |parameters| vector(parameters, String::capacity)),
    )
}
pub(in crate::regions) fn shared_macro(value: &Macro) -> usize {
    record::<Macro>().saturating_add(macro_heap(value))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn capacity_accounting_includes_unused_storage_and_saturates() {
        let mut values = Vec::with_capacity(31);
        let mut text = String::with_capacity(127);
        text.push('x');
        values.push(text);
        assert_eq!(
            vector(&values, String::capacity),
            values.capacity() * size_of::<String>() + values[0].capacity()
        );
        assert_eq!(slice::<u64>(usize::MAX), usize::MAX);
        assert_eq!(arc_bytes(usize::MAX, 8), usize::MAX);
    }
}
