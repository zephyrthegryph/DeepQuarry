use byond_dmb::{bytecode, dmb::Dmb};
use std::collections::BTreeMap;
fn main() {
    for file in std::env::args().skip(1) {
        let dmb = Dmb::from_bytes(&std::fs::read(&file).unwrap()).unwrap();
        let mut seen = BTreeMap::<(u32, u32), usize>::new();
        let mut followers = BTreeMap::<(u32, u32), usize>::new();
        for id in 0..dmb.procs.len() {
            let items = bytecode::decode(dmb.proc_code_words(id).unwrap_or_default())
                .unwrap()
                .into_iter()
                .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                .collect::<Vec<_>>();
            for (i, pair) in items.windows(2).enumerate() {
                if matches!(pair[0].opcode, 0x37 | 0x38) {
                    *followers
                        .entry((pair[0].opcode, pair[1].opcode))
                        .or_default() += 1;
                }
                if matches!(pair[0].opcode, 0x37 | 0x38)
                    && matches!(pair[1].opcode, 0x12 | 0xb2 | 0xb3 | 0xe)
                    && seen
                        .get(&(pair[0].opcode, pair[1].opcode))
                        .copied()
                        .unwrap_or(0)
                        < 3
                {
                    *seen.entry((pair[0].opcode, pair[1].opcode)).or_default() += 1;
                    println!(
                        "{file} proc#{id} {} follower={:#x}",
                        String::from_utf8_lossy(
                            dmb.string(dmb.procs[id].strings[0]).unwrap_or_default()
                        ),
                        pair[1].opcode
                    );
                    for item in &items[i.saturating_sub(6)..(i + 5).min(items.len())] {
                        println!("{:x} {} {:?}", item.offset, item.name, item.operands);
                    }
                }
            }
        }
        println!("{file} FOLLOWER_COUNTS {followers:?}");
    }
}
