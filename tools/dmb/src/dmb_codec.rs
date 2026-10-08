use super::*;

pub(super) fn invalid(message: &'static str) -> io::Error {
    io::Error::new(ErrorKind::InvalidData, message)
}

pub(super) struct Reader<'a> {
    pub(super) data: &'a [u8],
    pub(super) at: usize,
    pub(super) object_size: usize,
    pub(super) compatibility_version: u16,
}

impl<'a> Reader<'a> {
    pub(super) fn take(&mut self, len: usize) -> io::Result<&'a [u8]> {
        let end = self
            .at
            .checked_add(len)
            .ok_or_else(|| invalid("offset overflow"))?;
        let bytes = self.data.get(self.at..end).ok_or_else(|| {
            io::Error::new(
                ErrorKind::InvalidData,
                format!("truncated DMB at byte {} reading {len} bytes", self.at),
            )
        })?;
        self.at = end;
        Ok(bytes)
    }
    pub(super) fn u8(&mut self) -> io::Result<u8> {
        Ok(self.take(1)?[0])
    }
    pub(super) fn u16(&mut self) -> io::Result<u16> {
        Ok(u16::from_le_bytes(self.take(2)?.try_into().unwrap()))
    }
    pub(super) fn u32(&mut self) -> io::Result<u32> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }
    pub(super) fn object(&mut self) -> io::Result<u32> {
        if self.object_size == 2 {
            Ok(u32::from(self.u16()?))
        } else {
            self.u32()
        }
    }
    pub(super) fn f32_bits(&mut self) -> io::Result<u32> {
        self.u32()
    }
    pub(super) fn line(&mut self) -> io::Result<Vec<u8>> {
        let rest = &self.data[self.at..];
        let len = rest
            .iter()
            .position(|&x| x == b'\n')
            .ok_or_else(|| invalid("missing DMB header newline"))?
            + 1;
        Ok(self.take(len)?.to_vec())
    }
    pub(super) fn table<T>(
        &mut self,
        mut read: impl FnMut(&mut Self) -> io::Result<T>,
    ) -> io::Result<Vec<T>> {
        let count = self.object()? as usize;
        let mut entries = Vec::new();
        for _ in 0..count {
            entries.push(read(self)?);
        }
        Ok(entries)
    }
}

pub(super) struct Writer {
    pub(super) bytes: Vec<u8>,
    pub(super) object_size: usize,
    pub(super) object_overflow: bool,
    pub(super) compatibility_version: u16,
}
impl Writer {
    pub(super) fn new(object_size: usize, compatibility_version: u16) -> Self {
        Self {
            bytes: Vec::new(),
            object_size,
            object_overflow: false,
            compatibility_version,
        }
    }
    pub(super) fn at(&self) -> usize {
        self.bytes.len()
    }
    pub(super) fn raw(&mut self, bytes: &[u8]) {
        self.bytes.extend_from_slice(bytes);
    }
    pub(super) fn u8(&mut self, value: u8) {
        self.bytes.push(value);
    }
    pub(super) fn u16(&mut self, value: u16) {
        self.raw(&value.to_le_bytes());
    }
    pub(super) fn u32(&mut self, value: u32) {
        self.raw(&value.to_le_bytes());
    }
    pub(super) fn object(&mut self, value: u32) {
        if self.object_size == 2 {
            if value > u16::MAX as u32 {
                self.object_overflow = true;
            }
            self.u16(value as u16);
        } else {
            self.u32(value);
        }
    }
    pub(super) fn table<T>(
        &mut self,
        items: &[T],
        mut write: impl FnMut(&mut Self, &T),
    ) -> io::Result<()> {
        let count = u32::try_from(items.len()).map_err(|_| invalid("table exceeds u32 count"))?;
        self.object(count);
        for item in items {
            write(self, item);
        }
        Ok(())
    }
}

pub(super) fn compatibility_version(line: &[u8]) -> io::Result<u16> {
    let text = std::str::from_utf8(line).map_err(|_| invalid("non-ASCII compatibility line"))?;
    let number = text
        .strip_prefix("min compatibility v")
        .and_then(|tail| tail.split_ascii_whitespace().next())
        .ok_or_else(|| invalid("unsupported compatibility header"))?;
    number
        .parse::<u16>()
        .map_err(|_| invalid("invalid compatibility version"))
}
