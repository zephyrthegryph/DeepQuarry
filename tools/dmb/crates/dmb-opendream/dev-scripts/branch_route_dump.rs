//! Read-only route dump. TSV rows are native ProcID, translated ProcID, path.
use byond_dmb::{bytecode, dmb::Dmb};
fn main() {
    let a: Vec<_> = std::env::args().collect();
    assert_eq!(
        a.len(),
        4,
        "usage: branch_route_dump NATIVE.dmb ACTUAL.dmb PAIRS.tsv"
    );
    let n = Dmb::from_bytes(&std::fs::read(&a[1]).unwrap()).unwrap();
    let t = Dmb::from_bytes(&std::fs::read(&a[2]).unwrap()).unwrap();
    for l in std::fs::read_to_string(&a[3]).unwrap().lines() {
        let z: Vec<_> = l.split('\t').collect();
        println!("PATH {}", z[2]);
        for (d, id) in [(&n, z[0]), (&t, z[1])] {
            let v = bytecode::decode(d.proc_code_words(id.parse().unwrap()).unwrap()).unwrap();
            let v: Vec<_> = v
                .iter()
                .filter(|i| !matches!(i.opcode, 0x84 | 0x85))
                .collect();
            let target = |x: u32| {
                v.iter()
                    .position(|i| i.offset >= x as usize)
                    .unwrap_or(v.len())
            };
            for (k, i) in v.iter().enumerate() {
                println!(
                    "{k} {:x} {:?} targets{:?}",
                    i.opcode,
                    i.operands,
                    i.branch_targets()
                        .unwrap()
                        .into_iter()
                        .map(target)
                        .collect::<Vec<_>>()
                );
            }
            println!("NEXT");
        }
    }
}
