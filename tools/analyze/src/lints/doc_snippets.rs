//! Original registry delegates the unique doc source/custom-baseline policy.
pub fn register(reg:&mut crate::lint::Registry){crate::doc_snippets_policy::register(reg)}
