/// Preserve native frozen receiver values when repeated direct-root selectors
/// reuse Cache. Re-reading a mutable binding after a call can select a different
/// object, and can also release Eval earlier than native code.
fn retain_frozen_root_cache(
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    delete_clears: &std::collections::HashSet<usize>,
    probability_regions: &[(u32, u32)],
) {
    use crate::bytecode::Operand;
    let Ok(instructions) = crate::bytecode::decode(out) else {
        return;
    };
    // Src field elimination is proven only for the native lvalue-delete
    // window, not every other Src operation in a metadata-bearing procedure.
    let executable: Vec<_> = instructions
        .iter()
        .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
        .collect();
    let src_field = |item: &crate::bytecode::Instruction| {
        let operands = item.typed_operands().ok()?;
        match operands.first()? {
            Operand::Variable(variable @ Variable::SetCache(owner, field))
                if owner.as_ref() == &Variable::Src
                    && matches!(field.as_ref(), Variable::Field(_)) =>
            {
                Some(variable.clone())
            }
            _ => None,
        }
    };
    let mut src_delete_words = std::collections::HashSet::new();
    for (index, clear) in executable.iter().enumerate() {
        if index < 2 || clear.opcode != 0x34 || !delete_clears.contains(&clear.offset) {
            continue;
        }
        let Some(field) = src_field(clear) else {
            continue;
        };
        let null = executable[index - 1];
        let getter = executable[index - 2];
        if getter.opcode != 0x33
            || src_field(getter).as_ref() != Some(&field)
            || null.opcode != 0x60
            || !matches!(null.typed_operands().ok().as_deref(),
                Some([Operand::Value(value)]) if value.kind() == crate::operands::ValueKind::Null)
        {
            continue;
        }
        src_delete_words.extend([getter.offset, clear.offset]);
        // Once deletion has proved Src remains the selected owner, later
        // direct Src field reads may reuse it. Ownership changes and joins
        // still invalidate the tracked value during the pass below.
        for later in executable.iter().skip(index + 1) {
            if later.opcode == 0x33 && src_field(later).is_some() {
                src_delete_words.insert(later.offset);
            }
        }
        if let Some(next) = executable.get(index + 2).filter(|next| {
            executable
                .get(index + 1)
                .is_some_and(|delete| delete.opcode == 0xc)
                && next.opcode == 0x33
                && src_field(next).as_ref() == Some(&field)
        }) {
            src_delete_words.insert(next.offset);
        }
    }
    let scalar_branch = crate::bytecode::is_branch_opcode;
    let mut encoded_branches = Vec::new();
    let mut incoming_branches =
        std::collections::HashMap::<usize, std::collections::HashSet<usize>>::new();
    for instruction in &instructions {
        let Ok(positions) = instruction.branch_target_word_offsets() else {
            return;
        };
        for at in positions {
            let target = if let Some(fixup) = fixups.iter().find(|fixup| fixup.at == at) {
                offsets
                    .get(&fixup.target)
                    .copied()
                    .map(|offset| offset as usize)
            } else {
                Some(out[at] as usize)
            };
            if let Some(target) = target {
                incoming_branches
                    .entry(target)
                    .or_default()
                    .insert(instruction.offset);
            }
            if !fixups.iter().any(|fixup| fixup.at == at) {
                encoded_branches.push((at, out[at] as usize));
            }
        }
    }
    let mut targets: std::collections::HashSet<usize> = fixups
        .iter()
        .filter_map(|fixup| offsets.get(&fixup.target).map(|target| *target as usize))
        .collect();
    targets.extend(encoded_branches.iter().map(|(_, target)| *target));
    fn root(variable: &Variable) -> bool {
        matches!(
            variable,
            Variable::Src
                | Variable::Usr
                | Variable::World
                | Variable::Arg(_)
                | Variable::Local(_)
                | Variable::Global(_)
        )
    }
    fn selector(
        variable: &Variable,
        cache: &mut Option<Variable>,
        delete_src_fields: bool,
        reuse_world_fields: bool,
    ) -> Variable {
        fn chain(path: &[&Variable]) -> Variable {
            let mut value = (*path.last().expect("nonempty receiver path")).clone();
            for owner in path[..path.len() - 1].iter().rev() {
                value = Variable::SetCache(Box::new((**owner).clone()), Box::new(value));
            }
            value
        }
        // Match the whole frozen receiver path, never just its outer root.
        fn derived(variable: &Variable) -> Option<Vec<&Variable>> {
            if !matches!(variable, Variable::SetCache(_, _)) {
                return None;
            }
            fn flatten<'a>(variable: &'a Variable, path: &mut Vec<&'a Variable>) {
                match variable {
                    Variable::SetCache(owner, next) => {
                        flatten(owner, path);
                        flatten(next, path);
                    }
                    value => path.push(value),
                }
            }
            let mut path = Vec::new();
            flatten(variable, &mut path);
            if path.len() < 3 || !root(path[0]) || *path[0] == Variable::Usr {
                return None;
            }
            if !path[1..path.len() - 1]
                .iter()
                .all(|owner| matches!(owner, Variable::Field(_)))
            {
                return None;
            }
            let next = path.last()?;
            if matches!(next, Variable::Initial(field) | Variable::IsSaved(field)
                if !matches!(field.as_ref(), Variable::Field(_)))
            {
                return None;
            }
            if !matches!(
                next,
                Variable::Field(_)
                    | Variable::DynamicProc(_)
                    | Variable::DynamicVerb(_)
                    | Variable::StaticProc(_)
                    | Variable::StaticVerb(_)
                    | Variable::Initial(_)
                    | Variable::IsSaved(_)
            ) {
                return None;
            }
            // Each SetCache reads its owner, copies that value into Cache, then
            // evaluates its next selector. Field-only chains therefore admit
            // either association with the same ordered reads/cache writes.
            // Native emits the right-associated form; never flatten computed,
            // indexed, Initial-owner or other unproved reference forms.
            Some(path)
        }
        if let Some(path) = derived(variable) {
            let receiver = chain(&path[..path.len() - 1]);
            let redundant = cache.as_ref() == Some(&receiver);
            *cache = Some(receiver);
            return if redundant {
                (*path[path.len() - 1]).clone()
            } else {
                chain(&path)
            };
        }
        match variable {
            Variable::SetCache(owner, field)
                if root(owner)
                    && !matches!(field.as_ref(), Variable::SetCache(_, _))
                    && (!matches!(owner.as_ref(), Variable::Src | Variable::World)
                        || delete_src_fields && owner.as_ref() == &Variable::Src
                        || reuse_world_fields && owner.as_ref() == &Variable::World
                        || matches!(
                            field.as_ref(),
                            Variable::DynamicProc(_)
                                | Variable::DynamicVerb(_)
                                | Variable::StaticProc(_)
                                | Variable::StaticVerb(_)
                        )) =>
            {
                let redundant = cache.as_ref() == Some(owner.as_ref());
                *cache = Some((**owner).clone());
                let field = selector(field, cache, delete_src_fields, reuse_world_fields);
                if redundant {
                    field
                } else {
                    Variable::SetCache(owner.clone(), Box::new(field))
                }
            }
            Variable::SetCache(owner, field) => {
                // Derived/computed owner values need separate value provenance.
                *cache = if owner.as_ref() == &Variable::Src
                    && matches!(field.as_ref(), Variable::Field(_))
                {
                    Some(Variable::Src)
                } else {
                    None
                };
                Variable::SetCache(owner.clone(), field.clone())
            }
            Variable::Initial(field) | Variable::IsSaved(field) => {
                if !matches!(field.as_ref(), Variable::Field(_)) {
                    *cache = None;
                }
                variable.clone()
            }
            _ => variable.clone(),
        }
    }
    let mut cache = None;
    let mut branched_since_selection = false;
    let mut src_context_selected = false;
    let mut world_context_selected = false;
    let mut deleting_cleared_owner = false;
    let mut preceding_frame_getter = None;
    let mut replacements = Vec::new();
    let mut switch_owners = std::collections::HashMap::<usize, Variable>::new();
    let probability_regions: Vec<_> = probability_regions
        .iter()
        .filter_map(|(begin, end)| {
            Some((*offsets.get(begin)? as usize, *offsets.get(end)? as usize))
        })
        .collect();
    let mut probability_contexts = std::collections::HashMap::new();
    for instruction in instructions {
        if targets.contains(&instruction.offset) {
            cache = switch_owners.get(&instruction.offset).cloned();
            preceding_frame_getter = None;
            branched_since_selection = false;
            deleting_cleared_owner = false;
        }
        if let Some((owner, branched)) = probability_contexts.remove(&instruction.offset) {
            // Native compiles candidate selectors using the context preceding
            // probability expressions. The expressions still execute first and
            // can change the actual VM cache; this restores frontend context,
            // not a claim that the runtime receiver survived unchanged.
            cache = owner;
            branched_since_selection = branched;
        }
        for &(_, end) in probability_regions
            .iter()
            .filter(|(begin, _)| *begin == instruction.offset)
        {
            probability_contexts.insert(end, (cache.clone(), branched_since_selection));
        }
        if matches!(instruction.opcode, 0x78 | 0x79 | 0x7a | 0xb1) {
            if let Some(owner) = &cache {
                for (&target, incoming) in &incoming_branches {
                    if incoming.len() == 1 && incoming.contains(&instruction.offset) {
                        // Native switch/pick entries retain the receiver saved
                        // before dispatch. Other incoming edges cannot prove it.
                        switch_owners.insert(target, owner.clone());
                    }
                }
            }
        }
        let supported = matches!(instruction.opcode, 0x29 | 0x2a | 0x33..=0x35
            | 0x45..=0x4e | 0x62..=0x67);
        let Ok(operands) = instruction.typed_operands() else {
            cache = None;
            continue;
        };
        let current_frame_getter = if instruction.opcode == 0x33 {
            operands.iter().find_map(|operand| match operand {
                Operand::Variable(Variable::SetCache(owner, field))
                    if matches!(owner.as_ref(), Variable::Src | Variable::World)
                        && matches!(field.as_ref(), Variable::Field(_)) =>
                {
                    Some((**owner).clone())
                }
                Operand::Variable(Variable::Field(_))
                    if matches!(cache, Some(Variable::Src | Variable::World)) =>
                {
                    cache.clone()
                }
                _ => None,
            })
        } else {
            None
        };
        let writes_field = operands.iter().any(|operand| {
            fn field_target(variable: &Variable) -> bool {
                match variable {
                    Variable::SetCache(_, next) => field_target(next),
                    Variable::Field(_) => true,
                    _ => false,
                }
            }
            matches!(operand, Operand::Variable(variable) if field_target(variable))
        });
        let mut replacement = vec![instruction.opcode];
        for operand in operands {
            match operand {
                Operand::Variable(variable) => {
                    let rewritten = if supported
                        && !(branched_since_selection
                            && !delete_clears.contains(&instruction.offset)
                            && !(src_context_selected && cache == Some(Variable::Src)
                                || world_context_selected && cache == Some(Variable::World))
                            && matches!(instruction.opcode, 0x34 | 0x35 | 0x45..=0x4e | 0x62..=0x67))
                    {
                        let reuse_world_field = (world_context_selected
                            || preceding_frame_getter == Some(Variable::World))
                            && cache == Some(Variable::World);
                        let reuse_src_field = src_delete_words.contains(&instruction.offset)
                            || (src_context_selected
                                || preceding_frame_getter == Some(Variable::Src))
                                && cache == Some(Variable::Src);
                        selector(&variable, &mut cache, reuse_src_field, reuse_world_field)
                    } else {
                        // A field write preserves the frozen direct owner, but
                        // native keeps its explicit selector at the write itself.
                        if let Variable::SetCache(owner, field) = &variable {
                            cache = if root(owner)
                                && !matches!(field.as_ref(), Variable::SetCache(_, _))
                            {
                                Some((**owner).clone())
                            } else {
                                None
                            };
                        } else if !matches!(instruction.opcode, 0x34 | 0x35 | 0x45..=0x4e | 0x62..=0x67)
                        {
                            cache = None;
                        }
                        variable.clone()
                    };
                    if let Variable::SetCache(owner, field) = &rewritten {
                        if root(owner) && !matches!(field.as_ref(), Variable::SetCache(_, _)) {
                            // This emitted selector freezes a fresh binding value.
                            // A prior branch no longer requires a later write to
                            // select that binding again.
                            branched_since_selection = false;
                        }
                    }
                    if matches!(instruction.opcode, 0x29 | 0x2a)
                        && cache.is_some()
                        && matches!(
                            rewritten,
                            Variable::DynamicProc(_)
                                | Variable::DynamicVerb(_)
                                | Variable::StaticProc(_)
                                | Variable::StaticVerb(_)
                        )
                    {
                        // Native method calls establish the retained receiver
                        // context for subsequent field mutations on this arm.
                        branched_since_selection = false;
                    }
                    // Paired native statement stores establish the direct frame
                    // owner for a following field reload. Keep getter-first and
                    // derived/computed selections outside this bounded context.
                    if matches!(instruction.opcode, 0x34 | 0x35) {
                        if let Variable::SetCache(owner, field) = &variable {
                            if matches!(field.as_ref(), Variable::Field(_)) {
                                match owner.as_ref() {
                                    Variable::Src => {
                                        cache = Some(Variable::Src);
                                        src_context_selected = true;
                                    }
                                    Variable::World => {
                                        cache = Some(Variable::World);
                                        world_context_selected = true;
                                    }
                                    _ => {}
                                }
                            }
                        }
                    }
                    replacement.extend(rewritten.encode());
                    if !matches!(instruction.opcode, 0x29 | 0x2a | 0x33)
                        && (matches!(variable, Variable::Cache)
                            || cache.as_ref().is_some_and(|owner| {
                                fn depends_on(owner: &Variable, binding: &Variable) -> bool {
                                    owner == binding
                                        || match owner {
                                            Variable::SetCache(parent, _) => {
                                                depends_on(parent, binding)
                                            }
                                            _ => false,
                                        }
                                }
                                depends_on(owner, &variable)
                            }))
                    {
                        cache = None;
                    }
                }
                Operand::Word(word) => replacement.push(word),
                Operand::Value(value) => replacement.extend(value.encode()),
                _ => {
                    replacement.truncate(1);
                    replacement.extend_from_slice(&instruction.operands);
                    cache = None;
                    break;
                }
            }
        }
        if matches!(instruction.opcode, 0x29 | 0x2a) && cache == Some(Variable::Src) {
            src_context_selected = true;
        }
        if matches!(instruction.opcode, 0x29 | 0x2a) && cache == Some(Variable::World) {
            world_context_selected = true;
        }
        if let Some(owner) = &current_frame_getter {
            // Native consecutive direct field loads retain the freshly selected
            // owner. This does not carry getter-only context across operations.
            cache = Some(owner.clone());
        }
        if !matches!(instruction.opcode, 0x84 | 0x85) {
            preceding_frame_getter = current_frame_getter;
        }
        if replacement[1..] != instruction.operands {
            replacements.push((
                instruction.offset,
                1 + instruction.operands.len(),
                replacement,
            ));
        }
        // Native statement assignments and augmented/postfix mutations reselect
        // a derived receiver afterward. SetVarExpr alone retains that context
        // within an ordinary assignment expression (paired native coverage).
        if (matches!(instruction.opcode, 0x62..=0x67)
            || writes_field && matches!(instruction.opcode, 0x34 | 0x45..=0x4e))
            && cache
                .as_ref()
                .is_some_and(|owner| matches!(owner, Variable::SetCache(_, _)))
        {
            cache = None;
        }
        // Paired native bodies retain the copied receiver through method calls,
        // ordinary value operations, list accesses, New and inherited calls.
        // Global/self calls invalidate frontend knowledge even though the VM's
        // cache value survives. Unknown effects must never authorize reuse.
        let preserves_owner = (instruction.opcode == 0x30
            && (cache == Some(Variable::Usr)
                || src_context_selected && cache == Some(Variable::Src)
                || world_context_selected && cache == Some(Variable::World)))
            || supported
            || instruction.opcode == 0x1a && instruction.operands == [0]
            || matches!(instruction.opcode, 0x34 | 0x35 | 0x45..=0x4e | 0x62..=0x67)
            || matches!(
                instruction.opcode,
                0x01 | 0x0d | 0x0e | 0x10 | 0x11 | 0x2c | 0x36
                    ..=0x44 | 0x50 | 0x51 | 0x60 | 0x7b | 0x7c | 0x84 | 0x85 | 0xb2 | 0xb3 | 0x13f
            );
        if scalar_branch(instruction.opcode) {
            branched_since_selection = true;
        }
        let preserves_cleared_owner = instruction.opcode == 0xc && deleting_cleared_owner;
        if !preserves_owner && !preserves_cleared_owner {
            cache = None;
        }
        if cache != Some(Variable::World) {
            world_context_selected = false;
        }
        if cache != Some(Variable::Src) {
            src_context_selected = false;
        }
        if !matches!(instruction.opcode, 0x84 | 0x85) {
            deleting_cleared_owner = delete_clears.contains(&instruction.offset)
                && instruction.opcode == 0x34
                && cache.is_some();
        }
    }
    for (at, len, replacement) in replacements.into_iter().rev() {
        let delta = replacement.len() as isize - len as isize;
        for (operand, target) in &mut encoded_branches {
            if *operand >= at + len {
                *operand = (*operand as isize + delta) as usize;
            }
            if *target >= at + len {
                *target = (*target as isize + delta) as usize;
            }
        }
        replace_words(out, offsets, fixups, at, len, &replacement);
    }
    for (operand, target) in encoded_branches {
        out[operand] = target as u32;
    }
}
