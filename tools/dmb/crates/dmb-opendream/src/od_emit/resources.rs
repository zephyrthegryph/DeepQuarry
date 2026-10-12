use super::*;

impl Builder<'_> {
    pub(super) fn build_resources(&mut self) -> Result<(), EmitError> {
        let mut paths = self.input.resources.clone();
        let mut skin_resource_names = Vec::new();
        let mut named_headers = Vec::<(Vec<u8>, u32, u8)>::new();
        let mut headers_by_path = HashMap::<String, (u32, u8)>::new();
        // Dream Maker imports icons named by a skin even when DM code never
        // references them. OpenDream's Resources array omits these DMF-only
        // dependencies. The paired DeepQuarry archive contains ss13_64.png
        // from interface/skin.dmf for precisely this reason.
        if let Some(interface) = self.input.interface.as_ref().filter(|s| !s.is_empty()) {
            if !paths
                .iter()
                .any(|path| path.replace('\\', "/") == interface.replace('\\', "/"))
            {
                return Err(EmitError::Invalid(format!(
                    "OpenDream interface {interface} is missing from Resources"
                )));
            }
            let skin = std::fs::read_to_string(self.resource_root.join(interface))?;
            for line in skin.lines() {
                let Some((key, value)) = line.split_once('=') else {
                    continue;
                };
                if key.trim() != "icon" {
                    continue;
                }
                let value = value.trim();
                if let Some(path) = value
                    .strip_prefix('\'')
                    .and_then(|v| v.split_once('\'').map(|p| p.0))
                {
                    skin_resource_names
                        .push(path.strip_prefix("icons/gen/").unwrap_or(path).to_owned());
                    if !paths
                        .iter()
                        .any(|existing| existing.replace('\\', "/") == path)
                    {
                        paths.push(path.to_owned());
                    }
                }
            }
        }
        let mut by_content: HashMap<u32, u32> = self
            .dmb
            .resources
            .iter()
            .enumerate()
            .map(|(index, entry)| (entry.id, index as u32))
            .collect();
        let mut materialized_by_path = HashMap::new();
        for (path_index, path) in paths.iter().enumerate() {
            let normalized = path.replace('\\', "/");
            let candidate = Path::new(&normalized);
            // Some OpenDream compiler builds emit the DMF path as an absolute
            // path even though other resources are relative. Keep the archive
            // name relative while requiring the file to stay under this root.
            let authored_names = self.input.resource_archive_names.get(path);
            if authored_names.is_some_and(Vec::is_empty) {
                return Err(EmitError::Invalid(format!(
                    "resource {path} has no authored archive names"
                )));
            }
            let relative = if authored_names.is_some() {
                candidate
            } else if candidate.is_absolute() {
                candidate
                    .strip_prefix(&self.resource_root)
                    .map_err(|_| EmitError::Invalid(format!("resource escapes root: {path}")))?
            } else {
                candidate
            };
            if authored_names.is_none()
                && relative.components().any(|part| {
                    matches!(
                        part,
                        std::path::Component::ParentDir
                            | std::path::Component::Prefix(_)
                            | std::path::Component::RootDir
                    )
                })
            {
                return Err(EmitError::Invalid(format!("resource escapes root: {path}")));
            }
            let extension = relative
                .extension()
                .and_then(|s| s.to_str())
                .unwrap_or("")
                .to_ascii_lowercase();
            let kind = match extension.as_str() {
                // Full DeepQuarry Dream Maker RSC confirms browser assets,
                // including WOFF2, WebP, and MP4, use text/generic kind 0.
                "dmf" | "dm" | "txt" | "html" | "htm" | "css" | "js" | "json" | "woff2"
                | "webp" | "mp4" => 0,
                "mid" | "midi" | "mod" | "it" | "xm" | "s3m" => 1,
                "ogg" | "wav" | "mp3" | "aiff" | "wma" => 2,
                "dmi" => 3,
                "png" => 6,
                "zip" => 9,
                "rsc" => 10,
                "bmp" => 5,
                "jpg" | "jpeg" => 11,
                "gif" => 13,
                "ttf" | "otf" => 14,
                // Native resources with unrecognized extensions are generic.
                _ => 0,
            };
            let id;
            if self.resource_mode != ResourceMode::Placeholder {
                let resource_path = self.resource_root.join(relative);
                let bytes = std::fs::read(&resource_path)?;
                let timestamp = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map_err(|_| {
                        EmitError::Invalid("resource creation time precedes Unix epoch".into())
                    })?
                    .as_secs() as u32;
                let source_timestamp = std::fs::metadata(&resource_path)?
                    .modified()?
                    .duration_since(std::time::UNIX_EPOCH)
                    .map_err(|_| {
                        EmitError::Invalid(format!(
                            "resource modification time precedes Unix epoch: {path}"
                        ))
                    })?
                    .as_secs() as u32;
                let archive_path = relative.to_string_lossy().replace('\\', "/");
                let legacy_name = archive_path
                    .strip_prefix("icons/gen/")
                    .unwrap_or(&archive_path);
                let names = authored_names
                    .cloned()
                    .unwrap_or_else(|| vec![legacy_name.to_owned()]);
                // Native stores the low 32 bits, including source times beyond
                // 2106. Cache aging and source freshness use these fields.
                let entry = NamedResource::from_data(
                    kind,
                    names[0].as_bytes().to_vec(),
                    bytes,
                    timestamp,
                    source_timestamp,
                )?;
                id = *by_content.entry(entry.id).or_insert_with(|| {
                    let index = self.dmb.resources.len() as u32;
                    self.dmb.resources.push(ResourceRef { id: entry.id, kind });
                    index
                });
                headers_by_path.insert(normalized.clone(), (entry.id, kind));
                for name in &names {
                    if !named_headers.iter().any(|header| {
                        header.0 == name.as_bytes() && header.1 == entry.id && header.2 == kind
                    }) {
                        named_headers.push((name.as_bytes().to_vec(), entry.id, kind));
                    }
                }
                if self.resource_mode == ResourceMode::Materialize {
                    materialized_by_path.insert(normalized.clone(), entry.clone());
                    for name in names {
                        if !self.archive.iter().any(|existing| matches!(existing, Entry::Named(resource) if resource.name == name.as_bytes() && resource.id == entry.id && resource.kind == entry.kind)) {
                            let mut alias = entry.clone();
                            alias.name = name.into_bytes();
                            self.archive.push(Entry::Named(alias));
                        }
                    }
                }
            } else {
                id = self.dmb.resources.len() as u32;
                self.dmb.resources.push(ResourceRef { id, kind });
            }
            if path_index < self.input.resources.len() {
                self.ids.resources.push(id);
            }
        }
        if self.resource_mode != ResourceMode::Placeholder {
            let mut aliases: Vec<_> = self.input.resource_aliases.iter().collect();
            aliases.sort_by_key(|(alias, _)| *alias);
            for (alias, canonical) in aliases {
                let canonical = canonical.replace('\\', "/");
                if !self
                    .input
                    .resources
                    .iter()
                    .any(|path| path.replace('\\', "/") == canonical)
                {
                    return Err(EmitError::Invalid(format!(
                        "resource alias {alias} targets absent canonical resource {canonical}"
                    )));
                }
                let &(content_id, kind) = headers_by_path.get(&canonical).ok_or_else(|| {
                    EmitError::Invalid(format!(
                        "resource alias {alias} has no materialized canonical entry"
                    ))
                })?;
                let archive_name = alias.replace('\\', "/");
                let archive_name = archive_name
                    .strip_prefix("icons/gen/")
                    .unwrap_or(&archive_name);
                if !named_headers
                    .iter()
                    .any(|header| header.0 == archive_name.as_bytes())
                {
                    named_headers.push((archive_name.as_bytes().to_vec(), content_id, kind));
                    if self.resource_mode == ResourceMode::Materialize {
                        let source = materialized_by_path.get(&canonical).ok_or_else(|| {
                            EmitError::Invalid(format!(
                                "resource alias {alias} has no materialized canonical data"
                            ))
                        })?;
                        let mut duplicate = source.clone();
                        duplicate.name = archive_name.as_bytes().to_vec();
                        self.archive.push(Entry::Named(duplicate));
                    }
                }
            }
            if let Some(order) = &self.input.native_resource_archive_order {
                let interface = self
                    .input
                    .interface
                    .as_ref()
                    .map(|path| path.replace('\\', "/"));
                let mut ranks = HashMap::<Vec<u8>, usize>::new();
                for name in order {
                    if interface.as_deref() == Some(name.replace('\\', "/").as_str()) {
                        for icon in &skin_resource_names {
                            let rank = ranks.len();
                            ranks.entry(icon.as_bytes().to_vec()).or_insert(rank);
                        }
                    }
                    if !named_headers
                        .iter()
                        .any(|header| header.0 == name.as_bytes())
                    {
                        return Err(EmitError::Invalid(format!(
                            "native resource archive order names an absent resource: {name}"
                        )));
                    }
                    let rank = ranks.len();
                    ranks.entry(name.as_bytes().to_vec()).or_insert(rank);
                }
                // Keep unannotated additions in their original relative order;
                // no alphabetic or content-ID order has native provenance.
                named_headers
                    .sort_by_key(|header| ranks.get(&header.0).copied().unwrap_or(usize::MAX));
                self.archive.sort_by_key(|entry| match entry {
                    Entry::Named(resource) => {
                        ranks.get(&resource.name).copied().unwrap_or(usize::MAX)
                    }
                    Entry::Opaque { .. } => usize::MAX,
                });
                let mut native_kinds = HashMap::new();
                for (_, content_id, kind) in named_headers {
                    native_kinds.entry(content_id).or_insert(kind);
                }
                for resource in &mut self.dmb.resources {
                    if let Some(&kind) = native_kinds.get(&resource.id) {
                        resource.kind = kind;
                    }
                }
            }
        }
        if let Some(interface) = self
            .input
            .interface
            .as_ref()
            .filter(|value| !value.is_empty())
        {
            let id = self
                .input
                .resources
                .iter()
                .position(|path| path.replace('\\', "/") == interface.replace('\\', "/"))
                .and_then(|index| self.ids.resources.get(index).copied())
                .ok_or_else(|| {
                    EmitError::Invalid(format!(
                        "OpenDream interface {interface} is missing from Resources"
                    ))
                })?;
            // Dream Maker stores the skin ResourceID in the final skin field.
            // The middle field remains the native scaffold's channel string.
            self.dmb.world.hub_channel_skin[2] = id;
        }
        Ok(())
    }
}
