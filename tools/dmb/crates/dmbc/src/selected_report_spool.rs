//! Resource-only staging for an already-judged selected Analyze report.
//! No source/producer/ALLOW authority can be constructed by these file helpers.
use std::{
    fs::File,
    io::{self, Read, Seek, SeekFrom, Write},
    path::Path,
};
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
        Ok((Verified(self), data))
    }
}

pub(crate) struct Verified(Sealed);
impl Verified {
    pub(crate) fn length(&self) -> u64 { self.0.length }
    pub(crate) fn hash(&self) -> u128 { self.0.hash }
    /// Append one previously verified, producer-owned JSON array as part of
    /// the enclosing private ordered report. This never decodes row semantics.
    #[cfg(test)]
    pub(crate) fn append_array_rows(mut self, output: &mut impl Write, first: &mut bool) -> io::Result<()> {
        let inner = self.0.length.checked_sub(2).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "short staged array"))?;
        let mut opening = [0u8;1];
        self.0.file.read_exact(&mut opening)?;
        if opening != [b'['] { return Err(io::Error::new(io::ErrorKind::InvalidData, "staged array lacks opening")); }
        if inner != 0 {
            if !*first { output.write_all(b",")?; }
            let mut reader = (&mut self.0.file).take(inner);
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
        self.0.file.read_exact(&mut closing)?;
        if closing != [b']'] { return Err(io::Error::new(io::ErrorKind::InvalidData, "staged array lacks closing")); }
        Ok(())
    }
    /// Call only after the authoritative source and terminal checks. Failed
    /// output IO is returned as-is and cannot retry or publish a new prefix.
    pub(crate) fn publish(self, output: &mut impl Write) -> io::Result<()> {
        let mut reader = self.0.file.take(self.0.length);
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
