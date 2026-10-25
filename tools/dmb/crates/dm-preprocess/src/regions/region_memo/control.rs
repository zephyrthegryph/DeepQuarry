//! One exact control codec for disk records and process-local admission.
use super::*;

pub(super) fn write(plan: &DirectivePlan, index: usize, mut emit: impl FnMut(&[u8])) -> Option<()> {
    let region = plan.regions.get(index)?;
    emit(&EXPANSION_VERSION.to_le_bytes());
    for (segment, line) in region
        .segments
        .iter()
        .enumerate()
        .flat_map(|(segment, value)| value.lines.iter().map(move |line| (segment, line)))
    {
        emit(&(segment as u64).to_le_bytes());
        emit(
            &(line
                .source_span
                .start
                .checked_sub(region.source_span.start)? as u64)
                .to_le_bytes(),
        );
        emit(&(line.text.len() as u64).to_le_bytes());
        emit(line.text.as_bytes());
    }
    Some(())
}

/// Digest of the control stream: what a record stores in place of the bytes.
pub(super) fn digest(plan: &DirectivePlan, index: usize) -> Option<u128> {
    let mut hash = xxhash_rust::xxh3::Xxh3::new();
    write(plan, index, |bytes| hash.update(bytes))?;
    Some(hash.digest128())
}

impl ExpansionRecord {
    pub(in crate::regions) fn matches_current_input(
        &self,
        plan: &DirectivePlan,
        index: usize,
    ) -> bool {
        let Some(region) = plan.regions.get(index) else {
            return false;
        };
        let Some(occurrence) = plan.occurrences.get(region.occurrence) else {
            return false;
        };
        let Some(owner) = plan.source_texts.get(occurrence.path.as_ref()) else {
            return false;
        };
        if owner.get(region.source_span.range()) != Some(self.source.as_str()) {
            return false;
        }
        digest(plan, index) == Some(self.control)
    }
}
