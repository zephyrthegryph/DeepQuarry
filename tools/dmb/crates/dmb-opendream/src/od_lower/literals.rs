use super::*;

/// Constants and packed switch cases share the same source reader and
/// absolute branch relocation contract. `true` means the source instruction
/// consumed a whole case chain and the outer dispatch loop should continue.
#[allow(clippy::too_many_arguments)]
pub(super) fn lower_constant_and_switch(
    op: u8,
    reader: &mut Reader<'_>,
    ids: &impl SymbolResolver,
    start: usize,
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut Vec<Fixup>,
    spawn_targets: &[u32],
) -> Result<bool, LowerError> {
    match op {
        0x11 => {
            if reader.code.get(reader.at) == Some(&0x32) {
                // A mixed constant switch can begin with the null case,
                // then continue with OpenDream's packed string/float
                // cases. Native BYOND stores all cases in one Switch.
                let switch_at = out.len();
                reader.byte()?; // SwitchCase for null
                let first_target = reader.word()?;
                let mut cases = vec![(
                    Value {
                        tag_word: 0,
                        data_word: 0,
                        extra_word: None,
                    },
                    first_target,
                )];
                while matches!(reader.code.get(reader.at), Some(0x8d | 0x93)) {
                    offsets.insert(reader.at as u32, switch_at as u32);
                    let case_op = reader.byte()?;
                    let value = if case_op == 0x93 {
                        let id = mapped(ids.string(reader.word()?), start, "switch string")?;
                        Value {
                            tag_word: 6 | ((id >> 16) << 8),
                            data_word: id & 0xffff,
                            extra_word: None,
                        }
                    } else {
                        let bits = reader.word()?;
                        Value {
                            tag_word: 0x2a,
                            data_word: bits >> 16,
                            extra_word: Some(bits & 0xffff),
                        }
                    };
                    cases.push((value, reader.word()?));
                }
                if reader.code.get(reader.at) != Some(&0x51) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "mixed switch lacks Pop before default".into(),
                    });
                }
                offsets.insert(reader.at as u32, switch_at as u32);
                reader.byte()?;
                let default = if reader.code.get(reader.at) == Some(&0x0e)
                    && !authored_control_jump(ids, reader.code, reader.at)
                {
                    offsets.insert(reader.at as u32, switch_at as u32);
                    reader.byte()?;
                    reader.word()?
                } else {
                    reader.at as u32
                };
                out.extend([0x78, cases.len() as u32]);
                for (value, target) in cases {
                    out.extend(value.encode());
                    let at = out.len();
                    out.push(0);
                    fixups.push(Fixup {
                        at,
                        target,
                        source: start,
                    });
                }
                let at = out.len();
                out.push(0);
                fixups.push(Fixup {
                    at,
                    target: default,
                    source: start,
                });
                return Ok(true);
            }
            if ids.native_null(start) {
                // The native Null reader clears retained Eval ownership at
                // this authored load, including left and conditional operands.
                // Packed switch keys above are values embedded in a table,
                // rather than executed null loads.
                out.extend([0x33, 0xffe6]);
                return Ok(true);
            }
            if reader.code.get(reader.at) == Some(&0x10)
                && spawn_targets.contains(&((reader.at + 1) as u32))
            {
                out.push(0); // DreamMaker ends spawned body with End
                offsets.insert(reader.at as u32, out.len() as u32);
                reader.byte()?; // OpenDream Return
                return Ok(true);
            }
            // `new /path` in OpenDream prefixes the type with a null
            // location. DreamMaker's New uses the type directly.
            if reader.code.get(reader.at) == Some(&0x02)
                && reader.code.get(reader.at + 5) == Some(&0x2e)
            {
                let mode = *reader.code.get(reader.at + 6).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::TruncatedOperand,
                    offset: start,
                    reason: "truncated CreateObject mode".into(),
                })?;
                let count = u32::from_le_bytes(
                    reader
                        .code
                        .get(reader.at + 7..reader.at + 11)
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::TruncatedOperand,
                            offset: start,
                            reason: "truncated CreateObject count".into(),
                        })?
                        .try_into()
                        .unwrap(),
                );
                if !(matches!((mode, count), (0, 0))
                    || mode == 1 && (1..=255).contains(&count)
                    || mode == 2 && (2..=510).contains(&count) && count % 2 == 0
                    || (mode, count) == (3, 1))
                {
                    return Err(LowerError {
                        kind: LowerErrorKind::UnsupportedConstruct,
                        offset: start,
                        reason: "CreateObject argument mode/count is unsupported".into(),
                    });
                }
                let old = u32::from_le_bytes(
                    reader.code[reader.at + 1..reader.at + 5]
                        .try_into()
                        .unwrap(),
                );
                let tag = ids.type_tag(old).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::UnresolvedSymbol,
                    offset: start,
                    reason: "unresolved type tag".into(),
                })?;
                let type_id = mapped(ids.type_id(old), start, "type")?;
                if count > 0 {
                    let args_at = constructor_argument_start(out, count as usize)
                        .or_else(|| {
                            // The final constructor argument may be a
                            // short-circuit `target || fallback` or
                            // `target && fallback`. Its
                            // first value and conditional jump precede the branch
                            // fallback, so split before that branch.
                            let branch = fixups.iter().rev().find(|fixup| {
                                fixup.target == start as u32
                                    && matches!(reader.code.get(fixup.source), Some(0x15 | 0x2f))
                            })?;
                            let branch_at = *offsets.get(&(branch.source as u32))? as usize;
                            constructor_argument_start(&out[..branch_at], count as usize)
                        })
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: "CreateObject arguments have unsupported stack effects".into(),
                        })?;
                    let mut type_push = Vec::new();
                    push_value(&mut type_push, tag, type_id);
                    insert_expression_prefix(out, offsets, fixups, args_at, &type_push);
                } else {
                    push_value(out, tag, type_id);
                }
                offsets.insert(reader.at as u32, out.len() as u32);
                reader.at += 5; // PushType + type ID
                offsets.insert(reader.at as u32, out.len() as u32);
                reader.at += 6; // CreateObject + mode + count
                if mode == 2 {
                    out.extend([0xc8, count / 2, 0xcf]);
                } else if mode == 3 {
                    out.push(0xcf);
                } else {
                    out.extend([0x01, count]);
                }
            } else {
                out.extend([0x60, 0, 0]);
            }
        }
        0x38 => {
            // PushFloat
            let bits = reader.word()?;
            if reader.code.get(reader.at) == Some(&0x32) {
                // Unoptimized OpenDream emits each constant case as a
                // separate push and SwitchCase. DreamMaker stores the
                // entire table in one Switch instruction.
                let switch_at = out.len();
                let mut cases = Vec::new();
                let mut case_bits = bits;
                loop {
                    if reader.byte()? != 0x32 {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "switch case lacks SwitchCase".into(),
                        });
                    }
                    cases.push((case_bits, reader.word()?));
                    if reader.code.get(reader.at) == Some(&0x38)
                        && reader.code.get(reader.at + 5) == Some(&0x32)
                    {
                        offsets.insert(reader.at as u32, switch_at as u32);
                        reader.at += 1;
                        case_bits = reader.word()?;
                    } else {
                        break;
                    }
                }
                if reader.code.get(reader.at) != Some(&0x51) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "switch case chain lacks Pop".into(),
                    });
                }
                offsets.insert(reader.at as u32, switch_at as u32);
                reader.at += 1;
                let default = if reader.code.get(reader.at) == Some(&0x0e)
                    && !authored_control_jump(ids, reader.code, reader.at)
                {
                    offsets.insert(reader.at as u32, switch_at as u32);
                    reader.at += 1;
                    reader.word()?
                } else {
                    reader.at as u32
                };
                out.extend([0x78, cases.len() as u32]);
                for (case_bits, target) in cases {
                    out.extend([0x2a, case_bits >> 16, case_bits & 0xffff]);
                    let at = out.len();
                    out.push(0);
                    fixups.push(Fixup {
                        at,
                        target,
                        source: start,
                    });
                }
                let at = out.len();
                out.push(0);
                fixups.push(Fixup {
                    at,
                    target: default,
                    source: start,
                });
                return Ok(true);
            }
            if let Some(old_type) = simple_new_tail(reader, 1) {
                let tag = ids.type_tag(old_type).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::UnresolvedSymbol,
                    offset: start,
                    reason: "unresolved type tag".into(),
                })?;
                push_value(out, tag, mapped(ids.type_id(old_type), start, "type")?);
                let null_at = reader.at;
                offsets.insert(null_at as u32, (out.len() - 3) as u32);
                offsets.insert((null_at + 1) as u32, (out.len() - 3) as u32);
                out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff]);
                offsets.insert((null_at + 6) as u32, out.len() as u32);
                out.extend([0x01, 1]);
                reader.at += 12;
            } else {
                out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff]);
            }
        }
        _ => unreachable!("constant family opcode"),
    }
    Ok(false)
}
