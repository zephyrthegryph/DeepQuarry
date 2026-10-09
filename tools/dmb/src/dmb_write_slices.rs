//! Exact-size records encode directly into disjoint final-buffer slices.
use super::*;

#[allow(clippy::too_many_arguments)] // Same canonical records context plus checked chunk plan.
pub(super) fn sized_records<T: Sync>(
    writer: &mut Writer,
    hash: &mut CanonicalHash,
    items: &[T],
    executor: &BuildExecutor,
    sizes: &[usize],
    spans: bool,
    encode: impl Fn(&mut Writer, &T, usize) -> io::Result<()> + Sync,
    ranges: Vec<Range<usize>>,
) -> io::Result<Vec<Range<usize>>> {
    if sizes.len() != items.len() {
        return Err(invalid("record sizing coverage mismatch"));
    }
    hash.pending(writer);
    let prefix = writer.at();
    let object_size = writer.object_size;
    let compatibility_version = writer.compatibility_version;
    let mut total = 0usize;
    let mut lengths = Vec::with_capacity(ranges.len());
    for range in &ranges {
        let length = sizes[range.clone()].iter().try_fold(0usize, |sum, &size| {
            sum.checked_add(size)
                .ok_or_else(|| invalid("serialization size overflow"))
        })?;
        total = total
            .checked_add(length)
            .ok_or_else(|| invalid("serialization size overflow"))?;
        lengths.push(length);
    }
    prefix
        .checked_add(total)
        .ok_or_else(|| invalid("serialization offset overflow"))?;
    type SliceOutput = io::Result<(bool, Vec<Range<usize>>)>;
    let mut outputs: Vec<Option<SliceOutput>> = (0..ranges.len()).map(|_| None).collect();
    let storage = writer.bytes.append_space(total)?;
    let scoped = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        executor.scope(|scope| {
            let mut remaining = storage;
            let mut base = prefix;
            for ((range, length), output) in ranges.iter().zip(lengths).zip(&mut outputs) {
                let (bytes, rest) = remaining.split_at_mut(length);
                remaining = rest;
                let chunk_base = base;
                base += length;
                let encode = &encode;
                scope.spawn(move |_| {
                    let _profile = dm_profile::stage("output.dmb_encode");
                    let mut chunk = Writer::bounded(bytes, object_size, compatibility_version);
                    let mut offsets = Vec::with_capacity(if spans { range.len() } else { 0 });
                    let result = (|| {
                        for index in range.clone() {
                            let start = chunk.at();
                            encode(&mut chunk, &items[index], chunk_base)?;
                            chunk.check_storage()?;
                            if chunk.at().checked_sub(start) != Some(sizes[index]) {
                                return Err(invalid(
                                    "record serialization differs from planned size",
                                ));
                            }
                            if spans {
                                offsets.push(chunk_base + start..chunk_base + chunk.at());
                            }
                        }
                        chunk.finish_bounded(length)?;
                        Ok((chunk.object_overflow, offsets))
                    })();
                    *output = Some(result);
                });
            }
        });
    }));
    if scoped.is_err() {
        return Err(io::Error::other("DMB encoding worker panicked"));
    }
    let mut offsets = Vec::with_capacity(if spans { items.len() } else { 0 });
    for output in outputs {
        let (overflow, spans) =
            output.ok_or_else(|| io::Error::other("DMB encoding worker omitted its result"))??;
        writer.object_overflow |= overflow;
        offsets.extend(spans);
    }
    hash.pending(writer);
    Ok(offsets)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn incorrect_size_plans_fail_closed_before_later_errors() {
        let executor = BuildExecutor::new(2).unwrap();
        let values: Vec<u32> = (0..128).collect();
        for first_size in [3, 5] {
            let mut sizes = vec![4; values.len()];
            sizes[0] = first_size;
            let mut writer = Writer::new(4, 516);
            writer.u8(7);
            let mut hash = CanonicalHash::default();
            let error = records(
                &mut writer,
                &mut hash,
                &values,
                Some(&executor),
                Some(&sizes),
                true,
                |writer, value, _| {
                    if *value == 127 {
                        return Err(invalid("later record failure"));
                    }
                    writer.u32(*value);
                    Ok(())
                },
            )
            .unwrap_err();
            assert_eq!(error.kind(), io::ErrorKind::InvalidData);
            assert!(!error.to_string().contains("later record failure"));
            assert_eq!(writer.bytes[0], 7);
            assert_eq!(executor.install(|| 11), 11);
        }
    }
    #[test]
    fn bounded_string_overflow_returns_error_without_cipher_slice_panic() {
        let mut bytes = [0u8; 3];
        let mut writer = Writer::bounded(&mut bytes, 4, 516);
        let string = DmString {
            data: b"too long".to_vec(),
            long_chunks: 0,
        };
        assert_eq!(
            write_string(&mut writer, &string, 0, 0).unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
    }
}
