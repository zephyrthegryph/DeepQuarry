use super::*;
impl HeapCensus {
    pub(crate) fn callable_roster(&mut self, roster: &Arc<dm_tree::frontend::CallableRoster>) {
        use dm_tree::frontend::CallableRosterStorage as V;
        let name = "frontend.callable_roster";
        if !self.arc_object(name, roster) {
            return;
        }
        if let Some(abi) = roster.abi() {
            self.callable_abi_roster(abi);
        }
        let mut index_admitted = false;
        roster.visit_storage(|view| {
            if let V::IndexOwner(owner) = view {
                index_admitted = self.arc_object("frontend.callable_index_recipe", owner);
                return;
            }
            if !index_admitted { return; }
            match view {
            V::IndexOwner(_) => unreachable!("handled index owner"),
            V::SourceOrder(values) => { self.vec_payload(name, values); },
            V::Effective(values) => { self.vec_payload(name, values); },
            V::Bindings(values) => {
                self.observe_items(name, values.len());
                self.unknown(name, "symbolic source binding BTreeSet private nodes excluded");
            },
            V::Members(values) => { self.vec_payload(name, values); },
            V::Identities(values) => { self.vec_payload(name, values); },
            V::Ready(values) => { self.vec_payload(name, values); },
            V::Dependents(values) => {
                if self.vec_payload(name, values) {
                    for value in values { self.vec_payload(name, value); }
                }
            }
            V::Ordinals { len, capacity } => {
                self.observe_items(name, len);
                self.unknown(name, &format!("member ordinal HashMap backing: {len} entries/{capacity} capacity; private buckets excluded"));
            }
            }
        });
        self.unknown(name, "strong semantic tree backing shared with snapshot; retained tree-only payload counted by snapshot visitor when present");
    }
}
