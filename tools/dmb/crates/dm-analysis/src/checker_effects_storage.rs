//! Exposed capacities of unique checker work, kept separate from admission
//! estimates and allocator/RSS claims. Shared original owners are not copied.
use super::*;
#[derive(Clone, Copy, Debug)]
pub enum Storage {
    Buffer {
        owner: &'static str,
        address: usize,
        logical: usize,
        capacity: usize,
    },
    Unknown {
        owner: &'static str,
        items: usize,
    },
}
fn buf<T>(owner: &'static str, s: &[T], capacity: usize, v: &mut impl FnMut(Storage)) {
    v(Storage::Buffer {
        owner,
        address: s.as_ptr() as usize,
        logical: std::mem::size_of_val(s),
        capacity: capacity.saturating_mul(std::mem::size_of::<T>()),
    });
}
fn object<T>(owner: &'static str, x: &T, v: &mut impl FnMut(Storage)) {
    v(Storage::Buffer {
        owner,
        address: x as *const T as usize,
        logical: std::mem::size_of::<T>(),
        capacity: std::mem::size_of::<T>(),
    });
}
fn string(s: &String, v: &mut impl FnMut(Storage)) {
    buf("purity.diagnostic_text", s.as_bytes(), s.capacity(), v)
}
fn point(p: &SourceNoteOrigin, v: &mut impl FnMut(Storage)) {
    object("purity.original_path_owner", p.path.as_ref(), v);
    let b = p.path.as_os_str().as_encoded_bytes();
    buf("purity.original_path", b, p.path.capacity(), v)
}
fn diagnostic(d: &Diagnostic, v: &mut impl FnMut(Storage)) {
    string(&d.message, v);
    buf("purity.notes", &d.notes, d.notes.capacity(), v);
    for n in &d.notes {
        string(&n.message, v);
        if let Some(p) = &n.source {
            point(p, v)
        }
    }
}
impl EffectInput {
    pub fn visit_storage(&self, v: &mut impl FnMut(Storage)) {
        object("purity.input", self, v);
        buf(
            "purity.original_identity_order",
            &self.order,
            self.order.len(),
            v,
        );
        if let Some(receipt)=&self.original_receipt{v(Storage::Buffer{owner:"checker.original_receipt_weak_backing",address:receipt.as_ptr()as usize,logical:0,capacity:std::mem::size_of::<dm_tree::diagnostic_declarations::DiagnosticDeclarationReceipt>()+2*std::mem::size_of::<usize>()});}
    }
}
impl BodyEffects {
    pub fn visit_storage(&self, v: &mut impl FnMut(Storage)) {
        object("purity.body", self, v);
        match &self.callable_origin{Ok(origin)=>point(origin,v),Err(_)=>{}}
        buf("purity.direct", &self.direct, self.direct.len(), v);
        buf("purity.calls", &self.calls, self.calls.len(), v);
        buf("effects.blocking", &self.blocking, self.blocking.len(), v);
        buf("purity.immediate", &self.immediate, self.immediate.len(), v);
        buf("checker.original_body_diagnostics",&self.original,self.original.len(),v);buf("checker.accepted_keyword_uses",&self.keywords,self.keywords.len(),v);for row in self.original.iter(){diagnostic(&row.diagnostic,v)}
        for d in self.immediate.iter() {
            diagnostic(d, v)
        }
    }
}
impl EffectPlan {
    pub fn visit_storage(&self, v: &mut impl FnMut(Storage)) {
        object("purity.plan", self, v);
        buf("purity.bodies", &self.bodies, self.bodies.len(), v);
        for b in self.bodies.iter() {
            b.visit_storage(v)
        }
        buf(
            "purity.adjacency",
            &self.adjacency,
            self.adjacency.capacity(),
            v,
        );
        for row in &self.adjacency {
            buf("purity.edges", row, row.capacity(), v)
        }
        buf(
            "purity.overrides",
            &self.overrides,
            self.overrides.capacity(),
            v,
        );
        for row in &self.overrides {
            buf("purity.override_edges", row, row.capacity(), v)
        }
        buf(
            "purity.SCC_components",
            &self.components,
            self.components.capacity(),
            v,
        );
        v(Storage::Unknown {
            owner: "purity.procedure_index_BTree_nodes",
            items: self.index.len(),
        });
    }
}
impl SccSummary {
    pub fn visit_storage(&self, v: &mut impl FnMut(Storage)) {
        object("purity.SCC_summary", self, v);
        buf(
            "purity.SCC_effect_flags",
            &self.has_effect,
            self.has_effect.len(),
            v,
        );
        self.plan.visit_storage(v)
    }
}
pub fn visit_report(rows: &Vec<Produced>, v: &mut impl FnMut(Storage)) {
    object("purity.report", rows, v);
    buf("purity.report_rows", rows, rows.capacity(), v);
    for r in rows {produced(r,v)}
}

// Conservative cache admission, NOT a full allocator/RSS measurement. Sum
// actual exposed capacities without allocating a second census/map; aliases
// may be counted repeatedly. That safely overcounts shared original paths and
// body owners, including when a returned report outlives its source snapshot.
const ALLOCATION_ENVELOPE: usize = 64;
const UNKNOWN_NODE_ENVELOPE: usize = 1024;
fn retained_bound(mut visit: impl FnMut(&mut dyn FnMut(Storage))) -> usize {
    let mut total = 0usize;
    visit(&mut |allocation| {
        total = total.saturating_add(match allocation {
            Storage::Buffer { capacity, .. } => capacity.saturating_add(ALLOCATION_ENVELOPE),
            Storage::Unknown { items, .. } => items
                .saturating_mul(UNKNOWN_NODE_ENVELOPE)
                .saturating_add(UNKNOWN_NODE_ENVELOPE),
        });
    });
    total
}
pub(super) fn body_capacity_bound(body: &BodyEffects) -> usize {
    retained_bound(|visit| body.visit_storage(&mut |s| visit(s)))
}
pub(super) fn plan_capacity_bound(plan: &EffectPlan) -> usize {
    retained_bound(|visit| plan.visit_storage(&mut |s| visit(s)))
}
pub(super) fn summary_capacity_bound(summary: &SccSummary) -> usize {
    retained_bound(|visit| summary.visit_storage(&mut |s| visit(s)))
}
pub fn report_capacity_bound(rows: &Vec<Produced>) -> usize {
    retained_bound(|visit| visit_report(rows, &mut |s| visit(s)))
}
#[cfg(test)]
mod capacity_tests {
    use super::*;
    #[test]
    fn report_admission_accounts_real_spare_message_and_path_capacity_without_a_second_census() {
        // Resource-container fixture only, not fabricated semantic judgment evidence.
        let path = Arc::new(std::path::PathBuf::from("fixture.dm"));
        let mut rows = vec![Produced {
            phase: ProducedPhase::BodyImmediate,
            registration_tag: None,
            severity: DiagnosticSeverity::Error,
            diagnostic: Diagnostic {
                family: "must_be_pure",
                severity: Severity::Error,
                span: Span::new(0, 1),
                expression_span: Span::new(0, 1),
                message: "refusal".into(),
                notes: Vec::new(),
            },
            origin: SourceNoteOrigin {
                path,
                line: 1,
                byte_column: 1,
            },
        }];
        let initial = report_capacity_bound(&rows);
        let old_message = rows[0].diagnostic.message.capacity();
        let old_path = rows[0].origin.path.capacity();
        rows[0].diagnostic.message.reserve_exact(8192);
        Arc::make_mut(&mut rows[0].origin.path).reserve(4096);
        let message_delta = rows[0].diagnostic.message.capacity() - old_message;
        let path_delta = rows[0].origin.path.capacity() - old_path;
        assert!(message_delta > 0 && path_delta > 0);
        assert_eq!(
            report_capacity_bound(&rows) - initial,
            message_delta + path_delta
        );
        assert_eq!(rows[0].diagnostic.message, "refusal");
        assert_eq!(rows[0].origin.path.as_os_str(), "fixture.dm");
    }
}

fn produced(row:&Produced,visit:&mut impl FnMut(Storage)){diagnostic(&row.diagnostic,visit);point(&row.origin,visit)}
pub(super) fn produced_capacity_bound(row:&Produced)->usize{retained_bound(|visit|produced(row,&mut|allocation|visit(allocation)))}
