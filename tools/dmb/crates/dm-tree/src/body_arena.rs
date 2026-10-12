//! Lazy full-body syntax owned by one build, never persisted with semantic facts.
use super::{internal, BodyOccurrence, ColdFrontend, Diagnostic, ParsedBody};
use std::sync::{Mutex, MutexGuard};

/// Startup may inspect stored declarations before lowering takes the same AST.
/// Only inspected bodies are retained; taking a body releases its arena slot.
pub struct BodyArena<'frontend> {
    frontend: &'frontend ColdFrontend,
    statement_support: Option<fn(&[dm_syntax::Statement]) -> bool>,
    ordinal_base: usize,
    slots: Vec<Mutex<BodyState<'frontend>>>,
    #[cfg(test)]
    parses: std::sync::atomic::AtomicUsize,
}

enum BodyState<'frontend> {
    Unparsed,
    Ready(Box<Result<ParsedBody<'frontend>, Diagnostic>>),
    Consumed,
}

/// Diagnostic backing metadata; addresses are never semantic identities.
pub struct BodyArenaStorage {
    pub address: usize,
    pub len: usize,
    pub capacity: usize,
    pub slot_bytes: usize,
}

impl<'frontend> BodyArena<'frontend> {
    pub fn retained_result_bytes() -> usize {
        std::mem::size_of::<Result<ParsedBody<'frontend>, Diagnostic>>()
    }
    /// Borrow only already-retained results, without parsing or consuming slots.
    /// The callback holds one slot lock and must not reenter that same slot.
    /// Call at a quiescent boundary for a consistent whole-arena census.
    pub fn visit_retained(
        &self,
        mut visitor: impl FnMut(usize, Result<&ParsedBody<'frontend>, &Diagnostic>),
    ) -> BodyArenaStorage {
        for (ordinal, slot) in self.slots.iter().enumerate() {
            let slot = slot.lock().unwrap_or_else(|error| error.into_inner());
            if let BodyState::Ready(result) = &*slot {
                visitor(self.ordinal_base + ordinal, result.as_ref().as_ref());
            }
        }
        BodyArenaStorage {
            address: self.slots.as_ptr() as usize,
            len: self.slots.len(),
            capacity: self.slots.capacity(),
            slot_bytes: std::mem::size_of::<Mutex<BodyState<'frontend>>>(),
        }
    }
    pub fn new(frontend: &'frontend ColdFrontend) -> Self {
        Self {
            frontend,
            statement_support: None,
            ordinal_base: 0,
            slots: (0..frontend.issued_bodies.len())
                .map(|_| Mutex::new(BodyState::Unparsed))
                .collect(),
            #[cfg(test)]
            parses: std::sync::atomic::AtomicUsize::new(0),
        }
    }

    /// Production bodies retain one admitted statement model, or lossless
    /// syntax when the target needs its existing fallback. Parsing stays lazy.
    pub fn new_typed(
        frontend: &'frontend ColdFrontend,
        supported: fn(&[dm_syntax::Statement]) -> bool,
    ) -> Self {
        let mut arena = Self::new(frontend);
        arena.statement_support = Some(supported);
        arena
    }
    /// Independently parse one current issued body with the same statement policy.
    /// The original slot may be consumed; no parsed state or other body slots are copied.
    pub fn fork_body(&self, occurrence: &BodyOccurrence) -> Result<Self, Diagnostic> {
        // The ordinary slot lookup authenticates both the exact issuance and scope.
        drop(self.slot(occurrence)?);
        let ordinal = self.frontend.body_by_declaration[&occurrence.declaration];
        Ok(Self {
            frontend: self.frontend,
            statement_support: self.statement_support,
            ordinal_base: ordinal,
            slots: vec![Mutex::new(BodyState::Unparsed)],
            #[cfg(test)]
            parses: std::sync::atomic::AtomicUsize::new(0),
        })
    }
    /// Inspect one issued body. The callback runs under this body's slot lock;
    /// it must not recursively access the same slot. Other bodies are independent.
    pub fn with_parsed<R>(
        &self,
        occurrence: &BodyOccurrence,
        operation: impl FnOnce(&ParsedBody<'frontend>) -> R,
    ) -> Result<R, Diagnostic> {
        let mut slot = self.slot(occurrence)?;
        self.ensure_parsed(&mut slot, occurrence);
        match &*slot {
            BodyState::Ready(result) => match result.as_ref() {
                Ok(parsed) => Ok(operation(parsed)),
                Err(error) => Err(error.clone()),
            },
            BodyState::Consumed => Err(internal("parsed body was already consumed")),
            BodyState::Unparsed => unreachable!("body parse fills its slot"),
        }
    }

    /// Move syntax to its final consumer. Even a failed parse is consumed once;
    /// later consumers receive an internal error rather than triggering a reparse.
    pub fn take_parsed(
        &self,
        occurrence: &BodyOccurrence,
    ) -> Result<ParsedBody<'frontend>, Diagnostic> {
        let mut slot = self.slot(occurrence)?;
        self.ensure_parsed(&mut slot, occurrence);
        match std::mem::replace(&mut *slot, BodyState::Consumed) {
            BodyState::Ready(result) => *result,
            BodyState::Consumed => Err(internal("parsed body was already consumed")),
            BodyState::Unparsed => unreachable!("body parse fills its slot"),
        }
    }

    /// Release a memo-hit body's slot without parsing uninspected syntax. A
    /// previously observed syntax error is preserved; consumption is terminal.
    pub fn discard_parsed(&self, occurrence: &BodyOccurrence) -> Result<(), Diagnostic> {
        let mut slot = self.slot(occurrence)?;
        match std::mem::replace(&mut *slot, BodyState::Consumed) {
            BodyState::Ready(result) => (*result).map(|_| ()),
            BodyState::Consumed => Err(internal("parsed body was already consumed")),
            BodyState::Unparsed => Ok(()),
        }
    }

    fn slot(
        &self,
        occurrence: &BodyOccurrence,
    ) -> Result<MutexGuard<'_, BodyState<'frontend>>, Diagnostic> {
        self.frontend.compact_body(occurrence)?;
        let ordinal = *self
            .frontend
            .body_by_declaration
            .get(&occurrence.declaration)
            .ok_or_else(|| internal("body arena occurrence has no issued ordinal"))?;
        if !std::ptr::eq(&self.frontend.issued_bodies[ordinal], occurrence) {
            return Err(internal(
                "body arena occurrence belongs to a different issuance",
            ));
        }
        let index = ordinal
            .checked_sub(self.ordinal_base)
            .filter(|index| *index < self.slots.len())
            .ok_or_else(|| internal("body is outside this arena's issued scope"))?;
        Ok(self.slots[index]
            .lock()
            .unwrap_or_else(|error| error.into_inner()))
    }

    fn ensure_parsed(&self, slot: &mut BodyState<'frontend>, occurrence: &BodyOccurrence) {
        if matches!(slot, BodyState::Unparsed) {
            // Counts actual lazy parse executions, independently of consumers
            // demanding a body or reusing an already prepared statement owner.
            let _profile = dm_profile::item("frontend.body_arena_parse");
            #[cfg(test)]
            self.parses
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            *slot = BodyState::Ready(Box::new(self.frontend.parse_body(occurrence).map(
                |parsed| match self.statement_support {
                    Some(supported) => parsed.admit_statements(supported),
                    None => parsed,
                },
            )));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::frontend::{build, DiagnosticKind};
    use std::collections::BTreeMap;
    use std::path::Path;
    use std::sync::atomic::Ordering;

    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    fn frontend() -> ColdFrontend {
        build(Path::new("project.dme"), &Source("/proc/probe()\n    if(1)\n        set waitfor = 0\n        return 7\n/proc/other()\n    return 2\n"), &BTreeMap::new(), 1).unwrap()
    }

    #[test]
    fn single_body_fork_preserves_policy_and_current_issuance_after_consumption() {
        let frontend = frontend();
        let foreign = self::frontend();
        let arena = BodyArena::new_typed(&frontend, |_| true);
        let body = &frontend.bodies[1];
        arena.discard_parsed(body).unwrap();
        let fork = arena.fork_body(body).unwrap();
        assert_eq!(fork.slots.len(), 1);
        assert!(fork.fork_body(&foreign.bodies[1]).is_err());
        assert!(fork.take_parsed(&frontend.bodies[0]).is_err());
        let parsed = fork.take_parsed(body).unwrap();
        assert!(parsed.statement_body().is_some());
        assert!(parsed.item().children.is_empty());
        assert!(arena.take_parsed(body).is_err());
        assert_eq!(arena.parses.load(Ordering::Relaxed), 0);
        assert_eq!(fork.parses.load(Ordering::Relaxed), 1);
    }
    #[test]
    fn lazy_slots_do_not_reserve_each_unparsed_body_payload() {
        let compact = std::mem::size_of::<Mutex<BodyState<'static>>>();
        let inline = std::mem::size_of::<Mutex<Result<ParsedBody<'static>, Diagnostic>>>();
        assert!(compact < inline);
        eprintln!(
            "body arena compact slot {compact} bytes; former inline payload slot {inline} bytes"
        );
    }
    #[test]
    fn stored_receipt_is_shared_and_rejects_wrong_identity_before_capture() {
        let frontend = build(
            Path::new("project.dme"),
            &Source("/proc/probe()\n    var/static/cache = 1\n    return cache\n"),
            &BTreeMap::new(),
            1,
        )
        .unwrap();
        let arena = BodyArena::new_typed(&frontend, |_| true);
        let identity = dm_ir::ProcedureIdentity {
            owner: dm_ir::SymbolId::of("/"),
            name: dm_ir::SymbolId::of("probe"),
            verb: false,
            occurrence: 0,
        };
        let receipt = arena
            .with_parsed(&frontend.bodies[0], |parsed| {
                let mut wrong = identity;
                wrong.occurrence = 1;
                assert!(parsed.capture_stored_declarations(wrong).is_err());
                assert!(parsed.stored_declaration_receipt().is_none());
                let receipt = parsed.capture_stored_declarations(identity).unwrap();
                let again = parsed.capture_stored_declarations(identity).unwrap();
                assert!(std::sync::Arc::ptr_eq(&receipt, &again));
                let legacy = crate::procedure_statics::capture_issued_statements(
                    identity,
                    parsed.statement_body().unwrap(),
                )
                .unwrap();
                assert_eq!(receipt.plan().declarations, legacy.declarations);
                assert_eq!(receipt.plan().origins, legacy.origins);
                receipt
            })
            .unwrap();
        let taken = arena.take_parsed(&frontend.bodies[0]).unwrap();
        assert!(std::sync::Arc::ptr_eq(
            &receipt,
            &taken.stored_declaration_receipt().unwrap()
        ));
        drop(taken);
        assert_eq!(receipt.plan().declarations.len(), 1);
        assert_eq!(arena.parses.load(Ordering::Relaxed), 1);
    }
    #[test]
    fn typed_body_is_lazy_shared_with_startup_and_consumed_once() {
        let frontend = frontend();
        let arena = BodyArena::new_typed(&frontend, |_| true);
        assert_eq!(arena.parses.load(Ordering::Relaxed), 0);
        let body = &frontend.bodies[0];
        let statements = arena
            .with_parsed(body, |parsed| {
                assert!(parsed.item().children.is_empty());
                parsed
                    .statement_body()
                    .unwrap()
                    .parsed()
                    .statements
                    .as_ptr()
            })
            .unwrap();
        let taken = arena.take_parsed(body).unwrap();
        assert!(taken.item().children.is_empty());
        assert_eq!(
            taken.statement_body().unwrap().parsed().statements.as_ptr(),
            statements
        );
        assert_eq!(arena.parses.load(Ordering::Relaxed), 1);
        assert!(arena.take_parsed(body).is_err());
    }
    #[test]
    fn rejected_typed_admission_preserves_lossless_and_statement_model() {
        let frontend = frontend();
        let arena = BodyArena::new_typed(&frontend, |_| false);
        let parsed = arena.take_parsed(&frontend.bodies[0]).unwrap();
        assert!(!parsed.item().children.is_empty());
        assert!(parsed.statement_body().is_some());
        assert!(parsed.statement_attempted());
    }
    #[test]
    fn retained_visit_neither_parses_nor_consumes() {
        let frontend = frontend();
        let arena = BodyArena::new(&frontend);
        let storage = arena.visit_retained(|_, _| panic!("nothing retained"));
        assert_eq!(storage.len, frontend.bodies.len());
        assert!(storage.capacity >= storage.len);
        assert_eq!(arena.parses.load(Ordering::Relaxed), 0);
        arena.with_parsed(&frontend.bodies[0], |_| ()).unwrap();
        let mut visited = Vec::new();
        arena.visit_retained(|ordinal, parsed| {
            visited.push(ordinal);
            assert_eq!(
                parsed.unwrap().occurrence().declaration,
                frontend.bodies[0].declaration
            );
        });
        assert_eq!(visited, [0]);
        assert_eq!(arena.parses.load(Ordering::Relaxed), 1);
        arena.take_parsed(&frontend.bodies[0]).unwrap();
        arena.visit_retained(|_, _| panic!("consumed slot retained"));
    }

    #[test]
    fn startup_inspection_and_lowering_take_parse_once_and_release_slot() {
        let frontend = frontend();
        let arena = BodyArena::new(&frontend);
        let body = &frontend.bodies[0];
        let expected = frontend.body(body).unwrap();
        for _ in 0..2 {
            arena
                .with_parsed(body, |parsed| assert_eq!(parsed.item(), &expected))
                .unwrap();
        }
        assert_eq!(arena.parses.load(Ordering::Relaxed), 1);
        assert!(matches!(
            *arena.slots[1].lock().unwrap(),
            BodyState::Unparsed
        ));
        let owned = arena.take_parsed(body).unwrap();
        assert_eq!(owned.item(), &expected);
        assert!(matches!(
            *arena.slots[0].lock().unwrap(),
            BodyState::Consumed
        ));
        assert!(arena.take_parsed(body).is_err());
        assert!(arena.with_parsed(body, |_| ()).is_err());
        assert_eq!(arena.parses.load(Ordering::Relaxed), 1);
        frontend.validate_parsed_body(&owned, body).unwrap();
        let executable = crate::settings::strip_setting_items(owned.item().children.clone());
        assert_eq!(executable[0].header, "if(1)");
        assert_eq!(executable[0].children.len(), 1);
        assert_eq!(executable[0].children[0].header, "return 7");
    }

    #[test]
    fn ordinary_locals_do_not_retain_stored_header_roster_but_statics_do() {
        for (source, expected_static) in [
            (
                "/proc/probe()\n    var/local = 1\n    return local\n",
                false,
            ),
            (
                "/proc/probe()\n    var/static/local = 1\n    return local\n",
                true,
            ),
        ] {
            let frontend = build(
                Path::new("project.dme"),
                &Source(source),
                &BTreeMap::new(),
                1,
            )
            .unwrap();
            let arena = BodyArena::new_typed(&frontend, |_| true);
            let identity = dm_ir::ProcedureIdentity {
                owner: dm_ir::SymbolId::of("/"),
                name: dm_ir::SymbolId::of("probe"),
                verb: false,
                occurrence: 0,
            };
            arena
                .with_parsed(&frontend.bodies[0], |parsed| {
                    let body = parsed.statement_body().unwrap();
                    assert_eq!(body.may_contain_stored_declarations(), expected_static);
                    let (length, capacity) = body.declaration_header_storage();
                    if expected_static {
                        assert_eq!(length, 1);
                    } else {
                        assert_eq!((length, capacity), (0, 0));
                    }
                    let captured =
                        crate::procedure_statics::capture_issued_statements(identity, body)
                            .unwrap();
                    assert_eq!(captured.declarations.len(), usize::from(expected_static));
                    assert_eq!(captured.origins.len(), usize::from(expected_static));
                })
                .unwrap();
        }
    }

    #[test]
    fn concurrent_inspections_share_one_parse() {
        let frontend = frontend();
        let arena = BodyArena::new(&frontend);
        std::thread::scope(|scope| {
            for _ in 0..8 {
                let arena = &arena;
                let body = &frontend.bodies[0];
                scope.spawn(move || {
                    arena
                        .with_parsed(body, |parsed| assert!(!parsed.item().children.is_empty()))
                        .unwrap()
                });
            }
        });
        assert_eq!(arena.parses.load(Ordering::Relaxed), 1);
        assert!(arena.take_parsed(&frontend.bodies[0]).is_ok());
    }

    #[test]
    fn memo_hit_discard_never_parses_and_releases_ready_syntax() {
        let frontend = frontend();
        let arena = BodyArena::new(&frontend);
        arena.discard_parsed(&frontend.bodies[0]).unwrap();
        assert_eq!(arena.parses.load(Ordering::Relaxed), 0);
        assert!(arena.take_parsed(&frontend.bodies[0]).is_err());
        arena.with_parsed(&frontend.bodies[1], |_| ()).unwrap();
        assert_eq!(arena.parses.load(Ordering::Relaxed), 1);
        arena.discard_parsed(&frontend.bodies[1]).unwrap();
        assert!(matches!(
            *arena.slots[1].lock().unwrap(),
            BodyState::Consumed
        ));
        assert!(arena.discard_parsed(&frontend.bodies[1]).is_err());
    }

    #[test]
    fn foreign_or_forged_occurrences_do_not_parse_or_consume() {
        let frontend = frontend();
        let foreign = self::frontend();
        let arena = BodyArena::new(&frontend);
        assert!(arena.with_parsed(&foreign.bodies[0], |_| ()).is_err());
        let mut forged = frontend.bodies[0].clone();
        forged.expanded_span.end -= 1;
        assert!(arena.take_parsed(&forged).is_err());
        assert_eq!(arena.parses.load(Ordering::Relaxed), 0);
        assert!(arena.take_parsed(&frontend.bodies[0]).is_ok());
    }

    #[test]
    fn failed_full_parse_is_cached_across_inspection_and_take() {
        let mut frontend = frontend();
        // Keep the declaration/settings projection and offsets fixed while
        // constructing an issued executable slice with a malformed quote.
        let malformed: dm_preprocess::SourceText = frontend
            .expanded
            .text
            .replace("return 2", "return \"")
            .into();
        frontend.expanded.text = malformed.clone();
        frontend.issued_arena = malformed;
        let arena = BodyArena::new(&frontend);
        let body = &frontend.bodies[1];
        let first = arena.with_parsed(body, |_| ()).unwrap_err();
        let second = arena.with_parsed(body, |_| ()).unwrap_err();
        assert_eq!(first.stage, super::super::DiagnosticStage::Syntax);
        assert_eq!(first.message, second.message);
        assert_eq!(
            first.location.as_ref().unwrap().span,
            second.location.as_ref().unwrap().span
        );
        assert_eq!(arena.parses.load(Ordering::Relaxed), 1);
        let taken = match arena.take_parsed(body) {
            Err(error) => error,
            Ok(_) => panic!("expected syntax error"),
        };
        assert_eq!(first.message, taken.message);
        assert!(arena.with_parsed(body, |_| ()).is_err());
        assert_eq!(arena.parses.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn cached_parse_error_is_replayed_then_consumed_without_reparse() {
        let frontend = frontend();
        let arena = BodyArena::new(&frontend);
        let body = &frontend.bodies[0];
        let mut error = internal("cached syntax error");
        error.kind = DiagnosticKind::SourceError;
        error.stage = super::super::DiagnosticStage::Syntax;
        error.location = Some(body.source.clone());
        *arena.slots[0].lock().unwrap() = BodyState::Ready(Box::new(Err(error.clone())));
        for _ in 0..2 {
            let observed = arena.with_parsed(body, |_| ()).unwrap_err();
            assert_eq!(observed.message, error.message);
            assert_eq!(observed.stage, error.stage);
            assert_eq!(observed.location.unwrap().span, body.source.span);
        }
        let observed = match arena.take_parsed(body) {
            Err(error) => error,
            Ok(_) => panic!("expected syntax error"),
        };
        assert_eq!(observed.message, error.message);
        assert!(arena.with_parsed(body, |_| ()).is_err());
        assert_eq!(arena.parses.load(Ordering::Relaxed), 0);
    }
}
