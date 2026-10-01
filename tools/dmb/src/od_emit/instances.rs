use super::*;

impl Builder<'_> {
    pub(super) fn build_instances(&mut self) -> Result<(), EmitError> {
        self.ids.instances = vec![NONE; self.input.types.len()];
        let mut order: Vec<_> = (0..self.input.types.len()).collect();
        order.sort_by_key(|&id| {
            let mut depth = 0usize;
            let mut parent = self.input.types[id].parent;
            while let Some(index) = parent {
                depth += 1;
                if depth > self.input.types.len() {
                    break;
                }
                parent = self.input.types[index].parent;
            }
            depth
        });
        for od_id in order {
            let typ = &self.input.types[od_id];
            let class = self.ids.classes[od_id];
            if class == NONE {
                continue;
            }
            let path = typ.path.as_str();
            let tag = self
                .input
                .native_type_tag(od_id)
                .ok_or_else(|| EmitError::Invalid(format!("invalid ancestry for {path}")))?;
            let (kind, target) = if tag == 8 {
                let mob = if let Some(index) =
                    self.dmb.mobs.iter().position(|mob| mob.class == class)
                {
                    index as u32
                } else {
                    let parent_class = self.dmb.classes[class as usize].parent_class_id();
                    let parent = self
                        .dmb
                        .mobs
                        .iter()
                        .find(|mob| mob.class == parent_class)
                        .cloned()
                        .unwrap_or(MobType {
                            class,
                            key: NONE,
                            sight: 0,
                            extended_sight: None,
                        });
                    let mut record = parent;
                    record.class = class;
                    for (name, setting) in [("sight", 0), ("see_in_dark", 1), ("see_invisible", 2)]
                    {
                        let Some(json) = typ.variables.get(name) else {
                            continue;
                        };
                        let unchanged = self
                            .baseline
                            .and_then(|base| {
                                self.baseline_type_by_path
                                    .get(typ.path.as_str())
                                    .and_then(|&index| base.types.get(index))
                                    .map(|t| (base, t))
                            })
                            .and_then(|(base, t)| t.variables.get(name).map(|old| (base, old)))
                            .is_some_and(|(base, old)| {
                                same_od_constant(json, old, self.input, base)
                            });
                        if unchanged {
                            continue;
                        }
                        let number = json.as_u64().ok_or_else(|| {
                            EmitError::Unsupported(format!(
                                "mob {path} {name} requires a nonnegative integer"
                            ))
                        })?;
                        let mut bits = record.sight_bits();
                        // Compact records omit the effective built-in darkness
                        // range; promoting one must preserve Dream Maker's 2.
                        let mut dark = record.see_in_dark_setting().unwrap_or(2);
                        let mut invisible = record.see_invisible_setting().unwrap_or(0);
                        match setting {
                            0 => {
                                bits = u32::try_from(number).map_err(|_| {
                                    EmitError::Unsupported(format!("mob {path} sight exceeds u32"))
                                })?
                            }
                            // Dream Maker stores these in bytes and wraps
                            // large values: see_in_dark=1_000_000 -> 64.
                            1 => dark = number as u8,
                            _ => invisible = number as u8,
                        }
                        if record.extended_sight.is_some() || setting != 0 || bits > 0x7f {
                            record.sight = 0x80;
                            record.extended_sight = Some((bits, dark, invisible));
                        } else {
                            record.sight = bits as u8;
                        }
                    }
                    let index = self.dmb.mobs.len() as u32;
                    self.dmb.mobs.push(record);
                    index
                };
                (8, mob)
            } else if matches!(tag, 9 | 10 | 11 | 63) {
                (tag, class)
            } else {
                continue;
            };
            let candidate = Instance {
                kind,
                class: target,
                initializer: NONE,
            };
            let key = (candidate.kind, candidate.class, candidate.initializer);
            let id = if let Some(&index) = self.instance_index.get(&key) {
                index
            } else {
                if self.dmb.instances.len() >= NONE as usize {
                    return Err(EmitError::Invalid(
                        "instance table reaches native unsupported ID 65535".into(),
                    ));
                }
                let index = self.dmb.instances.len() as u32;
                self.dmb.instances.push(candidate);
                self.instance_index.insert(key, index);
                index
            };
            self.ids.instances[od_id] = id;
        }
        Ok(())
    }
    pub(super) fn apply_class_field(
        &mut self,
        class_id: u32,
        name: &str,
        value: &Value,
    ) -> Result<bool, EmitError> {
        let mut current = Some(class_id);
        let mut appearance_class = false;
        while let Some(id) = current {
            let class = &self.dmb.classes[id as usize];
            let path = self.dmb.string(class.path_string_id()).unwrap_or_default();
            if [
                b"/atom".as_slice(),
                b"/obj",
                b"/mob",
                b"/turf",
                b"/area",
                b"/image",
                b"/mutable_appearance",
            ]
            .contains(&path)
            {
                appearance_class = true;
                break;
            }
            current = (class.parent_class_id() != NONE).then_some(class.parent_class_id());
        }
        if !appearance_class {
            return Ok(false);
        }
        let id = if value.tag() == 0 { NONE } else { value.id() };
        let number = value.number_bits().map(f32::from_bits);
        let gender = if name == "gender" && value.tag() == 6 {
            Some(match self.dmb.string(id) {
                Some(b"neuter") => 0,
                Some(b"male") => 1,
                Some(b"female") => 2,
                Some(b"plural") => 3,
                _ => return Err(EmitError::Unsupported("unknown class gender value".into())),
            })
        } else {
            None
        };
        let class = &mut self.dmb.classes[class_id as usize];
        match name {
            "name" if matches!(value.tag(), 0 | 6) => class.initial_ids[2] = id,
            "desc" if matches!(value.tag(), 0 | 6) => class.initial_ids[3] = id,
            "icon" if matches!(value.tag(), 0 | 12) => class.initial_ids[4] = id,
            "icon_state" if matches!(value.tag(), 0 | 6) => class.initial_ids[5] = id,
            "text" if matches!(value.tag(), 0 | 6) => class.text = id,
            "maptext" if matches!(value.tag(), 0 | 6) => class.maptext = id,
            "maptext_x" | "maptext_y" | "maptext_width" | "maptext_height" if number.is_some() => {
                let geometry = number.unwrap();
                let geometry_index = match name {
                    "maptext_width" => 0,
                    "maptext_height" => 1,
                    "maptext_x" => 2,
                    _ => 3,
                };
                let signed = geometry_index >= 2;
                let minimum = if signed { i16::MIN as f32 } else { 0.0 };
                let maximum = if signed {
                    i16::MAX as f32
                } else {
                    u16::MAX as f32
                };
                if !geometry.is_finite()
                    || geometry.fract() != 0.0
                    || geometry < minimum
                    || geometry > maximum
                {
                    return Err(EmitError::Unsupported(format!(
                        "{name} must be an integer within its 16-bit geometry range"
                    )));
                }
                class.maptext_geometry[geometry_index] = if signed {
                    (geometry as i16) as u16
                } else {
                    geometry as u16
                };
            }
            "suffix" if matches!(value.tag(), 0 | 6) => class.suffix = id,
            "dir" if number.is_some() => {
                let direction = number.unwrap() as u8;
                class.direction = if direction == 0 { 2 } else { direction };
            }
            "layer" if number.is_some() => class.layer_bits = number.unwrap().to_bits(),
            "invisibility" if number.is_some() => {
                class.flags = (class.flags & !4) | if number.unwrap() == 0.0 { 4 } else { 0 };
            }
            "density" if number.is_some() => class.set_dense(number.unwrap() != 0.0),
            "opacity" if number.is_some() => class.set_opaque(number.unwrap() != 0.0),
            "luminosity" if number.is_some() => class.set_luminosity(number.unwrap() as u8)?,
            "mouse_opacity" if number.is_some() => class.set_mouse_opacity(number.unwrap() as u8)?,
            "animate_movement" if number.is_some() => {
                class.set_animate_movement(number.unwrap() as u8)?
            }
            "appearance_flags" if number.is_some() => {
                class.set_appearance_flags(number.unwrap() as u32)
            }
            "gender" if gender.is_some() => class.set_gender_code(gender.unwrap())?,
            _ => return Ok(false),
        }
        Ok(true)
    }
    pub(super) fn direct_argument_source(&self, index: usize) -> Option<u32> {
        let code = self.input.procs.get(index)?.bytecode.as_deref()?;
        // Paired Dream Maker output stores these source expressions directly
        // in ProcArgument.value_source, without an anonymous procedure.
        if code == [0x97, 0x05] {
            return Some(0x7f10); // world
        }
        if code.len() == 7 && code[..2] == [0x86, 0x03] && code[6] == 0x10 {
            let field = u32::from_le_bytes(code[2..6].try_into().ok()?) as usize;
            if self.input.strings.get(field)?.as_str() == "contents" {
                return Some(0x7f08); // usr.contents
            }
        }
        if code.len() == 17
            && code[0] == 0x38
            && code[5..7] == [0x0a, 0x0b]
            && code[11..] == [1, 1, 0, 0, 0, 0x10]
        {
            let proc_id = u32::from_le_bytes(code[7..11].try_into().ok()?) as usize;
            let radius = f32::from_bits(u32::from_le_bytes(code[1..5].try_into().ok()?));
            if radius.fract() == 0.0 && (0.0..=255.0).contains(&radius) {
                let source_kind = match self.input.procs.get(proc_id)?.name.as_str() {
                    "view" => 0x01,
                    "oview" => 0x02,
                    "range" => 0x05,
                    _ => return None,
                };
                return Some(((radius as u32) << 8) | source_kind);
            }
        }
        if code.len() == 12 && code[..2] == [0x0a, 0x0b] && code[6..] == [0, 0, 0, 0, 0, 0x10] {
            let proc_id = u32::from_le_bytes(code[2..6].try_into().ok()?) as usize;
            return match self.input.procs.get(proc_id)?.name.as_str() {
                "view" => Some(0x7d01),
                "oview" => Some(0x7d02),
                _ => None,
            };
        }
        None
    }
}
