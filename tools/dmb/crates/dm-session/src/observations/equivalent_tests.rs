use super::*;
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning, Resolver, SymbolId};
struct Host;
impl Resolver for Host {
    fn resolve(&self, q: ResolveQuery) -> ResolvedMeaning {
        ResolvedMeaning::Unsupported(q)
    }
}
fn equivalent(a: &ResolvedMeaning, b: &ResolvedMeaning) -> bool {
    <Host as ObservationHost<ResolveQuery, ResolvedMeaning, ReadDomain>>::equivalent(&Host, a, b)
}
#[test]
fn exact_answer_equality_preserves_canonical_physical_index_fallback() {
    assert!(equivalent(
        &ResolvedMeaning::Missing,
        &ResolvedMeaning::Missing
    ));
    assert!(!equivalent(
        &ResolvedMeaning::Missing,
        &ResolvedMeaning::Presence(false)
    ));
    let a = ResolvedMeaning::RetainedProc {
        declaring_owner: SymbolId::of("/datum"),
        name: SymbolId::of("New"),
        verb: false,
        engine_identity: 7,
        wire_proc: 1,
    };
    let mut b = a.clone();
    if let ResolvedMeaning::RetainedProc { wire_proc, .. } = &mut b {
        *wire_proc = 9;
    }
    assert_ne!(a, b);
    assert!(
        equivalent(&a, &b),
        "wire index is intentionally absent from canonical semantic evidence"
    );
    if let ResolvedMeaning::RetainedProc {
        engine_identity, ..
    } = &mut b
    {
        *engine_identity = 8;
    }
    assert!(!equivalent(&a, &b));
}
