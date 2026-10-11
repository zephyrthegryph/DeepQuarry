//! Canonical v516 writer with bounded borrowed-worker table encoding.
use super::*;
use dm_exec::BuildExecutor;
use std::ops::Range;
use xxhash_rust::xxh3::Xxh3;

/// Immutable canonical bytes paired with the digest computed by serialization.
/// Consuming the owner into mutable bytes discards the digest certificate.
#[derive(Clone, Debug)]
pub struct EncodedDmb {
    bytes: std::sync::Arc<Vec<u8>>,
    content_hash: u128,
}
impl EncodedDmb {
    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }
    pub fn content_hash(&self) -> u128 {
        self.content_hash
    }
    pub fn len(&self) -> usize {
        self.bytes.len()
    }
    /// Retained backing capacity, exposed without mutable byte access.
    pub fn capacity(&self) -> usize {
        self.bytes.capacity()
    }
    pub fn is_empty(&self) -> bool {
        self.bytes.is_empty()
    }
    pub fn shared_bytes(&self) -> &std::sync::Arc<Vec<u8>> {
        &self.bytes
    }
    pub fn into_bytes(self) -> Vec<u8> {
        std::sync::Arc::try_unwrap(self.bytes).unwrap_or_else(|bytes| bytes.as_ref().clone())
    }
}
impl AsRef<[u8]> for EncodedDmb {
    fn as_ref(&self) -> &[u8] {
        self.bytes()
    }
}
impl std::ops::Deref for EncodedDmb {
    type Target = [u8];
    fn deref(&self) -> &Self::Target {
        self.bytes()
    }
}

#[derive(Default)]
struct CanonicalHash {
    state: Xxh3,
    through: usize,
}
impl CanonicalHash {
    fn pending(&mut self, writer: &Writer) {
        self.state.update(&writer.bytes[self.through..]);
        self.through = writer.at();
    }
    fn append(&mut self, writer: &mut Writer, bytes: &[u8]) {
        debug_assert_eq!(self.through, writer.at());
        self.state.update(bytes);
        writer.raw(bytes);
        self.through = writer.at();
    }
    fn finish(mut self, writer: Writer<'static>) -> EncodedDmb {
        self.pending(&writer);
        EncodedDmb {
            bytes: std::sync::Arc::new(writer.bytes.into_owned()),
            content_hash: self.state.digest128(),
        }
    }
}

#[path = "dmb_write_slices.rs"]
mod slices;
use slices::sized_records;

struct Chunk {
    writer: Writer<'static>,
    spans: Vec<Range<usize>>,
}

fn table<T: Sync>(
    writer: &mut Writer,
    hash: &mut CanonicalHash,
    items: &[T],
    executor: Option<&BuildExecutor>,
    sizes: Option<&[usize]>,
    spans: bool,
    encode: impl Fn(&mut Writer, &T, usize) -> io::Result<()> + Sync,
) -> io::Result<Vec<Range<usize>>> {
    let count = u32::try_from(items.len()).map_err(|_| invalid("table exceeds u32 count"))?;
    writer.object(count);
    records(writer, hash, items, executor, sizes, spans, encode)
}

fn records<T: Sync>(
    writer: &mut Writer,
    hash: &mut CanonicalHash,
    items: &[T],
    executor: Option<&BuildExecutor>,
    sizes: Option<&[usize]>,
    spans: bool,
    encode: impl Fn(&mut Writer, &T, usize) -> io::Result<()> + Sync,
) -> io::Result<Vec<Range<usize>>> {
    let Some(executor) = executor.filter(|executor| executor.workers() > 1 && items.len() >= 64)
    else {
        let mut offsets = Vec::with_capacity(if spans { items.len() } else { 0 });
        for item in items {
            let start = writer.at();
            encode(writer, item, 0)?;
            if spans {
                offsets.push(start..writer.at());
            }
        }
        hash.pending(writer);
        return Ok(offsets);
    };
    let ranges = chunk_ranges(items.len(), sizes, executor.workers().saturating_mul(4))?;
    if let Some(sizes) = sizes {
        return sized_records(writer, hash, items, executor, sizes, spans, encode, ranges);
    }
    hash.pending(writer);
    let prefix = writer.at();
    let object_size = writer.object_size;
    let compatibility_version = writer.compatibility_version;
    let mut bases = Vec::with_capacity(ranges.len());
    let mut base = prefix;
    for range in &ranges {
        bases.push(base);
        if let Some(sizes) = sizes {
            for &size in &sizes[range.clone()] {
                base = base
                    .checked_add(size)
                    .ok_or_else(|| invalid("serialization offset overflow"))?;
            }
        }
    }
    let mut outputs: Vec<Option<io::Result<Chunk>>> = (0..ranges.len()).map(|_| None).collect();
    let scoped = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        executor.scope(|scope| {
            for ((range, base), output) in ranges.iter().zip(bases).zip(&mut outputs) {
                let encode = &encode;
                scope.spawn(move |_| {
                    let _profile = dm_profile::stage("output.dmb_encode");
                    let mut chunk = Writer::new(object_size, compatibility_version);
                    if let Some(sizes) = sizes {
                        // The prefix sum above has already checked this count.
                        let count = sizes[range.clone()].iter().sum();
                        chunk.bytes.reserve(count);
                    }
                    let mut offsets = Vec::with_capacity(if spans { range.len() } else { 0 });
                    let result = (|| {
                        for item in &items[range.clone()] {
                            let start = chunk.at();
                            encode(&mut chunk, item, base)?;
                            if spans {
                                offsets.push(start..chunk.at());
                            }
                        }
                        Ok(Chunk {
                            writer: chunk,
                            spans: offsets,
                        })
                    })();
                    *output = Some(result);
                });
            }
        });
    }));
    if scoped.is_err() {
        return Err(io::Error::other("DMB encoding worker panicked"));
    }
    // Choose errors in canonical chunk order, independent of completion order.
    let chunks: Vec<Chunk> = outputs
        .into_iter()
        .map(|output| {
            output.ok_or_else(|| io::Error::other("DMB encoding worker omitted its result"))?
        })
        .collect::<io::Result<_>>()?;
    let bytes = chunks.iter().try_fold(0usize, |total, chunk| {
        total
            .checked_add(chunk.writer.bytes.len())
            .ok_or_else(|| invalid("serialization size overflow"))
    })?;
    writer.bytes.reserve(bytes);
    let mut offsets = Vec::with_capacity(if spans { items.len() } else { 0 });
    for chunk in chunks {
        let at = writer.at();
        writer.object_overflow |= chunk.writer.object_overflow;
        hash.append(writer, &chunk.writer.bytes);
        offsets.extend(
            chunk
                .spans
                .into_iter()
                .map(|span| at + span.start..at + span.end),
        );
    }
    Ok(offsets)
}

fn chunk_ranges(
    count: usize,
    sizes: Option<&[usize]>,
    chunks: usize,
) -> io::Result<Vec<Range<usize>>> {
    if let Some(sizes) = sizes {
        if sizes.len() != count {
            return Err(invalid("serialization size count mismatch"));
        }
    }
    if count == 0 {
        return Ok(Vec::new());
    }
    let total = if let Some(sizes) = sizes {
        sizes
            .iter()
            .try_fold(0usize, |sum, &size| sum.checked_add(size))
            .ok_or_else(|| invalid("serialization size overflow"))?
    } else {
        count
    };
    let chunks = chunks.max(1).min(count);
    let target = total.div_ceil(chunks).max(1);
    let mut ranges = Vec::with_capacity(chunks);
    let mut start = 0;
    let mut weight = 0usize;
    for index in 0..count {
        weight = weight
            .checked_add(sizes.map_or(1, |sizes| sizes[index]))
            .ok_or_else(|| invalid("serialization size overflow"))?;
        if weight >= target && ranges.len() + 1 < chunks {
            ranges.push(start..index + 1);
            start = index + 1;
            weight = 0;
        }
    }
    if start < count {
        ranges.push(start..count);
    }
    Ok(ranges)
}

fn string_size(string: &DmString) -> io::Result<usize> {
    let long_bytes = usize::from(string.long_chunks)
        .checked_mul(u16::MAX as usize)
        .ok_or_else(|| invalid("invalid long string chunks"))?;
    let remaining = string
        .data
        .len()
        .checked_sub(long_bytes)
        .ok_or_else(|| invalid("invalid long string chunks"))?;
    if remaining >= u16::MAX as usize {
        return Err(invalid("string needs additional length chunks"));
    }
    string
        .data
        .len()
        .checked_add((usize::from(string.long_chunks) + 1) * 2)
        .ok_or_else(|| invalid("string serialization size overflow"))
}

fn write_string(
    writer: &mut Writer,
    string: &DmString,
    base: usize,
    origin: usize,
) -> io::Result<()> {
    let remaining = string.data.len() - usize::from(string.long_chunks) * u16::MAX as usize;
    for _ in 0..string.long_chunks {
        let offset = base
            .checked_add(writer.at())
            .and_then(|offset| offset.checked_sub(origin))
            .ok_or_else(|| invalid("string cipher offset overflow"))?;
        writer.u16(u16::MAX ^ offset as u16);
    }
    let offset = base
        .checked_add(writer.at())
        .and_then(|offset| offset.checked_sub(origin))
        .ok_or_else(|| invalid("string cipher offset overflow"))?;
    writer.u16((remaining as u16) ^ offset as u16);
    let start = writer.at();
    let offset = base
        .checked_add(start)
        .and_then(|offset| offset.checked_sub(origin))
        .ok_or_else(|| invalid("string cipher offset overflow"))?;
    writer.raw(&string.data);
    writer.check_storage()?;
    // Encrypt the just-appended payload in place, eliminating the old clone.
    crypt_string(&mut writer.bytes[start..], offset);
    Ok(())
}

pub(super) fn write(
    dmb: &Dmb,
    executor: Option<&BuildExecutor>,
) -> io::Result<(EncodedDmb, Vec<Range<usize>>)> {
    write_reusing_lists(dmb, executor, None)
}
pub(super) fn write_reusing_lists(
    dmb: &Dmb,
    executor: Option<&BuildExecutor>,
    previous: Option<&super::word_lists::ListEncoding>,
) -> io::Result<(EncodedDmb, Vec<Range<usize>>)> {
    if dmb.header.version_line != b"world bin v516\n"
        || !dmb
            .header
            .compatibility_line
            .starts_with(b"min compatibility v")
        || !dmb.header.compatibility_line.ends_with(b"\n")
        || dmb
            .header
            .compatibility_line
            .iter()
            .filter(|&&byte| byte == b'\n')
            .count()
            != 1
        || (dmb.header.flags & 0x8000_0000 != 0) != dmb.header.extended_flags.is_some()
    {
        return Err(invalid("unsupported DMB header"));
    }
    dmb.validate_references()?;
    let cells = dmb
        .dimensions
        .iter()
        .try_fold(1usize, |product, &value| {
            product.checked_mul(usize::from(value))
        })
        .ok_or_else(|| invalid("grid dimensions overflow"))?;
    let mut covered = 0usize;
    for run in &dmb.grid {
        if run.copies == 0 {
            return Err(invalid("zero-length grid run"));
        }
        covered = covered
            .checked_add(usize::from(run.copies))
            .ok_or_else(|| invalid("grid run count overflow"))?;
    }
    if covered != cells {
        return Err(invalid("grid runs do not cover map dimensions"));
    }
    if dmb.lists.iter().any(|list| list.len() > u16::MAX as usize) {
        return Err(invalid("list exceeds u16 element count"));
    }
    if dmb.world.client_script_files.len() > u16::MAX as usize {
        return Err(invalid("client script file list exceeds u16 count"));
    }
    if compatibility_version(&dmb.header.compatibility_line)? <= 514
        && dmb.world.savefile_byond_version != 0
    {
        return Err(invalid(
            "savefile version has no field at this compatibility level",
        ));
    }
    for class in &dmb.classes {
        if (class.interface == 15) != class.extended_interface.is_some()
            || (class.transform_flag != 0) != class.transform.is_some()
            || (class.color_matrix_flag != 0) != class.color_matrix.is_some()
        {
            return Err(invalid("class presence flag disagrees with data"));
        }
    }
    if dmb
        .mobs
        .iter()
        .any(|mob| (mob.sight & 0x80 != 0) != mob.extended_sight.is_some())
    {
        return Err(invalid("mob sight flag disagrees with data"));
    }
    if dmb
        .procs
        .iter()
        .any(|proc| (proc.flags & 0x80 != 0) != proc.extended_flags.is_some())
    {
        return Err(invalid("proc flag disagrees with data"));
    }
    let mut hash = CanonicalHash::default();
    let mut w = Writer::new(
        if dmb.header.flags & 0x4000_0000 != 0 {
            4
        } else {
            2
        },
        compatibility_version(&dmb.header.compatibility_line)?,
    );
    if let Some(line) = &dmb.header.executor_line {
        // Native world.executor text may contain newlines. The reader stops
        // at a version line followed by a compatibility line, so reject
        // that ambiguous sentinel rather than valid multiline text.
        if !line.starts_with(b"#!")
            || !line.ends_with(b"\n")
            || line
                .windows(b"\nworld bin v516\nmin compatibility v".len())
                .any(|part| part == b"\nworld bin v516\nmin compatibility v")
        {
            return Err(invalid("invalid executor shebang"));
        }
        w.raw(line);
    }
    w.raw(&dmb.header.version_line);
    w.raw(&dmb.header.compatibility_line);
    w.u32(dmb.header.flags);
    if let Some(flags) = dmb.header.extended_flags {
        w.u32(flags);
    }
    for value in dmb.dimensions {
        w.u16(value);
    }
    records(
        &mut w,
        &mut hash,
        &dmb.grid,
        executor,
        None,
        false,
        |w, run, _| {
            w.object(run.turf);
            w.object(run.area);
            w.object(run.contents);
            w.u8(run.copies);
            Ok(())
        },
    )?;
    let total_string_bytes = dmb.strings.iter().try_fold(0usize, |sum, string| {
        sum.checked_add(string.data.len() + 1)
            .ok_or_else(|| invalid("string total overflow"))
    })?;
    w.u32(u32::try_from(total_string_bytes).map_err(|_| invalid("string total exceeds u32"))?);
    table(
        &mut w,
        &mut hash,
        &dmb.classes,
        executor,
        None,
        false,
        |w, item, _| {
            item.write(w);
            Ok(())
        },
    )?;
    table(
        &mut w,
        &mut hash,
        &dmb.mobs,
        executor,
        None,
        false,
        |w, item, _| {
            item.write(w);
            Ok(())
        },
    )?;
    w.object(u32::try_from(dmb.strings.len()).map_err(|_| invalid("string count exceeds u32"))?);
    let string_origin = dmb.header.executor_line.as_ref().map_or(0, Vec::len);
    let string_sizes = dmb
        .strings
        .iter()
        .map(string_size)
        .collect::<io::Result<Vec<_>>>()?;
    records(
        &mut w,
        &mut hash,
        &dmb.strings,
        executor,
        Some(&string_sizes),
        false,
        |w, string, base| write_string(w, string, base, string_origin),
    )?;
    // CRC remains a serial canonical-order fold over clear payload bytes.
    // Cipher work can run in parallel; there is no composable CRC scheme.
    let mut string_hash = u32::MAX;
    for string in &dmb.strings {
        string_hash = nqcrc(string_hash, &string.data);
        string_hash = nqcrc(string_hash, &[0]);
    }
    w.u32(string_hash);
    let list_sizes = dmb
        .lists
        .iter()
        .map(|list| {
            list.len()
                .checked_mul(w.object_size)
                .and_then(|bytes| bytes.checked_add(2))
                .ok_or_else(|| invalid("list serialization size overflow"))
        })
        .collect::<io::Result<Vec<_>>>()?;
    let rows: Vec<_> = dmb.lists.storage().iter().enumerate().collect();
    let list_spans = table(
        &mut w,
        &mut hash,
        &rows,
        executor,
        Some(&list_sizes),
        true,
        |w, &(ordinal, list), _| {
            if let Some(bytes) =
                previous.and_then(|previous| previous.row(list, ordinal, w.object_size))
            {
                w.raw(bytes);
                return Ok(());
            }
            w.u16(list.len() as u16);
            for &value in list.iter() {
                w.object(value);
            }
            Ok(())
        },
    )?;
    table(
        &mut w,
        &mut hash,
        &dmb.procs,
        executor,
        None,
        false,
        |w, item, _| {
            item.write(w);
            Ok(())
        },
    )?;
    table(
        &mut w,
        &mut hash,
        &dmb.variables,
        executor,
        None,
        false,
        |w, item, _| {
            w.u8(item.kind);
            w.u32(item.value);
            w.object(item.name);
            Ok(())
        },
    )?;
    w.u32(dmb.variable_footer);
    table(
        &mut w,
        &mut hash,
        &dmb.proc_references,
        executor,
        None,
        false,
        |w, value, _| {
            w.object(*value);
            Ok(())
        },
    )?;
    table(
        &mut w,
        &mut hash,
        &dmb.instances,
        executor,
        None,
        false,
        |w, item, _| {
            w.u8(item.kind);
            w.u32(item.class);
            w.object(item.initializer);
            Ok(())
        },
    )?;
    w.u32(
        u32::try_from(dmb.map_objects.len())
            .map_err(|_| invalid("map object count exceeds u32"))?,
    );
    records(
        &mut w,
        &mut hash,
        &dmb.map_objects,
        executor,
        None,
        false,
        |w, item, _| {
            w.u16(item.offset);
            w.object(item.instance);
            Ok(())
        },
    )?;
    dmb.world.write(&mut w);
    table(
        &mut w,
        &mut hash,
        &dmb.resources,
        executor,
        None,
        false,
        |w, item, _| {
            w.u32(item.id);
            w.u8(item.kind);
            Ok(())
        },
    )?;
    if w.object_overflow {
        return Err(invalid("object ID exceeds selected 16-bit width"));
    }
    Ok((hash.finish(w), list_spans))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn populated(wide: bool) -> Dmb {
        let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        if wide {
            dmb.header.flags |= 0x4000_0000;
        } else {
            dmb.header.flags &= !0x4000_0000;
        }
        dmb.header.flags |= 0x8000_0000;
        dmb.header.extended_flags = Some(0x54);
        dmb.header.executor_line =
            Some(b"#!/usr/bin/env DreamDaemon\n# second authored line\n".to_vec());
        for index in 0..256 {
            dmb.strings.push(DmString {
                data: [vec![0xff, 0x81, 0, index as u8], vec![b'x'; index % 63]].concat(),
                long_chunks: 0,
            });
        }
        dmb.strings.push(DmString {
            data: vec![0x80; u16::MAX as usize + 7],
            long_chunks: 1,
        });
        for index in 0..512 {
            dmb.lists.push(
                (0..(index % 127))
                    .map(|word| (word + index) as u32)
                    .collect(),
            );
        }
        dmb
    }

    #[test]
    fn parallel_and_serial_match_wide_and_narrow_cipher_crc_and_spans() {
        let executor = BuildExecutor::new(3).unwrap();
        for wide in [false, true] {
            let dmb = populated(wide);
            let serial = dmb.to_bytes_with_list_spans().unwrap();
            let parallel = dmb.to_bytes_with_list_spans_on_executor(&executor).unwrap();
            assert_eq!(parallel, serial);
            let (decoded, spans) = Dmb::from_bytes_with_list_spans(&parallel.0).unwrap();
            assert_eq!(decoded, dmb);
            assert_eq!(spans, parallel.1);
            for (list, span) in dmb.lists.iter().zip(&parallel.1) {
                assert_eq!(span.len(), 2 + list.len() * if wide { 4 } else { 2 });
            }
        }
    }

    #[test]
    fn one_worker_and_many_workers_keep_identical_generation_bytes() {
        let dmb = populated(true);
        let baseline = dmb.to_bytes().unwrap();
        for workers in [1, 2, 8] {
            let executor = BuildExecutor::new(workers).unwrap();
            assert_eq!(dmb.to_bytes_on_executor(&executor).unwrap(), baseline);
        }
    }

    #[test]
    fn immutable_owner_digest_matches_exact_ciphertext_for_all_worker_counts() {
        for wide in [false, true] {
            let dmb = populated(wide);
            let baseline = dmb.to_bytes().unwrap();
            let owner = dmb.encode().unwrap();
            assert_eq!(owner.bytes(), baseline);
            assert_eq!(owner.content_hash(), xxhash_rust::xxh3::xxh3_128(&baseline));
            assert_eq!(owner.len(), baseline.len());
            assert!(!owner.is_empty());
            for workers in [1, 2, 8] {
                let executor = BuildExecutor::new(workers).unwrap();
                let encoded = dmb.encode_on_executor(&executor).unwrap();
                assert_eq!(encoded.bytes(), owner.bytes());
                assert_eq!(encoded.content_hash(), owner.content_hash());
                assert_eq!(encoded.into_bytes(), baseline);
            }
        }
    }

    #[test]
    fn parallel_worker_panic_is_an_io_error_and_all_jobs_finish() {
        let executor = BuildExecutor::new(3).unwrap();
        let values: Vec<_> = (0..128).collect();
        let completed = std::sync::atomic::AtomicUsize::new(0);
        let mut writer = Writer::new(4, 516);
        let mut hash = CanonicalHash::default();
        let error = records(
            &mut writer,
            &mut hash,
            &values,
            Some(&executor),
            None,
            false,
            |writer, value, _| {
                completed.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                if *value == 64 {
                    panic!("intentional encoder panic");
                }
                writer.u32(*value);
                Ok(())
            },
        )
        .unwrap_err();
        assert_eq!(error.kind(), ErrorKind::Other);
        assert!(completed.load(std::sync::atomic::Ordering::SeqCst) > 64);
        // A scoped panic did not detach jobs or poison the reusable executor.
        assert_eq!(executor.install(|| 7), 7);
    }

    #[test]
    fn parallel_narrow_chunks_propagate_object_overflow() {
        let mut dmb = populated(false);
        dmb.lists.last_mut().unwrap().push(0x1_0000);
        let executor = BuildExecutor::new(2).unwrap();
        assert_eq!(dmb.to_bytes().unwrap_err().kind(), ErrorKind::InvalidData);
        assert_eq!(
            dmb.to_bytes_on_executor(&executor).unwrap_err().kind(),
            ErrorKind::InvalidData
        );
    }
}
