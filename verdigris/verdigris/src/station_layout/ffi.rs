use super::contract::CatalogMapping;
use super::{LayoutError, LayoutRequest, StationLayout, generate};

fn generate_catalog_layout(
    request: &LayoutRequest,
    mapping: &CatalogMapping,
) -> Result<StationLayout, LayoutError> {
    let layout = generate(request)?;
    if !mapping.architecture_choices.contains(&layout.archetype) {
        return Err(LayoutError(
            "generated architecture is excluded by the request".into(),
        ));
    }
    for room in &layout.rooms {
        let room_type = request
            .departments
            .iter()
            .find(|department| department.id == room.department_id)
            .and_then(|department| {
                department
                    .room_types
                    .iter()
                    .find(|room_type| room_type.id == room.room_type_id)
            })
            .ok_or_else(|| LayoutError(format!("room {} lost its catalog contract", room.id)))?;
        let tile_count = room.tiles.len();
        let maximum = usize::from(room_type.max_width) * usize::from(room_type.max_height);
        if tile_count > maximum {
            return Err(LayoutError(format!(
                "room {} contains {tile_count} tiles but its authored maximum is {maximum}",
                room.id
            )));
        }
    }
    Ok(layout)
}

#[cfg(target_arch = "x86")]
mod binds {
    use super::super::{decode_catalog, encode_plan};
    use super::generate_catalog_layout;
    use byondapi::prelude::*;
    use eyre::Result;

    #[byondapi::bind("/proc/verdigris_generate_station_layout")]
    #[auxmacros::panic_safe]
    fn verdigris_generate_station_layout(payload: ByondValue) -> Result<ByondValue> {
        let payload = payload.get_string()?;
        let (request, mapping) = decode_catalog(&payload)?;
        let layout = generate_catalog_layout(&request, &mapping)
            .map_err(|error| eyre::eyre!(error.to_string()))?;
        let response = encode_plan(&layout, &mapping)?;
        Ok(ByondValue::new_str(response.into_bytes())?)
    }
}
