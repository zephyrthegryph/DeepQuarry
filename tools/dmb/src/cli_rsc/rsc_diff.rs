//! Exact live filename/kind/payload comparison through the shared lossless decoder.
use super::*;
use byond_dmb::rsc::read_entry_with_limit;
use serde::Serialize;
const ENTRY_LIMIT: usize = 32 * 1024 * 1024;
use std::{
    collections::BTreeMap,
    io::{Read, Seek, SeekFrom},
};
#[derive(Serialize)]
struct Report {
    schema_version: u32,
    snapshot_id: String,
    complete: bool,
    expected_resources: usize,
    actual_resources: usize,
    differences: usize,
    unknown_wrappers: usize,
    examples: Vec<String>,
}
struct Row {
    offset: u64,
    kind: u8,
    bytes: usize,
}
fn index(reader: &mut (impl Read + Seek)) -> io::Result<(BTreeMap<Vec<u8>, Row>, usize)> {
    let mut rows = BTreeMap::new();
    let mut unknown = 0;
    let mut count = 0;
    let mut name_bytes = 0usize;
    loop {
        let offset = reader.stream_position()?;
        let Some(entry) = read_entry_with_limit(reader, ENTRY_LIMIT)? else {
            break;
        };
        count += 1;
        if count > 100_000 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "RSC comparison entry limit exceeded",
            ));
        }
        match entry {
            Entry::Named(resource) => {
                if resource.name.len() > 65_536
                    || resource.declared_size as usize != resource.data.len()
                {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "invalid named RSC comparison record",
                    ));
                }
                name_bytes += resource.name.len();
                if name_bytes > 8 * 1024 * 1024 {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "RSC filename roster exceeds comparison limit",
                    ));
                }
                let row = Row {
                    offset,
                    kind: resource.kind,
                    bytes: resource.data.len(),
                };
                if rows.insert(resource.name, row).is_some() {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "duplicate live RSC filename",
                    ));
                }
            }
            Entry::Opaque { wrapper: 0, .. } => {}
            Entry::Opaque { .. } => unknown += 1,
        }
    }
    Ok((rows, unknown))
}
fn compare(
    expected: &mut (impl Read + Seek),
    actual: &mut (impl Read + Seek),
    snapshot: &str,
) -> io::Result<Report> {
    let (left, lu) = index(expected)?;
    let (right, ru) = index(actual)?;
    let mut report = Report {
        schema_version: 1,
        snapshot_id: snapshot.into(),
        complete: lu + ru == 0,
        expected_resources: left.len(),
        actual_resources: right.len(),
        differences: 0,
        unknown_wrappers: lu + ru,
        examples: Vec::new(),
    };
    let mut difference = |kind: &str, name: &[u8]| {
        report.differences += 1;
        if report.examples.len() < 20 {
            report
                .examples
                .push(format!("{kind}: {}", String::from_utf8_lossy(name)));
        }
    };
    for (name, row) in &left {
        let Some(other) = right.get(name) else {
            difference("missing", name);
            continue;
        };
        if row.kind != other.kind {
            difference("kind", name);
            continue;
        }
        if row.bytes != other.bytes {
            difference("payload length", name);
            continue;
        }
        expected.seek(SeekFrom::Start(row.offset))?;
        actual.seek(SeekFrom::Start(other.offset))?;
        match (
            read_entry_with_limit(expected, ENTRY_LIMIT)?,
            read_entry_with_limit(actual, ENTRY_LIMIT)?,
        ) {
            (Some(Entry::Named(a)), Some(Entry::Named(b)))
                if a.name == *name
                    && b.name == *name
                    && a.kind == row.kind
                    && b.kind == other.kind
                    && a.data.len() == row.bytes
                    && b.data.len() == other.bytes =>
            {
                if a.data != b.data {
                    difference("payload", name);
                }
            }
            _ => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "RSC changed during comparison",
                ))
            }
        }
    }
    for name in right.keys() {
        if !left.contains_key(name) {
            difference("extra", name);
        }
    }
    Ok(report)
}
pub(super) fn execute(args: &[String]) -> io::Result<()> {
    let mut expected = BufReader::new(File::open(&args[2])?);
    let mut actual = BufReader::new(File::open(&args[3])?);
    let report = compare(&mut expected, &mut actual, &args[5])?;
    let mut output = BufWriter::new(File::create(&args[4])?);
    serde_json::to_writer_pretty(&mut output, &report)?;
    output.flush()
}
#[cfg(test)]
mod tests {
    use super::*;
    use byond_dmb::rsc::NamedResource;
    use std::io::Cursor;
    fn archive(rows: &[(&str, &[u8])]) -> Cursor<Vec<u8>> {
        let mut bytes = Vec::new();
        for (name, data) in rows {
            let row = NamedResource {
                kind: 1,
                id: 0,
                timestamp: 0,
                source_timestamp: 0,
                declared_size: data.len() as u32,
                name: name.as_bytes().to_vec(),
                data: data.to_vec(),
            };
            write_entry(&mut bytes, &Entry::Named(row)).unwrap();
        }
        Cursor::new(bytes)
    }
    #[test]
    fn caller_limit_rejects_before_payload_read_and_default_decoder_is_unchanged() {
        let bytes = archive(&[("a", b"payload")]).into_inner();
        let mut limited = Cursor::new(bytes.clone());
        assert!(read_entry_with_limit(&mut limited, 4).is_err());
        assert_eq!(
            limited.position(),
            4,
            "reject at framing before allocating/reading payload"
        );
        assert!(matches!(
            read_entry(&mut Cursor::new(bytes)).unwrap(),
            Some(Entry::Named(_))
        ));
        let mut truncated = Cursor::new(vec![1, 0]);
        assert_eq!(
            read_entry_with_limit(&mut truncated, 4).unwrap_err().kind(),
            io::ErrorKind::UnexpectedEof
        );
    }
    #[test]
    fn compares_payloads_by_exact_filename_instead_of_archive_order() {
        let mut a = archive(&[("a", b"first"), ("b", b"second")]);
        let mut b = archive(&[("b", b"second"), ("a", b"first")]);
        let report = compare(&mut a, &mut b, "fixture").unwrap();
        assert!(report.complete);
        assert_eq!(report.differences, 0);
        let mut changed = archive(&[("b", b"seconD"), ("a", b"first")]);
        a.set_position(0);
        assert_eq!(
            compare(&mut a, &mut changed, "fixture")
                .unwrap()
                .differences,
            1
        );
    }
    #[test]
    fn duplicate_truncated_and_unknown_records_do_not_claim_complete_parity() {
        assert!(index(&mut archive(&[("a", b"x"), ("a", b"x")])).is_err());
        let mut truncated = archive(&[("a", b"x")]).into_inner();
        truncated.pop();
        assert!(index(&mut Cursor::new(truncated)).is_err());
        let mut bytes = Vec::new();
        write_entry(
            &mut bytes,
            &Entry::Opaque {
                wrapper: 2,
                payload: vec![],
            },
        )
        .unwrap();
        let report = compare(&mut archive(&[]), &mut Cursor::new(bytes), "fixture").unwrap();
        assert!(!report.complete);
        assert_eq!(report.unknown_wrappers, 1);
    }
}
