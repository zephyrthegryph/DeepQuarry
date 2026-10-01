use byond_dmb::dmb::Dmb;
use std::collections::HashSet;

fn main() {
    let path = std::env::args().nth(1).expect("DMB path");
    let dmb = Dmb::from_bytes(&std::fs::read(path).unwrap()).unwrap();
    let class_init: HashSet<u32> = dmb
        .classes
        .iter()
        .map(|class| class.initializer_proc_id())
        .filter(|&id| id != 0xffff)
        .collect();
    let instance_init: HashSet<u32> = dmb
        .instances
        .iter()
        .map(|instance| instance.initializer)
        .filter(|&id| id != 0xffff)
        .collect();
    let reference_set: HashSet<u32> = dmb.proc_references.iter().copied().collect();
    let mut unseen = 0;
    let mut in_references = 0;
    for (id, proc) in dmb.procs.iter().enumerate() {
        if proc.strings[0] != 0xffff
            || class_init.contains(&(id as u32))
            || instance_init.contains(&(id as u32))
        {
            continue;
        }
        unseen += 1;
        if reference_set.contains(&(id as u32)) {
            in_references += 1;
        }
        if unseen <= 40 {
            let strings = proc.strings.map(|id| {
                dmb.string(id)
                    .map(|s| String::from_utf8_lossy(s).into_owned())
            });
            let code = dmb.proc_code_words(id).unwrap_or_default();
            println!(
                "{id}: strings={strings:?} flags={} code_len={} first={:?}",
                proc.flags,
                code.len(),
                &code[..code.len().min(20)]
            );
        }
    }
    println!("unreferenced anonymous={unseen} in_proc_references={in_references}");
}
