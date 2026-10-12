use super::*;

pub(super) fn cache_frame_depth(words: &[u32]) -> usize {
    byond_dmb::bytecode::decode(words).ok().map_or(0, |items| {
        items.iter().fold(0usize, |depth, item| match item.opcode {
            0x142 => depth + 1,
            0x143 => depth.saturating_sub(1),
            _ => depth,
        })
    })
}

pub(super) fn branch_retains_discarded_value(fixup: &Fixup, code: &[u8], words: &[u32]) -> bool {
    // Native logical-assignment statement branches consume their tested
    // value; expression branches (JmpOr/JmpAnd) retain it for the shared Pop.
    !matches!(
        (code.get(fixup.source), words.get(fixup.at.wrapping_sub(1))),
        (Some(0x66 | 0x67), Some(0x10 | 0x11)) | (Some(0x65), Some(0x13e))
    )
}

pub(super) fn simple_new_tail(reader: &Reader<'_>, arguments: u32) -> Option<u32> {
    let tail = reader.code.get(reader.at..reader.at + 12)?;
    if tail[0] != 0x11
        || tail[1] != 0x02
        || tail[6] != 0x2e
        || tail[7] != 1
        || u32::from_le_bytes(tail[8..12].try_into().ok()?) != arguments
    {
        return None;
    }
    Some(u32::from_le_bytes(tail[2..6].try_into().ok()?))
}

pub(super) fn emit_float_field_assignment(
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    start: usize,
    field: u32,
    bits: u32,
) -> Result<(), LowerError> {
    let items = byond_dmb::bytecode::decode(out).map_err(|error| LowerError {
        kind: LowerErrorKind::MalformedControlFlow,
        offset: start,
        reason: format!("cannot inspect float field owner: {}", error.reason),
    })?;
    if let Some(owner) = items.last().filter(|item| {
        item.opcode == 0x33 && !fixups.iter().any(|fixup| fixup.target == start as u32)
    }) {
        let (variable, used) = Variable::decode(&owner.operands).map_err(|error| LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
            offset: start,
            reason: format!("cannot decode float field owner: {}", error.reason),
        })?;
        if used != owner.operands.len() {
            return Err(LowerError {
                kind: LowerErrorKind::MalformedControlFlow,
                offset: start,
                reason: "float field owner has extra operands".into(),
            });
        }
        let mut replacement = vec![0x60, 0x2a, bits >> 16, bits & 0xffff, 0x34];
        replacement.extend(append_field(variable, field).encode());
        replace_words(
            out,
            offsets,
            fixups,
            owner.offset,
            1 + owner.operands.len(),
            &replacement,
        );
    } else {
        // A computed/branch-selected owner must be consumed into the cache;
        // leaving it under the scalar would corrupt the VM operand stack.
        out.extend([
            0x34,
            0xffd8,
            0x60,
            0x2a,
            bits >> 16,
            bits & 0xffff,
            0x34,
            field,
        ]);
    }
    Ok(())
}

/// OpenDream emits log(value, base) operands in VM order; native DM evaluates
/// the authored base argument first. Move complete expressions, including their
/// internal branches, rather than swapping already evaluated stack values.
pub(super) fn reorder_log_arguments(
    out: &mut [u32],
    code: &[u8],
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    source: usize,
) -> Result<(), LowerError> {
    let argument_start = |words: &[u32]| {
        guarded_assignment_spans(words, code, offsets, fixups, source, 0)
            .map(|(_, rhs)| rhs)
            .or_else(|| constructor_argument_start(words, 1))
    };
    let middle = argument_start(out).ok_or_else(|| LowerError {
        kind: LowerErrorKind::MalformedControlFlow,
        offset: source,
        reason: "log base argument has unknown stack effects".into(),
    })?;
    let begin = argument_start(&out[..middle]).ok_or_else(|| LowerError {
        kind: LowerErrorKind::MalformedControlFlow,
        offset: source,
        reason: "log value argument has unknown stack effects".into(),
    })?;
    let end = out.len();
    let left_len = middle - begin;
    let right_len = end - middle;
    let old_fixups = fixups.to_vec();
    for (byte, word) in offsets.iter_mut() {
        let position = *word as usize;
        let left_join = position == middle
            && old_fixups
                .iter()
                .any(|f| f.target == *byte && f.at >= begin && f.at < middle);
        let right_join = position == end
            && old_fixups
                .iter()
                .any(|f| f.target == *byte && f.at >= middle && f.at < end);
        let outside_entry = position == begin
            && old_fixups
                .iter()
                .any(|f| f.target == *byte && (f.at < begin || f.at >= end));
        *word = if left_join {
            end
        } else if right_join {
            begin + right_len
        } else if outside_entry {
            begin
        } else if (begin..middle).contains(&position) {
            position + right_len
        } else if (middle..end).contains(&position) {
            position - left_len
        } else {
            position
        } as u32;
    }
    for fixup in fixups {
        if (begin..middle).contains(&fixup.at) {
            fixup.at += right_len;
        } else if (middle..end).contains(&fixup.at) {
            fixup.at -= left_len;
        }
    }
    out[begin..end].rotate_left(left_len);
    Ok(())
}

pub(super) fn append_field(owner: Variable, field: u32) -> Variable {
    match owner {
        Variable::SetCache(lhs, rhs) => {
            Variable::SetCache(lhs, Box::new(append_field(*rhs, field)))
        }
        other => Variable::SetCache(Box::new(other), Box::new(Variable::Field(field))),
    }
}

pub(super) fn append_method_selector(owner: Variable, selector: Variable) -> Variable {
    match owner {
        Variable::SetCache(lhs, rhs) => {
            Variable::SetCache(lhs, Box::new(append_method_selector(*rhs, selector)))
        }
        other => Variable::SetCache(Box::new(other), Box::new(selector)),
    }
}

pub(super) fn constructor_argument_start(words: &[u32], count: usize) -> Option<usize> {
    // Source markers do not consume or produce VM values. Ignore them only
    // during span analysis, preserving their original offsets and wire words
    // when callers relocate an expression.
    let instructions: Vec<_> = byond_dmb::bytecode::decode(words)
        .ok()?
        .into_iter()
        .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
        .collect();
    let mut cache_stack = Vec::new();
    let mut cache_stores = Vec::new();
    let mut cache_calls = Vec::new();
    let mut cache_ops = Vec::new();
    for (index, item) in instructions.iter().enumerate() {
        if item.opcode == 0x142 {
            cache_stack.push(index);
        } else if item.opcode == 0x143 {
            if let Some(push) = cache_stack.pop() {
                if push > 0
                    && instructions[push - 1].opcode == 0x34
                    && instructions[push - 1].operands == [0xffd8]
                    && instructions.get(index + 1).is_some_and(|call| {
                        call.opcode == 0x29
                            && Variable::decode(&call.operands).is_ok_and(|(variable, _)| {
                                matches!(
                                    variable,
                                    Variable::DynamicProc(_) | Variable::DynamicVerb(_)
                                )
                            })
                    })
                {
                    cache_stores.push(push - 1);
                    cache_calls.push(index + 1);
                    cache_ops.extend([push, index]);
                }
            }
        }
    }
    let mut needed = count as i64;
    for (index, instruction) in instructions.iter().enumerate().rev() {
        // Teq exposes its boolean through the comparison flag. Keep the
        // materialization together while locating argument expressions.
        if (instruction.opcode == 0x36
            && index >= 2
            && instructions[index - 1].opcode == 0x51
            && matches!(instructions[index - 2].opcode, 0x37 | 0x71))
            || (instruction.opcode == 0x51
                && index > 0
                && matches!(instructions[index - 1].opcode, 0x37 | 0x71)
                && instructions
                    .get(index + 1)
                    .is_some_and(|next| next.opcode == 0x36))
        {
            continue;
        }
        if cache_ops.contains(&index) || cache_stores.contains(&index) {
            continue;
        }
        if instruction.opcode == 0x36
            && index > 0
            && matches!(
                instructions[index - 1].opcode,
                0x86..=0x8a | 0x149 | 0xa9 | 0x11e
            )
        {
            // Treat a verified flag-producing opcode plus GetFlag as one
            // expression when finding its argument span.
            continue;
        }
        let cached_field = |item: &byond_dmb::bytecode::Instruction| {
            matches!(item.opcode, 0x33 | 0x62..=0x65)
                && Variable::decode(&item.operands).is_ok_and(|(var, used)| {
                    used == item.operands.len()
                        && matches!(
                            var,
                            Variable::Field(_) | Variable::Initial(_) | Variable::IsSaved(_)
                        )
                })
        };
        if cached_field(instruction)
            && index > 0
            && instructions[index - 1].opcode == 0x34
            && instructions[index - 1].operands == [0xffd8]
        {
            // The cached field read depends on the owner consumed immediately
            // before it; keep the pair within the owner's expression span.
            continue;
        }
        if instruction.opcode == 0x13f
            && index > 0
            && matches!(instructions[index - 1].opcode, 0x45..=0x4e | 0x177 | 0x15a)
        {
            // PushEval reads the result of the immediately preceding Aug*.
            continue;
        }
        let (pops, pushes) = match instruction.opcode {
            0x33 | 0x50 | 0x60 | 0x62..=0x65 | 0x13f => (0, 1), // GetVar, literals, Pre/PostInc/Dec, PushEval
            0x23
            | 0x71
            | 0x37..=0x3c
            | 0x3e..=0x42
            | 0x44
            | 0x6a
            | 0x56 // Num2Text(number, precision)
            | 0x158 // Text2NumRadix(text, radix)
            | 0x7b
            | 0x7d
            | 0x7e..=0x80
            | 0x140 | 0x141
            | 0x82
            | 0x83
            | 0x90 => (2, 1),
            0x93 | 0x95 | 0x6b => (2, 1), // GetStepTowards/GetDist/Turn
            0x86 | 0x89 | 0xa9
                if instructions.get(index + 1).is_some_and(|next| next.opcode == 0x36) => (2, 1),
            0x87 | 0x88 | 0x11e
                if instructions.get(index + 1).is_some_and(|next| next.opcode == 0x36) => (3, 1),
            0x8a | 0x149
                if instructions.get(index + 1).is_some_and(|next| next.opcode == 0x36) => (1, 1),
            0x21 // Prob(value)
            | 0x0e
            | 0x13..=0x17
            | 0x81
            | 0x22
            | 0x43
            | 0x3d
            | 0x68
            | 0x69
            | 0x6d
            | 0x77 // Num2Text(number)
            | 0x9e
            | 0xc2..=0xc5
            | 0x138
            | 0x139
            | 0x145
            | 0x182..=0x184
            | 0x109
            | 0xb7
            | 0x148 // Ref(object)
            | 0x169 // Ceil(value)
            | 0x31 // LogE(value)
            | 0x16a | 0x16b // Trunc/Fract(value)
            | 0x178 // RefCount(object)
            | 0x16e // TrimText(text)
            | 0x74 | 0x75 // UpperText/LowerText(text)
            | 0x9f // IsNum(value)
            | 0xa0 // IsText(value)
            | 0x147 // IsList(value)
            | 0x9a // File2Text(file)
            | 0x10a // Text2Path(text)
            | 0xbf // HtmlDecode(text)
            | 0xa8 // CKey(text)
            | 0x14d // LengthChar(text)
            | 0xb9 // CKeyEx(text)
            | 0x94 // GetStepRand(atom)
            | 0x5f // RollStr(dice)
            | 0xcd // CallGlobalArgList consumes one argument list and returns a value
            | 0xd2 // Pick(list)
            | 0x35 => (1, 1),
            0x1a => (*instruction.operands.first()? as i64, 1),
            0xa5 => (*instruction.operands.first()? as i64, 1), // Min(args...)
            0xa6 | 0xa7 | 0x13a | 0xd4 => (*instruction.operands.first()? as i64, 1), // Max/TypesOf/Regex/Image
            0xc8 => (2 * *instruction.operands.first()? as i64, 1), // associative list
            0xbb => (3, 1),                                     // Rgb(r,g,b)
            0x5b => (1, 1), // LocateRef(value)
            0x5a => (3, 1),                                     // LocatePos(x,y,z)
            0x6e | 0x14e => (3, 1),                                     // CopyText(text,start,end)
            0x91 | 0x92 => (3, 1),                                     // GetStepTo
            0x57 | 0x118 | 0x99 | 0xe7 | 0xe8 | 0x32 => (2, 1),
            0x14b | 0x108 | 0xd0 | 0xd1 | 0x128 | 0x129 | 0xba | 0xdc => (1, 1),
            0x2e => (0, 1),                              // Text2File/OHearers
            0x6f | 0x70 | 0x14f | 0x15f | 0x160 => (4, 1), // FindText and SpliceText
            0x134 | 0x135 | 0x155 | 0x156 | 0x18b | 0x18c => (3, 1),
            0x14c => (2, 1), // Text2AsciiChar
            0x136 | 0x157 => (5, 1),                            // SplitText[_char]
            0xc0 => (2, 1),                                     // Time2Text(value, format)
            0x132 => (4, 1), // FindLastText(haystack, needle, start, end)
            0x170 => (6, 1), // BlockCoordinates(x1,y1,z1,x2,y2,z2)
            0x15d => (*instruction.operands.first()? as i64, 1), // Time2TextTZ
            0x167 => (*instruction.operands.first()? as i64, 1), // JsonEncodeFlags
            0xc1 => (4 + i64::from(*instruction.operands.get(2)? == 64), 1), // Input with optional selection list
            0xc6 => (5, 1), // InputColor config plus four arguments
            0x18 => (6, 1), // Alert
            0x161 => (5, 1), // RgbEx
            0x113 => (4, 1), // Rgba(r,g,b,a)
            0x14a => (3, 1), // Clamp(value, low, high)
            0x12a if instruction.operands.first() == Some(&0) => (0, 1), // matrix()
            0x01 => (*instruction.operands.first()? as i64 + 1, 1), // New(type, args...)
            0xe9 | 0xea => (0, 1), // database constructor singletons
            0xc9 | 0xca => (1, 1), // parent/self arglist calls
            0x2f => (*instruction.operands.first()? as i64, 1), // recursive CallSelfArgs
            0x02 => (*instruction.operands.get(1)? as i64, 1),
            0x29 if cache_calls.contains(&index) => {
                let count = *instruction.operands.last()?;
                (if count == 0xffff { 2 } else { count as i64 + 1 }, 1)
            }
            0x29 => {
                let count = *instruction.operands.last()?;
                (if count == 0xffff { 1 } else { count as i64 }, 1)
            } // Call, including one arglist value
            0x30 => (*instruction.operands.first()? as i64, 1), // CallGlob
            0xb5 | 0x116 => (*instruction.operands.first()? as i64 + 2, 1), // CallName/CallLib(two targets, args...)
            0x2b | 0x17a => (*instruction.operands.first()? as i64 + 1, 1), // CallPath/CallExt(one target, args...)
            0xd3 => (1, 1), // NewImageArgList
            0xcf | 0x61 => (2, 1), // NewArgList / NewImage
            0xcb | 0x17b => (2, 1), // one target and one arglist
            0xcc | 0x117 => (3, 1), // two targets and one arglist
            0x34 if instruction.operands == [0xffd8]
                && instructions.get(index + 1).is_some_and(cached_field) => (1, 1),
            0x45..=0x4e | 0x177 | 0x15a => (1, i64::from(instructions.get(index+1).is_some_and(|next| next.opcode == 0x13f))),
            0x7c => (3, 0), // ListSet consumes value/list/key.
            0x24 | 0xda => (1, 0), // sleep/rand_seed
            0x5c | 0x8f => (2, 0), // flick/walk_rand
            0x8b | 0x8e | 0x127 | 0x10c | 0x10e | 0x10f => (3, 0),
            0x8c | 0x8d | 0x123 | 0x126 => (4, 0),
            0x124 | 0x125 => (5, 0),
            0x13c => (1, 2), // PushTop duplicates the existing stack value.
            0x142 | 0x143 => (0, 0), // Saved cache frames do not change the value stack.
            0x34 => (1, 0), // SetVar, including cached dynamic initial owner
            _ => return None,
        };
        if instruction.opcode == 0x13c {
            needed = (needed - 2).max(0) + 1;
            continue;
        }
        needed = needed - pushes + pops;
        if needed == 0 {
            return Some(instruction.offset);
        }
        if needed < 0 {
            return None;
        }
    }
    None
}

pub(super) fn is_simple_continue_tail(code: &[u8], source: usize, target: u32) -> bool {
    let mut at = target as usize;
    if matches!(code.get(at), Some(0x56 | 0x57 | 0x62 | 0x63))
        && matches!(code.get(at + 1), Some(8 | 9))
    {
        at += 3; // increment/decrement of a direct argument or local
        if code.get(at) == Some(&0x51) {
            at += 1;
        }
    }
    if code.get(at) != Some(&0x0e) {
        return false;
    }
    code.get(at + 1..at + 5)
        .and_then(|bytes| bytes.try_into().ok())
        .is_some_and(|bytes: [u8; 4]| u32::from_le_bytes(bytes) < source as u32)
}

/// Restore the native exception-aware exits after all branch boundaries are
/// known. Ordinary jumps within a protected body retain their usual encoding.
pub(super) fn restore_try_branch_exits(
    words: &mut [u32],
    code: &[u8],
    fixups: &[Fixup],
    regions: &[(usize, usize)],
) {
    if regions.is_empty() {
        return;
    }
    let jumps: Vec<_> = fixups
        .iter()
        .filter(|fixup| {
            code.get(fixup.source) == Some(&0x0e)
                && fixup.target as usize <= code.len()
                && matches!(words.get(fixup.at.wrapping_sub(1)), Some(0x0f | 0xf8))
        })
        .collect();
    // An explicit continue can have the same backward destination as the
    // natural loop tail. The last backward edge to that label is the tail.
    let mut tails = HashMap::<u32, usize>::new();
    for jump in &jumps {
        if (jump.target as usize) < jump.source {
            tails
                .entry(jump.target)
                .and_modify(|source| *source = (*source).max(jump.source))
                .or_insert(jump.source);
        }
    }
    let loops: Vec<_> = fixups
        .iter()
        .filter(|branch| {
            matches!(code.get(branch.source), Some(0x0c | 0x3b | 0x43 | 0x72))
                && matches!(
                    words.get(branch.at.wrapping_sub(1)),
                    Some(0x11 | 0xfd | 0xff)
                )
                && branch.target as usize > branch.source
        })
        .flat_map(|branch| {
            tails.iter().filter_map(move |(head, tail)| {
                ((*head as usize <= branch.source)
                    && (*tail > branch.source)
                    && (*tail < branch.target as usize))
                    .then_some((branch.source, *tail, branch.target))
            })
        })
        .collect();
    for jump in jumps {
        if !regions
            .iter()
            .any(|(start, end)| *start <= jump.source && jump.source < *end)
        {
            continue;
        }
        let loop_exit = loops.iter().any(|(condition, tail, exit)| {
            *exit == jump.target && *condition < jump.source && jump.source < *tail
        });
        let continues = is_simple_continue_tail(code, jump.source, jump.target)
            || tails
                .get(&jump.target)
                .is_some_and(|tail| jump.source < *tail);
        let leaves_region = regions.iter().any(|(start, end)| {
            *start <= jump.source
                && jump.source < *end
                // EndTry lowers to the native Catch cleanup instruction. A
                // join at that exact boundary must enter the cleanup normally;
                // it is not a goto that exits the protected body.
                && !(*start <= jump.target as usize && (jump.target as usize) <= *end)
        });
        if loop_exit {
            words[jump.at - 1] = 0x12e; // Catch: native break with protected cleanup.
        } else if continues || leaves_region {
            words[jump.at - 1] = 0x12f; // TryJmp: continue/goto, including nested exits.
        }
    }
}

pub(super) fn literal_switch_case_at(code: &[u8], at: usize) -> bool {
    match code.get(at) {
        Some(0x8d | 0x93) => true,
        Some(0x02 | 0x03 | 0x21 | 0x26 | 0x38) => code.get(at + 5) == Some(&0x32),
        Some(0x9f) => code.get(at + 9) == Some(&0x32),
        Some(0x11) => code.get(at + 1) == Some(&0x32),
        Some(0x88) => {
            code.get(at + 1..at + 5) == Some(&[2, 0, 0, 0]) && code.get(at + 13) == Some(&0x05)
        }
        _ => false,
    }
}

/// Literal switch labels can mix compacted and ordinary pushes. Parse their
/// common case chain as one native table instead of splitting it by value type.
pub(super) fn lower_literal_switch_chain(
    reader: &mut Reader<'_>,
    ids: &impl SymbolResolver,
    start: usize,
    first_op: u8,
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut Vec<Fixup>,
) -> Result<bool, LowerError> {
    if !literal_switch_case_at(reader.code, start) {
        return Ok(false);
    }
    let switch_at = out.len() as u32;
    let mut cases = Vec::new();
    let mut ranges = Vec::new();
    let mut op = first_op;
    loop {
        if op == 0x88 {
            if reader.word()? != 2 {
                unreachable!("range prefix checked");
            }
            let low = reader.word()?;
            let high = reader.word()?;
            reader.byte()?; // SwitchCaseRange, checked by prefix recognition.
            ranges.push((low, high, reader.word()?));
        } else {
            let value = match op {
                0x38 | 0x8d => {
                    let bits = reader.word()?;
                    Value {
                        tag_word: 42,
                        data_word: bits >> 16,
                        extra_word: Some(bits & 0xffff),
                    }
                }
                0x03 | 0x93 => {
                    let id = mapped(ids.string(reader.word()?), start, "string")?;
                    Value {
                        tag_word: 6 | ((id >> 16) << 8),
                        data_word: id & 0xffff,
                        extra_word: None,
                    }
                }
                0x02 => {
                    let old = reader.word()?;
                    let tag = mapped(ids.type_tag(old).map(u32::from), start, "type tag")?;
                    let id = mapped(ids.type_id(old), start, "type")?;
                    Value {
                        tag_word: tag | ((id >> 16) << 8),
                        data_word: id & 0xffff,
                        extra_word: None,
                    }
                }
                0x21 | 0x26 => {
                    let old = reader.word()?;
                    let id = mapped(
                        if op == 0x21 {
                            ids.resource(old)
                        } else {
                            ids.proc_id(old)
                        },
                        start,
                        if op == 0x21 { "resource" } else { "proc" },
                    )?;
                    Value {
                        tag_word: (if op == 0x21 { 12 } else { 38 }) | ((id >> 16) << 8),
                        data_word: id & 0xffff,
                        extra_word: None,
                    }
                }
                0x9f => {
                    let old_type = reader.word()?;
                    let old_string = reader.word()?;
                    let id = mapped(
                        ids.modified_instance(old_type, old_string),
                        start,
                        "modified instance",
                    )?;
                    Value {
                        tag_word: 41 | ((id >> 16) << 8),
                        data_word: id & 0xffff,
                        extra_word: None,
                    }
                }
                0x11 => Value {
                    tag_word: 0,
                    data_word: 0,
                    extra_word: None,
                },
                _ => unreachable!("literal case prefix checked"),
            };
            if !matches!(op, 0x8d | 0x93) {
                offsets.insert(reader.at as u32, switch_at);
                reader.byte()?; // SwitchCase, checked by prefix recognition.
            }
            cases.push((value, reader.word()?));
        }
        if !literal_switch_case_at(reader.code, reader.at) {
            break;
        }
        offsets.insert(reader.at as u32, switch_at);
        op = reader.byte()?;
    }
    if reader.code.get(reader.at) != Some(&0x51) {
        return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
            offset: start,
            reason: "literal switch case chain lacks Pop".into(),
        });
    }
    offsets.insert(reader.at as u32, switch_at);
    reader.byte()?;
    let default = if reader.code.get(reader.at) == Some(&0x0e)
        && !authored_control_jump(ids, reader.code, reader.at)
    {
        offsets.insert(reader.at as u32, switch_at);
        reader.byte()?;
        reader.word()?
    } else {
        reader.at as u32
    };
    if ranges.is_empty() {
        out.extend([0x78, cases.len() as u32]);
    } else {
        out.extend([0x7a, ranges.len() as u32]);
        for (low, high, target) in ranges {
            out.extend([42, low >> 16, low & 0xffff, 42, high >> 16, high & 0xffff]);
            fixups.push(Fixup {
                at: out.len(),
                target,
                source: start,
            });
            out.push(0);
        }
        out.push(cases.len() as u32);
    }
    for (value, target) in cases {
        out.extend(value.encode());
        fixups.push(Fixup {
            at: out.len(),
            target,
            source: start,
        });
        out.push(0);
    }
    fixups.push(Fixup {
        at: out.len(),
        target: default,
        source: start,
    });
    out.push(0);
    Ok(true)
}
