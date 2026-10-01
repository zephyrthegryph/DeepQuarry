/// Lower OpenDream call forms into native BYOND call instructions.

struct CallLowering<'a, 'code, R: SymbolResolver> {
    code: &'code [u8],
    reader: &'a mut Reader<'code>,
    ids: &'a R,
    start: usize,
    out: &'a mut Vec<u32>,
    offsets: &'a mut HashMap<u32, u32>,
    fixups: &'a mut Vec<Fixup>,
    world_flow: &'a mut WorldFlow,
    state: &'a mut LowerState,
    pending_view_range_iterator: &'a mut Option<u32>,
    pending_orange_iterator: &'a mut bool,
    is_initializer: bool,
}

impl<R: SymbolResolver> CallLowering<'_, '_, R> {
    fn lower(&mut self) -> Result<(), LowerError> {
        let code = self.code;
        let mut reader = &mut *self.reader;
        let ids = self.ids;
        let start = self.start;
        let mut out = &mut *self.out;
        let mut offsets = &mut *self.offsets;
        let mut fixups = &mut *self.fixups;
        let world_flow = &mut *self.world_flow;
        let state = &mut *self.state;
        let pending_view_range_iterator = &mut *self.pending_view_range_iterator;
        let pending_orange_iterator = &mut *self.pending_orange_iterator;
        let is_initializer = self.is_initializer;
        // Call(reference, argument source, stack argument count)
        let ref_at = reader.at;
        let ref_kind = reader.byte()?;
        if ref_kind == 14 {
            let old_field = reader.word()?;
            let field = mapped(ids.self_call_name(old_field), start, "self proc name")?;
            let selector = if ids.self_call_is_verb(old_field) {
                Variable::DynamicVerb(field)
            } else {
                Variable::DynamicProc(field)
            };
            let mode = reader.byte()?;
            let count = reader.word()?;
            if !(matches!((mode, count), (0, 0) | (3, 1))
                || mode == 1 && count <= 255
                || mode == 2 && (2..=510).contains(&count) && count % 2 == 0)
            {
                return Err(LowerError {
                    kind: LowerErrorKind::UnsupportedConstruct,
                    offset: start,
                    reason: "self proc call argument form is unsupported".into(),
                });
            }
            if mode == 2 {
                out.extend([0xc8, count / 2]);
            }
            // Native CallStatement retains the managed result in
            // Eval and skips its following Pop marker. A shared Pop
            // reached by another branch must remain an actual Pop.
            let discard_result = world_flow.pop_is_unshared(&reader, &fixups);
            out.push(if discard_result { 0x2a } else { 0x29 });
            out.extend(Variable::SetCache(Box::new(Variable::Src), Box::new(selector)).encode());
            out.push(if mode == 2 || mode == 3 {
                0xffff
            } else {
                count
            });
            finish_native_statement_call(&mut reader, &mut out, &mut offsets, discard_result);
            state.cached_world_owner = false;
            if let Some(pending) = &mut state.pending_world_ref {
                pending.rhs_changed_cache = true;
            }
            return Ok(());
        }
        let (target, builtin) = match ref_kind {
            2 => (None, None), // current proc (`.`)
            6 => (None, None), // SuperProc
            11 => {
                let old = reader.word()?;
                let target = ids.proc_id(old);
                let builtin = ids.builtin_proc(old);
                if target.is_none() && builtin.is_none() {
                    return Err(LowerError {
                        kind: LowerErrorKind::UnresolvedSymbol,
                        offset: ref_at,
                        reason: format!("unresolved OpenDream proc ID {old}"),
                    });
                }
                (target, builtin)
            }
            _ => {
                return Err(LowerError {
                    kind: LowerErrorKind::UnsupportedConstruct,
                    offset: ref_at,
                    reason: format!(
                        "call reference kind {ref_kind} has no verified BYOND lowering"
                    ),
                })
            }
        };
        let arguments_type = reader.byte()?;
        let count = reader.word()?;
        state.cached_world_owner = false;
        if let Some(pending) = &mut state.pending_world_ref {
            pending.rhs_changed_cache = true;
        }
        match (target, builtin, arguments_type) {
            (None, Some(0xe9 | 0xea), 0) if count == 0 => out.push(builtin.unwrap()),
            (None, Some(0x10001), mode)
                if mode == 1 && (3..=4).contains(&count) || mode == 3 && count == 1 =>
            {
                let generator =
                    mapped(ids.generator_type_string(), start, "/generator type string")?;
                let args_at = guarded_assignment_spans(
                    &out,
                    code,
                    &offsets,
                    &fixups,
                    start,
                    count as usize - 1,
                )
                .map(|(first, _)| first)
                .or_else(|| constructor_argument_start(&out, count as usize))
                .ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "generator arguments have unknown stack effects".into(),
                })?;
                let mut type_words = Vec::new();
                push_value(&mut type_words, 6, generator);
                insert_expression_prefix(&mut out, &mut offsets, &mut fixups, args_at, &type_words);
                if mode == 3 {
                    out.push(0xcf);
                } else {
                    out.extend([0x01, count]);
                }
            }
            (None, Some(0xa5), 1 | 3) if count == 1 => out.push(0xd0),
            (None, Some(0xa6), 1 | 3) if count == 1 => out.push(0xd1),
            (None, None, 0) if ref_kind == 2 && count == 0 => out.push(0x2e),
            (None, Some(0x160), 1) if count == 4 => out.push(0x160),
            (None, Some(0x108), 1) if count == 1 => out.push(0x108),
            (None, Some(0x127), 1) if (2..=3).contains(&count) => {
                out.push(if count == 2 { 0x8f } else { 0x127 });
                finish_native_void_result(&mut reader, &mut out, &mut offsets, &fixups, world_flow);
            }
            (None, Some(0x118), 1) if count == 2 => out.push(0x118),
            (None, Some(0x14b), 1) if count == 1 => out.push(0x14b),
            (None, Some(0x10e), 1) if count == 3 => {
                out.push(0x10e);
                finish_native_void_result(&mut reader, &mut out, &mut offsets, &fixups, world_flow);
            }
            (None, Some(0x57), 1) if count == 1 => out.push(0x5f),
            (None, Some(0x57), 1) if count == 2 => out.push(0x57),
            (None, Some(0xb9 | 0x94), 1) if count == 1 => out.push(builtin.unwrap()),
            (None, Some(0xda), 1) if count == 1 => {
                out.push(0xda);
                finish_native_void_result(&mut reader, &mut out, &mut offsets, &fixups, world_flow);
            }
            (None, Some(0x18), 1) if (1..=6).contains(&count) => {
                for _ in count..6 {
                    out.extend([0x60, 0, 0]);
                }
                out.push(0x18); // alert has six native stack arguments
            }
            (None, Some(0x10f), 1) if count == 3 => {
                out.push(0x10f); // winshow is void
                finish_native_void_result(&mut reader, &mut out, &mut offsets, &fixups, world_flow);
            }
            (None, Some(0x1b | 0x59 | 0x1c | 0xe5 | 0xe6 | 0xe7 | 0xe8), 0 | 1)
                if count <= 2 && {
                    let iterator_at = if reader.code.get(reader.at) == Some(&0xab) {
                        reader.at + 5
                    } else {
                        reader.at
                    };
                    matches!(reader.code.get(iterator_at), Some(&0x41) | Some(&0x3a))
                        && !fixups.iter().any(|fixup| {
                            (reader.at..=iterator_at).contains(&(fixup.target as usize))
                        })
                } =>
            {
                for _ in count..2 {
                    out.extend([0x60, 0, 0]);
                }
                *pending_view_range_iterator = Some(match builtin.unwrap() {
                    0x1b => 7,
                    0x1c => 8,
                    0x59 => 13,
                    0xe5 => 15,
                    0xe6 => 16,
                    0xe7 => 17,
                    0xe8 => 18,
                    _ => unreachable!(),
                });
            }
            (None, Some(0x1000e), 0 | 1)
                if count <= 2 && {
                    let iterator_at = if reader.code.get(reader.at) == Some(&0xab) {
                        reader.at + 5
                    } else {
                        reader.at
                    };
                    matches!(reader.code.get(iterator_at), Some(&0x41) | Some(&0x3a))
                        && !fixups.iter().any(|fixup| {
                            (reader.at..=iterator_at).contains(&(fixup.target as usize))
                        })
                } =>
            {
                // orange(range, center) is consumed directly by a
                // native orange iterator (IterLoad mode 14).
                for _ in count..2 {
                    out.extend([0x60, 0, 0]);
                }
                *pending_orange_iterator = true;
            }
            (None, Some(0x1000e), 0 | 1) if count <= 2 => {
                for _ in count..2 {
                    out.extend([0x60, 0, 0]);
                }
                out.extend([0xad, 174]); // orange() list result
            }
            (None, None, 3) if ref_kind == 2 && count == 1 => out.push(0xca), // .(arglist(L))
            (None, None, 1) if ref_kind == 2 => out.extend([0x2f, count]),    // .(args)
            (None, None, 0) if is_initializer && start == 0 && count == 0 => {}
            (None, None, 4) if ref_kind == 6 => out.push(0x2c), // CallParent, inherited proc args
            (None, None, 1) if ref_kind == 6 => out.extend([0x2d, count]), // CallParentArgs
            (None, None, 3) if ref_kind == 6 && count == 1 => out.push(0xc9), // ..(arglist(L))
            (None, None, 2) if ref_kind == 6 && (2..=510).contains(&count) && count % 2 == 0 => {
                out.extend([0xc8, count / 2, 0xc9]);
            }
            (Some(proc_id), _, 1) => out.extend([0x30, count, proc_id]), // CallGlob
            (Some(proc_id), _, 0) if count == 0 => out.extend([0x30, 0, proc_id]),
            (Some(proc_id), _, 3) if count == 1 => out.extend([0xcd, proc_id]),
            (Some(proc_id), _, 2) if (2..=510).contains(&count) && count % 2 == 0 => {
                out.extend([0xc8, count / 2, 0xcd, proc_id]);
            }
            (None, Some(0xe4), 1) if count == 1 => out.push(0xe4), // isfile(x)
            (None, Some(0x9a | 0x10a | 0xbf | 0xa8 | 0x14d), 1) if count == 1 => {
                out.push(builtin.unwrap()); // file2text/text2path/html_decode/ckey
            }
            (None, Some(0x149), 1) if count == 1 => {
                out.extend([0x149, 0x36]); // ismovable result needs GetFlag
            }
            (None, Some(0x6b | 0xe7 | 0xe8), 1) if count == 2 => {
                out.push(builtin.unwrap()); // turn/hearers
            }
            (None, Some(0x169), 1) if count == 1 => out.push(0x169), // ceil
            (None, Some(0x99), 1) if count == 2 => out.push(0x99),   // text2file
            (None, Some(0x8a), 1) if count == 1 => out.extend([0x8a, 0x36]), // step_rand
            (None, Some(0x91), 1) if (2..=3).contains(&count) => {
                if count == 2 {
                    out.extend([0x60, 0, 0]);
                }
                out.push(0x91); // get_step_to
            }
            (None, Some(0x8c | 0x8e), 1)
                if (2..=if builtin == Some(0x8c) { 5 } else { 4 }).contains(&count) =>
            {
                let native_count = if builtin == Some(0x8c) { 4 } else { 3 };
                for _ in count..native_count {
                    out.extend([0x60, 0, 0]);
                }
                out.push(if count > native_count {
                    if builtin == Some(0x8c) {
                        0x124
                    } else {
                        0x126
                    }
                } else {
                    builtin.unwrap()
                });
                finish_native_void_result(&mut reader, &mut out, &mut offsets, &fixups, world_flow);
            }
            (None, Some(0x37 | 0x71), 1) if (2..=255).contains(&count) => {
                let opcode = builtin.unwrap();
                if count == 2 {
                    // Both comparisons retain an operand and expose
                    // their result through the VM comparison flag.
                    out.push(opcode);
                    if reader.code.get(reader.at) != Some(&0x0c)
                        || fixups
                            .iter()
                            .any(|fixup| fixup.target as usize == reader.at)
                    {
                        out.extend([0x51, 0x36]);
                    }
                } else {
                    let mut end = out.len();
                    let mut spans = Vec::new();
                    for _ in 0..count {
                        let at = guarded_assignment_spans(
                            &out[..end],
                            reader.code,
                            &offsets,
                            &fixups,
                            start,
                            0,
                        )
                        .map(|(_, rhs)| rhs)
                        .or_else(|| constructor_argument_start(&out[..end], 1))
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "variadic text comparison argument has unknown stack effects"
                                .into(),
                        })?;
                        spans.push((at, end));
                        end = at;
                    }
                    spans.reverse();
                    let internal_fixups: Vec<_> = fixups
                        .iter()
                        .enumerate()
                        .filter(|(_, fixup)| fixup.at >= end && fixup.at < out.len())
                        .map(|(index, fixup)| (index, *fixup))
                        .collect();
                    let mut replacement = Vec::new();
                    let mut moved = Vec::new();
                    let mut jumps = Vec::new();
                    for (index, &(lo, hi)) in spans.iter().enumerate() {
                        if index >= 2 {
                            jumps.push(end + replacement.len() + 1);
                            replacement.extend([0x11, 0]);
                        }
                        moved.push(((lo, hi), end + replacement.len()));
                        replacement.extend_from_slice(&out[lo..hi]);
                        if index >= 1 {
                            replacement.push(opcode);
                        }
                    }
                    let cleanup = end + replacement.len();
                    replacement.extend([0x51, 0x36]);
                    let relocated: Vec<_> = offsets
                        .iter()
                        .filter_map(|(&source, &position)| {
                            let joins_argument = internal_fixups
                                .iter()
                                .any(|(_, fixup)| fixup.target == source);
                            moved
                                .iter()
                                .find(|((lo, hi), _)| {
                                    (position as usize) >= *lo
                                        && ((position as usize) < *hi
                                            || joins_argument && position as usize == *hi)
                                })
                                .map(|((lo, _), new)| {
                                    (source, (*new + position as usize - *lo) as u32)
                                })
                        })
                        .collect();
                    let old_len = out.len() - end;
                    replace_words(
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        end,
                        old_len,
                        &replacement,
                    );
                    offsets.extend(relocated);
                    for (index, fixup) in internal_fixups {
                        let ((lo, _), new) = moved
                            .iter()
                            .find(|((lo, hi), _)| fixup.at >= *lo && fixup.at < *hi)
                            .unwrap();
                        fixups[index].at = new + fixup.at - lo;
                    }
                    let target = u32::MAX - start as u32;
                    offsets.insert(target, cleanup as u32);
                    for at in jumps {
                        fixups.push(Fixup {
                            at,
                            target,
                            source: start,
                        });
                    }
                }
            }
            (None, Some(0x134 | 0x135 | 0x155 | 0x156), 1) if (2..=3).contains(&count) => {
                if count == 2 {
                    out.extend([0x50, 1]);
                }
                out.push(builtin.unwrap());
            }
            (None, Some(0x15f | 0x160), 1) if (2..=4).contains(&count) => {
                for _ in count..4 {
                    out.extend([0x60, 0, 0]);
                }
                out.push(builtin.unwrap());
            }
            (None, Some(0x16a | 0x16b), 1) if count == 1 => out.push(builtin.unwrap()),
            (None, Some(0x14c), 1) if (1..=2).contains(&count) => {
                if count == 1 {
                    out.extend([0x60, 0, 0]);
                }
                out.push(0x14c);
            }
            (None, Some(0x18b | 0x18c), 1) if count == 2 => {
                out.extend([0x60, 0, 0, builtin.unwrap()]);
            }
            (None, Some(0x86 | 0x89), 1) if count == 2 => {
                out.extend([builtin.unwrap(), 0x36]); // step/step_towards
            }
            (None, Some(0x88 | 0x87), 1) if (2..=3).contains(&count) => {
                if count == 2 {
                    out.extend([0x60, 0, 0]);
                }
                out.extend([builtin.unwrap(), 0x36]); // step_away/step_to
            }
            (None, Some(0x92), 1) if (2..=3).contains(&count) => {
                if count == 2 {
                    out.extend([0x60, 0, 0]);
                }
                out.push(0x92); // get_step_away
            }
            (None, Some(0x93), 1) if count == 2 => out.push(0x93), // get_step_towards
            (None, Some(0x107), 1) if count == 1 => {
                out.extend([0x60, 0, 0, 0x107]); // url_encode
            }
            (None, Some(0x5c | 0x8b), 1) if count == 2 => {
                if builtin == Some(0x8b) {
                    out.extend([0x60, 0, 0]); // walk's omitted speed
                }
                out.push(builtin.unwrap()); // flick/walk
                finish_native_void_result(&mut reader, &mut out, &mut offsets, &fixups, world_flow);
            }
            (None, Some(0xc7), 1) if count == 1 => {
                out.push(0xc7); // CRASH(msg) never returns a value.
                if reader.code.get(reader.at) == Some(&0x51)
                    && !fixups.iter().any(|fixup| fixup.target == reader.at as u32)
                {
                    offsets.insert(reader.at as u32, out.len() as u32);
                    reader.byte()?;
                }
            }
            (None, Some(0x9f), 1) if count == 1 => out.push(0x9f), // isnum(x)
            (None, Some(0x43), 1) if count == 1 => out.push(0x43), // round
            (None, Some(0x43), 1) if count == 2 => out.push(0x44), // round to multiple
            (None, Some(0x22), 1) if count == 1 => out.push(0x22), // rand(max)
            (None, Some(0x22), 1) if count == 2 => out.push(0x23), // rand(min,max)
            (None, Some(0x22), 0) if count == 0 => out.extend([0x60, 0, 0, 0x22]), // rand()
            (None, Some(0x14a), 1) if count == 3 => out.push(0x14a), // clamp
            (None, Some(0xf7), 1) if count == 1 => out.push(0xf7), // fexists
            (None, Some(0xa0), 1) if count == 1 => out.push(0xa0), // istext
            (None, Some(0x147), 1) if count == 1 => out.push(0x147), // islist
            (None, Some(0xbc), 1) if count == 2 => out.push(0xbc), // hascall
            (None, Some(0x137), 1) if count == 4 => out.push(0x137), // jointext
            (None, Some(0x136 | 0x157), 1) if (2..=5).contains(&count) => {
                if count == 2 {
                    out.extend([0x50, 1]);
                }
                for _ in count.max(3)..5 {
                    out.extend([0x60, 0, 0]);
                }
                out.push(builtin.unwrap()); // splittext[_char](text, delimiter, start, end, limit)
            }
            (None, Some(0x130 | 0x131), 1) if (3..=5).contains(&count) => {
                if count == 3 {
                    out.extend([0x50, 1]);
                }
                if count < 5 {
                    out.extend([0x60, 0, 0]);
                }
                out.push(builtin.unwrap()); // replacetext/Ex
            }
            (None, Some(0x95), 1) if count == 2 => out.push(0x95), // get_dist
            (None, Some(0x1b | 0x1c | 0xe5 | 0xe6 | 0xe7 | 0xe8), 1) if count == 2 => {
                out.push(builtin.unwrap()); // view/oview/viewers/oviewers
            }
            (None, Some(0x59), 1) if count == 2 => out.extend([0x59, 174]), // range(range, center)
            (None, Some(0x1f), 1) if count == 2 => out.push(0x1f), // block(corner1, corner2)
            (None, Some(0x1f), 1) if count == 6 => out.push(0x170), // block(x1,y1,z1,x2,y2,z2)
            (None, Some(0x59), 1) if count == 1 => out.extend([0x60, 0, 0, 0x59, 174]),
            (None, Some(0x59), 0) if count == 0 => {
                out.extend([0x60, 0, 0, 0x60, 0, 0, 0x59, 174]);
            }
            (None, Some(0x1b | 0x1c | 0xe5 | 0xe6 | 0xe7 | 0xe8), 1) if count == 1 => {
                out.extend([0x60, 0, 0, builtin.unwrap()]);
            }
            (None, Some(0x1b | 0x1c | 0xe5 | 0xe6 | 0xe7 | 0xe8), 0) if count == 0 => {
                out.extend([0x60, 0, 0, 0x60, 0, 0, builtin.unwrap()]);
            }
            (None, Some(0xac), 1) if count == 1 => out.push(0xac), // flist
            (None, Some(0x109), 1) if count == 1 => out.push(0x109), // md5
            (None, Some(0x9b), 1) if count == 2 => out.push(0x9b), // fcopy
            (None, Some(0xd7), 1) if count == 1 => out.push(0xd7), // fcopy_rsc
            (None, Some(0xb4), 1) if count == 1 => out.push(0xb4), // fdel
            (None, Some(0x13b), 3) if count == 1 => out.push(0x13b), // filter(arglist(L))
            (None, Some(0x13a), 1) if (1..=2).contains(&count) => out.extend([0x13a, count]), // regex(pattern, flags)
            (None, Some(0xb8), 1) if count == 1 => out.push(0xb8), // params2list
            (None, Some(0x75), 1) if count == 1 => out.push(0x75), // lowertext
            (None, Some(0x16e), 1) if count == 1 => out.push(0x16e), // trimtext
            (None, Some(0x178), 1) if count == 1 => out.push(0x178), // refcount
            (None, Some(0x74), 1) if count == 1 => out.push(0x74), // uppertext
            (None, Some(0x13b), 2) if (2..=510).contains(&count) && count % 2 == 0 => {
                out.extend([0xc8, count / 2, 0x13b]); // filter(named pairs)
            }
            (None, Some(0x6f | 0x70 | 0x14f), 1) if (2..=4).contains(&count) => {
                if count == 2 {
                    out.extend([0x50, 1]);
                }
                if count < 4 {
                    out.extend([0x60, 0, 0]);
                }
                out.push(builtin.unwrap()); // findtext/Ex
            }
            (None, Some(0x137), 1) if count == 3 => out.extend([0x60, 0, 0, 0x137]),
            (None, Some(0x137), 1) if count == 2 => {
                out.extend([0x50, 1, 0x60, 0, 0, 0x137]);
            }
            (None, Some(0x28), 1) if count == 1 => out.push(0x28), // isicon
            (None, Some(0xbe), 1) if count == 1 => out.push(0xbe), // html_encode
            (None, Some(0x170), 3) if count == 1 => {
                let sound = mapped(ids.sound_type_string(), start, "/sound type string")?;
                let args_at = guarded_assignment_spans(&out, code, &offsets, &fixups, start, 0)
                    .map(|(first, _)| first)
                    .or_else(|| constructor_argument_start(&out, 1))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "sound arglist has unknown stack effects".into(),
                    })?;
                insert_expression_prefix(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    args_at,
                    &[0x60, 6, sound],
                );
                out.push(0xcf);
            }
            (None, Some(0x173), 3) if count == 1 => out.push(0xd3), // image(arglist(L))
            (None, Some(0x170), 1) if (1..=255).contains(&count) => {
                let sound = mapped(ids.sound_type_string(), start, "/sound type string")?;
                let args_at = guarded_assignment_spans(
                    &out,
                    code,
                    &offsets,
                    &fixups,
                    start,
                    count as usize - 1,
                )
                .map(|(first, _)| first)
                .or_else(|| constructor_argument_start(&out, count as usize))
                .ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "sound constructor arguments have unknown stack effects".into(),
                })?;
                insert_expression_prefix(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    args_at,
                    &[0x60, 6, sound],
                );
                out.extend([0x01, count]);
            }
            (None, Some(0x170), 2) if (2..=510).contains(&count) && count % 2 == 0 => {
                let sound = mapped(ids.sound_type_string(), start, "/sound type string")?;
                let mut end = out.len();
                let mut spans = Vec::new();
                for _ in 0..count {
                    let at =
                        guarded_assignment_spans(&out[..end], code, &offsets, &fixups, start, 0)
                            .map(|(first, _)| first)
                            .or_else(|| constructor_argument_start(&out[..end], 1))
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "named sound arguments have unknown stack effects".into(),
                            })?;
                    spans.push((at, end));
                    end = at;
                }
                spans.reverse();
                let args_at = spans[0].0;
                for index in (0..count as usize / 2).rev() {
                    let (key_at, key_end) = spans[index * 2];
                    if out[key_at..key_end] == [0x60, 0, 0] {
                        replace_words(
                            &mut out,
                            &mut offsets,
                            &mut fixups,
                            key_at,
                            3,
                            &[0x50, index as u32 + 1],
                        );
                    }
                }
                let mut type_words = Vec::new();
                push_value(&mut type_words, 6, sound);
                insert_expression_prefix(&mut out, &mut offsets, &mut fixups, args_at, &type_words);
                out.extend([0xc8, count / 2, 0xcf]);
            }
            (None, Some(0x171), 1) if (1..=255).contains(&count) => {
                let icon = mapped(ids.icon_type_string(), start, "/icon type string")?;
                let args_at = guarded_assignment_spans(
                    &out,
                    code,
                    &offsets,
                    &fixups,
                    start,
                    count as usize - 1,
                )
                .map(|(first, _)| first)
                .or_else(|| constructor_argument_start(&out, count as usize))
                .or_else(|| {
                    // A conditional final argument ends in OD's
                    // JumpIfFalse/Jump diamond. Find its branch start,
                    // then split only the preceding arguments.
                    let jump = fixups.iter().rev().find(|fixup| {
                        fixup.target == start as u32 && reader.code.get(fixup.source) == Some(&0x0e)
                    })?;
                    let branch = fixups.iter().rev().find(|fixup| {
                        fixup.source < jump.source
                            && fixup.target == (jump.source + 5) as u32
                            && reader.code.get(fixup.source) == Some(&0x8b)
                    })?;
                    let conditional_at = *offsets.get(&(branch.source as u32))? as usize;
                    constructor_argument_start(&out[..conditional_at], count as usize - 1)
                })
                .ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "icon constructor arguments have unknown stack effects".into(),
                })?;
                insert_expression_prefix(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    args_at,
                    &[0x60, 6, icon],
                );
                out.extend([0x01, count]);
            }
            (None, Some(0x170 | 0x171), 0) if count == 0 => {
                let path = if builtin == Some(0x170) {
                    mapped(ids.sound_type_string(), start, "/sound type string")?
                } else {
                    mapped(ids.icon_type_string(), start, "/icon type string")?
                };
                out.extend([0x60, 6, path, 0x01, 0]);
            }
            (None, Some(0x171), 2) if (2..=510).contains(&count) && count % 2 == 0 => {
                let icon = mapped(ids.icon_type_string(), start, "/icon type string")?;
                let mut end = out.len();
                let mut spans = Vec::new();
                for _ in 0..count {
                    let at =
                        guarded_assignment_spans(&out[..end], code, &offsets, &fixups, start, 0)
                            .map(|(first, _)| first)
                            .or_else(|| constructor_argument_start(&out[..end], 1))
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "named icon arguments have unknown stack effects".into(),
                            })?;
                    spans.push((at, end));
                    end = at;
                }
                spans.reverse();
                let args_at = spans[0].0;
                for index in (0..count as usize / 2).rev() {
                    let (key_at, key_end) = spans[index * 2];
                    if out[key_at..key_end] == [0x60, 0, 0] {
                        replace_words(
                            &mut out,
                            &mut offsets,
                            &mut fixups,
                            key_at,
                            3,
                            &[0x50, index as u32 + 1],
                        );
                    }
                }
                let mut type_words = Vec::new();
                push_value(&mut type_words, 6, icon);
                insert_expression_prefix(&mut out, &mut offsets, &mut fixups, args_at, &type_words);
                out.extend([0xc8, count / 2, 0xcf]);
            }
            (None, Some(0x173), 1) if count == 1 => out.extend([0xd4, 1]),
            (None, Some(0x173), 1) if count == 2 => out.push(0x61),
            (None, Some(0x173), 1) if count == 3 => out.extend([0xd4, 3]),
            (None, Some(0x173), 1) if (4..=5).contains(&count) => out.extend([0xd4, count]),
            (None, Some(0x114), 1) if count == 2 => out.push(0x114),
            (None, Some(0x114), 1) if count == 1 => out.push(0xdd),
            (None, Some(0x162), 1) if count == 1 => out.extend([0x50, 0, 0x162]),
            (None, Some(0x162), 1) if count == 2 => out.push(0x162),
            (None, Some(0x173), 2) if (2..=510).contains(&count) && count % 2 == 0 => {
                out.extend([0xc8, count / 2, 0xd3]); // image(named arguments)
            }
            (None, Some(0x172), 3) if count == 1 => {
                let args_at = guarded_assignment_spans(&out, code, &offsets, &fixups, start, 0)
                    .map(|(first, _)| first)
                    .or_else(|| constructor_argument_start(&out, 1))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "file arglist has unknown stack effects".into(),
                    })?;
                insert_expression_prefix(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    args_at,
                    &[0x60, 39, 0],
                );
                out.push(0xcf);
            }
            (None, Some(0x172), 1) if count == 1 => {
                let args_at = guarded_assignment_spans(&out, code, &offsets, &fixups, start, 0)
                    .map(|(first, _)| first)
                    .or_else(|| constructor_argument_start(&out, 1))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "file constructor argument has unknown stack effects".into(),
                    })?;
                insert_expression_prefix(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    args_at,
                    &[0x60, 39, 0],
                );
                out.extend([0x01, 1]);
            }
            (None, Some(0x12a), 1) if count <= 255 => out.extend([0x12a, count]),
            (None, Some(0x12a), 0) if count == 0 => out.extend([0x12a, 0]),
            (None, Some(0x13..=0x17), 1) if count == 1 => {
                out.push(builtin.unwrap()); // isloc/ismob/isobj/isarea/isturf
                if reader.code.get(reader.at) != Some(&0x0c)
                    || fixups
                        .iter()
                        .any(|fixup| fixup.target as usize == reader.at)
                {
                    out.push(0x36);
                }
            }
            (None, Some(0x16c | 0x16d), 1) if count == 1 => {
                out.push(builtin.unwrap()); // isnan/isinf
                if reader.code.get(reader.at) != Some(&0x0c)
                    || fixups
                        .iter()
                        .any(|fixup| fixup.target as usize == reader.at)
                {
                    out.push(0x36);
                }
            }
            (None, Some(0xf5), 1) if count == 1 => out.push(0xf5), // ispath(x)
            (None, Some(0xf5), 1) if count == 2 => out.push(0xf6), // ispath(x, type)
            (None, Some(0xa7), 1) if (1..=255).contains(&count) => out.extend([0xa7, count]), // typesof
            (None, Some(0x72 | 0x73), 1) if count == 2 => {
                out.extend([builtin.unwrap(), 2]); // sorttext/sorttextEx
            }
            (None, Some(0x76), 1) if count == 1 => out.push(0x76), // text2num
            (None, Some(0xdb), 1) if count == 1 => out.extend([0x60, 0, 0, 0xdb]),
            (None, Some(0xdb), 1) if count == 2 => out.push(0xdb),
            (None, Some(0xdc), 1) if count == 1 => out.push(0xdc),
            (None, Some(0x6e), 1) if count == 3 => out.push(0x6e), // copytext
            (None, Some(0x6e), 1) if count == 2 => {
                out.extend([0x60, 0, 0, 0x6e]); // omitted end index
            }
            (None, Some(0x14e), 1) if count == 3 => out.push(0x14e),
            (None, Some(0x14e), 1) if count == 2 => {
                out.extend([0x60, 0, 0, 0x14e]); // omitted end index
            }
            (None, Some(0x132), 1) if count == 2 => {
                out.extend([0x50, 0, 0x50, 1, 0x132]); // findlasttext(text, needle)
            }
            (None, Some(0x132), 1) if count == 3 => out.extend([0x50, 1, 0x132]),
            (None, Some(0x132), 1) if count == 4 => out.push(0x132),
            (None, Some(0xc0), 1) if count == 1 => out.extend([0x60, 0, 0, 0xc0]),
            (None, Some(0xc0), 1) if count == 2 => out.push(0xc0), // time2text
            (None, Some(0xc0), 1) if count == 3 => out.extend([0x15d, 3]), // time2text timezone
            (None, Some(0x159), 1) if count == 1 => out.push(0x77), // num2text(x)
            (None, Some(0x159), 1) if count == 2 => out.push(0x56), // num2text(x, precision)
            (None, Some(0x159), 1) if count == 3 => out.push(0x159), // num2text radix
            (None, Some(0x138), 1) if count == 2 => out.extend([0x167, 2]), // json_encode flags
            (None, Some(0x10c | 0x10d), 1) if count == 3 => {
                out.push(builtin.unwrap()); // winset/winget
                if builtin == Some(0x10c) {
                    finish_native_void_result(
                        &mut reader,
                        &mut out,
                        &mut offsets,
                        &fixups,
                        world_flow,
                    );
                }
            }
            (None, Some(0x76), 1) if count == 2 => out.push(0x158), // text2num radix
            (None, Some(0x138 | 0x139), 1) if count == 1 => out.push(builtin.unwrap()),
            (None, Some(0xb7), 1) if count == 1 => out.push(0xb7), // list2params
            (None, Some(0xa5 | 0xa6), 1) if (1..=255).contains(&count) => {
                out.extend([builtin.unwrap(), count]); // min/max
            }
            (None, Some(0x24), 1) if count == 1 => {
                out.push(0x24); // sleep(t) has no BYOND result
                finish_native_void_result(&mut reader, &mut out, &mut offsets, &fixups, world_flow);
            }
            (None, Some(0x98), 1) if count == 1 => out.push(0x98), // shell(command)
            (None, Some(0x09), 1)
                if count == 1
                    && reader.code.get(reader.at..reader.at + 2) == Some(&[0x4e, 1][..]) =>
            {
                // `src << run(file)` is one native OutputRun opcode.
                state.pending_output_run = true;
            }
            (None, Some(0x148), 1) if count == 1 => out.push(0x148), // ref(object)
            (None, Some(0x179), 1) if count == 2 => out.push(0x179), // load_ext(lib, fn)
            (None, Some(0xe7), 1) if count == 1 => out.extend([0x60, 0, 0, 0xe7]),
            (None, Some(0x86), 1) if count == 3 => out.extend([0x11e, 0x36]),
            (None, Some(0x8b), 1) if (3..=4).contains(&count) => {
                out.push(if count == 3 { 0x8b } else { 0x123 });
                finish_native_void_result(&mut reader, &mut out, &mut offsets, &fixups, world_flow);
            }
            (None, Some(0x125), 1) if (3..=4).contains(&count) => {
                if count == 3 {
                    out.extend([0x60, 0, 0]);
                }
                out.push(0x8d);
                finish_native_void_result(&mut reader, &mut out, &mut offsets, &fixups, world_flow);
            }
            (None, Some(0x125), 1) if count == 5 => {
                out.push(0x125); // walk_away(movable, target, distance, delay, speed)
                finish_native_void_result(&mut reader, &mut out, &mut offsets, &fixups, world_flow);
            }
            (None, Some(0x186 | 0x188 | 0x189), 1) if count == 1 => {
                out.push(builtin.unwrap());
            }
            (None, Some(0x18a | 0x181), 1) if count == 2 => {
                out.push(builtin.unwrap());
            }
            (None, Some(0x187 | 0x18b | 0x18c), 1) if count == 3 => {
                out.push(builtin.unwrap());
            }
            (None, Some(0x17f | 0x180), 1) if (1..=255).contains(&count) => {
                out.extend([builtin.unwrap(), count]);
            }
            _ => {
                return Err(LowerError {
                    kind: LowerErrorKind::UnsupportedConstruct,
                    offset: start,
                    reason: format!(
                        "call argument mode {arguments_type} has no verified BYOND lowering"
                    ),
                })
            }
        }
        Ok(())
    }
}
