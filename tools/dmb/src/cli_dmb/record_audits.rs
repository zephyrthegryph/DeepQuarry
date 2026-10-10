//! Procedure flag and mob sight record audits.
use super::{io, load_dmb};
pub(super) fn proc_flags_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut flags = std::collections::BTreeMap::<u8, usize>::new();
    let mut extended = std::collections::BTreeMap::<(u32, u8), usize>::new();
    for proc in &dmb.procs {
        *flags.entry(proc.flags).or_default() += 1;
        if let Some(extra) = proc.extended_flags {
            *extended.entry(extra).or_default() += 1;
        }
    }
    println!("flags={flags:?} extended={extended:?}");
    Ok(())
}

pub(super) fn proc_source_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut groups = std::collections::BTreeMap::<(u8, u8), (usize, String)>::new();
    for proc in &dmb.procs {
        groups
            .entry((proc.source_kind, proc.source_parameter))
            .and_modify(|entry| entry.0 += 1)
            .or_insert_with(|| {
                (
                    1,
                    String::from_utf8_lossy(dmb.string(proc.strings[0]).unwrap_or_default())
                        .into_owned(),
                )
            });
    }
    for (code, (count, path)) in groups {
        println!("source={code:?} count={count} example={path}");
    }
    Ok(())
}

pub(super) fn proc_flag_context(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let target = u32::from_str_radix(args[3].trim_start_matches("0x"), 16)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid flag hex"))?;
    for (id, proc) in dmb
        .procs
        .iter()
        .enumerate()
        .filter(|(_, proc)| proc.effective_flags() & target == target)
        .take(30)
    {
        println!(
            "proc#{id} flags={:#x} path={}",
            proc.effective_flags(),
            String::from_utf8_lossy(dmb.string(proc.strings[0]).unwrap_or_default())
        );
    }
    Ok(())
}

pub(super) fn proc_flags_context(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    for (id, proc) in dmb
        .procs
        .iter()
        .enumerate()
        .filter(|(_, p)| p.extended_flags.is_some())
    {
        println!(
            "proc#{id} flags={:#x} extended={:?} path={}",
            proc.flags,
            proc.extended_flags,
            String::from_utf8_lossy(dmb.string(proc.strings[0]).unwrap_or_default())
        );
    }
    Ok(())
}

pub(super) fn mob_sight_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut compact = std::collections::BTreeMap::<u8, usize>::new();
    let mut extended = std::collections::BTreeMap::<(u32, u8, u8), usize>::new();
    for mob in &dmb.mobs {
        if let Some(ext) = mob.extended_sight {
            *extended.entry(ext).or_default() += 1;
        } else {
            *compact.entry(mob.sight).or_default() += 1;
        }
    }
    println!("compact={compact:?} extended={extended:?}");
    Ok(())
}
