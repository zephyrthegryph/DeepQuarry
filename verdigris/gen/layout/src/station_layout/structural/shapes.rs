use super::*;

pub(super) fn projected_room_tile_area(cells: &BTreeSet<CellPoint>) -> usize {
    let interiors = cells.len() * usize::from(INTERIOR).pow(2);
    let shared_edges = cells
        .iter()
        .map(|point| {
            usize::from(cells.contains(&CellPoint {
                x: point.x.saturating_add(1),
                y: point.y,
            })) + usize::from(cells.contains(&CellPoint {
                x: point.x,
                y: point.y.saturating_add(1),
            }))
        })
        .sum::<usize>();
    let shared_vertices = cells
        .iter()
        .filter(|point| {
            let Some(east_x) = point.x.checked_add(1) else {
                return false;
            };
            let Some(north_y) = point.y.checked_add(1) else {
                return false;
            };
            cells.contains(&CellPoint {
                x: east_x,
                y: point.y,
            }) && cells.contains(&CellPoint {
                x: point.x,
                y: north_y,
            }) && cells.contains(&CellPoint {
                x: east_x,
                y: north_y,
            })
        })
        .count();
    interiors + shared_edges * usize::from(INTERIOR) + shared_vertices
}

pub(super) fn projected_room_dimensions(cells: &BTreeSet<CellPoint>) -> (usize, usize) {
    let Some(min_x) = cells.iter().map(|point| point.x).min() else {
        return (0, 0);
    };
    let max_x = cells.iter().map(|point| point.x).max().unwrap_or(min_x);
    let min_y = cells.iter().map(|point| point.y).min().unwrap_or(0);
    let max_y = cells.iter().map(|point| point.y).max().unwrap_or(min_y);
    (
        usize::from(max_x - min_x) * usize::from(PITCH) + usize::from(INTERIOR),
        usize::from(max_y - min_y) * usize::from(PITCH) + usize::from(INTERIOR),
    )
}

pub(super) fn room_has_center_lobe(cells: &BTreeSet<CellPoint>) -> bool {
    cells.iter().any(|point| {
        let Some(east) = point.x.checked_add(1) else {
            return false;
        };
        let Some(north) = point.y.checked_add(1) else {
            return false;
        };
        cells.contains(&CellPoint {
            x: east,
            y: point.y,
        }) && cells.contains(&CellPoint {
            x: point.x,
            y: north,
        }) && cells.contains(&CellPoint { x: east, y: north })
    })
}

pub(super) fn room_minimum_area(room: &RoomType) -> usize {
    // `content_area` is the authoritative authored capacity contract supplied
    // by DM. Center activity affects shape preference, not whether the planner
    // may silently shrink a complete room program into one logical cell.
    usize::try_from(room.content_area).unwrap_or(usize::MAX)
}

pub(super) fn room_shape_fits(room: &RoomType, cells: &BTreeSet<CellPoint>) -> bool {
    let area = projected_room_tile_area(cells);
    let (width, height) = projected_room_dimensions(cells);
    let minimum_area = room_minimum_area(room);
    // Content programs own room capacity. A large residual lobe must become
    // another purposeful room, not stretch one workstation across a hangar.
    let ideal_area = usize::try_from(room.ideal_area).unwrap_or(usize::MAX);
    let maximum_area = if ideal_area >= 40 {
        ideal_area.saturating_add(20)
    } else {
        ideal_area.saturating_mul(2)
    }
    .min(64)
    .max(room_minimum_area(room));
    let maximum_area = maximum_area.saturating_add(
        usize::from(maximum_area < 48) * usize::from(PITCH) * usize::from(INTERIOR),
    );
    // The logical grid advances in multi-tile modules, so a generated lobe can
    // legitimately land between an authored minimum and the next grid pitch.
    // Minimum usable area and short-side thickness express the lower bound;
    // the physical maxima remain hard and may be rotated with the room.
    let pitch_slack = usize::from(PITCH) * 3;
    let direct_envelope = width <= usize::from(room.max_width) + pitch_slack
        && height <= usize::from(room.max_height) + pitch_slack;
    let rotated_envelope = height <= usize::from(room.max_width) + pitch_slack
        && width <= usize::from(room.max_height) + pitch_slack;
    // The structural boundary on the open side completes the apparent room
    // width. Count it for thickness/aspect, but never for usable content area.
    let short_side = width.min(height).saturating_add(1);
    let long_side = width.max(height);
    let aspect_millis = long_side.saturating_mul(1000) / short_side.max(1);
    if area < minimum_area
        || area > maximum_area
        || !(direct_envelope || rotated_envelope)
        || short_side < usize::from(room.min_short_side)
        || aspect_millis > room.max_aspect_ratio_millis as usize
    {
        return false;
    }

    // A room whose authored program uses its center needs a genuine interior
    // lobe, not a one-cell-wide snake whose bounding box merely looks large.
    !room.requires_center_activity || room_has_center_lobe(cells)
}

pub(super) fn room_shape_within_maximum(room: &RoomType, cells: &BTreeSet<CellPoint>) -> bool {
    let area = projected_room_tile_area(cells);
    let (width, height) = projected_room_dimensions(cells);
    let slack = usize::from(PITCH) * 3;
    let direct = width <= usize::from(room.max_width) + slack
        && height <= usize::from(room.max_height) + slack;
    let rotated = height <= usize::from(room.max_width) + slack
        && width <= usize::from(room.max_height) + slack;
    let ideal_area = usize::try_from(room.ideal_area).unwrap_or(usize::MAX);
    let maximum_area = if ideal_area >= 40 {
        ideal_area.saturating_add(20)
    } else {
        ideal_area.saturating_mul(2)
    }
    .min(64)
    .max(room_minimum_area(room));
    let maximum_area = maximum_area.saturating_add(
        usize::from(maximum_area < 48) * usize::from(PITCH) * usize::from(INTERIOR),
    );
    if area > maximum_area || !(direct || rotated) {
        return false;
    }
    if area < room_minimum_area(room) {
        return true;
    }
    let short_side = width.min(height).saturating_add(1);
    let long_side = width.max(height);
    short_side >= usize::from(room.min_short_side)
        && long_side.saturating_mul(1000) / short_side.max(1)
            <= room.max_aspect_ratio_millis as usize
}

pub(super) fn room_shape_score(room: &RoomType, cells: &BTreeSet<CellPoint>) -> usize {
    let area = projected_room_tile_area(cells);
    let (width, height) = projected_room_dimensions(cells);
    let area_error = area.abs_diff(room.ideal_area as usize);
    let aspect_penalty = width.max(height).saturating_sub(width.min(height));
    let logical_width = cells
        .iter()
        .map(|point| point.x)
        .max()
        .zip(cells.iter().map(|point| point.x).min())
        .map_or(0, |(max, min)| usize::from(max - min) + 1);
    let logical_height = cells
        .iter()
        .map(|point| point.y)
        .max()
        .zip(cells.iter().map(|point| point.y).min())
        .map_or(0, |(max, min)| usize::from(max - min) + 1);
    // Missing modules inside the bounding envelope are allowed, producing
    // useful L/T rooms, but are costly enough that long hooks and amoeba-like
    // claims lose to compact alternatives.
    let envelope_voids = logical_width
        .saturating_mul(logical_height)
        .saturating_sub(cells.len());
    let envelope_center_width = usize::from(room.min_width + room.max_width) / 2;
    let envelope_center_height = usize::from(room.min_height + room.max_height) / 2;
    let direct_dimension_error =
        width.abs_diff(envelope_center_width) + height.abs_diff(envelope_center_height);
    let rotated_dimension_error =
        height.abs_diff(envelope_center_width) + width.abs_diff(envelope_center_height);
    area_error * 8
        + aspect_penalty * 12
        + envelope_voids * 18
        + direct_dimension_error.min(rotated_dimension_error) * 3
}

pub(super) fn split_shape_for_authored_rooms<'a>(
    shape: &BTreeSet<CellPoint>,
    variants: &'a [RoomType],
    width: u16,
    height: u16,
    depth: usize,
    frontage_cut_vertical: Option<bool>,
) -> Option<Vec<(BTreeSet<CellPoint>, &'a RoomType)>> {
    if let Some(variant) = variants
        .iter()
        .filter(|variant| room_shape_fits(variant, shape))
        .min_by_key(|variant| room_shape_score(variant, shape))
    {
        return Some(vec![(shape.clone(), variant)]);
    }
    if depth == 0 || shape.len() < 2 {
        return None;
    }
    let min_x = shape.iter().map(|point| point.x).min()?;
    let max_x = shape.iter().map(|point| point.x).max()?;
    let min_y = shape.iter().map(|point| point.y).min()?;
    let max_y = shape.iter().map(|point| point.y).max()?;
    let mut cuts = Vec::new();
    if max_x > min_x && frontage_cut_vertical != Some(false) {
        for cut in min_x..max_x {
            cuts.push((max_x - min_x, true, cut));
        }
    }
    if max_y > min_y && frontage_cut_vertical != Some(true) {
        for cut in min_y..max_y {
            cuts.push((max_y - min_y, false, cut));
        }
    }
    cuts.sort_by_key(|(span, vertical, cut)| {
        let midpoint = if *vertical {
            min_x + (max_x - min_x) / 2
        } else {
            min_y + (max_y - min_y) / 2
        };
        (Reverse(*span), cut.abs_diff(midpoint))
    });
    cuts.truncate(1);
    for (_, vertical, cut) in cuts {
        let left = shape
            .iter()
            .copied()
            .filter(|point| {
                if vertical {
                    point.x <= cut
                } else {
                    point.y <= cut
                }
            })
            .collect::<BTreeSet<_>>();
        let right = shape.difference(&left).copied().collect::<BTreeSet<_>>();
        if left.is_empty()
            || right.is_empty()
            || !cells_connected(&left, width, height)
            || !cells_connected(&right, width, height)
        {
            continue;
        }
        if let (Some(mut left_rooms), Some(right_rooms)) = (
            split_shape_for_authored_rooms(
                &left,
                variants,
                width,
                height,
                depth - 1,
                frontage_cut_vertical,
            ),
            split_shape_for_authored_rooms(
                &right,
                variants,
                width,
                height,
                depth - 1,
                frontage_cut_vertical,
            ),
        ) {
            left_rooms.extend(right_rooms);
            return Some(left_rooms);
        }
    }
    variants
        .iter()
        .filter(|variant| room_shape_within_maximum(variant, shape))
        .min_by_key(|variant| room_shape_score(variant, shape))
        .map(|variant| vec![(shape.clone(), variant)])
}

pub(super) fn force_split_authored_shape<'a>(
    shape: &BTreeSet<CellPoint>,
    variants: &'a [RoomType],
    width: u16,
    height: u16,
    frontage_cut_vertical: Option<bool>,
) -> Option<Vec<(BTreeSet<CellPoint>, &'a RoomType)>> {
    let min_x = shape.iter().map(|point| point.x).min()?;
    let max_x = shape.iter().map(|point| point.x).max()?;
    let min_y = shape.iter().map(|point| point.y).min()?;
    let max_y = shape.iter().map(|point| point.y).max()?;
    let mut cuts = Vec::new();
    for cut in min_x..max_x {
        if frontage_cut_vertical == Some(false) {
            continue;
        }
        cuts.push((
            Reverse(max_x - min_x),
            cut.abs_diff((min_x + max_x) / 2),
            true,
            cut,
        ));
    }
    for cut in min_y..max_y {
        if frontage_cut_vertical == Some(true) {
            continue;
        }
        cuts.push((
            Reverse(max_y - min_y),
            cut.abs_diff((min_y + max_y) / 2),
            false,
            cut,
        ));
    }
    cuts.sort();
    for (_, _, vertical, cut) in cuts {
        let left = shape
            .iter()
            .copied()
            .filter(|point| {
                if vertical {
                    point.x <= cut
                } else {
                    point.y <= cut
                }
            })
            .collect::<BTreeSet<_>>();
        let right = shape.difference(&left).copied().collect::<BTreeSet<_>>();
        if left.is_empty()
            || right.is_empty()
            || !cells_connected(&left, width, height)
            || !cells_connected(&right, width, height)
        {
            continue;
        }
        if let (Some(mut left_rooms), Some(right_rooms)) = (
            split_shape_for_authored_rooms(
                &left,
                variants,
                width,
                height,
                6,
                frontage_cut_vertical,
            ),
            split_shape_for_authored_rooms(
                &right,
                variants,
                width,
                height,
                6,
                frontage_cut_vertical,
            ),
        ) {
            left_rooms.extend(right_rooms);
            return Some(left_rooms);
        }
    }
    None
}
