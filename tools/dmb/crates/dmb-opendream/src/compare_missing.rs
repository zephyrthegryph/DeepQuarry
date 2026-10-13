//! Full evidence for unmatched procedures; presence/count alone is insufficient.
use super::*;

pub(super) fn compare_missing_procedures(
    expected: &memo::NormalizationContext<'_>,
    actual: &memo::NormalizationContext<'_>,
    out: &mut Collector,
    left: &BTreeMap<String, u32>,
    right: &BTreeMap<String, u32>,
) {
    for site in left.keys().chain(right.keys()).collect::<BTreeSet<_>>() {
        match (left.get(site), right.get(site)) {
            (Some(&id), None) => out.add(
                site,
                "proc.unmatched_payload",
                payload_tree(expected, site, id, left),
                "absent",
            ),
            (None, Some(&id)) => out.add(
                site,
                "proc.unmatched_payload",
                "absent",
                payload_tree(actual, site, id, right),
            ),
            _ => {}
        }
    }
}

fn payload_tree(
    dmb: &memo::NormalizationContext<'_>,
    site: &str,
    id: u32,
    ownership: &BTreeMap<String, u32>,
) -> Vec<(String, String)> {
    let mut result = vec![(site.into(), payload(dmb, id))];
    let prefix = format!("{site}::<");
    for (child, id) in ownership.range(prefix.clone()..) {
        if !child.starts_with(&prefix) {
            break;
        }
        result.push((child.clone(), payload(dmb, *id)));
    }
    result
}

fn payload(dmb: &memo::NormalizationContext<'_>, id: u32) -> String {
    let proc_ = &dmb.procs[id as usize];
    let strings: Vec<_> = proc_
        .strings
        .iter()
        .map(|id| optional_proc_string(dmb, *id))
        .collect();
    let arguments: Vec<_> = dmb
        .proc_arguments(id as usize)
        .unwrap_or_default()
        .iter()
        .map(|arg| argument(dmb, arg))
        .collect();
    let locals = dmb
        .lists
        .get(proc_.code_locals_args[1] as usize)
        .map(|list| {
            list.iter()
                .map(|id| {
                    dmb.variables
                        .get(*id as usize)
                        .and_then(|var| bytes(dmb, var.name))
                })
                .collect::<Vec<_>>()
        });
    let code = match normalized_code(dmb, id as usize) {
        Ok(code) => code
            .iter()
            .map(|item| {
                format!(
                    "opcode={};operands={:?}",
                    item.opcode,
                    item.operands
                        .iter()
                        .map(operand_payload)
                        .collect::<Vec<_>>()
                )
            })
            .collect::<Vec<_>>(),
        Err(error) => vec![format!("uncovered_decode_error:{error:?}")],
    };
    format!("strings={strings:?};source={:?};flags={};invisibility={:?};arguments={arguments:?};locals={locals:?};code={code:?}", proc_.source_location(), proc_.effective_flags(), proc_.invisibility_setting())
}

fn operand_payload(operand: &NormalOperand) -> String {
    match operand {
        NormalOperand::Value(value) => format!("Value({})", value_payload(value)),
        NormalOperand::Switch(cases, default) => format!(
            "Switch({:?},{default:?})",
            cases
                .iter()
                .map(|(value, target)| (value_payload(value), target))
                .collect::<Vec<_>>()
        ),
        NormalOperand::RangeSwitch(ranges, exact, default) => format!(
            "RangeSwitch({:?},{:?},{default:?})",
            ranges
                .iter()
                .map(|(a, b, target)| (value_payload(a), value_payload(b), target))
                .collect::<Vec<_>>(),
            exact
                .iter()
                .map(|(value, target)| (value_payload(value), target))
                .collect::<Vec<_>>()
        ),
        _ => format!("{operand:?}"),
    }
}

fn value_payload(value: &NormalValue) -> String {
    match value {
        // The owner's rooted use supplies identity; retain unknown code evidence,
        // not an allocation ProcID. Coverage still labels this opaque.
        NormalValue::InstanceType(kind, class, InstanceInitializer::Opaque(_, words)) => {
            format!("OpaqueInstance(type={kind},class={class:?},initializer_words={words:?})")
        }
        _ => format!("{value:?}"),
    }
}
