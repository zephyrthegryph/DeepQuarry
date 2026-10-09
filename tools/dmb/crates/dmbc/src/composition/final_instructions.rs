//! Independent checks of immutable final procedure images, merged by table index.
use super::*;
use crate::symbolic::BytecodeFeatures;

type Certificates<'a> = HashMap<u32, (&'a [u32], BytecodeFeatures)>;

fn procedure(
    dmb: &Dmb,
    certificates: &Certificates<'_>,
    index: usize,
) -> Result<(bool, bool), CompositionError> {
    if dmb.is_reserved_proc_slot(index) {
        return Ok((false, false));
    }
    let words = dmb
        .proc_code_words(index)
        .ok_or_else(|| unsupported("missing procedure code"))?;
    if let Some(&(certified_words, features)) = certificates.get(&(index as u32)) {
        if certified_words == words {
            return Ok((features.external, features.debug));
        }
    }
    let mut external = false;
    let mut debug = false;
    byond_dmb::bytecode::visit_instructions(words, |instruction| {
        external |= matches!(instruction.name, "LoadExt" | "CallExt");
        debug |= matches!(instruction.name, "DbgFile" | "DbgLine");
    }, |_| {}).map_err(|e| {
        let proc_record = &dmb.procs[index];
        let path = dmb.string(proc_record.strings[0]).map(String::from_utf8_lossy);
        let name = dmb.string(proc_record.strings[1]).map(String::from_utf8_lossy);
        let start = e.offset.saturating_sub(4).min(words.len());
        let end = e.offset.saturating_add(8).min(words.len());
        unsupported(format!("invalid composed bytecode: proc={index}, path={path:?}, name={name:?}, error={e:?}, words[{start}..{end}]={:?}", &words[start..end]))
    })?;
    Ok((external, debug))
}

pub(super) fn validate(
    dmb: &Dmb,
    certificates: &Certificates<'_>,
    executor: Option<&dm_exec::BuildExecutor>,
) -> Result<(bool, bool), CompositionError> {
    let Some(executor) = executor.filter(|executor| executor.workers() > 1 && dmb.procs.len() > 1)
    else {
        let mut features = (false, false);
        for index in 0..dmb.procs.len() {
            let found = procedure(dmb, certificates, index)?;
            features.0 |= found.0;
            features.1 |= found.1;
        }
        return Ok(features);
    };
    // Weight by accessible word counts without decoding or selecting diagnostics.
    // At most one task/span per worker avoids tiny CPU intervals and trace churn.
    let ranges = weighted_ranges(dmb, executor.workers());
    let mut outputs: Vec<_> = (0..dmb.procs.len()).map(|_| None).collect();
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        executor.scope(|scope| {
            let mut remaining = outputs.as_mut_slice();
            for range in ranges {
                let (chunk, rest) = remaining.split_at_mut(range.len());
                remaining = rest;
                scope.spawn(move |_| {
                    let _profile = dm_profile::stage("composition.final_instruction_validation");
                    let first = range.start;
                    for (offset, output) in chunk.iter_mut().enumerate() {
                        *output = Some(procedure(dmb, certificates, first + offset));
                    }
                });
            }
        })
    }))
    .map_err(|_| unsupported("final instruction validation worker panicked"))?;
    // All workers finish even when a later job fails first. Only this ordered
    // reduction selects the diagnostic visible to the caller.
    let mut features = (false, false);
    for output in outputs {
        let found =
            output.ok_or_else(|| unsupported("final instruction worker omitted procedure"))??;
        features.0 |= found.0;
        features.1 |= found.1;
    }
    Ok(features)
}

/// Missing code receives planning weight only; diagnostics remain with visitor.
fn weighted_ranges(dmb: &Dmb, workers: usize) -> Vec<std::ops::Range<usize>> {
    dm_exec::weighted_ranges(dmb.procs.len(), workers, |index| {
        dmb.proc_code_words(index).map_or(1, <[u32]>::len)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn parallel_validation_preserves_first_procedure_error_and_valid_features() {
        let mut dmb = Dmb::from_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../fixtures/native_template.bin"
        )))
        .unwrap();
        let certificates = HashMap::new();
        let expected = validate(&dmb, &certificates, None).unwrap();
        for workers in [1, 2, 8] {
            let executor = dm_exec::BuildExecutor::new(workers).unwrap();
            assert_eq!(
                validate(&dmb, &certificates, Some(&executor)).unwrap(),
                expected
            );
        }
        let record = dmb
            .procs
            .iter()
            .enumerate()
            .find(|(index, _)| !dmb.is_reserved_proc_slot(*index))
            .unwrap()
            .1
            .clone();
        // Span all weighted tasks. The first error must win regardless of
        // which later task completes first.
        let first = dmb.procs.len();
        for _ in 0..259 {
            let mut record = record.clone();
            record.code_locals_args[0] = dmb.lists.len() as u32;
            dmb.lists.push(vec![u32::MAX]);
            dmb.procs.push(record);
        }
        for workers in [1, 2, 8] {
            let ranges = weighted_ranges(&dmb, workers);
            assert_eq!(ranges.len(), workers.min(dmb.procs.len()));
            assert_eq!(ranges.first().unwrap().start, 0);
            assert_eq!(ranges.last().unwrap().end, dmb.procs.len());
            assert!(ranges.iter().all(|range| !range.is_empty()));
            assert!(ranges.windows(2).all(|pair| pair[0].end == pair[1].start));
        }
        let expected = format!("{:?}", validate(&dmb, &certificates, None).unwrap_err());
        assert!(expected.contains(&format!("proc={first},")));
        for workers in [1, 2, 8] {
            let executor = dm_exec::BuildExecutor::new(workers).unwrap();
            assert_eq!(
                format!(
                    "{:?}",
                    validate(&dmb, &certificates, Some(&executor)).unwrap_err()
                ),
                expected
            );
        }
    }
}
