//! Indexed serialization of edits confined to existing DMB list records.
//! The encrypted string prefix and all unchanged tables are copied verbatim.
use byond_dmb::dmb::Dmb;
use std::{
    io::{self},
    ops::Range,
};

pub struct ListImage {
    image: Vec<u8>,
    spans: Vec<Range<usize>>,
    tables: Dmb,
    wide: bool,
}

fn tables(d: &Dmb) -> Dmb {
    Dmb {
        header: d.header.clone(),
        dimensions: d.dimensions,
        grid: d.grid.clone(),
        classes: d.classes.clone(),
        mobs: d.mobs.clone(),
        strings: d.strings.clone(),
        lists: Default::default(),
        procs: d.procs.clone(),
        variables: d.variables.clone(),
        variable_footer: d.variable_footer,
        proc_references: d.proc_references.clone(),
        instances: d.instances.clone(),
        map_objects: d.map_objects.clone(),
        world: d.world.clone(),
        resources: d.resources.clone(),
    }
}
fn same_tables(a: &Dmb, b: &Dmb) -> bool {
    a.header == b.header
        && a.dimensions == b.dimensions
        && a.grid == b.grid
        && a.classes == b.classes
        && a.mobs == b.mobs
        && a.strings == b.strings
        && a.procs == b.procs
        && a.variables == b.variables
        && a.variable_footer == b.variable_footer
        && a.proc_references == b.proc_references
        && a.instances == b.instances
        && a.map_objects == b.map_objects
        && a.world == b.world
        && a.resources == b.resources
}
impl ListImage {
    /// Capture decoder-provided spans and verify their correspondence before
    /// trusting them as an output index.
    pub fn capture(image: Vec<u8>, dmb: &Dmb, spans: Vec<Range<usize>>) -> io::Result<Self> {
        if spans.len() != dmb.lists.len() {
            return Err(io::Error::other("list index count mismatch"));
        }
        let wide = dmb.header.flags & 0x4000_0000 != 0;
        let mut end = 0;
        for (span, words) in spans.iter().zip(&dmb.lists) {
            if span.start < end || image.get(span.clone()) != Some(encode(words, wide)?.as_slice())
            {
                return Err(io::Error::other("list index does not match image"));
            }
            end = span.end;
        }
        Ok(Self {
            image,
            spans,
            tables: tables(dmb),
            wide,
        })
    }
    /// Internal compiler path: the same decoded world and exact spans already
    /// came from the format reader/writer and its reference-validation barrier.
    /// Unlike capture, this does not encode every unchanged bytecode list.
    #[doc(hidden)]
    pub fn from_verified_serialization(
        image: Vec<u8>,
        dmb: &Dmb,
        spans: Vec<Range<usize>>,
    ) -> io::Result<Self> {
        let wide = dmb.header.flags & 0x4000_0000 != 0;
        if spans.len() != dmb.lists.len() {
            return Err(io::Error::other("list count mismatch"));
        }
        let mut end = 0;
        for (span, words) in spans.iter().zip(&dmb.lists) {
            if span.start < end
                || span.end > image.len()
                || span.end - span.start != 2 + words.len() * if wide { 4 } else { 2 }
            {
                return Err(io::Error::other("invalid verified list spans"));
            }
            end = span.end;
        }
        Ok(Self {
            image,
            spans,
            tables: tables(dmb),
            wide,
        })
    }
    pub fn bytes(&self) -> &[u8] {
        &self.image
    }
    pub fn spans(&self) -> &[Range<usize>] {
        &self.spans
    }
    /// Replace only an image just produced by this index's accepted serializer.
    pub fn rebase(&mut self, image: Vec<u8>, spans: Vec<Range<usize>>) {
        self.image = image;
        self.spans = spans;
    }
    pub fn resident_bytes(&self) -> usize {
        self.image.capacity()
            + self.spans.capacity() * std::mem::size_of::<Range<usize>>()
            + self
                .tables
                .strings
                .iter()
                .map(|s| s.data.capacity() + std::mem::size_of_val(s))
                .sum::<usize>()
            + self.tables.classes.capacity() * std::mem::size_of::<byond_dmb::dmb::Class>()
            + self.tables.procs.capacity() * std::mem::size_of::<byond_dmb::dmb::Proc>()
            + self.tables.variables.capacity() * std::mem::size_of::<byond_dmb::dmb::Variable>()
            + self.tables.grid.capacity() * std::mem::size_of::<byond_dmb::dmb::GridRun>()
            + self.tables.mobs.capacity() * std::mem::size_of::<byond_dmb::dmb::MobType>()
            + self.tables.instances.capacity() * std::mem::size_of::<byond_dmb::dmb::Instance>()
            + self.tables.map_objects.capacity() * std::mem::size_of::<byond_dmb::dmb::MapObject>()
    }

    /// None means a structural/table change requires the complete serializer.
    /// Length changes are safe: tables after the strings have no absolute offsets.
    pub fn serialize(&self, dmb: &Dmb) -> io::Result<Option<Vec<u8>>> {
        self.serialize_changed(dmb, &(0..dmb.lists.len() as u32).collect::<Vec<_>>())
    }
    /// Updated spans for an accepted splice; only list lengths are inspected.
    pub fn updated_spans(&self, dmb: &Dmb) -> io::Result<Vec<Range<usize>>> {
        if dmb.lists.len() != self.spans.len() {
            return Err(io::Error::other("list count changed"));
        }
        let mut result = Vec::with_capacity(self.spans.len());
        let mut shift = 0i64;
        for (old, words) in self.spans.iter().zip(&dmb.lists) {
            let length = 2 + words.len() * if self.wide { 4 } else { 2 };
            let start = usize::try_from(old.start as i64 + shift)
                .map_err(|_| io::Error::other("list offset overflow"))?;
            result.push(start..start + length);
            shift += length as i64 - (old.end - old.start) as i64;
        }
        Ok(result)
    }

    /// The compiler mutation ledger must include every changed list. This avoids
    /// touching any unchanged bytecode list during ordinary body-only emission.
    pub fn serialize_changed(&self, dmb: &Dmb, changed: &[u32]) -> io::Result<Option<Vec<u8>>> {
        if dmb.lists.len() != self.spans.len() || !same_tables(&self.tables, dmb) {
            return Ok(None);
        }
        dmb.validate_changed_lists(changed)?;
        let mut edits = Vec::new();
        for id in changed
            .iter()
            .copied()
            .collect::<std::collections::BTreeSet<_>>()
        {
            let span = self
                .spans
                .get(id as usize)
                .ok_or_else(|| io::Error::other("changed list outside index"))?;
            let words = &dmb.lists[id as usize];
            let bytes = encode(words, self.wide)?;
            if self.image[span.clone()] != bytes {
                edits.push((span, bytes));
            }
        }
        let mut output = Vec::with_capacity(self.image.len());
        let mut cursor = 0;
        for (span, bytes) in edits {
            output.extend_from_slice(&self.image[cursor..span.start]);
            output.extend_from_slice(&bytes);
            cursor = span.end;
        }
        output.extend_from_slice(&self.image[cursor..]);
        Ok(Some(output))
    }
}
fn encode(words: &[u32], wide: bool) -> io::Result<Vec<u8>> {
    let count =
        u16::try_from(words.len()).map_err(|_| io::Error::other("list exceeds u16 count"))?;
    let mut bytes = Vec::with_capacity(2 + words.len() * if wide { 4 } else { 2 });
    bytes.extend_from_slice(&count.to_le_bytes());
    for &word in words {
        if wide {
            bytes.extend_from_slice(&word.to_le_bytes());
        } else {
            bytes.extend_from_slice(
                &u16::try_from(word)
                    .map_err(|_| io::Error::other("list word exceeds object width"))?
                    .to_le_bytes(),
            );
        }
    }
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn code_growth_and_shrink_equal_full_writer_and_tables_fall_back() {
        let bytes = include_bytes!("../../../fixtures/native_template.bin").to_vec();
        let (mut dmb, spans) = Dmb::from_bytes_with_list_spans(&bytes).unwrap();
        let indexed = ListImage::capture(bytes, &dmb, spans).unwrap();
        let code = dmb
            .procs
            .iter()
            .find_map(|p| {
                let id = p.code_locals_args[0] as usize;
                dmb.lists.get(id).filter(|w| !w.is_empty()).map(|_| id)
            })
            .unwrap();
        let old = dmb.lists[code].clone();
        dmb.lists[code].extend_from_slice(&[0, 0]);
        assert_eq!(
            indexed.serialize(&dmb).unwrap().unwrap(),
            dmb.to_bytes().unwrap()
        );
        dmb.lists[code] = old;
        assert_eq!(
            indexed.serialize(&dmb).unwrap().unwrap(),
            dmb.to_bytes().unwrap()
        );
        dmb.strings[0].data.push(b'x');
        assert!(indexed.serialize(&dmb).unwrap().is_none());
    }
}
