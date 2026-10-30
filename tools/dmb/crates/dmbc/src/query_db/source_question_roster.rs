//! Exact bounded preparation/query authorization metadata, never semantic facts.
use super::*;
use crate::daemon::query::QueryItem;
use std::io;
struct Requested {
    query: dm_ir::ResolveQuery,
    subject: [u8; 256],
    len: u16,
    present: bool,
}
pub(crate) struct SourceQuestionRoster {
    items: allocator_api2::vec::Vec<Requested, SourceAllocator>,
}
impl SourceQuestionRoster {
    pub(crate) fn capture(db: &QueryDb, questions: &[QueryItem]) -> io::Result<Self> {
        crate::request::validate_source_question_roster(questions)?;
        let allocator = SourceAllocator::new_source(Arc::clone(&db.answers.values.source_ledger))?;
        let handle = allocator.clone();
        let _mode = handle
            .source_mode()
            .map_err(|_| io::ErrorKind::WouldBlock)?;
        let mut items = allocator_api2::vec::Vec::new_in(allocator);
        items
            .try_reserve_exact(questions.len())
            .map_err(|_| io::ErrorKind::OutOfMemory)?;
        for q in questions {
            crate::daemon::control::checkpoint()?;
            let mut item = Requested {
                query: q.query,
                subject: [0; 256],
                len: 0,
                present: q.subject.is_some(),
            };
            if let Some(text) = &q.subject {
                item.subject[..text.len()].copy_from_slice(text.as_bytes());
                item.len = text.len() as u16;
            }
            items.push(item);
        }
        Ok(Self { items })
    }
    pub(super) fn duplicate(&self, db: &QueryDb) -> io::Result<Self> {
        let allocator = SourceAllocator::new_source(Arc::clone(&db.answers.values.source_ledger))?;
        let handle = allocator.clone();
        let _mode = handle
            .source_mode()
            .map_err(|_| io::ErrorKind::WouldBlock)?;
        let mut items = allocator_api2::vec::Vec::new_in(allocator);
        items
            .try_reserve_exact(self.items.len())
            .map_err(|_| io::ErrorKind::OutOfMemory)?;
        for item in &self.items {
            crate::daemon::control::checkpoint()?;
            items.push(Requested {
                query: item.query,
                subject: item.subject,
                len: item.len,
                present: item.present,
            });
        }
        Ok(Self { items })
    }
    pub(super) fn require(&self, questions: &[QueryItem]) -> io::Result<()> {
        crate::request::validate_source_question_roster(questions)?;
        if self.items.len() != questions.len()
            || self.items.iter().zip(questions).any(|(a, b)| {
                a.query != b.query
                    || a.present != b.subject.is_some()
                    || b.subject.as_deref().unwrap_or("").as_bytes()
                        != &a.subject[..usize::from(a.len)]
            })
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "source questions differ from the exact ordered prepared roster",
            ));
        }
        Ok(())
    }
    pub(super) fn census(&self, c: &mut crate::heap_census::HeapCensus) {
        self.items.allocator().census_backing(
            c,
            "answers.original_source_question_roster",
            self.items.len() * std::mem::size_of::<Requested>(),
            self.items.len(),
        );
    }
}
