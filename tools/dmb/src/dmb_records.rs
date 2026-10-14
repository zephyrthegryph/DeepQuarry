use super::*;

#[derive(Clone, Debug, PartialEq)]
pub struct Header {
    /// Optional native CGI executor prefix, including all its authored lines.
    pub executor_line: Option<Vec<u8>>,
    pub version_line: Vec<u8>,
    pub compatibility_line: Vec<u8>,
    pub flags: u32,
    /// Present when bit 31 of `flags` is set. Its bit meanings need probes.
    pub extended_flags: Option<u32>,
}
impl Header {
    /// Dream Maker emits DbgFile/DbgLine instructions when this bit is set.
    pub fn debug_symbols(&self) -> bool {
        self.flags & 0x0002_0000 != 0
    }
    pub fn uses_large_object_ids(&self) -> bool {
        self.flags & 0x4000_0000 != 0
    }
    pub fn loop_checks_disabled(&self) -> bool {
        self.flags & 0x2 != 0
    }
    pub fn sleeps_offline(&self) -> bool {
        self.flags & 0x20 != 0
    }
    pub fn hidden_from_hub(&self) -> bool {
        self.flags & 0x2000 != 0
    }
    pub fn verb_panel_disabled(&self) -> bool {
        self.flags & 0x400 != 0
    }
    pub fn hub_authentication_disabled(&self) -> bool {
        self.flags & 0x8000 != 0
    }
    pub fn client_map_disabled(&self) -> bool {
        self.flags & 0x10_0000 != 0
    }
    pub fn popup_menus_disabled(&self) -> bool {
        self.flags & 0x1000_0000 != 0
    }
    pub fn uses_dynamic_calls(&self) -> bool {
        self.flags & 0x2000_0000 != 0
    }
    pub fn resource_preload_mode(&self) -> Option<u8> {
        match self.flags & 0x1800 {
            0 => Some(1),
            0x800 => Some(0),
            0x1000 => Some(2),
            _ => None,
        }
    }
    pub fn movement_mode_setting(&self) -> Option<u8> {
        match self.extended_flags.unwrap_or(0) & 0xc {
            0 => Some(0),
            4 => Some(1),
            8 => Some(2),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct GridRun {
    pub turf: u32,
    pub area: u32,
    pub contents: u32,
    pub copies: u8,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Class {
    pub initial_ids: [u32; 6],
    pub direction: u8,
    pub interface: u8,
    pub extended_interface: Option<u32>,
    pub text: u32,
    pub maptext: u32,
    pub maptext_geometry: [u16; 4],
    pub suffix: u32,
    pub flags: u64,
    pub lists_and_procs: [u32; 6],
    pub layer_bits: u32,
    pub transform_flag: u8,
    pub transform: Option<[u32; 6]>,
    pub color_matrix_flag: u8,
    pub color_matrix: Option<[u32; 20]>,
    pub overrides: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ClassInterface {
    Regular,
    Image,
    Sound,
    Icon,
    Matrix,
    Regex,
    MutableAppearance,
    Generator,
    DatabaseQuery,
    Other {
        discriminator: u8,
        extension: Option<u32>,
    },
}

impl Class {
    pub fn native_interface(&self) -> ClassInterface {
        match (self.interface, self.extended_interface) {
            (1, None) => ClassInterface::Regular,
            (15, Some(65)) => ClassInterface::Image,
            (15, Some(545)) => ClassInterface::Sound,
            (15, Some(769)) => ClassInterface::Icon,
            (15, Some(1025)) => ClassInterface::Matrix,
            (15, Some(8193)) => ClassInterface::Regex,
            (15, Some(16449)) => ClassInterface::MutableAppearance,
            (15, Some(32769)) => ClassInterface::Generator,
            (15, Some(36865)) => ClassInterface::DatabaseQuery,
            (discriminator, extension) => ClassInterface::Other {
                discriminator,
                extension,
            },
        }
    }
    /// Initial invisibility is zero when this flag is set.
    pub fn is_normally_visible(&self) -> bool {
        self.flags & 0x4 != 0
    }

    pub fn set_normally_visible(&mut self, visible: bool) {
        self.flags = (self.flags & !0x4) | (u64::from(visible) << 2);
    }

    /// The three low luminosity bits stored with the initial appearance.
    pub fn luminosity(&self) -> u8 {
        ((self.flags >> 3) & 0x7) as u8
    }

    pub fn set_luminosity(&mut self, value: u8) -> io::Result<()> {
        if value > 7 {
            return Err(invalid("packed luminosity exceeds three bits"));
        }
        self.flags = (self.flags & !(0x7 << 3)) | (u64::from(value) << 3);
        Ok(())
    }

    pub fn has_mouse_event_proc(&self) -> bool {
        self.flags & 0x800 != 0
    }

    pub fn is_mouse_drop_zone(&self) -> bool {
        self.flags & 0x100 != 0
    }

    pub fn set_mouse_drop_zone(&mut self, enabled: bool) {
        self.flags = (self.flags & !0x100) | (u64::from(enabled) << 8);
    }

    pub fn has_mouse_move_proc(&self) -> bool {
        self.flags & 0x80000 != 0
    }

    pub fn has_mouse_wheel_proc(&self) -> bool {
        self.flags & 0x100000 != 0
    }

    /// Initial animate_movement (0 through 3). Zero additionally sets bit 10.
    pub fn animate_movement(&self) -> u8 {
        if self.flags & 0x400 != 0 {
            0
        } else {
            ((((self.flags >> 14) & 0x3) as u8) + 1) & 0x3
        }
    }

    pub fn set_animate_movement(&mut self, value: u8) -> io::Result<()> {
        if value > 3 {
            return Err(invalid("animate_movement exceeds two bits"));
        }
        self.flags &= !(0xc000 | 0x400);
        self.flags |= u64::from(value.wrapping_sub(1) & 0x3) << 14;
        if value == 0 {
            self.flags |= 0x400;
        }
        Ok(())
    }

    pub fn is_opaque(&self) -> bool {
        self.flags & 0x1 != 0
    }

    pub fn set_opaque(&mut self, opaque: bool) {
        self.flags = (self.flags & !0x1) | u64::from(opaque);
    }

    /// Initial density bit in the class flag word.
    pub fn is_dense(&self) -> bool {
        self.flags & 0x2 != 0
    }

    pub fn set_dense(&mut self, dense: bool) {
        self.flags = (self.flags & !0x2) | (u64::from(dense) << 1);
    }

    /// Enum encoding: 0 neuter, 1 male, 2 female, 3 plural.
    pub fn gender_code(&self) -> u8 {
        ((self.flags >> 6) & 0x3) as u8
    }

    pub fn set_gender_code(&mut self, code: u8) -> io::Result<()> {
        if code > 3 {
            return Err(invalid("gender code exceeds two bits"));
        }
        self.flags = (self.flags & !(0x3 << 6)) | (u64::from(code) << 6);
        Ok(())
    }

    /// Initial mouse_opacity (0 through 3), packed as value minus one.
    pub fn mouse_opacity(&self) -> u8 {
        (((self.flags >> 12) as u8 & 0x3) + 1) & 0x3
    }

    pub fn set_mouse_opacity(&mut self, value: u8) -> io::Result<()> {
        if value > 3 {
            return Err(invalid("mouse_opacity exceeds two bits"));
        }
        let encoded = (value.wrapping_sub(1) & 0x3) as u64;
        self.flags = (self.flags & !(0x3 << 12)) | (encoded << 12);
        Ok(())
    }

    /// Initial atom appearance_flags, packed above the 21 low class flag bits.
    pub fn appearance_flags(&self) -> u32 {
        (self.flags >> 21) as u32
    }

    pub fn set_appearance_flags(&mut self, value: u32) {
        self.flags = (self.flags & ((1u64 << 21) - 1)) | (u64::from(value) << 21);
    }

    pub fn path_string_id(&self) -> u32 {
        self.initial_ids[0]
    }
    pub fn parent_class_id(&self) -> u32 {
        self.initial_ids[1]
    }
    pub fn name_string_id(&self) -> u32 {
        self.initial_ids[2]
    }
    pub fn description_string_id(&self) -> u32 {
        self.initial_ids[3]
    }
    pub fn icon_resource_id(&self) -> u32 {
        self.initial_ids[4]
    }
    pub fn icon_state_string_id(&self) -> u32 {
        self.initial_ids[5]
    }
    pub fn verb_list_id(&self) -> u32 {
        self.lists_and_procs[0]
    }
    pub fn proc_list_id(&self) -> u32 {
        self.lists_and_procs[1]
    }
    pub fn initializer_proc_id(&self) -> u32 {
        self.lists_and_procs[2]
    }
    pub fn initialized_variable_list_id(&self) -> u32 {
        self.lists_and_procs[3]
    }
    pub fn defining_variable_list_id(&self) -> u32 {
        self.lists_and_procs[4]
    }
    pub fn overriding_variable_list_id(&self) -> u32 {
        self.overrides
    }

    pub(super) fn read(r: &mut Reader<'_>) -> io::Result<Self> {
        let mut initial_ids = [0; 6];
        for id in &mut initial_ids {
            *id = r.object()?;
        }
        let direction = r.u8()?;
        let interface = r.u8()?;
        let extended_interface = if interface == 15 {
            Some(r.u32()?)
        } else {
            None
        };
        let text = r.object()?;
        let maptext = r.object()?;
        let mut maptext_geometry = [0; 4];
        for value in &mut maptext_geometry {
            *value = r.u16()?;
        }
        let suffix = r.object()?;
        let flags = u64::from(r.u32()?) | (u64::from(r.u32()?) << 32);
        let mut lists_and_procs = [0; 6];
        for id in &mut lists_and_procs {
            *id = r.object()?;
        }
        let layer_bits = r.f32_bits()?;
        let transform_flag = r.u8()?;
        let transform = if transform_flag != 0 {
            let mut values = [0; 6];
            for value in &mut values {
                *value = r.f32_bits()?;
            }
            Some(values)
        } else {
            None
        };
        let color_matrix_flag = r.u8()?;
        let color_matrix = if color_matrix_flag != 0 {
            let mut values = [0; 20];
            for value in &mut values {
                *value = r.f32_bits()?;
            }
            Some(values)
        } else {
            None
        };
        let overrides = r.object()?;
        Ok(Self {
            initial_ids,
            direction,
            interface,
            extended_interface,
            text,
            maptext,
            maptext_geometry,
            suffix,
            flags,
            lists_and_procs,
            layer_bits,
            transform_flag,
            transform,
            color_matrix_flag,
            color_matrix,
            overrides,
        })
    }
    pub(super) fn write(&self, w: &mut Writer) {
        for id in self.initial_ids {
            w.object(id);
        }
        w.u8(self.direction);
        w.u8(self.interface);
        if let Some(value) = self.extended_interface {
            w.u32(value);
        }
        w.object(self.text);
        w.object(self.maptext);
        for value in self.maptext_geometry {
            w.u16(value);
        }
        w.object(self.suffix);
        w.u32(self.flags as u32);
        w.u32((self.flags >> 32) as u32);
        for id in self.lists_and_procs {
            w.object(id);
        }
        w.u32(self.layer_bits);
        w.u8(self.transform_flag);
        if let Some(values) = self.transform {
            for value in values {
                w.u32(value);
            }
        }
        w.u8(self.color_matrix_flag);
        if let Some(values) = self.color_matrix {
            for value in values {
                w.u32(value);
            }
        }
        w.object(self.overrides);
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct MobType {
    pub class: u32,
    pub key: u32,
    pub sight: u8,
    pub extended_sight: Option<(u32, u8, u8)>,
}
pub mod mob_sight {
    pub const BLIND: u32 = 1;
    pub const SEE_MOBS: u32 = 4;
    pub const SEE_OBJS: u32 = 8;
    pub const SEE_TURFS: u32 = 16;
    pub const SEE_SELF: u32 = 32;
    pub const SEE_INFRA: u32 = 64;
    pub const SEE_PIXELS: u32 = 256;
    pub const SEE_THRU: u32 = 512;
    pub const SEE_BLACKNESS: u32 = 1024;
    pub const SEE_INFRARED: u32 = 65536;
}
impl MobType {
    /// Effective `sight` bit mask; bit 0x80 in the wire record marks the
    /// extended form and is removed from the semantic value.
    pub fn sight_bits(&self) -> u32 {
        self.extended_sight
            .map_or(u32::from(self.sight), |record| record.0)
            & !0x80
    }
    pub fn see_in_dark_setting(&self) -> Option<u8> {
        self.extended_sight.map(|record| record.1)
    }
    pub fn see_invisible_setting(&self) -> Option<u8> {
        self.extended_sight.map(|record| record.2)
    }
    pub(super) fn read(r: &mut Reader<'_>) -> io::Result<Self> {
        let class = r.object()?;
        let key = r.object()?;
        let sight = r.u8()?;
        let extended_sight = if sight & 0x80 != 0 {
            Some((r.u32()?, r.u8()?, r.u8()?))
        } else {
            None
        };
        Ok(Self {
            class,
            key,
            sight,
            extended_sight,
        })
    }
    pub(super) fn write(&self, w: &mut Writer) {
        w.object(self.class);
        w.object(self.key);
        w.u8(self.sight);
        if let Some((flags, dark, invisible)) = self.extended_sight {
            w.u32(flags);
            w.u8(dark);
            w.u8(invisible);
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct DmString {
    pub data: Vec<u8>,
    /// Original count of 0xffff length chunks, kept for exact round trips.
    pub long_chunks: u16,
}

pub(super) fn crypt_string(data: &mut [u8], offset: usize) {
    let mut key = offset as u8;
    for byte in data {
        *byte ^= key;
        key = key.wrapping_add(9);
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Proc {
    pub strings: [u32; 4],
    pub source_parameter: u8,
    pub source_kind: u8,
    pub flags: u8,
    pub extended_flags: Option<(u32, u8)>,
    pub code_locals_args: [u32; 3],
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProcSource {
    Default,
    InView(u8),
    InOView(u8),
    InRange(u8),
    InUsr,
    IsUsr,
    IsUsrLoc,
    Other { kind: u8, parameter: u8 },
}
impl Proc {
    pub fn source_location(&self) -> ProcSource {
        match self.source_kind {
            0 => ProcSource::Default,
            1 => ProcSource::InView(self.source_parameter),
            2 => ProcSource::InOView(self.source_parameter),
            3 => ProcSource::IsUsrLoc,
            5 => ProcSource::InRange(self.source_parameter),
            8 => ProcSource::InUsr,
            32 => ProcSource::IsUsr,
            kind => ProcSource::Other {
                kind,
                parameter: self.source_parameter,
            },
        }
    }
    /// Extended records replace the compact flag bits, retaining the same
    /// low-bit meanings and adding background/instant controls.
    pub fn effective_flags(&self) -> u32 {
        self.extended_flags
            .map_or(u32::from(self.flags), |extra| extra.0)
    }
    pub fn is_hidden(&self) -> bool {
        self.effective_flags() & 1 != 0
    }
    pub fn waits_for_completion(&self) -> bool {
        self.effective_flags() & 4 != 0
    }
    pub fn runs_in_background(&self) -> bool {
        self.effective_flags() & 0x100 != 0
    }
    pub fn is_instant(&self) -> bool {
        self.effective_flags() & 0x200 != 0
    }
    pub fn has_explicit_source(&self) -> bool {
        self.effective_flags() & 0x2 != 0
    }
    pub fn has_no_category(&self) -> bool {
        self.effective_flags() & 0x20 != 0
    }
    pub fn popup_menu_disabled(&self) -> bool {
        self.effective_flags() & 0x40 != 0
    }
    /// Explicit `set invisibility` value. Wire byte 255 encodes level zero;
    /// positive values use the byte directly and are capped at 127.
    pub fn invisibility_setting(&self) -> Option<u8> {
        let (flags, level) = self.extended_flags?;
        if flags & 0x8 == 0 {
            None
        } else if flags & 0x10 == 0 {
            Some(0)
        } else {
            Some(level)
        }
    }
    pub(super) fn read(r: &mut Reader<'_>) -> io::Result<Self> {
        let mut strings = [0; 4];
        for value in &mut strings {
            *value = r.object()?;
        }
        let source_parameter = r.u8()?;
        let source_kind = r.u8()?;
        let flags = r.u8()?;
        let extended_flags = if flags & 0x80 != 0 {
            Some((r.u32()?, r.u8()?))
        } else {
            None
        };
        let mut code_locals_args = [0; 3];
        for value in &mut code_locals_args {
            *value = r.object()?;
        }
        Ok(Self {
            strings,
            source_parameter,
            source_kind,
            flags,
            extended_flags,
            code_locals_args,
        })
    }
    pub(super) fn write(&self, w: &mut Writer) {
        for value in self.strings {
            w.object(value);
        }
        w.u8(self.source_parameter);
        w.u8(self.source_kind);
        w.u8(self.flags);
        if let Some((value, byte)) = self.extended_flags {
            w.u32(value);
            w.u8(byte);
        }
        for value in self.code_locals_args {
            w.object(value);
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Variable {
    pub kind: u8,
    pub value: u32,
    pub name: u32,
}
impl Variable {
    pub fn value_kind(&self) -> crate::operands::ValueKind {
        crate::operands::ValueKind::from_tag(self.kind)
    }
    pub fn number(&self) -> Option<f32> {
        (self.kind == 42).then(|| f32::from_bits(self.value))
    }
    /// Compiler-assigned marker for a value constructed by an initializer proc.
    /// The initializer bytecode uses the variable ID, not this marker.
    pub fn hidden_initializer_marker(&self) -> Option<u32> {
        (self.kind == 62).then_some(self.value)
    }
}
#[derive(Clone, Debug, PartialEq)]
pub struct Instance {
    pub kind: u8,
    pub class: u32,
    pub initializer: u32,
}
impl Instance {
    pub fn value_kind(&self) -> crate::operands::ValueKind {
        crate::operands::ValueKind::from_tag(self.kind)
    }
}
#[derive(Clone, Debug, PartialEq)]
pub struct MapObject {
    pub offset: u16,
    pub instance: u32,
}
#[derive(Clone, Debug, PartialEq)]
pub struct ResourceRef {
    pub id: u32,
    pub kind: u8,
}

/// Native loader interpretation of the serialized world.view word.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WorldViewEncoding {
    Radius(i16),
    Dimensions { width: u8, height: u8 },
}
impl WorldViewEncoding {
    /// Dimensions of the native loader's signed 16-bit axis fields.
    pub fn dimensions(self) -> (i16, i16) {
        match self {
            Self::Radius(radius) => {
                let side = radius.wrapping_mul(2).wrapping_add(1);
                (side, side)
            }
            Self::Dimensions { width, height } => (i16::from(width), i16::from(height)),
        }
    }
}
#[derive(Clone, Debug, PartialEq)]
pub struct World {
    pub ids: [u32; 7],
    /// `world.tick_lag` expressed in integer milliseconds by Dream Maker.
    pub tick_lag: u32,
    pub client: u32,
    pub image: u32,
    /// Initial /savefile/byond_version value.
    pub savefile_byond_version: u32,
    pub eye: u8,
    pub direction: u8,
    pub control: u16,
    /// Authored client Import-handler presence. Kept under its original public
    /// field name for compatibility; use the semantic accessors below.
    pub unknown_byte: u8,
    pub client_script: u32,
    pub client_script_files: Vec<u32>,
    /// Serialized world.view word; use view_encoding() for the native radius/axis interpretation.
    pub view_dimensions: u16,
    pub hub_password: u32,
    pub server_name: u32,
    pub hub_number: u32,
    pub version: u32,
    pub cache_lifespan: u16,
    pub command_ids: [u32; 2],
    pub hub_channel_skin: [u32; 3],
    pub icon_dimensions_format: [u16; 3],
}
impl World {
    pub fn has_client_import_handler(&self) -> bool {
        self.unknown_byte != 0
    }
    pub fn set_client_import_handler(&mut self, present: bool) {
        self.unknown_byte = u8::from(present);
    }
    pub fn mob_type_id(&self) -> u32 {
        self.ids[0]
    }
    pub fn turf_class_id(&self) -> u32 {
        self.ids[1]
    }
    pub fn area_class_id(&self) -> u32 {
        self.ids[2]
    }
    pub fn proc_list_id(&self) -> u32 {
        self.ids[3]
    }
    pub fn global_initializer_proc_id(&self) -> u32 {
        self.ids[4]
    }
    pub fn domain_string_id(&self) -> u32 {
        self.ids[5]
    }
    pub fn name_string_id(&self) -> u32 {
        self.ids[6]
    }
    pub fn client_command_text_id(&self) -> u32 {
        self.command_ids[0]
    }
    pub fn client_command_prompt_id(&self) -> u32 {
        self.command_ids[1]
    }
    pub fn hub_string_id(&self) -> u32 {
        self.hub_channel_skin[0]
    }
    pub fn channel_string_id(&self) -> u32 {
        self.hub_channel_skin[1]
    }
    pub fn skin_resource_id(&self) -> u32 {
        self.hub_channel_skin[2]
    }
    pub fn icon_size(&self) -> (u16, u16) {
        (
            self.icon_dimensions_format[0],
            self.icon_dimensions_format[1],
        )
    }
    pub fn map_format(&self) -> u16 {
        self.icon_dimensions_format[2]
    }
    pub fn view_encoding(&self) -> WorldViewEncoding {
        let signed = self.view_dimensions as i16;
        if signed <= 255 {
            WorldViewEncoding::Radius(signed)
        } else {
            WorldViewEncoding::Dimensions {
                width: (self.view_dimensions >> 8) as u8,
                height: self.view_dimensions as u8,
            }
        }
    }
    pub fn native_view_size(&self) -> (i16, i16) {
        self.view_encoding().dimensions()
    }
    /// Raw high/low bytes, retained for compatibility. These are not always axes.
    pub fn view_size(&self) -> (u8, u8) {
        (
            (self.view_dimensions >> 8) as u8,
            self.view_dimensions as u8,
        )
    }

    pub fn set_view_size(&mut self, width: u8, height: u8) {
        self.view_dimensions = (u16::from(width) << 8) | u16::from(height);
    }

    pub(super) fn read(r: &mut Reader<'_>) -> io::Result<Self> {
        let mut ids = [0; 7];
        for value in &mut ids {
            *value = r.object()?;
        }
        let tick_lag = r.u32()?;
        let client = r.object()?;
        let image = r.object()?;
        let savefile_byond_version = if r.compatibility_version <= 514 {
            0
        } else {
            r.u32()?
        };
        let eye = r.u8()?;
        let direction = r.u8()?;
        let control = r.u16()?;
        let unknown_byte = r.u8()?;
        let client_script = r.object()?;
        let script_file_count = r.u16()? as usize;
        let mut client_script_files = Vec::with_capacity(script_file_count);
        for _ in 0..script_file_count {
            client_script_files.push(r.object()?);
        }
        let view_dimensions = r.u16()?;
        let hub_password = r.object()?;
        let server_name = r.object()?;
        let hub_number = r.u32()?;
        let version = r.u32()?;
        let cache_lifespan = r.u16()?;
        let mut command_ids = [0; 2];
        for value in &mut command_ids {
            *value = r.object()?;
        }
        let mut hub_channel_skin = [0; 3];
        for value in &mut hub_channel_skin {
            *value = r.object()?;
        }
        let mut icon_dimensions_format = [0; 3];
        for value in &mut icon_dimensions_format {
            *value = r.u16()?;
        }
        Ok(Self {
            ids,
            tick_lag,
            client,
            image,
            savefile_byond_version,
            eye,
            direction,
            control,
            unknown_byte,
            client_script,
            client_script_files,
            view_dimensions,
            hub_password,
            server_name,
            hub_number,
            version,
            cache_lifespan,
            command_ids,
            hub_channel_skin,
            icon_dimensions_format,
        })
    }
    pub(super) fn write(&self, w: &mut Writer) {
        for value in self.ids {
            w.object(value);
        }
        w.u32(self.tick_lag);
        w.object(self.client);
        w.object(self.image);
        if w.compatibility_version > 514 {
            w.u32(self.savefile_byond_version);
        }
        w.u8(self.eye);
        w.u8(self.direction);
        w.u16(self.control);
        w.u8(self.unknown_byte);
        w.object(self.client_script);
        w.u16(self.client_script_files.len() as u16);
        for value in &self.client_script_files {
            w.object(*value);
        }
        w.u16(self.view_dimensions);
        w.object(self.hub_password);
        w.object(self.server_name);
        w.u32(self.hub_number);
        w.u32(self.version);
        w.u16(self.cache_lifespan);
        for value in self.command_ids {
            w.object(value);
        }
        for value in self.hub_channel_skin {
            w.object(value);
        }
        for value in self.icon_dimensions_format {
            w.u16(value);
        }
    }
}
