//! Current procedure-input differences, with deliberately uncovered resolver reads.
//! No strong frontend history or copied source text is retained by this receipt.
use super::{FrontendIssuance, FrontendRevision};
use dm_ir::ProcedureIdentity;
use dm_session::{DependencyCoverage, InputDelta};

pub struct ProcedureInputDelta {
    previous: FrontendIssuance,
    current: FrontendIssuance,
    inputs: InputDelta<ProcedureIdentity>,
}
impl ProcedureInputDelta {
    pub fn issue(previous: &FrontendRevision, current: &FrontendRevision) -> Result<Self, String> {
        let old_roster = previous.callable_roster()?;
        let new_roster = current.callable_roster()?;
        let old_abi = old_roster
            .abi()
            .ok_or("previous complete ABI inputs unavailable")?;
        let new_abi = new_roster
            .abi()
            .ok_or("current complete ABI inputs unavailable")?;
        let old_graph = old_abi.graph();
        let new_graph = new_abi.graph();
        // Compare the complete graph once, never once per procedure. The bool
        // below records this exact comparison result, not a hash certificate.
        let graphs_equal = std::sync::Arc::ptr_eq(old_graph, new_graph)
            || old_graph.as_ref() == new_graph.as_ref();
        fn rows(
            revision: &FrontendRevision,
        ) -> Result<Vec<(ProcedureIdentity, (&str, dm_syntax::BodyTermination))>, String> {
            revision
                .bodies
                .iter()
                .map(|body| {
                    let input = revision.body_input(body).map_err(|error| error.message)?;
                    let identity = revision
                        .callable_roster()?
                        .identity_for_member(body.member)
                        .ok_or("body identity unavailable")?;
                    Ok((identity, (input.source(), input.termination())))
                })
                .collect()
        }
        let old_rows = rows(previous)?;
        let new_rows = rows(current)?;
        // Full graph Eq includes metadata, formal/immediate predecessors and
        // owner ancestry. Any topology change conservatively changes existing
        // local inputs; it never certifies unrelated semantic answers.
        let inputs = InputDelta::between(
            old_rows
                .into_iter()
                .map(|(key, input)| (key, (input, false))),
            new_rows
                .into_iter()
                .map(|(key, input)| (key, (input, !graphs_equal))),
        )
        .map_err(|_| "ambiguous procedure input identity")?;
        Ok(Self {
            previous: previous.issuance(),
            current: current.issuance(),
            inputs,
        })
    }
    pub fn authenticates(&self, previous: &FrontendRevision, current: &FrontendRevision) -> bool {
        self.previous.matches(previous) && self.current.matches(current)
    }
    pub fn inputs(&self) -> &InputDelta<ProcedureIdentity> {
        &self.inputs
    }
    pub fn dependency_coverage(&self) -> DependencyCoverage {
        DependencyCoverage::UncoveredAll
    }
}

#[cfg(test)]
#[path = "frontend_procedure_delta_tests.rs"]
mod tests;
