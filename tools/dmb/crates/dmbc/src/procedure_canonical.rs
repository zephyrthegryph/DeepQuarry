//! Producer-issued canonical ABI inputs; public mutable compatibility views are checked.
use super::*;
use std::collections::BTreeMap;
pub(crate) struct PreparedCanonical {
    inputs: Arc<ProcedureInputs>,
    abi: Option<Arc<PreparedAbi>>,
    pub(super) bytes: Arc<[u8]>,
}
impl PreparedCanonical {
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnOnce(&Arc<ProcedureInputs>, &Arc<[u8]>, Option<&Arc<PreparedAbi>>),
    ) {
        visitor(&self.inputs, &self.bytes, self.abi.as_ref());
    }
    pub(super) fn capture(
        inputs: &Arc<ProcedureInputs>,
        abi: Option<&Arc<PreparedAbi>>,
    ) -> Option<Self> {
        Some(Self {
            inputs: inputs.clone(),
            abi: abi.cloned(),
            bytes: encode(inputs, abi.map(AsRef::as_ref))?.into(),
        })
    }
    pub(super) fn matches(&self, b: &Arc<ProcedureInputs>, abi: Option<&Arc<PreparedAbi>>) -> bool {
        let a = &self.inputs;
        (Arc::ptr_eq(a, b)
            || (a.procedure_identity == b.procedure_identity
                && a.current_proc_path == b.current_proc_path
                && a.current_type_path == b.current_type_path
                && a.parameters == b.parameters
                && a.parameter_type_flags == b.parameter_type_flags
                && a.parameter_value_sources == b.parameter_value_sources
                && a.parameter_defaults == b.parameter_defaults
                && a.parameter_types == b.parameter_types
                && a.readonly_parameters == b.readonly_parameters
                && a.resource_search_context == b.resource_search_context))
            && match (&self.abi, abi) {
                (None, None) => true,
                (Some(a), Some(b)) => Arc::ptr_eq(a, b) || a == b,
                _ => false,
            }
    }
}
pub(super) fn encode(inputs: &ProcedureInputs, abi: Option<&PreparedAbi>) -> Option<Vec<u8>> {
    let mut key = Vec::new();
    let types = inputs.parameter_types.iter().collect::<BTreeMap<_, _>>();
    let bytes = dm_wire::encode(
        0x0204_0004,
        &(
            inputs.procedure_identity,
            &inputs.current_proc_path,
            &inputs.current_type_path,
            &inputs.parameters,
            &inputs.parameter_type_flags,
            &inputs.parameter_value_sources,
            &inputs.parameter_defaults,
            types,
            &inputs.readonly_parameters,
            inputs.resource_search_context,
        ),
    )
    .ok()?;
    key.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
    key.extend_from_slice(&bytes);
    match abi {
        None => key.push(0),
        Some(abi) => {
            key.push(1);
            let bytes = abi.canonical_bytes();
            key.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
            key.extend_from_slice(&bytes);
        }
    }
    Some(key)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn canonical_owner_reuses_exact_inputs_and_rejects_mutation() {
        let parsed = Item {
            kind: dm_syntax::ItemKind::Statement,
            header: String::new(),
            span: Default::default(),
            header_span: Default::default(),
            indent: 0,
            children: Vec::new(),
        };
        let mut unit = PreparedUnit::local_only(ProcedureInputs::default(), &parsed);
        Arc::make_mut(&mut unit.inputs).parameters.push("x".into());
        Arc::make_mut(&mut unit.inputs)
            .parameter_types
            .insert("x".into(), "/datum".into());
        // Independent legacy tuple/framing oracle, including sorted type names.
        let input = &unit.inputs;
        let wire = dm_wire::encode(
            0x0204_0004,
            &(
                input.procedure_identity,
                &input.current_proc_path,
                &input.current_type_path,
                &input.parameters,
                &input.parameter_type_flags,
                &input.parameter_value_sources,
                &input.parameter_defaults,
                input.parameter_types.iter().collect::<BTreeMap<_, _>>(),
                &input.readonly_parameters,
                input.resource_search_context,
            ),
        )
        .unwrap();
        let mut expected = (wire.len() as u64).to_le_bytes().to_vec();
        expected.extend_from_slice(&wire);
        expected.push(0);
        unit.issue_canonical();
        let before = unit.canonical_metadata().unwrap();
        assert_eq!(before.as_ref(), expected.as_slice());
        assert!(Arc::ptr_eq(&before, &unit.canonical_metadata().unwrap()));
        Arc::make_mut(&mut unit.inputs)
            .parameter_defaults
            .push(Some("7".into()));
        let changed = unit.canonical_metadata().unwrap();
        assert!(!Arc::ptr_eq(&before, &changed));
        unit.abi = Some(Arc::new(PreparedAbi {
            layout: ProcLayout::default(),
            argument_sources: Vec::new(),
            source_helpers: Vec::new(),
        }));
        assert!(!Arc::ptr_eq(&before, &unit.canonical_metadata().unwrap()));
        unit.abi = None;
        assert_eq!(
            changed.as_ref(),
            encode(&unit.inputs, None).unwrap().as_slice()
        );
    }
    #[test]
    fn prepared_replay_shares_input_owner_and_mutable_compatibility_detaches() {
        let parsed = Item {
            kind: dm_syntax::ItemKind::Proc,
            header: "p(x)".into(),
            span: Default::default(),
            header_span: Default::default(),
            indent: 0,
            children: Vec::new(),
        };
        let mut unit = PreparedUnit::local_only(ProcedureInputs::default(), &parsed);
        Arc::make_mut(&mut unit.inputs).parameters.push("x".into());
        unit.abi = Some(Arc::new(PreparedAbi {
            layout: ProcLayout::default(),
            argument_sources: Vec::new(),
            source_helpers: Vec::new(),
        }));
        unit.issue_canonical();
        let bytes = unit.canonical_metadata().unwrap();
        let certificate = unit.canonical.as_ref().unwrap();
        certificate.visit_storage(|inputs, _, _| assert!(Arc::ptr_eq(inputs, &unit.inputs)));
        let replay = PreparedReplay::from_unit(&unit).unwrap().into_view();
        assert!(Arc::ptr_eq(&unit.inputs, &replay.inputs));
        assert!(Arc::ptr_eq(&bytes, &replay.canonical_metadata().unwrap()));
        let mut once = crate::heap_census::HeapCensus::new("input.once");
        once.shared_procedure_inputs(&unit.inputs);
        let once = once.finish();
        let mut twice = crate::heap_census::HeapCensus::new("input.twice");
        twice.shared_procedure_inputs(&unit.inputs);
        twice.shared_procedure_inputs(&replay.inputs);
        assert_eq!(
            once.unique_known_capacity_bytes,
            twice.finish().unique_known_capacity_bytes
        );
        Arc::make_mut(&mut unit.inputs)
            .parameters
            .push("changed".into());
        assert!(!Arc::ptr_eq(&unit.inputs, &replay.inputs));
        assert_eq!(replay.inputs.parameters, ["x"]);
        assert!(Arc::ptr_eq(&bytes, &replay.canonical_metadata().unwrap()));
        assert_ne!(bytes.as_ref(), unit.canonical_metadata().unwrap().as_ref());
    }
}
