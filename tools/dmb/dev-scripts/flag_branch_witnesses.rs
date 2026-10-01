use byond_dmb::{bytecode, dmb::Dmb};
fn main() {
    for path in std::env::args().skip(1) {
        let dmb = Dmb::from_bytes(&std::fs::read(&path).unwrap()).unwrap();
        let mut count = 0;
        for id in 0..dmb.procs.len() {
            let items: Vec<_> = bytecode::decode(dmb.proc_code_words(id).unwrap())
                .unwrap()
                .into_iter()
                .filter(|i| !matches!(i.opcode, 0x84 | 0x85))
                .collect();
            for (index, item) in items.iter().enumerate() {
                if !matches!(item.opcode, 0xb2 | 0xb3) {
                    continue;
                }
                let target = item.operands[0] as usize;
                let Some(at) = items.iter().position(|i| i.offset >= target) else {
                    continue;
                };
                if items[at].opcode == 0x51
                    && items
                        .get(at + 1)
                        .is_some_and(|i| matches!(i.opcode, 0x10 | 0x11))
                {
                    count += 1;
                    if count <= 12 {
                        println!(
                            "{path} proc#{id} {} from{:x} target{:x}",
                            String::from_utf8_lossy(
                                dmb.string(dmb.procs[id].strings[0]).unwrap_or_default()
                            ),
                            item.offset,
                            target
                        );
                        println!(
                            "source {:?} destination {:?}",
                            &items[index.saturating_sub(5)..=index],
                            &items[at..(at + 3).min(items.len())]
                        );
                    }
                }
            }
        }
        println!("{path} witnesses={count}");
    }
}
