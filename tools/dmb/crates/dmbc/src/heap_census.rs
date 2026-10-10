//! Opt-in retained-owner census. This observes container payloads/capacities,
//! not allocator metadata, private memory, or a fabricated total heap size.
//! A boundary shares one census, so Arc aliases and nested buffers count once.
use serde::Serialize;
mod cache_batch;
mod declaration_syntax;
mod dmb_image;
mod effective_metadata;
pub(crate) mod initializer_artifacts;
mod initializer_ledger;
mod lexical_callable;
mod local_shape;
mod macro_environments;
mod metadata_dependencies;
mod resident_map_outputs;
mod source_text;
mod storage_inventory;
pub(crate) use resident_map_outputs::weight as resident_map_outputs_weight;
mod prepared;
mod prepared_inputs;
mod relocation_metrics;
mod resident_abi;
mod resident_initializer;
pub(crate) use prepared_inputs::inspect as prepared_input_census;
mod resident_owner_projection;
pub(crate) use resident_owner_projection::{
    inspect as owner_projection_census, weight as resident_owner_projection_weight,
};
mod resident_initializer_fragment;
pub(crate) use resident_abi::weight as resident_abi_weight;
mod expansion_inputs;
mod latest_images;
mod resident_maps;
pub(crate) use expansion_inputs::inspect as expansion_input_census;
mod resident_startup;
pub(crate) mod startup_artifacts;
pub(crate) use resident_maps::{
    geometry_weight as resident_map_geometry_weight, plan_weight as resident_map_plan_weight,
};
mod grammar_roster;
mod initializer_assemblies;
pub(crate) mod resident_weight;
mod retained_declarations;
pub(crate) use initializer_assemblies::inspect as initializer_assembly_census;
mod retained_normalization;
mod session_symbolic;
pub(crate) use resident_initializer::{
    modifier_weight as resident_modifier_weight,
    syntax_weight as resident_initializer_syntax_weight, weight as resident_initializer_weight,
};
pub(crate) use retained_declarations::inspect as retained_declaration_census;
mod typed_body;
use std::{
    collections::{BTreeMap, BTreeSet, HashSet},
    io::{self, Write},
    mem::size_of,
    path::PathBuf,
    sync::Arc,
};
#[derive(Default, Serialize)]
pub struct OwnerReport {
    pub owner: String,
    pub unique_payload_bytes: u64,
    pub unique_known_capacity_bytes: u64,
    pub unknown_capacity_payload_bytes: u64,
    pub unique_allocations: u64,
    pub shared_encounters: u64,
    pub observed_items: u64,
    pub unknown: BTreeSet<String>,
}
#[derive(Serialize)]
pub struct HeapCensusReport {
    pub schema: u32,
    pub stage: String,
    pub scope: &'static str,
    pub unique_known_capacity_bytes: u64,
    pub unknown_capacity_payload_bytes: u64,
    pub owners: Vec<OwnerReport>,
    pub limitations: Vec<&'static str>,
    pub frozen_code_metrics: relocation_metrics::RelocationMetrics,
}
pub struct HeapCensus {
    stage: String,
    owners: BTreeMap<String, OwnerReport>,
    // Addresses stay private to this diagnostic, never become output identities.
    allocations: HashSet<usize>,
    buffer_encounters: usize,
    collections: HashSet<usize>,
    frozen_code_metrics: relocation_metrics::RelocationMetrics,
}
impl HeapCensus {
    pub fn new(stage: impl Into<String>) -> Self {
        Self {
            stage: stage.into(),
            owners: BTreeMap::new(),
            allocations: HashSet::new(),
            buffer_encounters: 0,
            collections: HashSet::new(),
            frozen_code_metrics: Default::default(),
        }
    }
    /// Count logical entries without claiming their private index allocation layout.
    pub(crate) fn observe_items(&mut self, name: &str, count: usize) {
        self.owner(name).observed_items =
            self.owner(name).observed_items.saturating_add(count as u64);
    }
    /// Account a provider's exposed backing view; caller supplies actual capacities.
    pub(crate) fn exposed_buffer(
        &mut self,
        owner: &str,
        pointer: usize,
        payload: usize,
        capacity: usize,
    ) -> bool {
        self.buffer(owner, pointer, payload, capacity)
    }
    fn owner(&mut self, name: &str) -> &mut OwnerReport {
        if !self.owners.contains_key(name) {
            self.owners.insert(
                name.into(),
                OwnerReport {
                    owner: name.into(),
                    ..Default::default()
                },
            );
        }
        self.owners.get_mut(name).expect("census owner inserted")
    }
    pub fn unknown(&mut self, owner: &str, reason: &str) {
        self.owner(owner).unknown.insert(reason.into());
    }
    fn buffer(&mut self, owner: &str, pointer: usize, payload: usize, capacity: usize) -> bool {
        self.buffer_encounters = self.buffer_encounters.saturating_add(1);
        if capacity == 0 {
            return false;
        }
        let first = self.allocations.insert(pointer);
        let row = self.owner(owner);
        if first {
            row.unique_payload_bytes += payload as u64;
            row.unique_known_capacity_bytes += capacity as u64;
            row.unique_allocations += 1;
        } else {
            row.shared_encounters += 1;
        }
        first
    }
    /// Collection entries are logical lower bounds, not invented allocator capacities.
    pub(crate) fn collection_entries<T>(&mut self, owner: &str, address: usize, len: usize) {
        if len == 0 {
            return;
        }
        let first = self.collections.insert(address);
        let row = self.owner(owner);
        row.observed_items += len as u64;
        if first {
            let bytes = len.saturating_mul(size_of::<T>()) as u64;
            row.unique_payload_bytes += bytes;
            row.unknown_capacity_payload_bytes += bytes;
        } else {
            row.shared_encounters += 1;
        }
        row.unknown.insert("collection node/bucket backing capacity unavailable; entry bytes are logical lower bounds".into());
    }
    /// Vec backing contains inline element descriptors. Nested heap buffers are
    /// counted separately, without adding those descriptors again.
    pub fn vec_payload<T>(&mut self, owner: &str, values: &Vec<T>) -> bool {
        self.owner(owner).observed_items += values.len() as u64;
        self.buffer(
            owner,
            values.as_ptr() as usize,
            values.len().saturating_mul(size_of::<T>()),
            values.capacity().saturating_mul(size_of::<T>()),
        )
    }
    pub(crate) fn slice<T>(&mut self, owner: &str, values: &[T], exact_capacity: bool) -> bool {
        self.owner(owner).observed_items += values.len() as u64;
        if !exact_capacity {
            self.unknown(
                owner,
                "backing capacity unavailable; logical slice length is a lower bound",
            );
        }
        let bytes = values.len().saturating_mul(size_of::<T>());
        if exact_capacity {
            self.buffer(owner, values.as_ptr() as usize, bytes, bytes)
        } else if bytes != 0 {
            let first = self.allocations.insert(values.as_ptr() as usize);
            let row = self.owner(owner);
            if first {
                row.unique_payload_bytes += bytes as u64;
                row.unknown_capacity_payload_bytes += bytes as u64;
                row.unique_allocations += 1;
            } else {
                row.shared_encounters += 1;
            }
            first
        } else {
            false
        }
    }
    pub(crate) fn string(&mut self, owner: &str, value: &String) {
        self.buffer(
            owner,
            value.as_ptr() as usize,
            value.len(),
            value.capacity(),
        );
    }
    fn macro_trace(&mut self, owner: &str, expansion: &dm_preprocess::regions::MacroExpansion) {
        self.arc_text(owner, &expansion.name);
        let chain = &expansion.replacement_chain;
        if self.buffer(
            owner,
            chain.as_ptr() as usize,
            std::mem::size_of_val(chain.as_ref()),
            std::mem::size_of_val(chain.as_ref()),
        ) {
            for name in chain.iter() {
                self.arc_text(owner, name);
            }
        }
    }
    pub fn arc_text(&mut self, owner: &str, value: &Arc<str>) {
        self.buffer(owner, value.as_ptr() as usize, value.len(), value.len());
    }
    pub(crate) fn arc_object<T>(&mut self, owner: &str, value: &Arc<T>) -> bool {
        self.buffer(
            owner,
            Arc::as_ptr(value) as usize,
            size_of::<T>(),
            size_of::<T>(),
        )
    }
    pub(crate) fn path(&mut self, owner: &str, value: &PathBuf) {
        self.buffer(
            owner,
            value.as_os_str().as_encoded_bytes().as_ptr() as usize,
            value.as_os_str().as_encoded_bytes().len(),
            value.capacity(),
        );
    }
    pub(crate) fn arc_path(&mut self, owner: &str, value: &Arc<PathBuf>) {
        if self.arc_object(owner, value) {
            self.path(owner, value);
        }
    }
    fn strings(&mut self, owner: &str, values: &Vec<String>) {
        if self.vec_payload(owner, values) {
            for value in values {
                self.string(owner, value);
            }
        }
    }
    pub fn output_encoded(&mut self, owner: &str, image: &byond_dmb::dmb::EncodedDmb) {
        self.owner(owner).observed_items += image.len() as u64;
        if self.arc_object(owner, image.shared_bytes()) {
            self.vec_payload(owner, image.shared_bytes());
        }
        self.unknown(
            owner,
            "shared encoded Arc control block/allocator overhead is unavailable",
        );
    }
    pub fn output_resources(&mut self, owner: &str, image: &byond_dmb::rsc::EncodedRsc) {
        self.owner(owner).observed_items += image.len() as u64;
        self.buffer(
            owner,
            image.bytes().as_ptr() as usize,
            image.len(),
            image.capacity(),
        );
    }
    pub fn output_buffer(&mut self, owner: &str, bytes: &Vec<u8>) {
        self.vec_payload(owner, bytes);
    }
    pub fn frontend(&mut self, frontend: &dm_tree::frontend::ColdFrontend) {
        let owner = "frontend.source_text";
        for (path, text) in &frontend.plan.source_texts {
            self.path(owner, path);
            self.source_text(owner, text);
        }
        for (path, starts) in &frontend.plan.source_line_starts {
            self.path(owner, path);
            self.slice(owner, starts, true);
        }
        self.unknown(
            owner,
            "source_texts/source_line_starts BTreeMap node allocations are private",
        );
        self.slice(owner, &frontend.files, true);
        for file in frontend.files.iter() {
            self.source_text(owner, &file.text);
            self.arc_path(owner, &file.path);
            self.slice(owner, &file.line_starts, true);
        }
        self.source_text("frontend.expanded_text", &frontend.expanded.text);
        self.vec_payload("frontend.expanded_tokens", &frontend.expanded.tokens);
        frontend
            .expanded
            .origins
            .visit_storage(|pointer, items, bytes| {
                self.owner("frontend.expanded_provenance").observed_items += items as u64;
                self.buffer("frontend.expanded_provenance", pointer, bytes, bytes);
            });
        for origin in &frontend.expanded.origins {
            self.arc_path("frontend.expanded_provenance", origin.origin.path);
            if self.arc_object("frontend.macro_expansions", origin.macro_expansions)
                && self.vec_payload("frontend.macro_expansions", origin.macro_expansions)
            {
                for expansion in origin.macro_expansions.iter() {
                    self.macro_trace("frontend.macro_expansions", expansion);
                }
            }
        }
        self.vec_payload(
            "frontend.expanded_provenance",
            &frontend.expanded.emission_regions,
        );
        self.vec_payload("frontend.expansion_receipts", &frontend.expanded.receipts);
        self.unknown(
            "frontend.expansion_receipts",
            "private receipt-owned nested models and memo backing are not exposed",
        );
        self.vec_payload("frontend.directive_plan", &frontend.plan.occurrences);
        self.vec_payload("frontend.directive_plan", &frontend.plan.regions);
        self.vec_payload("frontend.directive_plan", &frontend.plan.items);
        self.vec_payload("frontend.directive_plan", &frontend.plan.file_dirs);
        for path in &frontend.plan.file_dirs {
            self.path("frontend.directive_plan", path);
        }
        for path in &frontend.plan.dependencies {
            self.path("frontend.directive_plan", path);
        }
        self.path("frontend.directive_plan", &frontend.plan.project_dir);
        for (name, definition) in &frontend.plan.final_macros {
            self.string("frontend.macros", name);
            self.string("frontend.macros", &definition.replacement);
            if let Some(parameters) = &definition.parameters {
                self.strings("frontend.macros", parameters);
            }
        }
        for occurrence in &frontend.plan.occurrences {
            self.arc_path("frontend.directive_plan", &occurrence.path);
            self.arc_text("frontend.directive_plan", &occurrence.semantic_path);
        }
        for region in &frontend.plan.regions {
            self.vec_payload("frontend.directive_plan", &region.effects);
            self.vec_payload("frontend.directive_plan", &region.segments);
            for segment in &region.segments {
                self.vec_payload("frontend.directive_plan", &segment.lines);
                for line in &segment.lines {
                    self.source_text("frontend.directive_plan", &line.text);
                }
            }
        }
        self.macro_environments(frontend);
        self.unknown(
            "frontend.directive_plan",
            "private hash indexes and persistent macro map nodes are not exposed",
        );
        self.declaration_syntax("frontend.declaration_ast", &frontend.syntax);
        self.slice("frontend.body_index", &frontend.bodies, true);
        for body in frontend.bodies.iter() {
            self.slice("frontend.body_index", &body.ast_path, true);
            self.slice("frontend.body_index", &body.setting_context_origins, true);
            self.source_location("frontend.body_index", &body.source);
            for location in body.setting_context_origins.iter() {
                self.source_location("frontend.body_index", location);
            }
        }
        self.slice("frontend.body_index", &frontend.emission_order, true);
        self.unknown(
            "frontend.body_index",
            "private issued bodies/source indexes are not exposed",
        );
        if self.arc_object("frontend.allocation_ledger", &frontend.allocation_ledger) {
            frontend
                .allocation_ledger
                .events
                .visit_storage(|pointer, items, bytes| {
                    let owner = "frontend.allocation_ledger";
                    self.owner(owner).observed_items += items as u64;
                    self.buffer(owner, pointer, bytes, bytes);
                });
        }
        self.snapshot(&frontend.snapshot);
    }
    pub fn syntax(&mut self, owner: &str, syntax: &Arc<dm_syntax::AstFile>) {
        if !self.arc_object(owner, syntax) {
            return;
        }
        self.items(owner, &syntax.items);
        if self.vec_payload(owner, &syntax.tokens) {
            for token in &syntax.tokens {
                self.string(owner, &token.text);
            }
        }
        if self.vec_payload(owner, &syntax.diagnostics) {
            for diagnostic in &syntax.diagnostics {
                self.string(owner, &diagnostic.message);
            }
        }
    }
    pub fn items(&mut self, owner: &str, items: &Vec<dm_syntax::Item>) {
        if !self.vec_payload(owner, items) {
            return;
        }
        let mut pending: Vec<_> = items.iter().collect();
        while let Some(item) = pending.pop() {
            self.string(owner, &item.header);
            if self.vec_payload(owner, &item.children) {
                pending.extend(item.children.iter());
            }
        }
    }
    fn source_location(&mut self, owner: &str, location: &dm_tree::frontend::SourceLocation) {
        self.arc_path(owner, &location.path);
        self.arc_text(owner, &location.semantic_path);
        self.slice(owner, &location.include_chain, true);
        self.unknown(
            owner,
            "source-location macro expansion payloads are shared with expansion provenance",
        );
    }
    pub fn snapshot(&mut self, snapshot: &dm_tree::TreeSnapshot) {
        let owner = "semantic_tree";
        if self.arc_object(owner, &snapshot.tree) {
            let tree = &snapshot.tree;
            effective_metadata::selections(self, tree);
            self.slice(owner, tree.types(), true);
            for node in tree.types() {
                self.slice(owner, &node.members, true);
            }
            let chunks = tree.members().chunks();
            self.owner(owner).observed_items += chunks.len() as u64;
            self.buffer(
                owner,
                chunks.as_ptr() as usize,
                chunks
                    .len()
                    .saturating_mul(size_of::<Arc<[dm_tree::MemberNode]>>()),
                tree.members()
                    .chunk_roster_capacity()
                    .saturating_mul(size_of::<Arc<[dm_tree::MemberNode]>>()),
            );
            for chunk in chunks {
                self.slice(owner, chunk, true);
            }
            for member in tree.members() {
                if self.arc_object("semantic_metadata", &member.metadata) {
                    self.declaration(&member.metadata);
                }
            }
            self.slice(owner, tree.declarations(), true);
            let symbols = tree.shared_symbols();
            self.symbols(&symbols);
            self.unknown(owner, "private resolver inventories, by_path/direct hash tables, and intrinsic field map backing");
        }
        if self.arc_object("semantic_occurrences", &snapshot.occurrences) {
            self.slice(
                "semantic_occurrences",
                snapshot.occurrences.source_order(),
                true,
            );
            for occurrence in snapshot.occurrences.source_order() {
                self.slice(
                    "semantic_occurrences",
                    &occurrence.provenance.expansion_stack,
                    true,
                );
            }
            snapshot
                .occurrences
                .visit_target_index_storage(|pointer, _, bytes| {
                    self.buffer("semantic_occurrence_index", pointer, bytes, bytes);
                });
            self.unknown(
                "semantic_occurrence_index",
                "private target HashMap bucket backing and shared Arc control blocks excluded",
            );
        }
    }
    fn symbols(&mut self, symbols: &Arc<dm_ir::SymbolTable>) {
        if !self.arc_object("semantic_symbols", symbols) {
            return;
        }
        self.symbol_table_storage("semantic_symbols", symbols);
        self.unknown(
            "semantic_symbols",
            "private symbol HashMap bucket allocations and Arc control blocks; spelling payload and shared ancestor owners are counted",
        );
    }
    fn expression(&mut self, owner: &str, value: &dm_ir::SymbolicExpression) {
        self.slice(owner, &value.tokens, true);
    }
    fn array(&mut self, owner: &str, array: &Arc<dm_ir::ArrayDeclaration>) {
        if self.arc_object(owner, array) && self.slice(owner, &array.dimensions, true) {
            for expression in array.dimensions.iter().flatten() {
                self.expression(owner, expression);
            }
        }
    }
    fn procedure_metadata(&mut self, owner: &str, metadata: &Arc<dm_ir::ProcedureMetadata>) {
        if !self.arc_object(owner, metadata) {
            return;
        }
        let signature_owner = if owner == "semantic_metadata" {
            "semantic_metadata.signature"
        } else {
            owner
        };
        let settings_owner = if owner == "semantic_metadata" {
            "semantic_metadata.settings"
        } else {
            owner
        };
        self.slice(signature_owner, &metadata.signature.parameters, true);
        for parameter in metadata.signature.parameters.iter() {
            for expression in [
                &parameter.default,
                &parameter.input_annotation,
                &parameter.source_expression,
            ]
            .into_iter()
            .flatten()
            {
                self.expression(signature_owner, expression);
            }
            if let Some(array) = &parameter.array {
                self.array(signature_owner, array);
            }
        }
        if let Some(expression) = &metadata.signature.return_annotation {
            self.expression(signature_owner, expression);
        }
        let mut pending = vec![metadata.settings.as_ref()];
        while let Some(nodes) = pending.pop() {
            if !self.slice(settings_owner, nodes, true) {
                continue;
            }
            for node in nodes {
                match node {
                    dm_ir::ProcedureSettingNode::Setting(setting) => {
                        self.expression(settings_owner, &setting.value)
                    }
                    dm_ir::ProcedureSettingNode::Conditional {
                        condition,
                        then_branch,
                        else_branch,
                    } => {
                        self.expression(settings_owner, condition);
                        pending.push(then_branch);
                        pending.push(else_branch);
                    }
                    dm_ir::ProcedureSettingNode::UnsupportedContext {
                        canonical_header,
                        children,
                    } => {
                        self.expression(settings_owner, canonical_header);
                        pending.push(children);
                    }
                }
            }
        }
    }
    fn declaration(&mut self, declaration: &dm_ir::DeclarationMeaning) {
        let owner = "semantic_metadata";
        self.slice("semantic_metadata.canonical", &declaration.canonical, true);
        for expression in [&declaration.initializer, &declaration.declared_initializer]
            .into_iter()
            .flatten()
        {
            self.expression(owner, expression);
        }
        if let Some(array) = &declaration.array {
            self.array(owner, array);
        }
        if let Some(procedure) = &declaration.procedure {
            self.procedure_metadata(owner, procedure);
        }
        if let Some(value) = &declaration.resolved_constant {
            self.semantic_value(owner, value);
        }
    }
    pub(crate) fn semantic_value(&mut self, owner: &str, value: &dm_ir::SemanticValue) {
        let mut pending = vec![value];
        while let Some(value) = pending.pop() {
            match value {
                dm_ir::SemanticValue::Text(bytes) => {
                    self.slice(owner, bytes, true);
                }
                dm_ir::SemanticValue::List(entries) => {
                    if self.slice(owner, entries, true) {
                        for (key, value) in entries.iter() {
                            if let Some(key) = key {
                                pending.push(key);
                            }
                            pending.push(value);
                        }
                    }
                }
                dm_ir::SemanticValue::ModifiedInstance(instance)
                    if self.arc_object(owner, instance) =>
                {
                    self.slice(owner, instance.canonical_bytes(), true);
                    if self.slice(owner, instance.fields(), true) {
                        for (name, _) in instance.fields() {
                            self.string(owner, name);
                        }
                    }
                    self.unknown(owner, "modified-instance Expr nested boxes/strings and private resource map nodes");
                }
                dm_ir::SemanticValue::ModifiedInstance(_)
                | dm_ir::SemanticValue::Null
                | dm_ir::SemanticValue::NumberBits(_)
                | dm_ir::SemanticValue::Type(_)
                | dm_ir::SemanticValue::Procedure(_)
                | dm_ir::SemanticValue::Resource(_) => (),
            }
        }
    }
    pub fn startup(&mut self, startup: &crate::startup::CapturedStartup<'_>) {
        let facts = startup.facts();
        if !self.arc_object("startup", &facts) {
            return;
        }
        let units = startup.unit_members();
        if self.arc_object("startup.unit_members", units) {
            self.owner("startup.unit_members").observed_items += units.len() as u64;
            self.unknown("startup.unit_members", "private BTreeMap node capacity excluded; one shared authoritative procedure identity index");
        }
        startup_artifacts::inventory(self, startup.static_inventory());
        let plan = startup.plan();
        self.snapshot(&plan.source);
        self.symbols(&plan.symbols);
        self.slice("startup", &plan.writes, true);
        self.slice("startup", &plan.origins, true);
        for write in plan.writes.iter() {
            match &write.value {
                dm_ir::InitializerValue::Expression(expression) => {
                    self.expression("startup", expression)
                }
                dm_ir::InitializerValue::ArrayAllocation(array) => self.array("startup", array),
                dm_ir::InitializerValue::NoAuthoredValue => (),
            }
            if let Some(array) = &write.declared_array {
                self.array("startup", array);
            }
        }
        self.slice("startup", startup.procedure_captures(), false);
        for (_, capture) in startup.procedure_captures() {
            if let crate::startup::ProcedureCapture::Issued(receipt) = capture {
                self.static_receipt(receipt);
            }
        }
        for (_, procedure) in startup.procedures() {
            self.static_plan(procedure);
        }
        self.unknown(
            "startup",
            "private procedure index and symbol HashMap bucket allocation; spelling payloads and ancestor owners are counted",
        );
    }
    fn debug(&mut self, owner: &str, debug: &crate::debug_sources::DebugOrigins) {
        if self.vec_payload(owner, &debug.entries) {
            for entry in &debug.entries {
                self.arc_text(owner, &entry.semantic_path);
            }
        }
    }
    fn frozen_debug(&mut self, owner: &str, debug: &crate::debug_sources::FrozenDebugOrigins) {
        debug.census(self, owner);
    }
    pub(crate) fn abi(&mut self, abi: &Arc<crate::procedure_policy::PreparedAbi>) {
        let owner = "procedure_abi";
        if !self.arc_object(owner, abi) {
            return;
        }
        if let Some(bytes) = &abi.layout.display_name {
            self.vec_payload(owner, bytes);
        }
        if let Some(bytes) = &abi.layout.description {
            self.vec_payload(owner, bytes);
        }
        if let dm_codegen_byond::procedure_abi::Category::Text(bytes) = &abi.layout.category {
            self.vec_payload(owner, bytes);
        }
        self.vec_payload(owner, &abi.argument_sources);
        self.vec_payload(owner, &abi.source_helpers);
        for helper in &abi.source_helpers {
            self.expression(owner, &helper.expression);
            self.strings(owner, &helper.frame_parameters);
        }
    }
    fn resolver_code(&mut self, code: &dm_codegen_byond::lower_resolver::ResolverProc) {
        let owner = "lowered_code";
        let procedure = &code.procedure;
        self.vec_payload(owner, &procedure.code.items);
        for item in &procedure.code.items {
            if let dm_codegen_byond::Item::Instruction(instruction) = item {
                self.vec_payload(owner, &instruction.operands);
                for word in &instruction.operands {
                    if let dm_codegen_byond::Word::Variable(variable) = word {
                        self.variable_boxes(variable);
                    }
                }
            }
        }
        self.vec_payload("lowered_strings", &procedure.strings);
        for payload in &procedure.strings {
            self.slice("lowered_strings", &payload.bytes, true);
        }
        self.vec_payload(owner, &procedure.class_paths);
        self.vec_payload(owner, &procedure.instance_paths);
        self.vec_payload(owner, &procedure.resources);
        self.strings(owner, &procedure.local_names);
        self.strings(owner, &procedure.argument_names);
        self.vec_payload(owner, &procedure.argument_type_flags);
        self.vec_payload(owner, &procedure.argument_value_sources);
        for captured in code.modified_instances.values() {
            self.vec_payload(owner, &captured.field_origins);
            self.slice(owner, captured.descriptor.canonical_bytes(), true);
        }
        self.unknown(
            owner,
            "resolver BTreeMap nodes and modified-instance nested expression buffers not exposed",
        );
    }
    fn variable_boxes(&mut self, variable: &dm_codegen_byond::VariableWord) {
        let mut pending = vec![variable];
        while let Some(variable) = pending.pop() {
            match variable {
                dm_codegen_byond::VariableWord::Initial(value)
                | dm_codegen_byond::VariableWord::IsSaved(value) => {
                    self.buffer(
                        "lowered_code",
                        value.as_ref() as *const _ as usize,
                        size_of::<dm_codegen_byond::VariableWord>(),
                        size_of::<dm_codegen_byond::VariableWord>(),
                    );
                    pending.push(value);
                }
                dm_codegen_byond::VariableWord::SetCache(a, b) => {
                    for value in [a, b] {
                        self.buffer(
                            "lowered_code",
                            value.as_ref() as *const _ as usize,
                            size_of::<dm_codegen_byond::VariableWord>(),
                            size_of::<dm_codegen_byond::VariableWord>(),
                        );
                        pending.push(value);
                    }
                }
                _ => (),
            }
        }
    }
    pub fn lowered(&mut self, batch: &crate::lowering::LoweringBatch) {
        self.vec_payload("lowered_units", &batch.units);
        self.vec_payload("lowered_units", &batch.diagnostics);
        for unit in &batch.units {
            self.resolver_code(&unit.code);
            self.procedure_metadata("semantic_metadata", &unit.metadata);
            if let Some(abi) = &unit.abi {
                self.abi(abi);
            }
            self.debug("lowered_units", &unit.debug_origins);
            self.source_location("lowered_units", &unit.origin.source);
            self.vec_payload("lowered_units", &unit.source_helpers);
            for helper in &unit.source_helpers {
                self.resolver_code(&helper.code);
                self.debug("lowered_units", &helper.debug_origins);
            }
        }
        for diagnostic in &batch.diagnostics {
            self.string("lowered_units", &diagnostic.message);
        }
    }
    pub(crate) fn entry_content(&mut self, owner: &str, content: &dm_link::EntryContent) {
        match content {
            dm_link::EntryContent::Bytes(bytes) => {
                self.slice(owner, bytes, true);
            }
            dm_link::EntryContent::Symbolic(content) => {
                if self.arc_object(owner, content) {
                    let (prefix, code, suffix) = content.parts();
                    self.slice(owner, prefix, true);
                    self.symbolic_code(code);
                    self.slice(owner, suffix, true);
                    if let Some(bytes) = content.materialized_bytes() {
                        self.slice(owner, bytes, true);
                    }
                }
            }
        }
    }
    fn symbolic_code(&mut self, code: &Arc<dm_ir::SymbolicCode>) {
        if self.arc_object("frozen_code", code) {
            self.frozen_code_metrics.observe(code);
            self.owner("frozen_code").observed_items +=
                (code.words().len() + code.relocations().len()) as u64;
            code.visit_storage(|address, length, capacity| {
                self.buffer("frozen_code", address, length, capacity);
            });
        }
    }
    fn frozen_code(&mut self, code: &Arc<dm_codegen_byond::FrozenProc>) {
        if !self.arc_object("frozen_code", code) {
            return;
        }
        self.symbolic_code(&code.shared_code());
        self.slice("frozen_code", code.labels(), false);
    }
    pub fn frozen(&mut self, batch: &crate::symbolic::FrozenBatch) {
        batch.census_current_images(self);
        self.vec_payload("frozen_units", &batch.units);
        self.vec_payload("frozen_units", &batch.helpers);
        self.vec_payload("frozen_units", &batch.initializers);
        for unit in &batch.units {
            self.latest_image(unit.latest_image());
            crate::composition::ProcedureMetadataRecipe::census(&unit.metadata_recipe, self);
            self.frozen_code(&unit.frozen);
            self.frozen_debug("frozen_units", &unit.lowered.debug_origins);
            self.frozen_frame("frozen_units", &unit.lowered.frame);
            if let Some(abi) = &unit.lowered.abi {
                self.abi(abi);
            }
        }
        for helper in &batch.helpers {
            self.latest_image(helper.latest_image());
            self.frozen_code(&helper.frozen);
            self.frozen_debug("frozen_units", &helper.debug_origins);
            self.strings("frozen_units", &helper.local_names);
        }
        for initializer in &batch.initializers {
            self.latest_image(initializer.latest_image());
            self.frozen_code(&initializer.frozen);
            self.frozen_debug("frozen_units", &initializer.debug_origins);
            self.strings("frozen_units", &initializer.local_names);
        }
        self.owner("link_tables").observed_items += batch.tables.assignments().len() as u64;
        for &key in batch.tables.assignments().keys() {
            if let Some(content) = batch.tables.content_value(key) {
                self.entry_content("link_tables", content);
            }
        }
        self.unknown("link_tables", "private Arc/BTreeMap node backing and slot maps; current image words and certificate rosters are counted separately");
    }
    pub fn dmb(&mut self, dmb: &byond_dmb::dmb::Dmb) {
        self.dmb_image(dmb);
    }
    pub fn resources(&mut self, captured: &dm_resources::capture::CapturedResources) {
        self.resource_set(&captured.resources);
        let owner = "resource_capture";
        self.slice(owner, captured.context.bytes(), true);
        self.vec_payload(owner, &captured.lookups);
        for lookup in &captured.lookups {
            self.string(owner, &lookup.path);
        }
        self.vec_payload(owner, &captured.observations);
        for observation in &captured.observations {
            self.path(owner, &observation.path);
        }
        self.vec_payload(owner, &captured.literals);
        for literal in &captured.literals {
            self.string(owner, &literal.path);
        }
        self.vec_payload(owner, &captured.unsupported);
        for unsupported in &captured.unsupported {
            self.string(owner, &unsupported.path);
        }
    }
    pub fn resource_set(&mut self, resources: &dm_resources::ResourceSet) {
        self.vec_payload("resource_records", &resources.inputs);
        for input in &resources.inputs {
            self.string("resource_records", &input.archive_name);
            self.path("resource_records", &input.disk_path);
            self.vec_payload("resource_records", &input.named.name);
            let bytes = input.named.shared_data().shared_owner();
            if self.arc_object("resource_payloads", bytes) {
                self.vec_payload("resource_payloads", bytes.bytes());
            }
        }
    }
    pub fn finish(self) -> HeapCensusReport {
        let owners: Vec<_> = self.owners.into_values().collect();
        HeapCensusReport {
            schema: 1,
            stage: self.stage,
            scope: "retained_accessible_container_payload_and_capacity_not_total_heap",
            unique_known_capacity_bytes: owners
                .iter()
                .map(|owner| owner.unique_known_capacity_bytes)
                .sum(),
            unknown_capacity_payload_bytes: owners
                .iter()
                .map(|owner| owner.unknown_capacity_payload_bytes)
                .sum(),
            owners,
            frozen_code_metrics: self.frozen_code_metrics,
            limitations: vec![
                "Shared allocations are deduplicated by live pointer and attributed to the first named owner in this boundary.",
                "Vec capacities include inline element descriptors; nested heap buffers are counted separately, never those descriptors twice.",
                "Arc control blocks, allocator size-class rounding/metadata, stack storage, private indexes, and explicitly unknown backing are excluded.",
                "Slices without exposed capacity contribute logical-length lower bounds, marked in their owner; this is not a complete heap or RSS total.",
                "The census is diagnostic-only, opt-in, and O(accessible retained nodes); its temporary pointer ledger is excluded.",
            ],
        }
    }
}

/// No structure walks, allocation hooks, or output happen unless explicitly
/// enabled. The caller chooses one boundary's complete set of live owners.
pub fn emit_if_enabled(stage: &str, observe: impl FnOnce(&mut HeapCensus)) -> io::Result<()> {
    let Some(path) = std::env::var_os("DMB_HEAP_CENSUS_PATH").filter(|path| !path.is_empty())
    else {
        return Ok(());
    };
    let mut census = HeapCensus::new(stage);
    observe(&mut census);
    let mut bytes = serde_json::to_vec(&census.finish()).map_err(io::Error::other)?;
    bytes.push(b'\n');
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)?;
    file.write_all(&bytes)
}

#[cfg(test)]
#[path = "heap_census/tests.rs"]
mod tests;

#[path = "heap_census/static_plan.rs"]
mod static_plan;

#[path = "heap_census/body_arena.rs"]
mod body_arena;

mod generation;
