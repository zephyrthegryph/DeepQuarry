use super::*;

impl Builder<'_> {
    pub(super) fn instance(&mut self, object: &OpenDreamMapObject) -> Result<u32, EmitError> {
        let prototype = *self
            .ids
            .instances
            .get(object.type_id)
            .ok_or_else(|| EmitError::Invalid("map object type ID out of range".into()))?;
        let prototype_record = if prototype == NONE {
            if self.input.native_type_tag(object.type_id) != Some(32) {
                return Err(EmitError::Unsupported(
                    "map object type has no BYOND instance prototype".into(),
                ));
            }
            // Paired modified datum paths have kind32 instances, without
            // requiring an extra unmodified datum prototype in the table.
            Instance {
                kind: 32,
                class: self.ids.classes[object.type_id],
                initializer: NONE,
            }
        } else {
            self.dmb.instances[prototype as usize].clone()
        };
        let mut ordered_overrides: Vec<_> = if object.override_order.is_empty() {
            let mut entries: Vec<_> = object.var_overrides.iter().collect();
            entries.sort_by_key(|(name, _)| *name);
            entries
        } else {
            let mut seen = HashSet::new();
            let mut entries = Vec::with_capacity(object.override_order.len());
            for name in &object.override_order {
                if !seen.insert(name) {
                    return Err(EmitError::Unsupported(format!(
                        "map object repeats override {name}; OpenDream JSON retains only its final value"
                    )));
                }
                let value = object.var_overrides.get(name).ok_or_else(|| {
                    EmitError::Invalid(format!("map override order names missing field {name}"))
                })?;
                entries.push((name, value));
            }
            if entries.len() != object.var_overrides.len() {
                return Err(EmitError::Invalid(
                    "map override order omits an override field".into(),
                ));
            }
            entries
        };
        let class_id = if prototype_record.kind == 8 {
            self.dmb.mobs[prototype_record.class as usize].class
        } else {
            prototype_record.class
        };
        // Dream Maker's DMM initializer writes fields in target declaration
        // order. The source map's assignment order does not affect its code
        // or instance deduplication (paired reversed-order DMM fixture).
        ordered_overrides.sort_by_key(|(name, _)| {
            if let Some(var_id) = self.inherited_variable(class_id, name) {
                (1u8, self.predicted_variable_ids[var_id as usize])
            } else {
                let builtin_rank = match name.as_str() {
                    "name" => 0,
                    "desc" => 1,
                    "icon" => 2,
                    "icon_state" => 3,
                    "dir" => 4,
                    "pixel_x" => 5,
                    "pixel_y" => 6,
                    "layer" => 7,
                    _ => 100,
                };
                (0u8, builtin_rank)
            }
        });
        let signature = if ordered_overrides.is_empty() {
            None
        } else {
            let entries: Vec<_> = ordered_overrides
                .iter()
                .map(|(name, value)| ((*name).clone(), value.to_string()))
                .collect();
            Some((prototype_record.kind, prototype_record.class, entries))
        };
        if let Some(key) = &signature {
            if let Some(&id) = self.map_instance_index.get(key) {
                return Ok(id);
            }
        }
        let mut candidate = prototype_record;
        let initializer = if ordered_overrides.is_empty() {
            NONE
        } else {
            let mut code = Vec::new();
            for (name, json) in ordered_overrides.drain(..) {
                self.push_map_constant(json, &mut code)?;
                code.extend([0x34, 0xffdc, 0xffce, self.string(name)]);
            }
            code.push(0);
            if let Some(&proc_id) = self.map_initializer_index.get(&code) {
                proc_id
            } else {
                let code_id = self.list(code.clone());
                let empty = self.list(Vec::new());
                self.reserve_proc_sentinel();
                let proc_id = self.dmb.procs.len() as u32;
                self.dmb.procs.push(Proc {
                    strings: [NONE; 4],
                    source_parameter: 255,
                    source_kind: 0,
                    flags: 4,
                    extended_flags: None,
                    code_locals_args: [code_id, empty, empty],
                });
                self.map_initializer_index.insert(code, proc_id);
                proc_id
            }
        };
        candidate.initializer = initializer;
        let key = (candidate.kind, candidate.class, candidate.initializer);
        if let Some(&existing) = self.instance_index.get(&key) {
            if let Some(signature) = signature {
                self.map_instance_index.insert(signature, existing);
            }
            return Ok(existing);
        }
        if self.dmb.instances.len() >= NONE as usize {
            return Err(EmitError::Invalid(
                "instance table reaches native unsupported ID 65535".into(),
            ));
        }
        let id = self.dmb.instances.len() as u32;
        self.dmb.instances.push(candidate);
        self.instance_index.insert(key, id);
        if let Some(signature) = signature {
            self.map_instance_index.insert(signature, id);
        }
        Ok(id)
    }
    pub(super) fn push_map_constant(
        &mut self,
        json: &JsonValue,
        code: &mut Vec<u32>,
    ) -> Result<(), EmitError> {
        if let Some(ModifiedTypeParts {
            path,
            overrides,
            order: override_order,
        }) = modified_type_json(json)?
        {
            let type_id = self
                .input
                .types
                .iter()
                .position(|typ| typ.path == path)
                .ok_or_else(|| {
                    EmitError::Invalid(format!(
                        "modified map type target {path} is absent from Types"
                    ))
                })?;
            let instance = self.instance(&OpenDreamMapObject {
                type_id,
                var_overrides: overrides,
                override_order,
            })?;
            code.push(0x60);
            code.extend(
                Value {
                    tag_word: 41,
                    data_word: instance,
                    extra_word: None,
                }
                .encode(),
            );
            return Ok(());
        }
        if json.get("type").and_then(JsonValue::as_u64) == Some(3) {
            let values = json
                .get("values")
                .and_then(JsonValue::as_array)
                .ok_or_else(|| EmitError::Invalid("list constant has no values".into()))?;
            let associative = values.iter().any(|value| value.get("key").is_some());
            for (index, value) in values.iter().enumerate() {
                if associative {
                    if let Some(key) = value.get("key") {
                        let item = value.get("value").ok_or_else(|| {
                            EmitError::Invalid("associative list entry has no value".into())
                        })?;
                        self.push_map_constant(key, code)?;
                        self.push_map_constant(item, code)?;
                    } else {
                        self.push_map_constant(&JsonValue::from(index + 1), code)?;
                        self.push_map_constant(value, code)?;
                    }
                } else {
                    self.push_map_constant(value, code)?;
                }
            }
            code.extend([if associative { 0xc8 } else { 0x1a }, values.len() as u32]);
            return Ok(());
        }
        let value = self.constant(json)?;
        if let Some(bits) = value.number_bits() {
            let number = f32::from_bits(bits);
            // PushInt reads an unsigned 16-bit operand in the native VM.
            // Negative or wider integers must retain their floating value.
            if number.fract() == 0.0 && (0.0..=u16::MAX as f32).contains(&number) {
                code.extend([0x50, number as u32]);
                return Ok(());
            }
        }
        code.push(0x60);
        code.extend(value.encode());
        Ok(())
    }
    pub(super) fn build_maps(&mut self) -> Result<(), EmitError> {
        // Authored dimensions create a default grid before included map levels.
        // Included maps replace its X/Y extent and append after its Z levels.
        let world = self.input.types.iter().find(|typ| typ.path == "/world");
        let mut generated = [0i32; 3];
        for (axis, name) in ["maxx", "maxy", "maxz"].iter().enumerate() {
            if let Some(value) = world.and_then(|typ| typ.variables.get(*name)) {
                if value.is_null()
                    && world.is_none_or(|typ| !typ.explicit_world_fields.contains(*name))
                {
                    continue;
                }
                let number = value
                    .as_f64()
                    .filter(|v| v.is_finite() && *v >= 0.0 && *v <= u16::MAX as f64)
                    .ok_or_else(|| {
                        EmitError::Unsupported(format!("world.{name} must be between 0 and 65535"))
                    })?;
                generated[axis] = number.trunc() as i32;
            }
        }
        if generated.iter().any(|&d| d > 0) {
            generated = generated.map(|d| d.max(1));
        }
        if self.input.maps.is_empty() && generated == [0; 3] {
            return Ok(());
        }
        let map_z_offset = if self.input.maps.is_empty() {
            0
        } else {
            generated[2]
        };
        let mut dims = if self.input.maps.is_empty() {
            generated
        } else {
            [0; 3]
        };
        for map in &self.input.maps {
            dims[0] = dims[0].max(map.max_x);
            dims[1] = dims[1].max(map.max_y);
            dims[2] = dims[2].max(map.max_z);
        }
        dims[2] = dims[2]
            .checked_add(map_z_offset)
            .ok_or_else(|| EmitError::Invalid("combined map Z dimensions overflow".into()))?;
        if dims.iter().any(|&d| d <= 0 || d > u16::MAX as i32) {
            return Err(EmitError::Invalid(
                "invalid OpenDream map dimensions".into(),
            ));
        }
        self.dmb.dimensions = dims.map(|d| d as u16);
        let count = dims
            .iter()
            .try_fold(1usize, |a, &b| a.checked_mul(b as usize))
            .ok_or_else(|| EmitError::Invalid("map cell count overflows usize".into()))?;
        let mut cells: Vec<Option<(u32, u32)>> = vec![None; count];
        let mut objects = Vec::<(usize, u32)>::new();
        for map in &self.input.maps {
            for block in &map.blocks {
                let expected = block
                    .width
                    .checked_mul(block.height)
                    .filter(|&n| n > 0)
                    .ok_or_else(|| EmitError::Invalid("invalid map block dimensions".into()))?
                    as usize;
                if block.cells.len() != expected {
                    return Err(EmitError::Invalid("map block cell count mismatch".into()));
                }
                for dy in 0..block.height {
                    for dx in 0..block.width {
                        let key = &block.cells[(dy * block.width + dx) as usize];
                        let cell = map.cell_definitions.get(key).ok_or_else(|| {
                            EmitError::Invalid(format!("missing map cell definition {key}"))
                        })?;
                        if cell.name != key.as_str() {
                            return Err(EmitError::Invalid(format!(
                                "map cell definition {key} has mismatched Name {}",
                                cell.name
                            )));
                        }
                        let x = block.x + dx;
                        // DMM block rows are written top to bottom while the DMB
                        // linear grid starts at the bottom row of each z-level.
                        let y = block.y + block.height - 1 - dy;
                        let z = block.z + map_z_offset;
                        if x < 1 || y < 1 || z < 1 || x > dims[0] || y > dims[1] || z > dims[2] {
                            return Err(EmitError::Invalid("map block outside dimensions".into()));
                        }
                        let turf = match &cell.turf {
                            Some(obj) => self.instance(obj)?,
                            None => NONE,
                        };
                        let area = match &cell.area {
                            Some(obj) => self.instance(obj)?,
                            None => NONE,
                        };
                        let index =
                            ((z - 1) * dims[0] * dims[1] + (y - 1) * dims[0] + (x - 1)) as usize;
                        for obj in &cell.objects {
                            objects.push((index, self.instance(obj)?));
                        }
                        if cells[index].replace((turf, area)).is_some() {
                            return Err(EmitError::Unsupported("overlapping map blocks".into()));
                        }
                    }
                }
            }
        }
        if cells.iter().any(Option::is_none) {
            // Dream Maker fills unallocated coordinates with world.turf and
            // world.area prototypes, including skipped z-levels.
            let default_instance = |class: u32| {
                self.dmb
                    .instances
                    .iter()
                    .position(|instance| instance.class == class)
                    .map(|id| id as u32)
            };
            let turf = default_instance(self.dmb.world.turf_class_id())
                .ok_or_else(|| EmitError::Invalid("world.turf has no instance prototype".into()))?;
            let area = default_instance(self.dmb.world.area_class_id())
                .ok_or_else(|| EmitError::Invalid("world.area has no instance prototype".into()))?;
            for cell in &mut cells {
                cell.get_or_insert((turf, area));
            }
        }
        for (turf, area) in cells.into_iter().flatten() {
            match self.dmb.grid.last_mut() {
                Some(run)
                    if run.turf == turf
                        && run.area == area
                        && run.contents == NONE
                        && run.copies < u8::MAX =>
                {
                    run.copies += 1
                }
                _ => self.dmb.grid.push(GridRun {
                    turf,
                    area,
                    contents: NONE,
                    copies: 1,
                }),
            }
        }
        objects.sort_by_key(|record| record.0);
        let mut prior = 0usize;
        for (index, instance) in objects {
            let delta = index - prior;
            let offset = u16::try_from(delta)
                .map_err(|_| EmitError::Unsupported("map object offset exceeds u16".into()))?;
            self.dmb.map_objects.push(MapObject { offset, instance });
            prior = index;
        }
        Ok(())
    }
}
