use crate::initializer_policy;
use dm_tree::frontend::ColdFrontend;
use dm_tree::initializers::InitializerPlan;

/// `DQ_DUMP_GLOBAL_ORDER=FILE` writes what ordered the global initializers (`startup_order`):
///
/// * `FILE`: one row per global initializer in the order `<global-init>` runs it. Columns: position, `shared` or `static`,
///   owner, procedure (statics), variable, source `file:line`, include occurrence, encounter ordinal, emission ordinal,
///   write ordinal, whether the write is runtime-phase, the initializer text, and the ledger event of its procedure.
/// * `FILE.events`: the allocation ledger, one row per event: index, kind, owner, name, formal, verb, `file:line`,
///   include occurrence.
///
/// `dmb-equiv global-order X.dmb` prints the order of a compiled world; `dump-vars --full` its variable table.
pub(crate) fn dump(
    path: &std::path::Path,
    frontend: &ColdFrontend,
    plan: &InitializerPlan,
    classified: &initializer_policy::ClassifiedInitializers,
) {
    use std::fmt::Write as _;
    let symbols = plan.symbols.as_ref();
    let text = |id: dm_ir::SymbolId| symbols.text(id).unwrap_or("?").to_string();
    let mut out = String::new();
    let mut event_rows = String::new();
    let mut procedure_events: std::collections::HashMap<
        (dm_ir::SymbolId, dm_ir::SymbolId, bool),
        Vec<usize>,
    > = Default::default();
    for (index, event) in frontend.allocation_ledger.events.iter().enumerate() {
        let (kind, owner, name, formal, verb) = match event.kind {
            dm_tree::allocation_ledger::AllocationKind::Type { path, absolute, .. } => {
                ("type", text(path), String::new(), absolute, false)
            }
            dm_tree::allocation_ledger::AllocationKind::Namespace {
                owner,
                kind,
                absolute,
            } => (
                "namespace",
                text(owner),
                format!("{kind:?}"),
                absolute,
                false,
            ),
            dm_tree::allocation_ledger::AllocationKind::Field {
                owner,
                name,
                formal,
                ..
            } => ("field", text(owner), text(name), formal, false),
            dm_tree::allocation_ledger::AllocationKind::Procedure {
                owner,
                formal,
                verb,
                name,
                ..
            } => {
                procedure_events
                    .entry((owner, name, verb))
                    .or_default()
                    .push(index);
                ("proc", text(owner), text(name), formal, verb)
            }
            dm_tree::allocation_ledger::AllocationKind::Parent { owner, .. } => {
                ("parent", text(owner), String::new(), false, false)
            }
        };
        let site = frontend
            .location(event.header_span.start)
            .map(|location| {
                format!(
                    "{}:{}	{}",
                    location.path.display(),
                    location.line,
                    location.include_occurrence
                )
            })
            .unwrap_or_default();
        let _ = writeln!(
            event_rows,
            "{index}	{kind}	{owner}	{name}	{formal}	{verb}	{site}"
        );
    }
    let mut position = 0usize;
    for group in classified
        .groups
        .iter()
        .filter(|group| group.receiver.is_none())
    {
        for &index in &group.writes {
            let row = &classified.writes[index];
            let (kind, owner, procedure, name) = match &row.write.target {
                dm_ir::InitializerTarget::Shared { owner, name, .. } => {
                    ("shared", text(*owner), String::new(), text(*name))
                }
                dm_ir::InitializerTarget::ProcedureStatic(identity) => (
                    "static",
                    text(identity.procedure.owner),
                    text(identity.procedure.name),
                    text(identity.name),
                ),
                dm_ir::InitializerTarget::Instance { .. } => continue,
            };
            let site = plan
                .origins
                .get(row.source_ordinal)
                .map(|origin| {
                    let span = origin.provenance.span;
                    let file = &frontend.files[span.file.index()];
                    let line = file
                        .line_starts
                        .partition_point(|&start| start <= span.start as usize);
                    format!(
                        "{}:{line}	{}	{}	{}",
                        file.path.display(),
                        origin.provenance.include_occurrence,
                        origin.encounter_ordinal,
                        origin.emission_ordinal
                    )
                })
                .unwrap_or_default();
            let event = match &row.write.target {
                dm_ir::InitializerTarget::ProcedureStatic(identity) => procedure_events
                    .get(&(
                        identity.procedure.owner,
                        identity.procedure.name,
                        identity.procedure.verb,
                    ))
                    .and_then(|list| list.get(identity.procedure.occurrence as usize))
                    .map_or(-1, |index| *index as i64),
                _ => -1,
            };
            let source_text = match &row.write.value {
                dm_ir::InitializerValue::Expression(expression) => expression
                    .source_text(symbols)
                    .map(|text| {
                        text.replace('\\', "\\\\")
                            .replace('\n', "\\n")
                            .replace('\t', "\\t")
                    })
                    .unwrap_or_default(),
                _ => String::new(),
            };
            let _ = writeln!(
                out,
                "{position}\t{kind}\t{owner}\t{procedure}\t{name}\t{site}\t{}\t{}\t{source_text}\t{event}",
                row.source_ordinal,
                row.phase == Some(initializer_policy::Phase::Runtime)
            );
            position += 1;
        }
    }
    let mut events_path = path.as_os_str().to_owned();
    events_path.push(".events");
    if let Err(error) = std::fs::write(&events_path, event_rows) {
        eprintln!("dmbc: cannot write events: {error}");
    }
    if let Err(error) = std::fs::write(path, out) {
        eprintln!("dmbc: cannot write {}: {error}", path.display());
    }
}
