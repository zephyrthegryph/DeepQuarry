use super::*;

const MAX_WORK: usize = 1_000_000;
const MAX_DISTANCE: usize = 256;

pub(super) struct Alignment {
    pub rows: Vec<(Option<usize>, Option<usize>)>,
    pub complete: bool,
}

// Target-free signatures select correspondence only. Actual edges are checked later.
fn signature(value: &NormalInstruction) -> NormalInstruction {
    let mut value = value.clone();
    map_targets(&mut value, |_| Some(0));
    value
}

pub(super) fn map_targets(
    value: &mut NormalInstruction,
    mut map: impl FnMut(usize) -> Option<usize>,
) -> bool {
    let mut valid = !(crate::bytecode::is_branch_opcode(value.opcode)
        && matches!(value.operands.first(), Some(NormalOperand::Word(_))))
        && !(value.opcode == 0xb1
            && matches!(value.operands.first(), Some(NormalOperand::Offsets(_))));
    fn target(
        value: &mut NormalTarget,
        map: &mut impl FnMut(usize) -> Option<usize>,
        valid: &mut bool,
    ) {
        if let NormalTarget::Instruction(index) = value {
            if let Some(mapped) = map(*index) {
                *index = mapped;
            } else {
                *valid = false;
            }
        } else {
            *valid = false;
        }
    }
    for operand in &mut value.operands {
        match operand {
            NormalOperand::Branch(index) => {
                if let Some(mapped) = map(*index) {
                    *index = mapped;
                } else {
                    valid = false;
                }
            }
            NormalOperand::Branches(indices) => {
                for index in indices {
                    if let Some(mapped) = map(*index) {
                        *index = mapped;
                    } else {
                        valid = false;
                    }
                }
            }
            NormalOperand::Switch(cases, default) => {
                for (_, value) in cases {
                    target(value, &mut map, &mut valid);
                }
                target(default, &mut map, &mut valid);
            }
            NormalOperand::PickSwitch(cases, default) => {
                for (_, value) in cases {
                    target(value, &mut map, &mut valid);
                }
                target(default, &mut map, &mut valid);
            }
            NormalOperand::RangeSwitch(ranges, exact, default) => {
                for (_, _, value) in ranges {
                    target(value, &mut map, &mut valid);
                }
                for (_, value) in exact {
                    target(value, &mut map, &mut valid);
                }
                target(default, &mut map, &mut valid);
            }
            _ => {}
        }
    }
    valid
}

pub(super) fn align(left: &[NormalInstruction], right: &[NormalInstruction]) -> Alignment {
    if left.len().saturating_add(right.len()) > 100_000 {
        return fallback(left.len(), right.len());
    }
    let a: Vec<_> = left.iter().map(signature).collect();
    let b: Vec<_> = right.iter().map(signature).collect();
    let mut work = 0;
    let width = MAX_DISTANCE * 2 + 3;
    let origin = MAX_DISTANCE + 1;
    let mut frontier = vec![0isize; width];
    let mut trace = Vec::new();
    for distance in 0..=MAX_DISTANCE.min(a.len() + b.len()) {
        trace.push(frontier.clone());
        for diagonal in (-(distance as isize)..=distance as isize).step_by(2) {
            work += 1;
            if work > MAX_WORK {
                return fallback(a.len(), b.len());
            }
            let slot = (origin as isize + diagonal) as usize;
            let mut x = if diagonal == -(distance as isize)
                || (diagonal != distance as isize && frontier[slot - 1] < frontier[slot + 1])
            {
                frontier[slot + 1]
            } else {
                frontier[slot - 1] + 1
            };
            let mut y = x - diagonal;
            while x < a.len() as isize && y < b.len() as isize && a[x as usize] == b[y as usize] {
                work += 1;
                if work > MAX_WORK {
                    return fallback(a.len(), b.len());
                }
                x += 1;
                y += 1;
            }
            frontier[slot] = x;
            if x == a.len() as isize && y == b.len() as isize {
                let mut rows = Vec::new();
                for d in (0..=distance).rev() {
                    let k = x - y;
                    let v = &trace[d];
                    let slot = (origin as isize + k) as usize;
                    let previous =
                        if k == -(d as isize) || (k != d as isize && v[slot - 1] < v[slot + 1]) {
                            k + 1
                        } else {
                            k - 1
                        };
                    let px = if d == 0 {
                        0
                    } else {
                        v[(origin as isize + previous) as usize]
                    };
                    let py = if d == 0 { 0 } else { px - previous };
                    while x > px && y > py {
                        x -= 1;
                        y -= 1;
                        rows.push((Some(x as usize), Some(y as usize)));
                    }
                    if d > 0 {
                        if x == px {
                            y -= 1;
                            rows.push((None, Some(y as usize)));
                        } else {
                            x -= 1;
                            rows.push((Some(x as usize), None));
                        }
                    }
                }
                rows.reverse();
                return Alignment {
                    rows,
                    complete: true,
                };
            }
        }
    }
    fallback(a.len(), b.len())
}

fn fallback(left: usize, right: usize) -> Alignment {
    Alignment {
        rows: (0..left.max(right))
            .map(|i| ((i < left).then_some(i), (i < right).then_some(i)))
            .collect(),
        complete: false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn word(opcode: u32) -> NormalInstruction {
        NormalInstruction {
            opcode,
            operands: vec![],
        }
    }
    #[test]
    fn insertion_and_repeated_instructions_are_deterministic() {
        let a = vec![word(1), word(2), word(2), word(3)];
        let b = vec![word(1), word(9), word(2), word(2), word(3)];
        let result = align(&a, &b);
        assert!(result.complete);
        assert_eq!(
            result.rows,
            vec![
                (Some(0), Some(0)),
                (None, Some(1)),
                (Some(1), Some(2)),
                (Some(2), Some(3)),
                (Some(3), Some(4))
            ]
        );
        assert_eq!(result.rows, align(&a, &b).rows);
    }
    #[test]
    fn targets_require_actual_paired_nodes() {
        let mut branch = NormalInstruction {
            opcode: 0,
            operands: vec![NormalOperand::Branch(2)],
        };
        assert!(!map_targets(&mut branch, |_| None));
        assert!(map_targets(&mut branch, |i| (i == 2).then_some(3)));
        assert_eq!(branch.operands, vec![NormalOperand::Branch(3)]);
        let mut malformed = NormalInstruction {
            opcode: 0,
            operands: vec![NormalOperand::Switch(vec![], NormalTarget::Raw(7))],
        };
        assert!(!map_targets(&mut malformed, |_| Some(0)));
    }
    #[test]
    fn bounded_fallback_preserves_every_row() {
        let a = vec![word(1); 300];
        let b = vec![word(2); 301];
        let result = align(&a, &b);
        assert!(!result.complete);
        assert_eq!(result.rows.len(), 301);
        assert_eq!(result.rows.last(), Some(&(None, Some(300))));
    }
}
