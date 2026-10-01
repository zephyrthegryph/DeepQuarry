use crate::load_dmb;
use byond_dmb::rsc::{read_entry, write_entry, Entry};
use std::fs::File;
use std::io::{self, BufReader, BufWriter, Write};

pub(crate) fn execute(name: &str, args: &[String]) -> io::Result<()> {
    match name {
        "pair-info" => pair_info(args),
        "rsc-info" => rsc_info(args),
        "rsc-kind-audit" => rsc_kind_audit(args),
        "rsc-id-audit" => rsc_id_audit(args),
        "rsc-copy" => rsc_copy(args),
        _ => Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("unknown command: {name}"),
        )),
    }
}

fn pair_info(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut reader = BufReader::new(File::open(&args[3])?);
    let archive = byond_dmb::rsc::read_all(&mut reader)?;
    let missing = dmb.missing_resources(&archive);
    println!(
        "dmb_resources={} rsc_entries={} missing={}",
        dmb.resources.len(),
        archive.len(),
        missing.len()
    );
    if !missing.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "DMB resource references are missing from RSC",
        ));
    }
    Ok(())
}

fn rsc_info(args: &[String]) -> io::Result<()> {
    let mut reader = BufReader::new(File::open(&args[2])?);
    let (mut named, mut opaque, mut mismatched) = (0usize, 0usize, 0usize);
    let mut recovered_deleted = 0usize;
    while let Some(entry) = read_entry(&mut reader)? {
        recovered_deleted += usize::from(entry.deleted_named_resource().is_some());
        match entry {
            Entry::Named(resource) => {
                named += 1;
                mismatched += usize::from(resource.declared_size as usize != resource.data.len());
            }
            Entry::Opaque { .. } => opaque += 1,
        }
    }
    println!("named={named} opaque={opaque} recovered_deleted={recovered_deleted} declared_size_mismatches={mismatched}");
    Ok(())
}

fn rsc_kind_audit(args: &[String]) -> io::Result<()> {
    let mut reader = BufReader::new(File::open(&args[2])?);
    let mut kinds = std::collections::BTreeMap::<u8, (usize, String)>::new();
    while let Some(entry) = read_entry(&mut reader)? {
        if let Entry::Named(resource) = entry {
            kinds
                .entry(resource.kind)
                .and_modify(|v| v.0 += 1)
                .or_insert_with(|| (1, String::from_utf8_lossy(&resource.name).to_string()));
        }
    }
    println!("{kinds:?}");
    Ok(())
}

fn rsc_id_audit(args: &[String]) -> io::Result<()> {
    let mut reader = BufReader::new(File::open(&args[2])?);
    let (mut matched, mut mismatch_count, mut mismatched) = (0usize, 0usize, Vec::new());
    while let Some(entry) = read_entry(&mut reader)? {
        if let Entry::Named(resource) = entry {
            let actual = resource.content_id()?;
            if actual == resource.id {
                matched += 1;
            } else {
                mismatch_count += 1;
                if mismatched.len() < 16 {
                    mismatched.push((
                        String::from_utf8_lossy(&resource.name).to_string(),
                        resource.id,
                        actual,
                    ));
                }
            }
        }
    }
    println!("matched={matched} mismatch_count={mismatch_count} examples={mismatched:?}");
    Ok(())
}

fn rsc_copy(args: &[String]) -> io::Result<()> {
    let mut reader = BufReader::new(File::open(&args[2])?);
    let mut writer = BufWriter::new(File::create(&args[3])?);
    while let Some(entry) = read_entry(&mut reader)? {
        write_entry(&mut writer, &entry)?;
    }
    writer.flush()?;
    Ok(())
}
