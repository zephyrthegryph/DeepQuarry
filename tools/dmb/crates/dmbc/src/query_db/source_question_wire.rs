//! Fallible original-source query wire. Whole batch holds ONE current binding.
//! Both nested rows and complete outer row use actual global-ledger allocators.
use super::*;
use dm_tree::{HierarchyAnswer, HierarchyAnswerKind};
use serde::{
    ser::{SerializeMap, SerializeSeq},
    Serialize, Serializer,
};
use std::{
    cell::{Cell, RefCell},
    io::{self, Write},
};
struct Wire {
    bytes: allocator_api2::vec::Vec<u8, SourceAllocator>,
    limit: usize,
    failed: RefCell<Option<io::Error>>,
}
impl Wire {
    fn new(db: &QueryDb, limit: usize) -> io::Result<Self> {
        Ok(Self {
            bytes: allocator_api2::vec::Vec::new_in(SourceAllocator::new_source(Arc::clone(
                &db.answers.values.source_ledger,
            ))?),
            limit,
            failed: RefCell::new(None),
        })
    }
}
impl Write for Wire {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        if self.failed.borrow().is_some() {
            return Err(io::Error::other("source JSON writer stopped"));
        }
        let result: io::Result<usize> = (|| {
            crate::daemon::control::checkpoint()?;
            let need = self
                .bytes
                .len()
                .checked_add(b.len())
                .filter(|n| *n <= self.limit)
                .ok_or(io::ErrorKind::OutOfMemory)?;
            if need > self.bytes.capacity() {
                let cap = need
                    .max(self.bytes.capacity().saturating_mul(2))
                    .max(64)
                    .min(self.limit);
                let handle = self.bytes.allocator().clone();
                let _mode = handle
                    .source_mode()
                    .map_err(|_| io::ErrorKind::WouldBlock)?;
                self.bytes
                    .try_reserve_exact(cap - self.bytes.len())
                    .map_err(|_| io::ErrorKind::OutOfMemory)?;
            }
            self.bytes.extend_from_slice(b);
            Ok(b.len())
        })();
        match result {
            Ok(n) => Ok(n),
            Err(error) => {
                if self.failed.borrow().is_none() {
                    *self.failed.borrow_mut() = Some(error);
                }
                Err(io::Error::other("source JSON writer stopped"))
            }
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}
fn json_error(e: serde_json::Error) -> io::Error {
    io::Error::new(e.io_error_kind().unwrap_or(io::ErrorKind::InvalidData), e)
}
fn hex<const N: usize>(mut value: u128) -> [u8; N] {
    let mut result = [b'0'; N];
    for b in result.iter_mut().rev() {
        *b = b"0123456789abcdef"[(value & 15) as usize];
        value >>= 4;
    }
    result
}
#[derive(Serialize)]
struct Symbol<'a> {
    id: &'a str,
    text: Option<&'a str>,
}
fn serialize_symbol<S: Serializer>(
    symbols: &dm_ir::SymbolTable,
    id: dm_ir::SymbolId,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    let bits = hex::<16>(id.bits() as u128);
    Symbol {
        id: std::str::from_utf8(&bits).expect("ASCII hex"),
        text: symbols.text(id),
    }
    .serialize(serializer)
}
struct SymbolValue<'a>(&'a dm_ir::SymbolTable, dm_ir::SymbolId);
impl Serialize for SymbolValue<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        serialize_symbol(self.0, self.1, s)
    }
}
struct Meaning<'a> {
    answer: &'a HierarchyAnswer<'a>,
    symbols: &'a dm_ir::SymbolTable,
    remaining: RefCell<usize>,
    error: RefCell<Option<io::Error>>,
}
struct Symbols<'a, 'b>(&'a Meaning<'b>);
impl Serialize for Symbols<'_, '_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut seq = s.serialize_seq(None)?;
        let result = self.0.answer.visit_symbols(
            &mut self.0.remaining.borrow_mut(),
            crate::daemon::control::checkpoint,
            |id| {
                seq.serialize_element(&SymbolValue(self.0.symbols, id))
                    .map_err(|_| io::Error::from(io::ErrorKind::Other))
            },
        );
        if let Err(error) = result {
            *self.0.error.borrow_mut() = Some(error);
            return Err(serde::ser::Error::custom(
                "borrowed hierarchy serialization failed",
            ));
        }
        seq.end()
    }
}
impl Serialize for Meaning<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut map = s.serialize_map(None)?;
        match self.answer.kind() {
            HierarchyAnswerKind::Missing => map.serialize_entry("status", "missing")?,
            HierarchyAnswerKind::Symbol(id) => {
                map.serialize_entry("status", "known")?;
                map.serialize_entry("kind", "symbol")?;
                map.serialize_entry("value", &SymbolValue(self.symbols, id))?;
            }
            HierarchyAnswerKind::Symbols => {
                map.serialize_entry("status", "known")?;
                map.serialize_entry("kind", "symbols")?;
                map.serialize_entry("values", &Symbols(self))?;
            }
        }
        map.end()
    }
}
struct StackJson {
    bytes: [u8; 512],
    len: usize,
}
impl Write for StackJson {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        let end = self
            .len
            .checked_add(b.len())
            .filter(|n| *n <= 512)
            .ok_or(io::ErrorKind::InvalidData)?;
        self.bytes[self.len..end].copy_from_slice(b);
        self.len = end;
        Ok(b.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}
#[derive(Serialize)]
struct Row<'a, 'b> {
    row: &'static str,
    schema: &'static str,
    subject: Option<&'a str>,
    query_wire: &'a str,
    domain: &'static str,
    domain_qualification: dm_ir::ReadDomain,
    meaning_fingerprint: &'a str,
    answer: &'a Meaning<'b>,
}
#[derive(Serialize)]
struct Envelope<'a> {
    row: &'static str,
    schema: &'static str,
    source_revision: &'a str,
    semantic_revision: &'a str,
    complete: bool,
    query_count: usize,
    captured_jsonl: &'a str,
}
impl QueryDb {
    pub(crate) fn write_source_question_batch(
        &self,
        scope: &SourceAnswerScope,
        tree: &dm_tree::SemanticTree,
        mapping: &dm_tree::frontend::SourceExportMapping,
        archive: &dm_tree::frontend::BodyArchive,
        questions: &[crate::daemon::query::QueryItem],
        source_revision: u128,
        output: &mut impl Write,
    ) -> io::Result<()> {
        crate::request::validate_source_question_roster(questions)?;
        scope
            .questions
            .as_ref()
            .ok_or(io::ErrorKind::Unsupported)?
            .require(questions)?;
        let current = self
            .answers
            .current
            .read()
            .unwrap_or_else(|e| e.into_inner());
        scope.require(self, &current, tree, mapping, archive)?;
        let view = tree
            .certified_hierarchy()
            .ok_or(io::ErrorKind::Unsupported)?;
        let mut rows = Wire::new(self, 192 * 1024)?;
        for question in questions {
            crate::daemon::control::checkpoint()?;
            scope.require(self, &current, tree, mapping, archive)?;
            let hash = self.source_answer_hash_bound(&current, tree, question.query)?;
            let dm_ir::ResolveQuery::CertifiedHierarchy { kind, path } = question.query else {
                return Err(io::ErrorKind::Unsupported.into());
            };
            let answer = view.borrowed_answer(kind, path);
            let meaning = Meaning {
                answer: &answer,
                symbols: tree.symbols(),
                remaining: RefCell::new(
                    view.node_bound()
                        .checked_mul(2)
                        .and_then(|n| n.checked_add(2))
                        .ok_or(io::ErrorKind::OutOfMemory)?,
                ),
                error: RefCell::new(None),
            };
            let mut query = StackJson {
                bytes: [0; 512],
                len: 0,
            };
            serde_json::to_writer(&mut query, &question.query).map_err(json_error)?;
            let fingerprint = hex::<32>(hash);
            let row = Row {
                row: "resolved_query",
                schema: "dm-resolved-query-v1",
                subject: question.subject.as_deref(),
                query_wire: std::str::from_utf8(&query.bytes[..query.len])
                    .map_err(|_| io::ErrorKind::InvalidData)?,
                domain: "owner_hierarchy",
                domain_qualification: question.query.domain(),
                meaning_fingerprint: std::str::from_utf8(&fingerprint).expect("ASCII hex"),
                answer: &meaning,
            };
            let result = serde_json::to_writer(&mut rows, &row);
            if let Some(error) = rows.failed.borrow_mut().take() {
                return Err(error);
            }
            if let Some(error) = meaning.error.borrow_mut().take() {
                return Err(error);
            }
            result.map_err(json_error)?;
            let ended = rows.write_all(b"\n");
            if let Some(error) = rows.failed.borrow_mut().take() {
                return Err(error);
            }
            ended?;
        }
        let source = hex::<32>(source_revision);
        let semantic = hex::<32>(tree.identity());
        let envelope = Envelope {
            row: "source_resolved_queries",
            schema: "dm-session-source-query-v1",
            source_revision: std::str::from_utf8(&source).unwrap(),
            semantic_revision: std::str::from_utf8(&semantic).unwrap(),
            complete: false,
            query_count: questions.len(),
            captured_jsonl: std::str::from_utf8(&rows.bytes)
                .map_err(|_| io::ErrorKind::InvalidData)?,
        };
        let mut wire = Wire::new(self, crate::daemon::query::MAX_OUTPUT)?;
        let encoded = serde_json::to_writer(&mut wire, &envelope).map_err(json_error);
        if let Some(error) = wire.failed.borrow_mut().take() {
            return Err(error);
        }
        encoded?;
        let ended = wire.write_all(b"\n");
        if let Some(error) = wire.failed.borrow_mut().take() {
            return Err(error);
        }
        ended?;
        crate::daemon::control::checkpoint()?;
        // All nested/outer serialization succeeded under same current guard.
        // Existing transport now receives only one complete bounded row.
        write_output_once(output, &wire.bytes)
    }
}

// Deliberately do NOT use Write::write_all here: retrying a caller's Interrupted
// forever would turn a cancelled operation into a busy loop. Partial writes
// still work; the original first error/source returns without recategorization.
fn write_output_once(output: &mut impl Write, mut bytes: &[u8]) -> io::Result<()> {
    while !bytes.is_empty() {
        crate::daemon::control::checkpoint()?;
        let n = output.write(bytes)?;
        if n == 0 {
            return Err(io::ErrorKind::WriteZero.into());
        }
        if n > bytes.len() {
            return Err(io::ErrorKind::InvalidData.into());
        }
        bytes = &bytes[n..];
    }
    crate::daemon::control::checkpoint()
}
#[cfg(test)]
mod nonretrying_tests {
    use super::*;
    struct CancelAfterPrefix {
        token: crate::daemon::control::Cancellation,
        progress: Cell<bool>,
    }
    impl Serialize for CancelAfterPrefix {
        fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
            let mut m = s.serialize_map(Some(2))?;
            m.serialize_entry("prefix", "actual wire bytes")?;
            self.progress.set(true);
            self.token.cancel();
            m.serialize_entry("after", &1)?;
            m.end()
        }
    }
    #[test]
    fn source_wire_mid_serialization_cancellation_unwinds_and_retains_original_error() {
        let token = crate::daemon::control::Cancellation::default();
        let bound = crate::daemon::control::bind_with_deadline(
            token.clone(),
            std::time::Instant::now() + std::time::Duration::from_secs(60),
        );
        // This tests actual Wire's IO behavior, not a source/profile publication.
        // Wire backing growth uses a bounded ledger; no source/profile permit
        // is fabricated for this operation-local IO fixture.
        let mut wire = Wire {
            bytes: allocator_api2::vec::Vec::new_in(SourceAllocator::new(SourceLedger::new(
                64 * 1024,
            ))),
            limit: 1024,
            failed: RefCell::new(None),
        };
        let value = CancelAfterPrefix {
            token,
            progress: Cell::new(false),
        };
        let proxy = serde_json::to_writer(&mut wire, &value).unwrap_err();
        assert!(value.progress.get());
        assert!(!wire.bytes.is_empty());
        assert_eq!(proxy.io_error_kind(), Some(io::ErrorKind::Other));
        let actual = wire.failed.borrow_mut().take().unwrap();
        assert_eq!(actual.kind(), io::ErrorKind::Interrupted);
        assert!(!wire.bytes.ends_with(b"\n"));
        drop(bound);
    }
    #[test]
    fn source_final_output_never_retries_callers_interrupted_and_recovers() {
        struct Refuse {
            calls: usize,
        }
        impl Write for Refuse {
            fn write(&mut self, _: &[u8]) -> io::Result<usize> {
                self.calls += 1;
                Err(io::Error::new(
                    io::ErrorKind::Interrupted,
                    "actual caller interrupted",
                ))
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        let mut out = Refuse { calls: 0 };
        let error = write_output_once(&mut out, b"complete\n").unwrap_err();
        assert_eq!(out.calls, 1);
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
        assert_eq!(error.to_string(), "actual caller interrupted");
        let mut okay = Vec::new();
        write_output_once(&mut okay, b"complete\n").unwrap();
        assert_eq!(okay, b"complete\n");
        struct Partial {
            token: crate::daemon::control::Cancellation,
            bytes: Vec<u8>,
            calls: usize,
        }
        impl Write for Partial {
            fn write(&mut self, b: &[u8]) -> io::Result<usize> {
                self.calls += 1;
                self.bytes.push(b[0]);
                self.token.cancel();
                Ok(1)
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        let token = crate::daemon::control::Cancellation::default();
        let bound = crate::daemon::control::bind_with_deadline(
            token.clone(),
            std::time::Instant::now() + std::time::Duration::from_secs(60),
        );
        let mut partial = Partial {
            token,
            bytes: Vec::new(),
            calls: 0,
        };
        let error = write_output_once(&mut partial, b"complete\n").unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
        assert_eq!(partial.calls, 1);
        assert_eq!(partial.bytes, b"c");
        drop(bound);
    }
}
