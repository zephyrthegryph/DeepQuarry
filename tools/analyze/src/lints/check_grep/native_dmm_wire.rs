use super::{Line, StaticFileData};
use crate::{
    captured_generator_budget::{Budget, MAX_ROWS},
    lint::{AllowUse, Run, Site},
};
use std::io::{self, Read, Write};

fn invalid(message: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

fn quota(message: String) -> io::Error {
    io::Error::new(io::ErrorKind::OutOfMemory, message)
}

fn number(out: &mut dyn Write, value: usize) -> io::Result<()> {
    out.write_all(&u32::try_from(value).map_err(|_| invalid("static fragment field exceeds wire width"))?.to_le_bytes())
}

fn take<const N: usize>(input: &mut dyn Read) -> io::Result<[u8; N]> {
    let mut bytes = [0; N];
    input.read_exact(&mut bytes)?;
    Ok(bytes)
}

fn read_number(input: &mut dyn Read) -> io::Result<u32> {
    Ok(u32::from_le_bytes(take(input)?))
}

fn text(out: &mut dyn Write, value: &str) -> io::Result<()> {
    number(out, value.len())?;
    out.write_all(value.as_bytes())
}

fn read_text(input: &mut dyn Read, budget: &Budget) -> io::Result<String> {
    let len = read_number(input)? as usize;
    if len == 0 { return Ok(String::new()); }
    let layout = std::alloc::Layout::array::<u8>(len).map_err(|_| io::ErrorKind::OutOfMemory)?;
    budget.charge(layout.size()).map_err(quota)?;
    // SAFETY: one exact nonzero funded Global allocation. Vec is initialized
    // before read_exact and owns the unchanged capacity on every path.
    let pointer = std::ptr::NonNull::new(unsafe { std::alloc::alloc(layout) })
        .ok_or(io::ErrorKind::OutOfMemory)?;
    let mut bytes = unsafe { Vec::from_raw_parts(pointer.as_ptr(), 0, len) };
    bytes.resize(len, 0);
    input.read_exact(&mut bytes)?;
    String::from_utf8(bytes).map_err(|_| invalid("static fragment spelling is not UTF-8"))
}

fn read_rows<T>(
    input: &mut dyn Read, budget: &Budget, poll: &dyn Fn() -> io::Result<()>,
    mut read: impl FnMut(&mut dyn Read) -> io::Result<T>,
) -> io::Result<Vec<T>> {
    let count = read_number(input)? as usize;
    if count > MAX_ROWS { return Err(invalid("static fragment has too many rows")); }
    let mut rows = Vec::new();
    for _ in 0..count {
        poll()?;
        if !budget.row(&mut rows) { return Err(io::ErrorKind::OutOfMemory.into()); }
        rows.push(read(input)?);
    }
    Ok(rows)
}

impl StaticFileData {
    /// Writes producer DATA only. Relative spelling is supplied by the exact
    /// ordered capture and is checked on both ends; it need not be repeated.
    pub fn write_dmm_fragment(&self, relative: &str, out: &mut dyn Write) -> io::Result<()> {
        number(out, self.run.sites.len())?;
        for site in &self.run.sites {
            if site.rel != relative { return Err(invalid("static fragment site belongs to another file")); }
            text(out, &site.rule)?;
            out.write_all(&site.line.to_le_bytes())?;
            text(out, &site.msg)?;
            text(out, &site.key)?;
            text(out, &site.ident)?;
        }
        number(out, self.run.notes.len())?;
        for note in &self.run.notes { text(out, note)?; }
        number(out, self.allow_used.len())?;
        for used in &self.allow_used {
            if used.rel != relative { return Err(invalid("static fragment ALLOW belongs to another file")); }
            out.write_all(&used.line.to_le_bytes())?;
            text(out, &used.name)?;
            text(out, &used.code)?;
        }
        number(out, self.lines.len())?;
        for line in &self.lines {
            if line.relative != relative { return Err(invalid("static fragment source line belongs to another file")); }
            out.write_all(&line.line.to_le_bytes())?;
            text(out, &line.text)?;
        }
        match self.allow_digest {
            Some(digest) => { out.write_all(&[1])?; out.write_all(&digest) }
            None => out.write_all(&[0]),
        }
    }

    /// Reads one fragment after its private host has verified source identity.
    /// Decoding a fragment does not make it a source witness or complete scan.
    pub fn read_dmm_fragment(
        relative: &str, input: &mut dyn Read, budget: &Budget,
        poll: &dyn Fn() -> io::Result<()>,
    ) -> io::Result<Self> {
        let own_relative = || -> io::Result<String> {
            let upper = relative.len().checked_mul(4).and_then(|bytes| bytes.checked_add(64))
                .ok_or(io::ErrorKind::OutOfMemory)?;
            budget.charge(upper).map_err(quota)?;
            Ok(relative.to_owned())
        };
        let sites = read_rows(input, budget, poll, |input| {
            Ok(Site {
                rule: read_text(input, budget)?, rel: own_relative()?, line: read_number(input)?,
                msg: read_text(input, budget)?, key: read_text(input, budget)?, ident: read_text(input, budget)?,
            })
        })?;
        let notes = read_rows(input, budget, poll, |input| read_text(input, budget))?;
        let allow_used = read_rows(input, budget, poll, |input| {
            Ok(AllowUse {
                rel: own_relative()?, line: read_number(input)?,
                name: read_text(input, budget)?, code: read_text(input, budget)?,
            })
        })?;
        let lines = read_rows(input, budget, poll, |input| {
            Ok(Line { relative: own_relative()?, line: read_number(input)?, text: read_text(input, budget)? })
        })?;
        let allow_digest = match take::<1>(input)?[0] {
            0 if allow_used.is_empty() => None,
            1 if !allow_used.is_empty() => Some(take(input)?),
            _ => return Err(invalid("static fragment ALLOW digest differs from its rows")),
        };
        Ok(Self { run: Run { sites, notes }, allow_used, lines, allow_digest })
    }
}
