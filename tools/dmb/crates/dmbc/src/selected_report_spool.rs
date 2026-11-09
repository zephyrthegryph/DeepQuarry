//! Resource-only staging for an already-judged selected Analyze report.
//! No source/producer/ALLOW authority can be constructed by these file helpers.
use std::{
    fs::File,
    io::{self, Read, Seek, SeekFrom, Write},
    path::Path,
    sync::{Arc, Mutex},
};
use dm_preprocess::source_arena_credit::{SourceArenaCredit, SourceArenaWork};
use xxhash_rust::xxh3::Xxh3;

const LIMIT: u64 = dq_analyze::selected_exclusions_wire::MAX_STREAM;
const BLOCK: usize = 8192;

pub(crate) struct Stage {
    file: File,
    length: u64,
    limit: u64,
    hash: Xxh3,
    failed: bool,
}

impl Stage {
    pub(crate) fn new(cache: &Path) -> io::Result<Self> {
        let file = crate::generation_staging::private_report_output(cache)?;
        Ok(Self { file, length: 0, limit: LIMIT, hash: Xxh3::new(), failed: false })
    }

    pub(crate) fn length(&self) -> u64 { self.length }

    pub(crate) fn restart_attempt(&mut self) -> io::Result<()> {
        crate::daemon::control::checkpoint()?;
        if self.failed {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected preparation diagnostic staging is poisoned"));
        }
        if self.length != 0 {
            self.failed = true;
            self.file.set_len(0)?;
            self.file.rewind()?;
            self.length = 0;
            self.hash = Xxh3::new();
            self.failed = false;
        }
        Ok(())
    }

    pub(crate) fn seal(mut self) -> io::Result<Sealed> {
        crate::daemon::control::checkpoint()?;
        if self.failed || self.length == 0 {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "failed or empty selected report staging"));
        }
        self.file.flush()?;
        if self.file.metadata()?.len() != self.length {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "staged selected report length differs"));
        }
        self.file.seek(SeekFrom::Start(0))?;
        let mut hash = Xxh3::new();
        let mut remaining = self.length;
        let mut block = [0u8; BLOCK];
        while remaining != 0 {
            crate::daemon::control::checkpoint()?;
            let count = remaining.min(BLOCK as u64) as usize;
            self.file.read_exact(&mut block[..count])?;
            hash.update(&block[..count]);
            remaining -= count as u64;
        }
        if hash.digest128() != self.hash.digest128() {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "staged selected report digest differs"));
        }
        self.file.seek(SeekFrom::Start(0))?;
        Ok(Sealed { file: self.file, length: self.length, hash: hash.digest128() })
    }
}

impl Write for Stage {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if self.failed {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report staging is poisoned"));
        }
        self.failed = true;
        crate::daemon::control::checkpoint()?;
        let end = self.length.checked_add(bytes.len() as u64).filter(|&end| end <= self.limit)
            .ok_or_else(|| io::Error::new(io::ErrorKind::OutOfMemory, "selected report exceeds the existing report bound"))?;
        self.file.write_all(bytes)?;
        self.hash.update(bytes);
        self.length = end;
        self.failed = false;
        Ok(bytes.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        if self.failed {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report staging is poisoned"));
        }
        self.failed = true;
        self.file.flush()?;
        self.failed = false;
        Ok(())
    }
}

pub(crate) struct Sealed { file: File, length: u64, hash: u128 }
impl Sealed {
    /// The actual report owner validates its selected policies, frame, status
    /// and ALLOW completion here. No public sink is available in this state.
    pub(crate) fn validate<T>(mut self, validate: impl FnOnce(&mut dyn Read) -> io::Result<T>) -> io::Result<(Verified, T)> {
        let mut reader = (&mut self.file).take(self.length);
        let data = validate(&mut reader)?;
        if reader.limit() != 0 {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report validation omitted staged bytes"));
        }
        self.file.seek(SeekFrom::Start(0))?;
        crate::daemon::control::checkpoint()?;
        Ok((Verified(VerifiedBacking::Single(self)), data))
    }
}

pub(crate) struct Verified(VerifiedBacking);

enum VerifiedBacking {
    Single(Sealed),
    Replay(Arc<ReplayFile>),
}

struct ReplayFile {
    file: Mutex<File>,
    length: u64,
    hash: u128,
    // The file and its control metadata disappear before their shared grant.
    _credit: SourceArenaCredit,
}

impl ReplayFile {
    fn read_at(&self, offset: u64, block: &mut [u8]) -> io::Result<()> {
        let mut file = self.file.lock().map_err(|_| io::Error::other("replay spool cursor poisoned"))?;
        file.seek(SeekFrom::Start(offset))?;
        file.read_exact(block)
    }

    fn visit(&self, mut consume: impl FnMut(&[u8]) -> io::Result<()>) -> io::Result<()> {
        let mut offset = 0;
        let mut block = [0; BLOCK];
        while offset < self.length {
            crate::daemon::control::checkpoint()?;
            let count = (self.length - offset).min(BLOCK as u64) as usize;
            self.read_at(offset, &mut block[..count])?;
            // Output may block or fail. Never hold the shared cursor then.
            consume(&block[..count])?;
            offset += count as u64;
        }
        Ok(())
    }
}

impl Verified {
    pub(crate) fn length(&self) -> u64 {
        match &self.0 {
            VerifiedBacking::Single(sealed) => sealed.length,
            VerifiedBacking::Replay(sealed) => sealed.length,
        }
    }
    pub(crate) fn hash(&self) -> u128 {
        match &self.0 {
            VerifiedBacking::Single(sealed) => sealed.hash,
            VerifiedBacking::Replay(sealed) => sealed.hash,
        }
    }

    /// Convert only a genuinely sealed producer stream. The caller must
    /// already enforce the aggregate retained disk bound. This reserves the
    /// shared control allocation and adopts the same private, unlinked file.
    pub(crate) fn into_replayable(self, work: &dyn SourceArenaWork) -> Result<Self, (Self, io::Error)> {
        let VerifiedBacking::Single(sealed) = self.0 else { return Ok(self); };
        let credit = match work.reserve(std::mem::size_of::<ReplayFile>() + 2 * std::mem::size_of::<usize>()) {
            Ok(credit) => credit,
            Err(error) => return Err((Self(VerifiedBacking::Single(sealed)), error)),
        };
        Ok(Self(VerifiedBacking::Replay(Arc::new(ReplayFile {
            file: Mutex::new(sealed.file),
            length: sealed.length,
            hash: sealed.hash,
            _credit: credit,
        }))))
    }

    pub(crate) fn replay_alias(&self) -> Option<Self> {
        match &self.0 {
            VerifiedBacking::Single(_) => None,
            VerifiedBacking::Replay(sealed) => Some(Self(VerifiedBacking::Replay(Arc::clone(sealed)))),
        }
    }

    #[cfg(test)]
    pub(crate) fn same_replay_backing(&self, other: &Self) -> bool {
        match (&self.0, &other.0) {
            (VerifiedBacking::Replay(a), VerifiedBacking::Replay(b)) => Arc::ptr_eq(a, b),
            _ => false,
        }
    }

    /// Validate all replay bytes before accepting the new native attempt.
    pub(crate) fn check_replay(&self) -> io::Result<bool> {
        let VerifiedBacking::Replay(sealed) = &self.0 else {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "ordinary spool has no replay loan"));
        };
        crate::daemon::control::checkpoint()?;
        let length = sealed.file.lock().map_err(|_| io::Error::other("replay spool cursor poisoned"))?.metadata()?.len();
        if length != sealed.length {
            return crate::daemon::control::checkpoint().map(|()| false);
        }
        let mut hash = Xxh3::new();
        sealed.visit(|block| {
            hash.update(block);
            Ok(())
        })?;
        crate::daemon::control::checkpoint()?;
        Ok(hash.digest128() == sealed.hash)
    }

    /// Append one previously verified, producer-owned JSON array as part of
    /// the enclosing private ordered report. This never decodes row semantics.
    pub(crate) fn append_array_rows(self, output: &mut impl Write, first: &mut bool) -> io::Result<()> {
        let VerifiedBacking::Single(mut sealed) = self.0 else {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "retained report cannot compose staged arrays"));
        };
        let inner = sealed.length.checked_sub(2).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "short staged array"))?;
        let mut opening = [0u8;1];
        sealed.file.read_exact(&mut opening)?;
        if opening != [b'['] { return Err(io::Error::new(io::ErrorKind::InvalidData, "staged array lacks opening")); }
        if inner != 0 {
            if !*first { output.write_all(b",")?; }
            let mut reader = (&mut sealed.file).take(inner);
            let mut block = [0u8; BLOCK];
            while reader.limit() != 0 {
                crate::daemon::control::checkpoint()?;
                let count = reader.limit().min(BLOCK as u64) as usize;
                reader.read_exact(&mut block[..count])?;
                output.write_all(&block[..count])?;
            }
            *first = false;
        }
        let mut closing = [0u8;1];
        sealed.file.read_exact(&mut closing)?;
        if closing != [b']'] { return Err(io::Error::new(io::ErrorKind::InvalidData, "staged array lacks closing")); }
        Ok(())
    }
    /// Call only after the authoritative source and terminal checks. Failed
    /// output IO is returned as-is and cannot retry or publish a new prefix.
    pub(crate) fn publish(self, output: &mut impl Write) -> io::Result<()> {
        let sealed = match self.0 {
            VerifiedBacking::Single(sealed) => sealed,
            VerifiedBacking::Replay(sealed) => {
                sealed.visit(|bytes| output.write_all(bytes))?;
                return output.flush();
            }
        };
        let mut reader = sealed.file.take(sealed.length);
        let mut block = [0u8; BLOCK];
        while reader.limit() != 0 {
            crate::daemon::control::checkpoint()?;
            let count = reader.limit().min(BLOCK as u64) as usize;
            reader.read_exact(&mut block[..count])?;
            output.write_all(&block[..count])?;
        }
        output.flush()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn replayed_spool_reads_share_exact_sealed_file_and_recover_after_output_failure() {
        let root = crate::test_scratch::dir("selected-report-replay-spool");
        let expected = "long private report line\n".repeat(BLOCK);
        let mut stage = Stage::new(&root).unwrap();
        stage.write_all(expected.as_bytes()).unwrap();
        let (output, _) = stage.seal().unwrap().validate(|reader| io::copy(reader, &mut io::sink())).unwrap();
        assert!(output.replay_alias().is_none());
        let host = crate::runner_host::BuildHost::default();
        let replay = output.into_replayable(host.source_arena_work()).map_err(|(_, error)| error).unwrap();
        assert!(replay.check_replay().unwrap());
        let first = replay.replay_alias().unwrap();
        let second = replay.replay_alias().unwrap();

        struct Broken;
        impl Write for Broken {
            fn write(&mut self, _: &[u8]) -> io::Result<usize> { Err(io::ErrorKind::BrokenPipe.into()) }
            fn flush(&mut self) -> io::Result<()> { Ok(()) }
        }
        assert_eq!(replay.replay_alias().unwrap().publish(&mut Broken).unwrap_err().kind(), io::ErrorKind::BrokenPipe);
        std::thread::scope(|scope| {
            let other = scope.spawn(move || {
                let mut bytes = Vec::new();
                first.publish(&mut bytes).unwrap();
                bytes
            });
            let mut bytes = Vec::new();
            second.publish(&mut bytes).unwrap();
            assert_eq!(bytes, expected.as_bytes());
            assert_eq!(other.join().unwrap(), expected.as_bytes());
        });
        let VerifiedBacking::Replay(sealed) = &replay.0 else { panic!("actual replay owner") };
        {
            let mut file = sealed.file.lock().unwrap();
            file.rewind().unwrap();
            file.write_all(b"X").unwrap();
        }
        assert!(!replay.check_replay().unwrap(), "equal-size backing change is a cold miss");
        sealed.file.lock().unwrap().set_len(1).unwrap();
        assert!(!replay.check_replay().unwrap(), "backing extent change is a cold miss");
        let _scope = crate::daemon::control::bind_with_deadline(
            crate::daemon::control::Cancellation::default(),
            std::time::Instant::now(),
        );
        assert!(replay.check_replay().is_err(), "cancellation is an operational error");
        drop(replay);
        assert_eq!(std::fs::read_dir(&root).unwrap().count(), 0);
    }

    #[test]
    fn selected_report_spool_never_returns_a_publishable_prefix_after_an_error() {
        let root = crate::test_scratch::dir("selected-report-spool");
        let mut stage = Stage::new(&root).unwrap();
        stage.limit = 8;
        stage.write_all(b"prefix").unwrap();
        assert_eq!(stage.write_all(b"tail").unwrap_err().kind(), io::ErrorKind::OutOfMemory);
        assert!(stage.seal().is_err());

        let mut stage = Stage::new(&root).unwrap();
        stage.write_all(b"valid").unwrap();
        stage.file.seek(SeekFrom::Start(0)).unwrap();
        stage.file.write_all(b"wrong").unwrap();
        assert!(stage.seal().is_err());

        let mut stage = Stage::new(&root).unwrap();
        stage.write_all(b"prefix").unwrap();
        assert!(stage.seal().unwrap().validate(|_| Ok(())).is_err());

        let mut stage = Stage::new(&root).unwrap();
        stage.write_all(b"whole checked report
").unwrap();
        let (output, count) = stage.seal().unwrap().validate(|reader| io::copy(reader, &mut io::sink())).unwrap();
        assert_eq!(output.length(), count);
        assert_eq!(output.hash(), xxhash_rust::xxh3::xxh3_128(b"whole checked report
"));
        let mut published = Vec::new();
        output.publish(&mut published).unwrap();
        assert_eq!(published, b"whole checked report
");
        assert_eq!(std::fs::read_dir(&root).unwrap().count(), 0);
    }
}
