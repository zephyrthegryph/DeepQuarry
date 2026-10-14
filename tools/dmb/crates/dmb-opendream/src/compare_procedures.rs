use super::*;
#[path = "compare_procedures_alignment.rs"]
mod alignment;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct NormalArgument {
    pub(super) name: Option<Vec<u8>>,
    pub(super) type_flags: u32,
    pub(super) source_kind: u8,
    pub(super) source_parameter: u8,
    pub(super) source_expression: Option<Vec<u8>>,
    pub(super) reserved: u32,
}

pub(super) fn argument(dmb: &memo::NormalizationContext<'_>, arg: &ProcArgument) -> NormalArgument {
    let expression = dmb
        .argument_source_proc_id(arg)
        .and_then(|id| dmb.reference_path(id));
    NormalArgument {
        name: dmb
            .variables
            .get(arg.variable_id as usize)
            .and_then(|v| bytes(dmb, v.name)),
        type_flags: arg.type_flags,
        source_kind: arg.value_source_kind(),
        source_parameter: if arg.source_expression_index().is_some() {
            0
        } else {
            arg.value_source_parameter()
        },
        source_expression: expression,
        reserved: arg.reserved,
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum NormalOperand {
    Word(u32),
    Branch(usize),
    Offsets(Vec<u32>),
    Branches(Vec<usize>),
    String(Option<Vec<u8>>),
    Proc(Option<Vec<u8>>),
    Value(NormalValue),
    Variable(NormalVariable),
    Switch(Vec<(NormalValue, NormalTarget)>, NormalTarget),
    PickSwitch(Vec<(u32, NormalTarget)>, NormalTarget),
    RangeSwitch(
        Vec<(NormalValue, NormalValue, NormalTarget)>,
        Vec<(NormalValue, NormalTarget)>,
        NormalTarget,
    ),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum NormalTarget {
    Raw(u32),
    Instruction(usize),
}

pub(super) fn normalize_target(target: &mut NormalTarget, offsets: &BTreeMap<usize, usize>) {
    if let NormalTarget::Raw(raw) = target {
        if let Some(&index) = offsets.get(&(*raw as usize)) {
            *target = NormalTarget::Instruction(index);
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct NormalInstruction {
    pub(super) opcode: u32,
    pub(super) operands: Vec<NormalOperand>,
}

pub(super) fn operand(dmb: &memo::NormalizationContext<'_>, operand: Operand) -> NormalOperand {
    match operand {
        Operand::Word(word) => NormalOperand::Word(word),
        Operand::Value(v) => NormalOperand::Value(value(dmb, v)),
        Operand::Variable(v) => NormalOperand::Variable(variable(dmb, &v)),
        Operand::PickProb(offsets) => NormalOperand::Offsets(offsets),
        Operand::Switch { cases, default } => NormalOperand::Switch(
            cases
                .into_iter()
                .map(|(v, target)| (value(dmb, v), NormalTarget::Raw(target)))
                .collect(),
            NormalTarget::Raw(default),
        ),
        Operand::PickSwitch { cases, default } => NormalOperand::PickSwitch(
            cases
                .into_iter()
                .map(|(weight, target)| (weight, NormalTarget::Raw(target)))
                .collect(),
            NormalTarget::Raw(default),
        ),
        Operand::RangeSwitch {
            ranges,
            exact,
            default,
        } => NormalOperand::RangeSwitch(
            ranges
                .into_iter()
                .map(|(low, high, target)| {
                    (value(dmb, low), value(dmb, high), NormalTarget::Raw(target))
                })
                .collect(),
            exact
                .into_iter()
                .map(|(v, target)| (value(dmb, v), NormalTarget::Raw(target)))
                .collect(),
            NormalTarget::Raw(default),
        ),
    }
}

pub(super) fn instruction(
    dmb: &memo::NormalizationContext<'_>,
    input: &bytecode::Instruction,
) -> Result<NormalInstruction, bytecode::DecodeError> {
    if input.opcode == 0x50 {
        // Dream Maker may use PushInt for a whole number where another build
        // emits the equivalent floating point PushVal.
        let integer = input.operands[0] as u16;
        return Ok(NormalInstruction {
            opcode: 0x60,
            operands: vec![NormalOperand::Value(NormalValue::Number(
                (integer as f32).to_bits(),
            ))],
        });
    }
    let mut operands = input
        .typed_operands()?
        .into_iter()
        .map(|item| operand(dmb, item))
        .collect::<Vec<_>>();
    if matches!(input.opcode, 0x2 | 0x4 | 0x84) {
        // Format, OutputFormat, and DbgFile carry a StringID first.
        if let Some(NormalOperand::Word(id)) = operands.first() {
            // An unresolved table reference is not a semantic string. Keep its
            // numeric identity so distinct malformed operands cannot compare equal.
            if let Some(value) = bytes(dmb, *id) {
                operands[0] = NormalOperand::String(Some(value));
            }
        }
    }
    let proc_operand = match input.opcode {
        0x30 => Some(1), // CallGlob: argument count, ProcID.
        0xcd => Some(0), // CallGlobalArgList: ProcID.
        _ => None,
    };
    if let Some(index) = proc_operand {
        if let Some(NormalOperand::Word(id)) = operands.get(index) {
            if let Some(path) = dmb.reference_path(*id) {
                operands[index] = NormalOperand::Proc(Some(path));
            }
        }
    }
    Ok(NormalInstruction {
        opcode: input.opcode,
        operands,
    })
}

pub(super) fn compare_code(
    a: &memo::NormalizationContext<'_>,
    ai: usize,
    b: &memo::NormalizationContext<'_>,
    bi: usize,
    name: &str,
    out: &mut Collector,
) {
    let ignore_debug = out.report.is_some();
    compare_code_options(a, ai, b, bi, name, out, ignore_debug);
}

pub(super) fn compare_code_options(
    a: &memo::NormalizationContext<'_>,
    ai: usize,
    b: &memo::NormalizationContext<'_>,
    bi: usize,
    name: &str,
    out: &mut Collector,
    ignore_debug: bool,
) {
    let acode = a.proc_code_words(ai).unwrap_or_default();
    let bcode = b.proc_code_words(bi).unwrap_or_default();
    let (left, right) = match (bytecode::decode(acode), bytecode::decode(bcode)) {
        (Ok(left), Ok(right)) => (left, right),
        (left, right) => {
            out.add(name, "bytecode.decode", left.err(), right.err());
            return;
        }
    };
    let offsets = |instructions: &[bytecode::Instruction], end: usize| {
        let mut map = BTreeMap::new();
        let mut index = 0;
        for instruction in instructions {
            map.insert(instruction.offset, index);
            if !ignore_debug || !matches!(instruction.opcode, 0x84 | 0x85) {
                index += 1;
            }
        }
        map.insert(end, index);
        map
    };
    let left_offsets = offsets(&left, acode.len());
    let right_offsets = offsets(&right, bcode.len());
    let left = left
        .into_iter()
        .filter(|item| !ignore_debug || !matches!(item.opcode, 0x84 | 0x85))
        .collect::<Vec<_>>();
    let right = right
        .into_iter()
        .filter(|item| !ignore_debug || !matches!(item.opcode, 0x84 | 0x85))
        .collect::<Vec<_>>();
    if let Some(report) = &mut out.report {
        report.observe_bytecode(name, left.len(), right.len());
    }
    out.check(name, "bytecode.instruction_count", left.len(), right.len());
    let normalized = |context: &memo::NormalizationContext<'_>,
                      input: &[bytecode::Instruction],
                      offsets: &BTreeMap<usize, usize>| {
        input
            .iter()
            .map(|item| {
                let mut value = instruction(context, item)?;
                normalize_instruction_targets(&mut value, offsets);
                Ok(value)
            })
            .collect::<Result<Vec<_>, bytecode::DecodeError>>()
    };
    let (left, right) = match (
        normalized(a, &left, &left_offsets),
        normalized(b, &right, &right_offsets),
    ) {
        (Ok(left), Ok(right)) => (left, right),
        (left, right) => {
            out.add(name, "bytecode.operands.decode", left.err(), right.err());
            return;
        }
    };
    let aligned = alignment::align(&left, &right);
    if !aligned.complete {
        out.add(
            name,
            "bytecode.alignment.incomplete",
            "bounded fallback",
            "edit/work budget exceeded",
        );
    }
    let mut paired = BTreeMap::new();
    if aligned.complete {
        for &(a, b) in &aligned.rows {
            if let (Some(a), Some(b)) = (a, b) {
                paired.insert(a, b);
            }
        }
        paired.insert(left.len(), right.len());
    }
    for (index, (ai, bi)) in aligned.rows.into_iter().enumerate() {
        if out.full() {
            break;
        }
        match (ai, bi) {
            (Some(ai), Some(bi)) => {
                let mut av = left[ai].clone();
                let bv = &right[bi];
                let edges_valid = if aligned.complete {
                    alignment::map_targets(&mut av, |target| paired.get(&target).copied())
                } else {
                    true
                };
                let mut checked_right = bv.clone();
                let right_edges_valid = alignment::map_targets(&mut checked_right, Some);
                if !edges_valid || !right_edges_valid || av != *bv {
                    out.add(
                        name,
                        &format!("bytecode[{index}].paired[{ai},{bi}]"),
                        av,
                        bv,
                    );
                }
            }
            (Some(ai), None) => out.add(
                name,
                &format!("bytecode[{index}].deleted[{ai}]"),
                Some(&left[ai]),
                None::<&NormalInstruction>,
            ),
            (None, Some(bi)) => out.add(
                name,
                &format!("bytecode[{index}].inserted[{bi}]"),
                None::<&NormalInstruction>,
                Some(&right[bi]),
            ),
            _ => unreachable!(),
        }
    }
}

/// Compare one paired procedure without traversing unrelated tables.
pub fn compare_proc_code(
    expected: &Dmb,
    expected_id: usize,
    actual: &Dmb,
    actual_id: usize,
    name: &str,
    limit: usize,
    ignore_debug: bool,
) -> Vec<Discrepancy> {
    let expected = &memo::NormalizationContext::new(expected);
    let actual = &memo::NormalizationContext::new(actual);

    let mut out = Collector {
        output: Vec::new(),
        limit,
        report: None,
    };
    compare_code_options(
        expected,
        expected_id,
        actual,
        actual_id,
        name,
        &mut out,
        ignore_debug,
    );
    out.output
}

pub(super) fn compare_proc(
    expected: &memo::NormalizationContext<'_>,
    actual: &memo::NormalizationContext<'_>,
    ids: (usize, usize),
    name: &str,
    options: &CompareOptions,
    compare_sources: bool,
    out: &mut Collector,
) {
    let (ai, bi) = ids;
    let left = &expected.procs[ai];
    let right = &actual.procs[bi];
    out.check(
        name,
        "proc.display",
        optional_proc_string(expected, left.strings[1]),
        optional_proc_string(actual, right.strings[1]),
    );
    out.check(
        name,
        "proc.description",
        optional_proc_string(expected, left.strings[2]),
        optional_proc_string(actual, right.strings[2]),
    );
    out.check(
        name,
        "proc.category",
        optional_proc_string(expected, left.strings[3]),
        optional_proc_string(actual, right.strings[3]),
    );
    out.check(
        name,
        "proc.source",
        left.source_location(),
        right.source_location(),
    );
    out.check(
        name,
        "proc.flags",
        left.effective_flags(),
        right.effective_flags(),
    );
    out.check(
        name,
        "proc.invisibility",
        left.invisibility_setting(),
        right.invisibility_setting(),
    );
    let arguments = |dmb: &memo::NormalizationContext<'_>, id| {
        dmb.proc_arguments(id)
            .unwrap_or_default()
            .iter()
            .map(|arg| argument(dmb, arg))
            .collect::<Vec<_>>()
    };
    out.check(
        name,
        "proc.arguments",
        arguments(expected, ai),
        arguments(actual, bi),
    );
    if compare_sources {
        for (index, (left_arg, right_arg)) in expected
            .proc_arguments(ai)
            .unwrap_or_default()
            .iter()
            .zip(actual.proc_arguments(bi).unwrap_or_default().iter())
            .enumerate()
        {
            match (
                expected.argument_source_proc_id(left_arg),
                actual.argument_source_proc_id(right_arg),
            ) {
                (Some(left_id), Some(right_id)) => compare_proc(
                    expected,
                    actual,
                    (left_id as usize, right_id as usize),
                    &format!("{name}::<argument {index} source>"),
                    options,
                    false,
                    out,
                ),
                (None, None) => {}
                (left, right) => out.add(
                    name,
                    &format!("argument[{index}].source_presence"),
                    left.is_some(),
                    right.is_some(),
                ),
            }
        }
    }
    let locals = |dmb: &memo::NormalizationContext<'_>, proc_: &byond_dmb::dmb::Proc| {
        dmb.lists
            .get(proc_.code_locals_args[1] as usize)
            .into_iter()
            .flatten()
            .map(|&id| {
                dmb.variables
                    .get(id as usize)
                    .and_then(|v| bytes(dmb, v.name))
            })
            .collect::<Vec<_>>()
    };
    out.check(
        name,
        "proc.locals",
        locals(expected, left),
        locals(actual, right),
    );
    if options.compare_bytecode {
        compare_code(expected, ai, actual, bi, name, out);
    }
}

pub(super) fn compare_initializer(
    expected: &memo::NormalizationContext<'_>,
    ai: u32,
    actual: &memo::NormalizationContext<'_>,
    bi: u32,
    name: &str,
    options: &CompareOptions,
    out: &mut Collector,
) {
    let a = expected.procs.get(ai as usize);
    let b = actual.procs.get(bi as usize);
    match (a, b) {
        (None, None) => {}
        (Some(_), Some(_)) => compare_proc(
            expected,
            actual,
            (ai as usize, bi as usize),
            name,
            options,
            true,
            out,
        ),
        _ => out.add(name, "proc.presence", a.is_some(), b.is_some()),
    }
}

fn normalize_instruction_targets(
    normalized: &mut NormalInstruction,
    targets: &BTreeMap<usize, usize>,
) {
    for operand in &mut normalized.operands {
        match operand {
            NormalOperand::Switch(cases, default) => {
                for (_, target) in cases {
                    normalize_target(target, targets);
                }
                normalize_target(default, targets);
            }
            NormalOperand::PickSwitch(cases, default) => {
                for (_, target) in cases {
                    normalize_target(target, targets);
                }
                normalize_target(default, targets);
            }
            NormalOperand::RangeSwitch(ranges, exact, default) => {
                for (_, _, target) in ranges {
                    normalize_target(target, targets);
                }
                for (_, target) in exact {
                    normalize_target(target, targets);
                }
                normalize_target(default, targets);
            }
            _ => {}
        }
    }
    if normalized.opcode == 0xb1 {
        if let Some(NormalOperand::Offsets(offsets)) = normalized.operands.first() {
            if let Some(branches) = offsets
                .iter()
                .map(|offset| targets.get(&(*offset as usize)).copied())
                .collect::<Option<Vec<_>>>()
            {
                normalized.operands[0] = NormalOperand::Branches(branches);
            }
        }
    }
    if byond_dmb::bytecode::is_branch_opcode(normalized.opcode) {
        if let Some(NormalOperand::Word(offset)) = normalized.operands.first() {
            if let Some(&target) = targets.get(&(*offset as usize)) {
                normalized.operands[0] = NormalOperand::Branch(target);
            }
        }
    }
}

/// Shared grammar/resolution and branch normalization for complete payload receipts.
pub(super) fn normalized_code(
    dmb: &memo::NormalizationContext<'_>,
    id: usize,
) -> Result<Vec<NormalInstruction>, bytecode::DecodeError> {
    let words = dmb.proc_code_words(id).unwrap_or_default();
    let input = bytecode::decode(words)?;
    let mut offsets = BTreeMap::new();
    let mut index = 0;
    for item in &input {
        offsets.insert(item.offset, index);
        if !matches!(item.opcode, 0x84 | 0x85) {
            index += 1;
        }
    }
    offsets.insert(words.len(), index);
    input
        .iter()
        .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
        .map(|item| {
            let mut normal = instruction(dmb, item)?;
            normalize_instruction_targets(&mut normal, &offsets);
            Ok(normal)
        })
        .collect()
}
