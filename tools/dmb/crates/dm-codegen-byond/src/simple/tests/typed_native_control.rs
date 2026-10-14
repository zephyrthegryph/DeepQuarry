//! Direct typed producer checks against committed Dream Maker captures.
use super::*;
use byond_dmb::dmb::Dmb;

fn fixture(relative: &str, source: &str, binary: &str) -> (dm_syntax::AstFile, Dmb) {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures")
        .join(relative);
    (
        dm_syntax::parse(&std::fs::read_to_string(root.join(source)).unwrap()),
        Dmb::from_bytes(&std::fs::read(root.join(binary)).unwrap()).unwrap(),
    )
}

fn procedure<'a>(native: &'a Dmb, path: &str) -> &'a [u32] {
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
        .unwrap();
    native.proc_code_words(id).unwrap()
}

fn linked(native: &Dmb, item: &Item, parameter: &str) -> Vec<u32> {
    let compiled = compile_simple_proc_with_params(&item.children, &[parameter.into()]).unwrap();
    let mut ledger = Ledger::default();
    for string in &compiled.strings {
        let id = native
            .strings
            .iter()
            .position(|entry| entry.data == string.bytes.as_ref())
            .unwrap();
        ledger.bind(SymRef::String(string.id), id as u32).unwrap();
    }
    for path in &compiled.class_paths {
        let id = native
            .classes
            .iter()
            .position(|class| {
                native
                    .string(class.path_string_id())
                    .and_then(|bytes| std::str::from_utf8(bytes).ok())
                    .map(SymbolId::of)
                    == Some(*path)
            })
            .unwrap();
        ledger
            .bind(reference(Table::Class, path), id as u32)
            .unwrap();
    }
    let frozen = crate::encoder::freeze_proc(&compiled.code).unwrap();
    let mut linked = link_proc(&compiled.code, &ledger).unwrap();
    // Match production dm-link's checked wire-domain patch at typed sites.
    // The Class ledger remains unique; only tag8 packed values use Mob IDs.
    for site in frozen.code().relocations() {
        if let dm_ir::RelocationEncoding::PackedValue24 { tag: 8 } = site.encoding {
            let SymRef::Type(path) = site.reference else {
                panic!("type site identity");
            };
            let class = ledger.id(&SymRef::Type(path)).unwrap();
            let mob = native
                .mobs
                .iter()
                .position(|mob| mob.class == class)
                .unwrap() as u32;
            let offset = site.offset as usize;
            assert_eq!(
                &linked.words[offset..offset + 2],
                &[8 | ((class >> 16) << 8), class & 0xffff]
            );
            linked.words[offset..offset + 2]
                .copy_from_slice(&[8 | ((mob >> 16) << 8), mob & 0xffff]);
        }
    }
    linked.words
}

fn transfer_signature(words: &[u32]) -> (Vec<usize>, usize, usize) {
    let body = byond_dmb::bytecode::decode(words).unwrap();
    let regions: Vec<_> = body
        .iter()
        .filter(|ins| ins.opcode == 0x12c)
        .map(|ins| (ins.offset + 2, ins.operands[0] as usize))
        .collect();
    let exits = body
        .iter()
        .filter(|ins| ins.opcode == 0x12f)
        .map(|ins| {
            let target = ins.operands[0] as usize - 1;
            regions
                .iter()
                .filter(|(start, end)| {
                    *start <= ins.offset
                        && ins.offset < *end
                        && !(*start <= target && target < *end)
                })
                .count()
        })
        .collect();
    (
        exits,
        body.iter().filter(|ins| ins.opcode == 0x12e).count(),
        body.iter().filter(|ins| ins.opcode == 0xf8).count(),
    )
}

#[test]
fn typed_try_loop_transfers_match_authenticated_native_matrix() {
    let (ast, native) = fixture(
        "translation/try_loop_provenance",
        "try_loop_provenance.dm",
        "try_loop_provenance.native.bin",
    );
    for item in ast
        .items
        .iter()
        .filter(|item| item.header.starts_with("/proc/try_"))
    {
        let path = item.header.split('(').next().unwrap();
        let parameter = if path.ends_with("indexed_continue") {
            "items"
        } else {
            "flag"
        };
        assert_eq!(
            transfer_signature(&linked(&native, item, parameter)),
            transfer_signature(procedure(&native, path)),
            "{path}"
        );
    }
}

// Disjoint constant cases may be sorted by native table layout. Compare the
// exact typed value words and their destinations, rather than physical rows.
fn table_signature(words: &[u32]) -> (u32, Vec<(Vec<u32>, u32)>, Vec<(Vec<u32>, u32)>, u32) {
    let body = byond_dmb::bytecode::decode(words).unwrap();
    let table = body
        .iter()
        .find(|ins| matches!(ins.opcode, 0x78 | 0x7a))
        .expect("constant authored switch must retain native dispatch table");
    let returned = |target: u32| {
        let value = body
            .iter()
            .find(|ins| ins.offset >= target as usize && !matches!(ins.opcode, 0x84 | 0x85))
            .unwrap();
        let bits = match value.opcode {
            0x50 => (value.operands[0] as f32).to_bits(),
            0x60 => byond_dmb::operands::Value::decode(&value.operands)
                .unwrap()
                .0
                .number_bits()
                .expect("fixture numeric return"),
            other => panic!("unexpected case destination opcode {other:x}"),
        };
        let next = body
            .iter()
            .find(|ins| {
                ins.offset >= value.offset + 1 + value.operands.len()
                    && !matches!(ins.opcode, 0x84 | 0x85)
            })
            .unwrap();
        assert_eq!(next.opcode, 0x12, "case must return its numeric value");
        bits
    };
    let mut at = 1;
    let mut ranges = Vec::new();
    if table.opcode == 0x7a {
        for _ in 0..table.operands[0] {
            let start = at;
            let (_, width) = byond_dmb::operands::Value::decode(&table.operands[at..]).unwrap();
            at += width;
            let (_, width) = byond_dmb::operands::Value::decode(&table.operands[at..]).unwrap();
            at += width;
            ranges.push((
                table.operands[start..at].to_vec(),
                returned(table.operands[at]),
            ));
            at += 1;
        }
    }
    let count = if table.opcode == 0x7a {
        let count = table.operands[at];
        at += 1;
        count
    } else {
        table.operands[0]
    };
    let mut exact = Vec::new();
    for _ in 0..count {
        let start = at;
        let (_, width) = byond_dmb::operands::Value::decode(&table.operands[at..]).unwrap();
        at += width;
        exact.push((
            table.operands[start..at].to_vec(),
            returned(table.operands[at]),
        ));
        at += 1;
    }
    let default = returned(table.operands[at]);
    assert_eq!(at + 1, table.operands.len());
    ranges.sort();
    exact.sort();
    (table.opcode, exact, ranges, default)
}

#[test]
fn typed_mixed_switch_cases_match_authenticated_native_matrix() {
    let (ast, native) = fixture("lowering", "flow_switch_mixed.dm", "flow_switch_mixed.bin");
    for item in ast
        .items
        .iter()
        .filter(|item| item.header.starts_with("/proc/flow_switch_"))
    {
        let path = item.header.split('(').next().unwrap();
        assert_eq!(
            table_signature(&linked(&native, item, "value")),
            table_signature(procedure(&native, path)),
            "{path}"
        );
    }
}
