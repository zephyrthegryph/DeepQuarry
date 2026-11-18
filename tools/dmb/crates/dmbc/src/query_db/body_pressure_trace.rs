//! Byte-preserving buffering for existing BODY pressure diagnostics only.
//! A row owns one existing stderr lock; no heap, cache, sampling or admission.
use std::{fmt, io::{self, Write}};
const TRACE_BUFFER_BYTES: usize = 4096;

struct StackTraceWriter<'a, W: Write + ?Sized> {
    output: &'a mut W,
    bytes: [u8; TRACE_BUFFER_BYTES],
    used: usize,
    failed: Option<io::ErrorKind>,
    draining: bool,
}
impl<'a, W: Write + ?Sized> StackTraceWriter<'a, W> {
    fn new(output: &'a mut W) -> Self {
        Self { output, bytes: [0; TRACE_BUFFER_BYTES], used: 0, failed: None, draining: false }
    }
    fn drain(&mut self) -> io::Result<()> {
        if let Some(kind) = self.failed { return Err(kind.into()); }
        self.draining = true;
        let mut written = 0;
        while written < self.used {
            match self.output.write(&self.bytes[written..self.used]) {
                Ok(0) => {
                    self.used = 0;
                    self.draining = false;
                    self.failed = Some(io::ErrorKind::WriteZero);
                    return Err(io::ErrorKind::WriteZero.into());
                }
                Ok(count) => written += count,
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(error) => {
                    // The emitted prefix is never retried, even by Drop.
                    // This is best-effort tracing: discard the unwritten tail.
                    self.used = 0;
                    self.draining = false;
                    self.failed = Some(error.kind());
                    return Err(error);
                }
            }
        }
        self.used = 0;
        self.draining = false;
        Ok(())
    }
}
impl<W: Write + ?Sized> Write for StackTraceWriter<'_, W> {
    fn write(&mut self, input: &[u8]) -> io::Result<usize> {
        if let Some(kind) = self.failed { return Err(kind.into()); }
        if input.is_empty() { return Ok(0); }
        // Flush ONLY before accepting current input. If draining fails, no
        // bytes from this write were consumed; Write's partial contract holds.
        if self.used == TRACE_BUFFER_BYTES { self.drain()?; }
        let count = input.len().min(TRACE_BUFFER_BYTES - self.used);
        self.bytes[self.used..self.used + count].copy_from_slice(&input[..count]);
        self.used += count;
        Ok(count)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.drain()?;
        match self.output.flush() {
            Ok(()) => Ok(()),
            Err(error) => { self.failed = Some(error.kind()); Err(error) }
        }
    }
}
// Preserve the prefix accepted before a formatter error or panic. A sink
// failure already discarded its tail; a panic inside an in-flight sink write
// has unknown progress and must never be retried by destructor cleanup.
impl<W: Write + ?Sized> Drop for StackTraceWriter<'_, W> {
    fn drop(&mut self) {
        if self.failed.is_none() && !self.draining && self.used != 0 {
            let _ = self.drain();
        }
    }
}
pub(super) fn write_row(output: &mut (impl Write + ?Sized), row: fmt::Arguments<'_>) -> io::Result<()> {
    let mut buffered = StackTraceWriter::new(output);
    buffered.write_fmt(format_args!("{row}\n"))?;
    buffered.drain()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[derive(Default)]
    struct CountingWriter {
        bytes: Vec<u8>, writes: usize, flushes: usize,
        max_write: Option<usize>, interrupt_alternate: bool,
        fail_after: Option<usize>, zero_after: Option<usize>, fail_flush: bool,
    }
    impl Write for CountingWriter {
        fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
            self.writes += 1;
            if self.interrupt_alternate && self.writes % 2 == 1 { return Err(io::ErrorKind::Interrupted.into()); }
            if self.fail_after.is_some_and(|n| self.bytes.len() >= n) { return Err(io::ErrorKind::PermissionDenied.into()); }
            if self.zero_after.is_some_and(|n| self.bytes.len() >= n) { return Ok(0); }
            let count = bytes.len().min(self.max_write.unwrap_or(bytes.len()))
                .min(self.fail_after.map_or(usize::MAX, |n| n - self.bytes.len()))
                .min(self.zero_after.map_or(usize::MAX, |n| n - self.bytes.len()));
            self.bytes.extend_from_slice(&bytes[..count]);
            Ok(count)
        }
        fn flush(&mut self) -> io::Result<()> {
            self.flushes += 1;
            if self.fail_flush { Err(io::ErrorKind::BrokenPipe.into()) } else { Ok(()) }
        }
    }
    struct Fragmented<'a>(&'a str);
    impl fmt::Display for Fragmented<'_> {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            for ch in self.0.chars() { write!(f, "{ch}")?; }
            Ok(())
        }
    }
    #[test]
    fn body_pressure_stack_buffer_preserves_every_formatted_byte_with_fewer_writes() {
        let text = "α🙂z".repeat(2300);
        let mut direct = CountingWriter::default();
        writeln!(&mut direct, "ORIGINAL_LIVE_SIGNATURE_RESERVATIONS key={:?} text={} count={}", (4, 97), Fragmented(&text), 2512).unwrap();
        let mut buffered = CountingWriter::default();
        write_row(&mut buffered, format_args!("ORIGINAL_LIVE_SIGNATURE_RESERVATIONS key={:?} text={} count={}", (4, 97), Fragmented(&text), 2512)).unwrap();
        assert_eq!(buffered.bytes, direct.bytes);
        assert!(buffered.writes < direct.writes);
        assert_eq!(buffered.writes, buffered.bytes.len().div_ceil(TRACE_BUFFER_BYTES));
        assert_eq!(buffered.flushes, 0);
        assert_eq!(TRACE_BUFFER_BYTES, 4096);
    }
    #[test]
    fn body_pressure_stack_buffer_keeps_exact_bytes_for_partial_and_interrupted_writes() {
        let text = "λ🙂x".repeat(1300);
        let expected = format!("row={} value={:?}\n", text, [1, 2, 3]);
        let mut writer = CountingWriter { max_write: Some(1), interrupt_alternate: true, ..Default::default() };
        write_row(&mut writer, format_args!("row={} value={:?}", text, [1, 2, 3])).unwrap();
        assert_eq!(writer.bytes, expected.as_bytes());
        assert_eq!(writer.writes, 2 * expected.len());
        assert_eq!(writer.flushes, 0);
    }
    #[test]
    fn body_pressure_stack_buffer_never_replays_prefix_after_write_or_flush_error() {
        let text = "abcdef".repeat(2400);
        let expected = format!("row={text}\n");
        for zero in [false, true] {
            let mut writer = CountingWriter { max_write: Some(1), fail_after: (!zero).then_some(73), zero_after: zero.then_some(73), ..Default::default() };
            let error = write_row(&mut writer, format_args!("row={text}")).unwrap_err();
            assert_eq!(error.kind(), if zero { io::ErrorKind::WriteZero } else { io::ErrorKind::PermissionDenied });
            assert_eq!(writer.bytes, expected.as_bytes()[..73]);
            assert_eq!(writer.writes, 74, "one failure, no destructor retry");
            assert_eq!(writer.flushes, 0);
        }
        // Like the original writeln!, completing a row never calls the
        // underlying writer's flush method (which could introduce an error).
        let mut writer = CountingWriter { fail_flush: true, ..Default::default() };
        write_row(&mut writer, format_args!("row={text}")).unwrap();
        assert_eq!(writer.bytes, expected.as_bytes());
        assert_eq!(writer.flushes, 0);
        struct BrokenFormat<'a> { prefix: &'a str, panic: bool }
        impl fmt::Display for BrokenFormat<'_> {
            fn fmt(&self, output: &mut fmt::Formatter<'_>) -> fmt::Result {
                write!(output, "{}", self.prefix)?;
                if self.panic { panic!("actual formatter panic after prefix"); }
                Err(fmt::Error)
            }
        }
        for panic in [false, true] {
            let mut direct = CountingWriter::default();
            let baseline = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let _ = writeln!(&mut direct, "row={}", BrokenFormat { prefix: &text, panic });
            }));
            let mut buffered = CountingWriter::default();
            let actual = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let _ = write_row(&mut buffered, format_args!("row={}", BrokenFormat { prefix: &text, panic }));
            }));
            assert!(baseline.is_err() && actual.is_err());
            assert_eq!(buffered.bytes, direct.bytes, "accepted formatter prefix is preserved exactly");
            assert_eq!(buffered.bytes, format!("row={text}").as_bytes());
            assert_eq!(buffered.flushes, 0);
        }
    }
}
