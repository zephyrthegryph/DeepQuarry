use super::*;
use crate::policy_body_demand::PolicyFailure;
use std::{io, mem::size_of};

#[derive(Clone, Copy)]
struct Coordinate { page: u32, local: u32 }

/// One operation-local inverse ordinal projection over authentic typed pages.
/// Neither the source, nor an owned page, nor a second semantic model is held.
pub struct CompactGraphReplay<'a> {
    input: &'a Arc<EffectInput>,
    proof: OriginalEffectSourceProof<'a>,
    pages: &'a [&'a CompactGraphPage],
    coordinates: Vec<Coordinate>,
}
impl<'a> CompactGraphReplay<'a> {
    pub fn new(input: &'a Arc<EffectInput>, pages: &'a [&'a CompactGraphPage],
        work: &mut impl EffectReportWork, checkpoint: &dyn Fn() -> io::Result<()>) -> Result<Self, PolicyFailure> {
        let proof = input.original_source_proof()?;
        let count = input.archive().len();
        if count >= u32::MAX as usize || pages.len() >= u32::MAX as usize {
            return Err(oom("compact graph replay coordinates overflow"));
        }
        let bound = count.checked_mul(4).and_then(|n| n.checked_mul(size_of::<Coordinate>())).ok_or_else(|| oom("compact replay allocation overflow"))?;
        let mark = work.mark().map_err(PolicyFailure::Operational)?;
        work.reserve(bound).map_err(PolicyFailure::Operational)?;
        let mut coordinates = Vec::new();
        coordinates.try_reserve_exact(count).map_err(|actual| PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory, actual)))?;
        if coordinates.capacity() > count.saturating_mul(4) { return Err(oom("compact replay allocation exceeds envelope")); }
        coordinates.resize(count, Coordinate { page: u32::MAX, local: 0 });
        let mut rank = 0;
        for (index, page) in pages.iter().enumerate() {
            checkpoint().map_err(PolicyFailure::Operational)?;
            page.loan_with_proof(input, &proof)?;
            if page.start() != rank || page.is_empty() { return Err("compact graph page order or coverage differs".into()); }
            for local in 0..page.len() {
                checkpoint().map_err(PolicyFailure::Operational)?;
                let ordinal = page.ordinal(local).ok_or("compact graph replay ordinal absent")?;
                let row = coordinates.get_mut(ordinal).ok_or("compact graph replay ordinal escapes archive")?;
                if row.page != u32::MAX { return Err("compact graph replay contains duplicate ordinal".into()); }
                *row = Coordinate { page: index as u32, local: local as u32 };
            }
            rank = rank.checked_add(page.len()).ok_or_else(|| oom("compact replay rank overflow"))?;
        }
        if rank != count { return Err("compact graph replay does not cover every actual body".into()); }
        work.reconcile(mark, coordinates.capacity() * size_of::<Coordinate>()).map_err(PolicyFailure::Operational)?;
        Ok(Self { input, proof, pages, coordinates })
    }

    pub fn body(&self, ordinal: usize) -> Result<CompactGraphBodyLoan<'a>, PolicyFailure> {
        let (page, local) = self.coordinate(ordinal)?;
        page.loan_with_proof(self.input, &self.proof)?.body(local)
    }
    pub(crate) fn graph_row(&self, ordinal: usize) -> Result<CompactGraphBodyLoan<'a>, PolicyFailure> {
        self.body(ordinal)
    }
    pub(crate) fn input(&self) -> &'a Arc<EffectInput> { self.input }
    fn coordinate(&self, ordinal: usize) -> Result<(&'a CompactGraphPage, usize), PolicyFailure> {
        let location = self.coordinates.get(ordinal).ok_or("compact graph replay ordinal absent")?;
        let page = self.pages.get(location.page as usize).ok_or("compact graph replay page absent")?;
        Ok((*page, location.local as usize))
    }
}
fn oom(message: &'static str) -> PolicyFailure {
    PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory, message))
}
