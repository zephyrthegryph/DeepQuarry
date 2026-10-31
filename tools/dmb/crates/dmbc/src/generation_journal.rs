//! Generation staging: no source/model handles or operation budgets escape a loan.
//! Only anonymous scratch and fixed counters survive the source callback.
use std::{
    fs::File,
    io::{self, Read, Seek, SeekFrom, Write},
};
const MAGIC: &[u8; 8] = b"DQGENJ01";
const HEADER: u64 = 8 + 8 + 8 + 16;
const LIMIT: u64 = 64 * 1024 * 1024;
pub(crate) struct StagedJournal {
    file: File,
    count: u64,
    length: u64,
    hash: xxhash_rust::xxh3::Xxh3,
    sealed: bool,
    failed: bool,
}
impl StagedJournal {
    pub(crate) fn new(mut file: File) -> io::Result<Self> {
        file.set_len(0)?;
        file.seek(SeekFrom::Start(0))?;
        file.write_all(&[0u8; HEADER as usize])?;
        Ok(Self {
            file,
            count: 0,
            length: HEADER,
            hash: xxhash_rust::xxh3::Xxh3::new(),
            sealed: false,
            failed: false,
        })
    }
    /// Caller validates the exact registered generator output path, checks every
    /// diagnostic, and holds the actual current source guard throughout this call.
    /// This function never installs output and allocates no path/text copies.
    pub(crate) fn append_generator(&mut self, ordinal: u32, name: &str) -> io::Result<()> {
        self.append(3, ordinal, name, "")
    }
    pub(crate) fn append_file(&mut self, path: &str, text: &str) -> io::Result<()> {
        self.append(1, 0, path, text)
    }
    pub(crate) fn append_diagnostic(
        &mut self,
        path: &str,
        line: u32,
        message: &str,
    ) -> io::Result<()> {
        self.append(2, line, path, message)
    }
    fn append(&mut self, kind: u8, line: u32, path: &str, text: &str) -> io::Result<()> {
        if self.sealed || self.failed {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "generation journal already sealed",
            ));
        }
        self.failed = true;
        let p = u32::try_from(path.len())
            .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "generation path too long"))?;
        let t = u64::try_from(text.len()).map_err(|_| {
            io::Error::new(
                io::ErrorKind::OutOfMemory,
                "generation output length overflow",
            )
        })?;
        let end = self
            .length
            .checked_add(17)
            .and_then(|n| n.checked_add(u64::from(p)))
            .and_then(|n| n.checked_add(t))
            .filter(|n| *n <= LIMIT)
            .ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::OutOfMemory,
                    "generation staging exceeds output bound",
                )
            })?;
        let count = self.count.checked_add(1).ok_or_else(|| {
            io::Error::new(io::ErrorKind::OutOfMemory, "generation file count overflow")
        })?;
        // An interrupted write invalidates this journal. It must not be reused; the
        // anonymous file is discarded with the whole failed generation operation.
        for bytes in [
            &[kind][..],
            &line.to_le_bytes()[..],
            &p.to_le_bytes()[..],
            &t.to_le_bytes()[..],
            path.as_bytes(),
            text.as_bytes(),
        ] {
            self.file.write_all(bytes)?;
            self.hash.update(bytes);
        }
        self.length = end;
        self.count = count;
        self.failed = false;
        Ok(())
    }
    pub(crate) fn seal(mut self) -> io::Result<SealedJournal> {
        if self.failed {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "failed generation journal cannot be sealed",
            ));
        }
        self.file.flush()?;
        let digest = self.hash.digest128();
        self.file.seek(SeekFrom::Start(0))?;
        self.file.write_all(MAGIC)?;
        self.file.write_all(&self.count.to_le_bytes())?;
        self.file.write_all(&self.length.to_le_bytes())?;
        self.file.write_all(&digest.to_le_bytes())?;
        self.file.flush()?;
        self.sealed = true;
        Ok(SealedJournal {
            file: self.file,
            count: self.count,
            length: self.length,
            digest,
        })
    }
}
/// A sealed journal is not source-read or output-install permission. The actual
/// coordinator must retire its source snapshot and validate the complete input
/// closure before opening any destination for mutation.
pub(crate) struct SealedJournal {
    file: File,
    count: u64,
    length: u64,
    digest: u128,
}
impl SealedJournal {
    pub(crate) fn verify(&mut self) -> io::Result<()> {
        self.file.seek(SeekFrom::Start(0))?;
        let mut header = [0u8; HEADER as usize];
        self.file.read_exact(&mut header)?;
        if &header[..8] != MAGIC
            || u64::from_le_bytes(header[8..16].try_into().unwrap()) != self.count
            || u64::from_le_bytes(header[16..24].try_into().unwrap()) != self.length
            || u128::from_le_bytes(header[24..40].try_into().unwrap()) != self.digest
            || self.file.metadata()?.len() != self.length
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "generation journal header changed",
            ));
        }
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        let mut remaining = self.length - HEADER;
        let mut block = [0u8; 8192];
        while remaining != 0 {
            let count = usize::try_from(remaining.min(block.len() as u64)).unwrap();
            self.file.read_exact(&mut block[..count])?;
            hash.update(&block[..count]);
            remaining -= count as u64;
        }
        if hash.digest128() != self.digest {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "generation journal content changed",
            ));
        }
        self.file.seek(SeekFrom::Start(HEADER))?;
        Ok(())
    }
}
impl SealedJournal {
    /// `admit` belongs to the source-free transaction, not a cached source Budget.
    /// The copied path is freed before the next record, and payload bytes stream
    /// from the anonymous journal without allocating a generated-text copy.
    pub(crate) fn visit(&mut self,admit:&mut impl FnMut(usize)->io::Result<()>,consume:&mut impl FnMut(u8,u32,&str,u64,&mut dyn Read)->io::Result<()>)->io::Result<()>{self.visit_indexed(admit,&mut|kind,line,path,length,body,_|consume(kind,line,path,length,body))}
    pub(crate) fn visit_indexed(
        &mut self,
        admit: &mut impl FnMut(usize) -> io::Result<()>,
        consume: &mut impl FnMut(u8, u32, &str, u64, &mut dyn Read,JournalPayload) -> io::Result<()>,
    ) -> io::Result<()> {
        self.verify()?;
        let mut position = HEADER;
        let mut admitted_path_peak = 0usize;
        for _ in 0..self.count {
            let mut header = [0u8; 17];
            self.file.read_exact(&mut header)?;
            let kind = header[0];
            let line = u32::from_le_bytes(header[1..5].try_into().unwrap());
            let path = u32::from_le_bytes(header[5..9].try_into().unwrap()) as usize;
            let text = u64::from_le_bytes(header[9..17].try_into().unwrap());
            let end = position
                .checked_add(17)
                .and_then(|n| n.checked_add(path as u64))
                .and_then(|n| n.checked_add(text))
                .filter(|n| *n <= self.length)
                .ok_or_else(|| {
                    io::Error::new(
                        io::ErrorKind::InvalidData,
                        "generation journal record outside sealed bytes",
                    )
                })?;
            if !matches!(kind, 1 | 2 | 3) || (kind == 1 && line != 0) || (kind == 3 && text != 0) {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "generation journal record kind invalid",
                ));
            }
            let charge = path
                .checked_mul(4)
                .and_then(|n| n.checked_add(std::mem::size_of::<Vec<u8>>()))
                .ok_or_else(|| {
                    io::Error::new(
                        io::ErrorKind::OutOfMemory,
                        "generation journal path admission overflow",
                    )
                })?;
            if charge > admitted_path_peak {
                admit(charge - admitted_path_peak)?;
                admitted_path_peak = charge;
            }
            let mut bytes = Vec::new();
            bytes
                .try_reserve_exact(path)
                .map_err(|e| io::Error::new(io::ErrorKind::OutOfMemory, e))?;
            if bytes.capacity() > path.saturating_mul(4) {
                return Err(io::Error::new(
                    io::ErrorKind::OutOfMemory,
                    "generation journal path allocation exceeds admission",
                ));
            }
            bytes.resize(path, 0);
            self.file.read_exact(&mut bytes)?;
            let path = std::str::from_utf8(&bytes).map_err(|_| {
                io::Error::new(
                    io::ErrorKind::InvalidData,
                    "generation journal path is not UTF8",
                )
            })?;
            let mut payload = Read::take(&mut self.file, text);
            consume(kind,line,path,text,&mut payload,JournalPayload{offset:position+17+u64::try_from(bytes.len()).map_err(|_|io::Error::other("journal offset overflow"))?,length:text})?;
            if payload.limit() != 0 {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "generation journal consumer left unread record bytes",
                ));
            }
            drop(bytes);
            position = end;
        }
        if position != self.length {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "generation journal record count differs from sealed bytes",
            ));
        }
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn journal() -> StagedJournal {
        let root = crate::test_scratch::dir("generation-journal");
        StagedJournal::new(crate::generation_staging::temporary_output(&root).unwrap()).unwrap()
    }
    #[test]
    fn generation_journal_roundtrips_full_ordered_files_diagnostics_and_empty_generator() {
        let mut s = journal();
        s.append_generator(0, "declare").unwrap();
        s.append_file("code/engine/_generated/declare.dm", "α\n\0\"actual")
            .unwrap();
        s.append_diagnostic("code/a.dm", 19, "ordered refusal")
            .unwrap();
        s.append_generator(1, "ui_types").unwrap();
        let mut s = s.seal().unwrap();
        let mut rows = Vec::new();
        let mut admitted = 0;
        s.visit(
            &mut |n| {
                admitted += n;
                Ok(())
            },
            &mut |k, l, p, _, b| {
                let mut text = String::new();
                b.read_to_string(&mut text)?;
                rows.push((k, l, p.to_owned(), text));
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(
            rows,
            vec![
                (3, 0, "declare".into(), "".into()),
                (
                    1,
                    0,
                    "code/engine/_generated/declare.dm".into(),
                    "α\n\0\"actual".into()
                ),
                (2, 19, "code/a.dm".into(), "ordered refusal".into()),
                (3, 1, "ui_types".into(), "".into())
            ]
        );
        assert!(admitted > 0);
    }
    #[test]
    fn generation_journal_corruption_refuses_before_any_consumer() {
        let mut s = journal();
        s.append_file("code/engine/_generated/ids.dm", "valid")
            .unwrap();
        let mut s = s.seal().unwrap();
        s.file.seek(SeekFrom::Start(HEADER + 17)).unwrap();
        s.file.write_all(b"X").unwrap();
        let seen = std::cell::Cell::new(false);
        let e = s
            .visit(&mut |_| Ok(()), &mut |_, _, _, _, _| {
                seen.set(true);
                Ok(())
            })
            .unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::InvalidData);
        assert!(!seen.get());
    }
    #[test]
    fn generation_journal_partial_consumer_cannot_skip_record_bytes() {
        let mut s = journal();
        s.append_file("code/engine/_generated/ids.dm", "not consumed")
            .unwrap();
        let e = s
            .seal()
            .unwrap()
            .visit(&mut |_| Ok(()), &mut |_, _, _, _, _| Ok(()))
            .unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::InvalidData);
    }
    #[test]
    fn generation_journal_path_admission_precedes_allocation_and_consumer() {
        let mut s = journal();
        s.append_file("code/engine/_generated/ids.dm", "actual")
            .unwrap();
        let e = s
            .seal()
            .unwrap()
            .visit(
                &mut |_| Err(io::Error::from_raw_os_error(1450)),
                &mut |_, _, _, _, _| panic!("denied path must not reach consumer"),
            )
            .unwrap_err();
        assert_eq!(e.raw_os_error(), Some(1450));
    }
    #[test]
    fn generation_journal_real_write_failure_poison_refuses_later_append_and_seal() {
        let root = crate::test_scratch::dir("generation-journal-write-error");
        let path = root.join("read-only-owned");
        std::fs::write(&path, b"").unwrap();
        let mut s = journal();
        s.file = std::fs::OpenOptions::new().read(true).open(&path).unwrap();
        assert!(s
            .append_file("code/engine/_generated/ids.dm", "realwrite")
            .is_err());
        assert!(s.failed);
        assert!(s
            .append_file("code/engine/_generated/ids.dm", "retry is forbidden")
            .is_err());
        assert!(s.seal().is_err());
    }
    #[test]
    fn generation_journal_bounds_refuse_before_writing_a_record() {
        let mut s = journal();
        s.length = LIMIT - 1;
        let before = s.file.metadata().unwrap().len();
        let e = s
            .append_file("code/engine/_generated/ids.dm", "too large")
            .unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::OutOfMemory);
        assert_eq!(s.file.metadata().unwrap().len(), before);
        assert_eq!(s.count, 0);
    }
}
#[cfg(test)]mod path_peak_tests{
 use super::*;
 #[test]fn generation_journal_reuses_only_the_funded_live_path_peak_across_all_records(){
  let root=crate::test_scratch::dir("generation-journal-live-path-peak");let mut journal=StagedJournal::new(crate::generation_staging::temporary_output(&root).unwrap()).unwrap();let mut longest=0usize;
  for index in 0..200{let path=if index%3==0{"code/engine/_generated/short.dm"}else{"tgui/packages/tgui/interfaces/generated/a_much_longer_original_type_name.d.ts"};longest=longest.max(path.len());journal.append_file(path,"actual output").unwrap();}
  let mut journal=journal.seal().unwrap();let mut charged=0;let mut records=0;journal.visit(&mut|bytes|{charged+=bytes;Ok(())},&mut|kind,line,_,length,body|{assert_eq!((kind,line,length),(1,0,13));let copied=io::copy(body,&mut io::sink())?;assert_eq!(copied,length);records+=1;Ok(())}).unwrap();assert_eq!(records,200);assert_eq!(charged,4*longest+std::mem::size_of::<Vec<u8>>(),"only simultaneous path storage is funded, never 200 already-freed paths");
 }
}

/// Source-free journal coordinates, minted only by the validated record walk.
#[derive(Clone,Copy)]pub(crate) struct JournalPayload{offset:u64,length:u64}
impl SealedJournal{
 pub(crate) fn copy_payload(&mut self,payload:JournalPayload,out:&mut impl Write)->io::Result<()>{
  if payload.offset<HEADER||payload.offset.checked_add(payload.length).is_none_or(|end|end>self.length){return Err(io::Error::new(io::ErrorKind::InvalidData,"journal payload outside sealed range"))}
  self.file.seek(SeekFrom::Start(payload.offset))?;let mut source=Read::take(&mut self.file,payload.length);let mut block=[0u8;8192];while source.limit()!=0{crate::daemon::control::checkpoint()?;let count=source.read(&mut block)?;if count==0{return Err(io::ErrorKind::UnexpectedEof.into())}out.write_all(&block[..count])?;}Ok(())
 }
}
