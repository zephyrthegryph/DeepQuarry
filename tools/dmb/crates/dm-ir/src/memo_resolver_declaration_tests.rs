use super::*;
use crate::{DeclarationMeaning, ProcedureDefinition, ProcedureIdentity, SymbolId};
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};
pub(super) fn declaration() -> ResolvedMeaning {
    ResolvedMeaning::Declaration {
        identity: ProcedureIdentity {
            owner: SymbolId::of("/datum/probe"),
            name: SymbolId::of("read"),
            verb: false,
            occurrence: 0,
        },
        definition: ProcedureDefinition::Declare,
        previous: None,
        data: Arc::new(DeclarationMeaning {
            inherited_opaque: None,
            declared_type: None,
            list_element_type: None,
            display_name: None,
            flags: 0,
            procedure: None,
            array: None,
            initializer: None,
            declared_initializer: None,
            resolved_constant: None,
            canonical: Arc::from(&b"exact declaration recipe"[..]),
        }),
    }
}
struct Host {
    calls: AtomicUsize,
    answer: ResolvedMeaning,
}
impl Resolver for Host {
    fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
        self.calls.fetch_add(1, Ordering::Relaxed);
        self.answer.clone()
    }
}
#[test]
fn bounded_declaration_chains_share_request_answers_and_negative_meanings() {
    let identity = ProcedureIdentity {
        owner: SymbolId::of("/datum/probe"),
        name: SymbolId::of("read"),
        verb: false,
        occurrence: 0,
    };
    let query = ResolveQuery::DeclarationChain {
        owner: identity.owner,
        name: identity.name,
        verb: false,
    };
    for answer in [
        ResolvedMeaning::Members(Arc::from([declaration()])),
        ResolvedMeaning::Missing,
        ResolvedMeaning::Presence(false),
    ] {
        let host = Host {
            calls: AtomicUsize::new(0),
            answer: answer.clone(),
        };
        let memo = MemoResolver::new(&host, 4);
        assert_eq!(memo.resolve(query), answer);
        assert_eq!(memo.resolve(query), answer);
        assert_eq!(host.calls.load(Ordering::Relaxed), 1);
        assert_eq!(memo.stats().hits, 1);
    }
}
#[test]
fn oversized_declaration_chain_keeps_existing_descriptor_and_node_limits() {
    let mut count = SEQUENCE_BYTES / std::mem::size_of::<ResolvedMeaning>() + 1;
    count = count.max(SEQUENCE_NODES + 1);
    let answer = ResolvedMeaning::Members((0..count).map(|_| declaration()).collect());
    let host = Host {
        calls: AtomicUsize::new(0),
        answer,
    };
    let memo = MemoResolver::new(&host, 4);
    let query = ResolveQuery::DeclarationChain {
        owner: SymbolId::of("/datum/probe"),
        name: SymbolId::of("read"),
        verb: false,
    };
    memo.resolve(query);
    memo.resolve(query);
    assert_eq!(host.calls.load(Ordering::Relaxed), 2);
    assert_eq!(memo.stats().retained_entries, 0);
}
