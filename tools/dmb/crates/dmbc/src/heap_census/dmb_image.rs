//! Physical owned DMB buffers, without allocating decoded argument/debug models.
use super::*;
use byond_dmb::dmb::Dmb;

impl HeapCensus {
    /// Counts actual Vec capacities. Shared list storage belongs to the first
    /// encountered role; role names describe consumers, not semantic validation.
    /// Debug instructions, procedure arguments and locals remain encoded in
    /// list words: decoding them here would measure census-created allocations.
    pub fn dmb_image(&mut self, dmb: &Dmb) {
        self.vec_payload("dmb_grid", &dmb.grid);
        self.vec_payload("dmb_classes", &dmb.classes);
        self.vec_payload("dmb_mobs", &dmb.mobs);
        self.vec_payload("dmb_procedures", &dmb.procs);
        self.vec_payload("dmb_variables", &dmb.variables);
        self.vec_payload("dmb_procedure_references", &dmb.proc_references);
        self.vec_payload("dmb_instances", &dmb.instances);
        self.vec_payload("dmb_map_objects", &dmb.map_objects);
        self.vec_payload("dmb_resource_references", &dmb.resources);
        if self.vec_payload("dmb_strings", &dmb.strings) {
            for string in &dmb.strings {
                self.vec_payload("dmb_string_payloads", &string.data);
            }
        }
        if self.vec_payload("dmb_list_descriptors", dmb.lists.storage()) {
            for procedure in &dmb.procs {
                for (id, role) in procedure.code_locals_args.iter().zip([
                    "dmb_procedure_code_and_debug_words",
                    "dmb_procedure_local_words",
                    "dmb_procedure_argument_words",
                ]) {
                    self.dmb_list(dmb, *id, role);
                }
            }
            for class in &dmb.classes {
                for (id, role) in [
                    (class.proc_list_id(), "dmb_class_procedure_words"),
                    (class.verb_list_id(), "dmb_class_verb_words"),
                    (
                        class.initialized_variable_list_id(),
                        "dmb_class_value_words",
                    ),
                    (
                        class.defining_variable_list_id(),
                        "dmb_class_declaration_words",
                    ),
                    (
                        class.overriding_variable_list_id(),
                        "dmb_class_override_words",
                    ),
                ] {
                    self.dmb_list(dmb, id, role);
                }
            }
            self.dmb_list(dmb, dmb.world.proc_list_id(), "dmb_world_procedure_words");
            self.dmb_list(dmb, dmb.variable_footer, "dmb_global_declaration_words");
            for run in &dmb.grid {
                self.dmb_list(dmb, run.contents, "dmb_grid_contents_words");
            }
            // Include every list, including lists not reachable through the
            // consumer roles above. The buffer ledger prevents double counting.
            for list in dmb.lists.storage() {
                if self.arc_object("dmb_list_word_owners", list) {
                    self.vec_payload("dmb_other_list_words", list);
                }
            }
        }
        dmb.lists.visit_encoding(|address,size,words,image,ranges,len,capacity| {
            if self.buffer("dmb_list_encoding",address,size,size) {
                self.vec_payload("dmb_list_encoding_words",words);
                for words in words {
                    if self.arc_object("dmb_list_word_owners",words) {self.vec_payload("dmb_other_list_words",words);}
                }
                self.output_encoded("dmb_list_encoding_bytes",image);
                self.vec_payload("dmb_list_encoding_ranges",ranges);
                self.observe_items("dmb_list_encoding_owner_index",len);
                self.unknown("dmb_list_encoding_owner_index","HashMap private backing/control layout excluded; logical capacity is not byte size");
                let _=capacity;
            }
        });
        self.vec_payload("dmb_world", &dmb.world.client_script_files);
        self.vec_payload("dmb_header", &dmb.header.version_line);
        self.vec_payload("dmb_header", &dmb.header.compatibility_line);
        if let Some(bytes) = &dmb.header.executor_line {
            self.vec_payload("dmb_header", bytes);
        }
        self.unknown("dmb_image", "allocator rounding/metadata are unavailable; inline record fields are included in table Vec storage; resource archive payloads belong to separate resource owners; shared list Arc control blocks are unknown structural overhead");
    }

    fn dmb_list(&mut self, dmb: &Dmb, id: u32, role: &str) {
        if let Some(list) = dmb.lists.shared(id as usize) {
            if self.arc_object("dmb_list_word_owners", list) {
                self.vec_payload(role, list);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn image_counts_every_owned_buffer_once_without_decoding_lists() {
        let mut dmb = Dmb::from_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../fixtures/native_template.bin"
        )))
        .expect("native template");
        dmb.lists.push(Vec::with_capacity(37));
        dmb.strings[0].data.reserve(71);
        fn capacity<T>(values: &Vec<T>) -> usize {
            values.capacity() * size_of::<T>()
        }
        let expected = capacity(&dmb.grid)
            + capacity(&dmb.classes)
            + capacity(&dmb.mobs)
            + capacity(&dmb.procs)
            + capacity(&dmb.variables)
            + capacity(&dmb.proc_references)
            + capacity(&dmb.instances)
            + capacity(&dmb.map_objects)
            + capacity(&dmb.resources)
            + capacity(&dmb.strings)
            + dmb
                .strings
                .iter()
                .map(|value| capacity(&value.data))
                .sum::<usize>()
            + capacity(dmb.lists.storage())
            + dmb.lists.len() * size_of::<Vec<u32>>()
            + dmb.lists.iter().map(capacity).sum::<usize>()
            + capacity(&dmb.world.client_script_files)
            + capacity(&dmb.header.version_line)
            + capacity(&dmb.header.compatibility_line)
            + dmb.header.executor_line.as_ref().map(capacity).unwrap_or(0);
        let mut census = HeapCensus::new("composition.ready");
        census.dmb_image(&dmb);
        census.dmb(&dmb);
        let report = census.finish();
        assert_eq!(report.unique_known_capacity_bytes, expected as u64);
        assert_eq!(report.unknown_capacity_payload_bytes, 0);
        assert!(report.owners.iter().any(|owner| {
            owner.owner == "dmb_other_list_words"
                && owner.unique_known_capacity_bytes >= 37 * size_of::<u32>() as u64
        }));
    }
}
