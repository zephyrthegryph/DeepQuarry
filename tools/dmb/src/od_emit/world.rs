use super::*;

impl Builder<'_> {
    pub(super) fn build_world(&mut self, project_name: Option<&str>) -> Result<(), EmitError> {
        self.dmb
            .world
            .set_client_import_handler(self.input.procs.iter().any(|proc| {
                proc.name == "Import"
                    && proc.attributes & 4 == 0
                    && proc.bytecode.is_some()
                    && self
                        .input
                        .type_inherits_path(proc.owning_type_id, "/client")
            }));
        self.dmb.world.client_script_files = self
            .input
            .native_client_script_files
            .iter()
            .map(|path| {
                let index = self
                    .input
                    .resources
                    .iter()
                    .position(|resource| resource == path)
                    .ok_or_else(|| {
                        EmitError::Invalid(format!(
                            "client script file not in resource table: {path}"
                        ))
                    })?;
                self.ids.resources.get(index).copied().ok_or_else(|| {
                    EmitError::Invalid(format!("client script file resource unresolved: {path}"))
                })
            })
            .collect::<Result<Vec<_>, _>>()?;
        self.dmb.world.client_script = NONE;
        if let Some((client_values, client_authored)) = native_client_configuration(self.input) {
            let baseline_client = self.baseline.and_then(native_client_configuration);
            let client_value = |name: &str| {
                client_values
                    .get(name)
                    .filter(|value| {
                        baseline_client
                            .as_ref()
                            .and_then(|(values, _)| values.get(name))
                            != Some(*value)
                            || (client_authored.contains(name)
                                && baseline_client
                                    .as_ref()
                                    .is_none_or(|(_, authored)| !authored.contains(name)))
                    })
                    .cloned()
            };
            for (name, mask, disabled) in [
                ("authenticate", 0x8000, true),
                ("show_map", 0x0010_0000, true),
                ("show_popup_menus", 0x1000_0000, true),
                ("macro_mode", 0x80, false),
            ] {
                let value = if matches!(name, "show_map" | "macro_mode") {
                    if client_authored.contains(name) {
                        client_values.get(name).cloned()
                    } else {
                        Some(JsonValue::from(if name == "show_map" { 1.0 } else { 0.0 }))
                    }
                } else {
                    client_value(name)
                };
                if let Some(value) = value {
                    let enabled = value
                        .as_f64()
                        .filter(|&value| value == 0.0 || value == 1.0)
                        .ok_or_else(|| {
                            EmitError::Unsupported(format!("client.{name} must be 0 or 1"))
                        })?
                        != 0.0;
                    if enabled != disabled {
                        self.dmb.header.flags |= mask;
                    } else {
                        self.dmb.header.flags &= !mask;
                    }
                }
            }
            // Unlike its value, authoring lazy_eye itself disables the native
            // implicit default. Explicit zero still clears this bit.
            if client_authored.contains("lazy_eye") {
                self.dmb.header.flags &= !0x100;
            } else if baseline_client
                .as_ref()
                .is_some_and(|(_, authored)| authored.contains("lazy_eye"))
            {
                self.dmb.header.flags |= 0x100;
            }
            if let Some(value) = client_value("lazy_eye") {
                let number = value.as_f64().ok_or_else(|| {
                    EmitError::Unsupported("client.lazy_eye must be numeric".into())
                })? as f32;
                // Native truncates the single-precision value to a signed
                // integer, then retains its low byte (negative values wrap).
                if !(-1.0..=35.0).contains(&number) {
                    return Err(EmitError::Unsupported(
                        "client.lazy_eye must be numeric in -1..=35".into(),
                    ));
                }
                let integer = number as i32;
                self.dmb.world.eye = integer as u8;
            }
            let control_value = client_value("control_freak");
            let preload_value = client_value("preload_rsc");
            // Rebuild this representation even when unchanged from the baseline:
            // included files are independent and precede an explicit script file.
            let script_value = client_values.get("script").cloned();
            let verb_panel_value = client_value("show_verb_panel");
            let perspective_value = client_value("perspective");
            if let Some(value) = control_value.as_ref() {
                let control = value
                    .as_f64()
                    .filter(|value| (0.0..=7.0).contains(value))
                    .ok_or_else(|| {
                        EmitError::Unsupported(
                            "client.control_freak must be numeric in 0..=7".into(),
                        )
                    })?;
                self.dmb.world.control = control as u16;
            }
            if let Some(value) = preload_value.as_ref() {
                let mode_bits = match value {
                    JsonValue::String(_) => 0x800,
                    _ => {
                        let mode = value
                            .as_f64()
                            .filter(|mode| (0.0..=2.0).contains(mode))
                            .ok_or_else(|| {
                                EmitError::Unsupported(
                                    "client.preload_rsc must be numeric in 0..=2 or constant text"
                                        .into(),
                                )
                            })?;
                        if mode == 0.0 {
                            0x800
                        } else if mode == 2.0 {
                            0x1000
                        } else {
                            0
                        }
                    }
                };
                self.dmb.header.flags = (self.dmb.header.flags & !0x1800) | mode_bits;
            }
            if let Some(value) = script_value.as_ref() {
                self.dmb.world.client_script = match value {
                    JsonValue::Null if !client_authored.contains("script") => NONE,
                    JsonValue::String(script) => self.string(script),
                    JsonValue::Object(map)
                        if map.get("type").and_then(JsonValue::as_u64) == Some(0) =>
                    {
                        let resource = self.constant(value)?;
                        self.dmb.world.client_script_files.push(resource.id());
                        NONE
                    }
                    _ => {
                        return Err(EmitError::Unsupported(
                            "client.script must be constant text or a resource file".into(),
                        ));
                    }
                };
            }
            if let Some(value) = perspective_value.as_ref() {
                let perspective = value
                    .as_f64()
                    .filter(|value| (0.0..=3.0).contains(value))
                    .ok_or_else(|| {
                        EmitError::Unsupported("client.perspective must be between 0 and 3".into())
                    })?;
                // Native truncates the class builtin value and also mirrors
                // its low bit in the header for initial client setup.
                self.dmb.header.flags = (self.dmb.header.flags & !0x0800_0000)
                    | if perspective as u32 & 1 != 0 {
                        0x0800_0000
                    } else {
                        0
                    };
            }
            if let Some(value) = verb_panel_value.as_ref() {
                match value.as_f64() {
                    Some(0.0) => self.dmb.header.flags |= 0x400,
                    Some(1.0) => self.dmb.header.flags &= !0x400,
                    _ => {
                        return Err(EmitError::Unsupported(
                            "client.show_verb_panel must be 0 or 1".into(),
                        ));
                    }
                }
            }
        }
        let Some(typ) = self.input.types.iter().find(|typ| typ.path == "/world") else {
            return Err(EmitError::Invalid("OpenDream JSON has no /world".into()));
        };
        let baseline = self
            .baseline
            .and_then(|program| program.types.iter().find(|typ| typ.path == "/world"));
        let changed = |name: &str| {
            let value = typ.variables.get(name);
            value.is_some()
                && (baseline.and_then(|typ| typ.variables.get(name)) != value
                    || (typ.explicit_world_fields.contains(name)
                        && baseline.is_none_or(|base| !base.explicit_world_fields.contains(name))))
        };
        for name in typ.variables.keys() {
            if changed(name)
                && !matches!(
                    name.as_str(),
                    "name"
                        | "status"
                        | "version"
                        | "executor"
                        | "hub"
                        | "hub_password"
                        | "cache_lifespan"
                        | "fps"
                        | "tick_lag"
                        | "view"
                        | "map_format"
                        | "icon_size"
                        | "turf"
                        | "area"
                        | "mob"
                        | "maxx"
                        | "maxy"
                        | "maxz"
                        | "loop_checks"
                        | "sleep_offline"
                        | "visibility"
                )
            {
                return Err(EmitError::Unsupported(format!(
                    "world.{name} translation is not decoded"
                )));
            }
        }
        if changed("name") {
            self.dmb.world.ids[6] = match &typ.variables["name"] {
                JsonValue::Null => NONE,
                JsonValue::String(name) => self.string(name),
                _ => {
                    return Err(EmitError::Unsupported(
                        "world.name must be constant text or null".into(),
                    ))
                }
            };
        } else if let Some(name) = project_name {
            self.dmb.world.ids[6] = self.string(name);
        }
        if changed("status") {
            self.dmb.world.server_name = match &typ.variables["status"] {
                JsonValue::Null => NONE,
                JsonValue::String(value) => self.string(value),
                _ => {
                    return Err(EmitError::Unsupported(
                        "world.status must be constant text or null".into(),
                    ))
                }
            };
        }
        if changed("version") {
            let value = typ.variables["version"]
                .as_f64()
                .ok_or_else(|| EmitError::Unsupported("world.version must be numeric".into()))?
                as f32 as f64;
            let integer = if value > 2147483648.0 {
                i32::MAX as i64
            } else if value < -2147483648.0 {
                -(i32::MAX as i64)
            } else {
                value.trunc() as i64
            };
            self.dmb.world.version = integer as u32;
        }
        if changed("executor") {
            let executor = &typ.variables["executor"];
            let value = if executor.is_null() {
                ""
            } else {
                executor.as_str().ok_or_else(|| {
                    EmitError::Unsupported("world.executor must be constant text or null".into())
                })?
            };
            self.dmb.header.executor_line = if value.is_empty() {
                None
            } else {
                Some({
                    let mut prefix = b"#!".to_vec();
                    prefix.extend(native_executor_bytes(value));
                    prefix.push(b'\n');
                    prefix
                })
            };
        }
        if changed("hub") {
            let hub = typ
                .variables
                .get("hub")
                .and_then(JsonValue::as_str)
                .ok_or_else(|| {
                    EmitError::Unsupported("world.hub must be a constant string".into())
                })?;
            self.dmb.world.hub_channel_skin[0] = self.string(hub);
        }
        if let Some(password) = self.input.native_hub_password.as_ref() {
            let encoded = crate::hash::hub_password_hash(&native_string_bytes(password));
            self.dmb.world.hub_password = self.string(&encoded);
        } else if baseline.is_some_and(|base| base.explicit_world_fields.contains("hub_password"))
            && !typ.explicit_world_fields.contains("hub_password")
        {
            self.dmb.world.hub_password = NONE;
        } else if changed("hub_password") {
            self.dmb.world.hub_password = match &typ.variables["hub_password"] {
                JsonValue::Null => NONE,
                JsonValue::String(password) => {
                    let encoded = crate::hash::hub_password_hash(&native_string_bytes(password));
                    self.string(&encoded)
                }
                _ => {
                    return Err(EmitError::Unsupported(
                        "world.hub_password must be constant text or null".into(),
                    ))
                }
            };
        }
        if changed("cache_lifespan") {
            let lifespan = typ.variables["cache_lifespan"].as_u64().ok_or_else(|| {
                EmitError::Unsupported("world.cache_lifespan must be a nonnegative integer".into())
            })?;
            self.dmb.world.cache_lifespan = u16::try_from(lifespan)
                .map_err(|_| EmitError::Invalid("world.cache_lifespan out of range".into()))?;
        }
        if changed("tick_lag") {
            let lag = typ
                .variables
                .get("tick_lag")
                .and_then(JsonValue::as_f64)
                .ok_or_else(|| EmitError::Unsupported("world.tick_lag must be numeric".into()))?;
            if !lag.is_finite() || lag < 0.0 || lag * 100.0 > u32::MAX as f64 {
                return Err(EmitError::Invalid("world.tick_lag out of range".into()));
            }
            self.dmb.world.tick_lag = (lag * 100.0).round() as u32;
        }
        if changed("fps") {
            if changed("tick_lag") {
                return Err(EmitError::Unsupported(
                    "world.fps and world.tick_lag are both authored; OpenDream JSON loses their assignment order"
                        .into(),
                ));
            }
            let fps = typ.variables["fps"]
                .as_u64()
                .ok_or_else(|| EmitError::Unsupported("world.fps must be an integer".into()))?;
            if !(1..=100).contains(&fps) {
                return Err(EmitError::Invalid(
                    "world.fps must be between 1 and 100".into(),
                ));
            }
            // Dream Maker stores integer milliseconds and truncates 1000/fps.
            self.dmb.world.tick_lag = (1000 / fps) as u32;
        }
        if changed("view") {
            let view = &typ.variables["view"];
            self.dmb.world.view_dimensions = native_world_view(view)?;
            self.dmb.header.flags &= !0x200;
        }
        if !typ.explicit_world_fields.contains("view")
            && baseline.is_some_and(|base| base.explicit_world_fields.contains("view"))
        {
            // Removing an authored override restores the implicit native mode,
            // including when its value equals the explicit default.
            self.dmb.header.flags |= 0x200;
        }
        if changed("map_format") {
            let format = typ.variables["map_format"]
                .as_u64()
                .ok_or_else(|| EmitError::Unsupported("world.map_format must be numeric".into()))?;
            self.dmb.world.icon_dimensions_format[2] = u16::try_from(format)
                .map_err(|_| EmitError::Invalid("world.map_format out of range".into()))?;
        }
        if changed("icon_size") {
            let size = typ.variables["icon_size"]
                .as_u64()
                .ok_or_else(|| EmitError::Unsupported("world.icon_size must be numeric".into()))?;
            let size = u16::try_from(size)
                .map_err(|_| EmitError::Invalid("world.icon_size out of range".into()))?;
            self.dmb.world.icon_dimensions_format[0] = size;
            self.dmb.world.icon_dimensions_format[1] = size;
        }
        if changed("icon_size") || changed("map_format") {
            self.dmb.header.compatibility_line = b"min compatibility v514 507\n".to_vec();
        }
        for (name, slot) in [("turf", 1usize), ("area", 2usize)] {
            if !changed(name) {
                continue;
            }
            let typ_id = typ.variables[name]
                .get("value")
                .and_then(JsonValue::as_u64)
                .ok_or_else(|| EmitError::Unsupported(format!("world.{name} must be type path")))?
                as usize;
            self.dmb.world.ids[slot] =
                *self.ids.classes.get(typ_id).ok_or_else(|| {
                    EmitError::Invalid(format!("world.{name} type ID out of range"))
                })?;
        }
        if changed("mob") {
            let typ_id = typ.variables["mob"]
                .get("value")
                .and_then(JsonValue::as_u64)
                .ok_or_else(|| EmitError::Unsupported("world.mob must be type path".into()))?
                as usize;
            let class = *self
                .ids
                .classes
                .get(typ_id)
                .ok_or_else(|| EmitError::Invalid("world.mob type ID out of range".into()))?;
            let mob = self
                .dmb
                .mobs
                .iter()
                .position(|mob| mob.class == class)
                .ok_or_else(|| {
                    EmitError::Unsupported(
                        "custom world.mob requires mob subtype record emission".into(),
                    )
                })?;
            self.dmb.world.ids[0] = mob as u32;
        }
        if changed("sleep_offline") {
            let value = typ.variables["sleep_offline"]
                .as_u64()
                .filter(|&value| value <= 1)
                .ok_or_else(|| {
                    EmitError::Unsupported("world.sleep_offline must be 0 or 1".into())
                })?;
            if value != 0 {
                self.dmb.header.flags |= 0x20;
            } else {
                self.dmb.header.flags &= !0x20;
            }
        }
        if changed("loop_checks") {
            match typ.variables["loop_checks"].as_i64() {
                Some(0) => self.dmb.header.flags |= 0x2,
                Some(_) => self.dmb.header.flags &= !0x2,
                None => {
                    return Err(EmitError::Unsupported(
                        "world.loop_checks must be numeric".into(),
                    ))
                }
            }
        }
        if changed("visibility") {
            match typ.variables["visibility"].as_i64() {
                Some(0) => self.dmb.header.flags |= 0x2000,
                Some(_) => self.dmb.header.flags &= !0x2000,
                None => {
                    return Err(EmitError::Unsupported(
                        "world.visibility must be numeric".into(),
                    ))
                }
            }
        }
        let compatibility = std::str::from_utf8(&self.dmb.header.compatibility_line)
            .ok()
            .and_then(|line| line.split_ascii_whitespace().nth(2))
            .and_then(|version| version.strip_prefix('v'))
            .and_then(|version| version.parse::<u16>().ok())
            .ok_or_else(|| EmitError::Invalid("invalid native compatibility header".into()))?;
        // Dream Maker stores the authored /savefile/byond_version override here.
        // An absent override is zero, independently of the compiler version.
        if let Some(value) = self
            .input
            .types
            .iter()
            .find(|typ| typ.path == "/savefile")
            .and_then(|typ| typ.variables.get("byond_version"))
        {
            let version = value
                .as_u64()
                .and_then(|v| u32::try_from(v).ok())
                .ok_or_else(|| {
                    EmitError::Unsupported(
                        "savefile.byond_version must be a nonnegative integer".into(),
                    )
                })?;
            self.dmb.world.savefile_byond_version = version;
            if version != 0 && compatibility <= 514 {
                self.dmb.header.compatibility_line = b"min compatibility v515 468\n".to_vec();
            }
        }
        Ok(())
    }
}
