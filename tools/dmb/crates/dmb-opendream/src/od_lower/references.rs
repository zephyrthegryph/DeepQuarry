use super::*;

pub(super) fn reference(
    reader: &mut Reader<'_>,
    ids: &impl SymbolResolver,
) -> Result<Variable, LowerError> {
    let at = reader.at;
    let kind = reader.byte()?;
    Ok(match kind {
        0 => Variable::Null,
        1 => Variable::Src,
        2 => Variable::Dot,
        3 => Variable::Usr,
        4 => Variable::Args,
        5 => Variable::World,
        15 => Variable::Callee,
        16 => Variable::Caller,
        17 => Variable::Cache, // Exporter-proven native frozen receiver, no index.
        8 => {
            let arg = reader.byte()?;
            reader.referenced_args.push(arg);
            let native = if reader.native_arg_slots.is_empty() {
                u32::from(arg)
            } else {
                reader
                    .native_arg_slots
                    .get(usize::from(arg))
                    .copied()
                    .flatten()
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: at,
                        reason: format!("OpenDream argument slot {arg} has no native formal"),
                    })?
            };
            Variable::Arg(native)
        }
        9 => {
            let local = usize::from(reader.byte()?);
            Variable::Local(if reader.remap_locals {
                *reader.local_slots.get(local).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: at,
                    reason: format!("OpenDream local slot {local} is inactive"),
                })?
            } else {
                local as u32
            })
        }
        10 => Variable::Global(mapped(ids.global(reader.word()?), at, "global")?),
        11 => Variable::StaticProc(mapped(ids.proc_id(reader.word()?), at, "proc")?),
        13 => {
            let id = mapped(ids.string(reader.word()?), at, "string")?;
            Variable::SetCache(Box::new(Variable::Src), Box::new(Variable::Field(id)))
        }
        12 => {
            let id = mapped(ids.string(reader.word()?), at, "string")?;
            Variable::Field(id)
        }
        _ => {
            return Err(LowerError {
                kind: LowerErrorKind::UnsupportedConstruct,
                offset: at,
                reason: format!("OpenDream reference kind {kind} has no verified BYOND lowering"),
            })
        }
    })
}

pub(super) fn finish_native_statement_call(
    reader: &mut Reader<'_>,
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    statement: bool,
) {
    if statement {
        // CallStatement skips exactly one wire word. Emit its marker now so
        // a source event on OD's Pop cannot insert a debug opcode between them.
        debug_assert_eq!(reader.code.get(reader.at), Some(&0x51));
        offsets.insert(reader.at as u32, out.len() as u32);
        out.push(0x51);
        reader.at += 1;
    }
}

pub(super) fn finish_native_void_result(
    reader: &mut Reader<'_>,
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &[Fixup],
    flow: &mut WorldFlow,
) {
    if flow.pop_is_unshared(reader, fixups) {
        offsets.insert(reader.at as u32, out.len() as u32);
        reader.at += 1;
    } else {
        // OpenDream exposes null for native statements. A common Pop must
        // remain reachable from every expression arm that joins here.
        out.extend([0x60, 0, 0]);
    }
}
