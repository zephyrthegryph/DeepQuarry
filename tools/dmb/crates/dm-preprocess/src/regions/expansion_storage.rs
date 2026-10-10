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
    /// Borrow every accessible owned field. Wire schema and admission are unchanged.
    /// Arc slice lengths are exact payload capacities; control blocks are excluded.
    pub fn visit_storage(&self, mut visit: impl FnMut(ExpansionStorageView<'_>)) {
        // Exhaustive field inventory makes newly retained owners require review.
        let ExpansionRecord {
            key: _,
            source: _,
            control: _,
            text: _,
            reads: _,
            locations: _,
            lines: _,
            diagnostics: _,
            fragments: _,
        } = self;
        visit(ExpansionStorageView::Source(&self.source));
        visit(slice_storage(&self.control));
        visit(ExpansionStorageView::Source(&self.text));
        visit(arc_storage(&self.reads));
        visit(vector_storage(&self.reads));
        for read in self.reads.iter() {
            visit(ExpansionStorageView::Text(&read.name));
            if let Some(definition) = &read.definition {
                visit(ExpansionStorageView::Macro(definition));
            }
        }
        visit(arc_storage(&self.locations));
        visit(vector_storage(&self.locations));
        for (_, _, location) in self.locations.iter() {
            visit(string_storage(location));
        }
        visit(arc_storage(&self.lines));
        visit(vector_storage(&self.lines));
        for line in self.lines.iter() {
            visit(vector_storage(&line.traces));
            for trace in &line.traces {
                visit(string_storage(&trace.name));
                visit(vector_storage(&trace.replacement_chain));
                for name in &trace.replacement_chain {
                    visit(string_storage(name));
                }
            }
        }
        visit(arc_storage(&self.diagnostics));
        visit(vector_storage(&self.diagnostics));
        for diagnostic in self.diagnostics.iter() {
            visit(string_storage(&diagnostic.message));
        }
        visit(vector_storage(&self.fragments));
        for fragment in &self.fragments {
            visit(slice_storage(&fragment.payload));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn record_visitor_reports_nested_owned_capacities_without_materialization() {
        let mut message = String::with_capacity(123);
        message.push_str("diagnostic");
        let pointer = message.as_ptr() as usize;
        let capacity = message.capacity();
        let mut chain = Vec::with_capacity(7);
        chain.push(String::from("nested"));
        let chain_pointer = chain.as_ptr() as usize;
        let chain_capacity = chain.capacity() * size_of::<String>();
        let fragment: Arc<[u8]> = Arc::from([1u8, 2, 3]);
        let fragment_pointer = fragment.as_ptr() as usize;
        let record = ExpansionRecord {
            key: 0,
            source: crate::SourceText::from(String::from("input")),
            control: Arc::from([0u8]),
            text: crate::SourceText::from(String::from("output")),
            reads: Arc::new(vec![]),
            locations: Arc::new(vec![(0, false, String::from("location"))]),
            lines: Arc::new(vec![Line {
                output: Span::new(0, 6),
                input: 0,
                traces: vec![Trace {
                    name: String::from("macro"),
                    invocation_span: Span::new(0, 1),
                    replacement_chain: chain,
                }],
            }]),
            diagnostics: Arc::new(vec![Error {
                input: 0,
                kind: DiagnosticKind::UserError,
                message,
            }]),
            fragments: vec![ParseFragment {
                schema: 0,
                span: Span::new(0, 1),
                payload: fragment,
            }],
        };
        let mut message_seen = false;
        let mut chain_seen = false;
        let mut fragment_seen = false;
        let mut sources = 0;
        record.visit_storage(|view| match view {
            ExpansionStorageView::Buffer {
                address,
                payload_bytes,
                capacity_bytes,
            } => {
                if address == pointer {
                    assert_eq!(payload_bytes, 10);
                    assert_eq!(capacity_bytes, capacity);
                    message_seen = true;
                }
                if address == chain_pointer {
                    assert_eq!(capacity_bytes, chain_capacity);
                    chain_seen = true;
                }
                if address == fragment_pointer {
                    assert_eq!((payload_bytes, capacity_bytes), (3, 3));
                    fragment_seen = true;
                }
            }
            ExpansionStorageView::Source(_) => sources += 1,
            _ => (),
        });
        assert!(message_seen && chain_seen && fragment_seen);
        assert_eq!(sources, 2);
    }
}
