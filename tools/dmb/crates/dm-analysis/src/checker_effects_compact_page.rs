//! Typed graph-only projection of actual once-evaluated Original bodies.
use super::*;
use crate::policy_body_demand::PolicyFailure;
use std::{io, mem::size_of, num::NonZeroU32, ops::Range};
use super::report_core::{ReportBodyLoan, ReportBodyView};

type OriginError = dm_tree::frontend::BorrowedCallableOriginError;

struct Dense {
    ordinal: u32,
    opening: Option<Span>,
    sparse: Option<NonZeroU32>,
}

struct Sparse {
    parent: Option<EffectTarget>,
    pure: Option<Span>,
    sleep: SleepSettings,
    calls: Range<u32>,
    direct: Range<u32>,
    blocking: Range<u32>,
    origin_error: Option<OriginError>,
}

/// Memory-only graph projection. Does not retain source, AST, diagnostic
/// rows, keyword uses, or a BodyEffects owner. Input keys are never reused.
pub struct CompactGraphPage {
    input: u64,
    start: usize,
    rows: Vec<Dense>,
    sparse: Vec<Sparse>,
    calls: Vec<CallEdge>,
    direct: Vec<DirectEffect>,
    blocking: Vec<DirectEffect>,
}

pub struct CompactGraphPageBuilder<'a> {
    input: &'a Arc<EffectInput>,
    page: CompactGraphPage,
    count: usize,
    failed: bool,
}

fn oom(message: &'static str) -> PolicyFailure {
    PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory, message))
}

fn range(start: usize, extra: usize) -> Result<Range<u32>, PolicyFailure> {
    let end = start.checked_add(extra).ok_or_else(|| oom("compact graph row range overflow"))?;
    let overflow = |_| oom("compact graph row range exceeds u32");
    Ok(u32::try_from(start).map_err(overflow)?..u32::try_from(end).map_err(overflow)?)
}

fn reserve<T>(rows: &mut Vec<T>, extra: usize, work: &mut impl EffectReportWork) -> Result<(), PolicyFailure> {
    let needed = rows.len().checked_add(extra).ok_or_else(|| oom("compact graph row count overflow"))?;
    let old = rows.capacity();
    if needed <= old { return Ok(()); }
    let requested = needed.max(old.saturating_mul(2));
    let exposed = requested.checked_mul(4).ok_or_else(|| oom("compact graph exposure overflow"))?;
    let bytes = exposed.checked_mul(size_of::<T>()).ok_or_else(|| oom("compact graph allocation overflow"))?;
    let mark = work.mark().map_err(PolicyFailure::Operational)?;
    work.reserve(bytes).map_err(PolicyFailure::Operational)?;
    rows.try_reserve_exact(requested - rows.len())
        .map_err(|actual| PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory, actual)))?;
    if rows.capacity() > exposed { return Err(oom("compact graph allocation exceeds envelope")); }
    let delta = (rows.capacity() - old) * size_of::<T>();
    work.reconcile(mark, delta).map_err(PolicyFailure::Operational)
}

impl<'a> CompactGraphPageBuilder<'a> {
    pub fn new(input: &'a Arc<EffectInput>, start: usize, count: usize, work: &mut impl EffectReportWork) -> Result<Self, PolicyFailure> {
        input.require_original_checker_source()?;
        if count == 0 || count > MAX_EVENTS || start.checked_add(count).is_none_or(|end| end > input.archive.callables().source_order().len()) {
            return Err("compact graph page is outside the actual source roster".into());
        }
        work.reserve(size_of::<CompactGraphPage>()).map_err(PolicyFailure::Operational)?;
        let mut page = CompactGraphPage {
            input: input.key(), start, rows: Vec::new(), sparse: Vec::new(),
            calls: Vec::new(), direct: Vec::new(), blocking: Vec::new(),
        };
        reserve(&mut page.rows, count, work)?;
        Ok(Self { input, page, count, failed: false })
    }

    pub fn push(&mut self, body: &BodyEffects, work: &mut impl EffectReportWork) -> Result<(), PolicyFailure> {
        if self.failed { return Err("compact graph page previously failed".into()); }
        self.failed = true;
        body.validate(self.input)?;
        let page = &mut self.page;
        let roster = self.input.archive.callables();
        if page.rows.len() >= self.count
            || roster.source_order().get(page.start + page.rows.len()) != Some(&body.ordinal)
            || roster.identity(body.ordinal) != Some(body.procedure)
            || body.original_evaluations != 1
        {
            return Err("compact graph page needs the next actual once-evaluated body".into());
        }
        let ordinal = u32::try_from(body.ordinal).map_err(|_| oom("compact graph ordinal exceeds u32"))?;
        let origin_error = match &body.callable_origin {
            Ok(original) => {
                let opening = body.opening_parenthesis.ok_or("compact graph callable origin lacks its opening token")?;
                let rebound = self.input.archive.borrowed_source_note_point(opening.start)?.into_owned();
                if !Arc::ptr_eq(&original.path, &rebound.path) || original.line != rebound.line || original.byte_column != rebound.byte_column {
                    return Err("compact graph callable origin differs from the authentic opening token".into());
                }
                None
            }
            Err(error) => Some(*error),
        };
        let nonempty = body.parent.is_some() || body.pure.is_some() || body.sleep.no_sleep.is_some()
            || body.sleep.exempt.is_some() || body.sleep.waitfor_disabled || !body.calls.is_empty()
            || !body.direct.is_empty() || !body.blocking.is_empty() || origin_error.is_some();
        let sparse = if nonempty {
            let index = page.sparse.len().checked_add(1).and_then(|n| u32::try_from(n).ok()).and_then(NonZeroU32::new)
                .ok_or_else(|| oom("compact graph sparse index overflow"))?;
            let calls = range(page.calls.len(), body.calls.len())?;
            let direct = range(page.direct.len(), body.direct.len())?;
            let blocking = range(page.blocking.len(), body.blocking.len())?;
            reserve(&mut page.sparse, 1, work)?;
            reserve(&mut page.calls, body.calls.len(), work)?;
            reserve(&mut page.direct, body.direct.len(), work)?;
            reserve(&mut page.blocking, body.blocking.len(), work)?;
            page.calls.extend_from_slice(&body.calls);
            page.direct.extend_from_slice(&body.direct);
            page.blocking.extend_from_slice(&body.blocking);
            page.sparse.push(Sparse { parent: body.parent, pure: body.pure, sleep: body.sleep, calls, direct, blocking, origin_error });
            Some(index)
        } else { None };
        page.rows.push(Dense { ordinal, opening: body.opening_parenthesis, sparse });
        self.failed = false;
        Ok(())
    }

    pub fn finish(self) -> Result<CompactGraphPage, PolicyFailure> {
        if self.failed || self.page.rows.len() != self.count {
            return Err("compact graph page is incomplete".into());
        }
        Ok(self.page)
    }
}

impl CompactGraphPage {
    pub fn retained_charge(&self) -> Option<usize> {
        fn bytes<T>(rows: &Vec<T>) -> Option<usize> { rows.capacity().checked_mul(size_of::<T>()) }
        size_of::<Self>().checked_add(bytes(&self.rows)?)?
            .checked_add(bytes(&self.sparse)?)?.checked_add(bytes(&self.calls)?)?
            .checked_add(bytes(&self.direct)?)?.checked_add(bytes(&self.blocking)?)
    }

    pub fn loan<'a>(&'a self, input: &'a Arc<EffectInput>) -> Result<CompactGraphPageLoan<'a>, PolicyFailure> {
        input.require_original_checker_source()?;
        if input.key() != self.input { return Err("compact graph page belongs to another input".into()); }
        Ok(CompactGraphPageLoan { page: self, input })
    }
}

pub struct CompactGraphPageLoan<'a> {
    page: &'a CompactGraphPage,
    input: &'a Arc<EffectInput>,
}

impl CompactGraphPageLoan<'_> {
    pub fn body(&self, index: usize) -> Result<CompactGraphBodyLoan<'_>, PolicyFailure> {
        let row = self.page.rows.get(index).ok_or("compact graph body index absent")?;
        let ordinal = row.ordinal as usize;
        let procedure = self.input.archive.callables().identity(ordinal).ok_or("compact graph callable absent")?;
        let sparse = row.sparse.map(|index| &self.page.sparse[index.get() as usize - 1]);
        let origin = if let Some(error) = sparse.and_then(|row| row.origin_error) {
            Err(error)
        } else {
            let opening = row.opening.ok_or("compact graph opening token absent")?;
            Ok(self.input.archive.borrowed_source_note_point(opening.start)?.into_owned())
        };
        Ok(CompactGraphBodyLoan { page: self.page, row, sparse, procedure, origin })
    }
}

pub struct CompactGraphBodyLoan<'a> {
    page: &'a CompactGraphPage,
    row: &'a Dense,
    sparse: Option<&'a Sparse>,
    procedure: ProcedureIdentity,
    origin: Result<SourceNoteOrigin, OriginError>,
}

impl CompactGraphBodyLoan<'_> {
    pub fn ordinal(&self) -> usize { self.row.ordinal as usize }
    pub fn has_direct_effect(&self) -> bool { !self.view().direct.is_empty() }
    pub fn visit_source_calls(&self, mut visit: impl FnMut(ProcedureIdentity, bool, bool)) {
        for edge in self.view().calls {
            if let EffectTarget::Source(id) = edge.callee { visit(id, edge.exact, edge.new_context); }
        }
    }
}

impl ReportBodyLoan for CompactGraphBodyLoan<'_> {
    fn view(&self) -> ReportBodyView<'_> {
        static EMPTY_SLEEP: SleepSettings = SleepSettings { no_sleep: None, exempt: None, waitfor_disabled: false };
        fn slice<T>(rows: &[T], range: Range<u32>) -> &[T] { &rows[range.start as usize..range.end as usize] }
        let sparse = self.sparse;
        ReportBodyView {
            ordinal: self.ordinal(),
            procedure: self.procedure,
            parent: sparse.and_then(|row| row.parent),
            pure: sparse.and_then(|row| row.pure),
            sleep: sparse.map_or(&EMPTY_SLEEP, |row| &row.sleep),
            calls: sparse.map_or(&[][..], |row| slice(&self.page.calls, row.calls.clone())),
            direct: sparse.map_or(&[][..], |row| slice(&self.page.direct, row.direct.clone())),
            blocking: sparse.map_or(&[][..], |row| slice(&self.page.blocking, row.blocking.clone())),
            opening_parenthesis: self.row.opening,
            callable_origin: &self.origin,
            immediate: &[],
            original: &[],
        }
    }
}
