//! Borrowed diagnostics only; no traversal or allocation on admission paths.
use super::*;
use std::mem::size_of;
/// Actual accessible backing capacities. Arc control blocks, map nodes and
/// allocator overhead are unknown and must not be represented as exact bytes.
pub enum ExpansionStorageView<'a> {
    Buffer {
        address: usize,
        payload_bytes: usize,
        capacity_bytes: usize,
    },
    Source(&'a crate::SourceText),
    Text(&'a Arc<str>),
    Macro(&'a Arc<Macro>),
    Index {
        entries: usize,
    },
}
pub(in crate::regions) fn vector_storage<T>(value: &Vec<T>) -> ExpansionStorageView<'_> {
    ExpansionStorageView::Buffer {
        address: value.as_ptr() as usize,
        payload_bytes: value.len().saturating_mul(size_of::<T>()),
        capacity_bytes: value.capacity().saturating_mul(size_of::<T>()),
    }
}
pub(in crate::regions) fn string_storage(value: &String) -> ExpansionStorageView<'_> {
    ExpansionStorageView::Buffer {
        address: value.as_ptr() as usize,
        payload_bytes: value.len(),
        capacity_bytes: value.capacity(),
    }
}
pub(in crate::regions) fn arc_storage<T>(value: &Arc<T>) -> ExpansionStorageView<'_> {
    ExpansionStorageView::Buffer {
        address: Arc::as_ptr(value) as usize,
        payload_bytes: size_of::<T>(),
        capacity_bytes: size_of::<T>(),
    }
}
pub(in crate::regions) fn slice_storage<T>(value: &[T]) -> ExpansionStorageView<'_> {
    let bytes = std::mem::size_of_val(value);
    ExpansionStorageView::Buffer {
        address: value.as_ptr() as usize,
        payload_bytes: bytes,
        capacity_bytes: bytes,
    }
}
impl ExpansionRecord {
    pub fn visit_storage(&self, mut visit: impl FnMut(ExpansionStorageView<'_>)) {
        visit(ExpansionStorageView::Text(&self.source));
        visit(slice_storage(&self.control));
        visit(ExpansionStorageView::Text(&self.text));
        visit(vector_storage(&self.reads));
        for read in &self.reads {
            visit(ExpansionStorageView::Text(&read.name));
            if let Some(definition) = &read.definition {
                visit(ExpansionStorageView::Macro(definition));
            }
        }
        visit(vector_storage(&self.locations));
        for (_, _, location) in &self.locations {
            visit(string_storage(location));
        }
        visit(vector_storage(&self.lines));
        for line in &self.lines {
            visit(vector_storage(&line.traces));
            for trace in &line.traces {
                visit(string_storage(&trace.name));
                visit(vector_storage(&trace.replacement_chain));
                for name in &trace.replacement_chain {
                    visit(string_storage(name));
                }
            }
        }
        visit(vector_storage(&self.diagnostics));
        for diagnostic in &self.diagnostics {
            visit(string_storage(&diagnostic.message));
        }
        visit(vector_storage(&self.fragments));
        for fragment in &self.fragments {
            visit(slice_storage(&fragment.payload));
        }
    }
}
