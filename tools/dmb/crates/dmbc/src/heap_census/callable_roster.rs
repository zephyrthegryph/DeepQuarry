use super::*;
impl HeapCensus {
    pub(crate) fn callable_roster(&mut self, roster: &Arc<dm_tree::frontend::CallableRoster>) {
        use dm_tree::frontend::CallableRosterStorage as V;
        let name = "frontend.callable_roster";
        if !self.arc_object(name, roster) {
            return;
        }
        roster.visit_storage(|view| match view {
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
        });
        self.unknown(name, "strong semantic tree backing shared with snapshot; retained tree-only payload counted by snapshot visitor when present");
    }
}
