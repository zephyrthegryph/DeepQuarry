use super::*;

pub(super) fn is_wall(class: TileClass) -> bool {
    matches!(
        class,
        TileClass::Hull | TileClass::Structure | TileClass::Partition
    )
}

pub(super) fn shortest_path_between_sets(
    starts: &BTreeSet<CellPoint>,
    goals: &BTreeSet<CellPoint>,
    allowed: &BTreeSet<CellPoint>,
    width: u16,
    height: u16,
) -> Option<Vec<CellPoint>> {
    let mut frontier: VecDeque<_> = starts.iter().copied().collect();
    let mut previous: BTreeMap<_, _> = starts.iter().map(|point| (*point, *point)).collect();
    let goal = loop {
        let point = frontier.pop_front()?;
        if goals.contains(&point) {
            break point;
        }
        for neighbor in cardinal_cells(point, width, height) {
            if allowed.contains(&neighbor) && !previous.contains_key(&neighbor) {
                previous.insert(neighbor, point);
                frontier.push_back(neighbor);
            }
        }
    };
    let mut path = Vec::new();
    let mut cursor = goal;
    loop {
        path.push(cursor);
        let prior = previous[&cursor];
        if prior == cursor {
            break;
        }
        cursor = prior;
    }
    Some(path)
}

/// Attaches one new branch to exactly one point of an existing public tree.
/// Keeping the branch away from every other tree edge prevents incidental
/// side-by-side contact from creating a closed hallway loop.
pub(super) fn connected_components(
    points: &BTreeSet<CellPoint>,
    width: u16,
    height: u16,
) -> Vec<BTreeSet<CellPoint>> {
    let mut remaining = points.clone();
    let mut components = Vec::new();
    while let Some(seed) = remaining.first().copied() {
        let mut component = BTreeSet::new();
        let mut frontier = VecDeque::from([seed]);
        while let Some(point) = frontier.pop_front() {
            if !remaining.remove(&point) {
                continue;
            }
            component.insert(point);
            frontier.extend(cardinal_cells(point, width, height));
        }
        components.push(component);
    }
    components
}

pub(super) fn cells_connected(points: &BTreeSet<CellPoint>, width: u16, height: u16) -> bool {
    points.is_empty() || connected_components(points, width, height).len() == 1
}

pub(super) fn point_components(points: &BTreeSet<Point>, width: u16, height: u16) -> Vec<BTreeSet<Point>> {
    let mut remaining = points.clone();
    let mut components = Vec::new();
    while let Some(seed) = remaining.first().copied() {
        let mut component = BTreeSet::new();
        let mut frontier = VecDeque::from([seed]);
        while let Some(point) = frontier.pop_front() {
            if !remaining.remove(&point) {
                continue;
            }
            component.insert(point);
            frontier.extend(cardinal_points(point, width, height));
        }
        components.push(component);
    }
    components
}

pub(super) fn points_connected(points: &BTreeSet<Point>, width: u16, height: u16) -> bool {
    points.is_empty() || point_components(points, width, height).len() == 1
}

pub(super) fn flood_points(
    start: Point,
    allowed: &BTreeSet<Point>,
    width: u16,
    height: u16,
) -> BTreeSet<Point> {
    let mut reached = BTreeSet::new();
    let mut frontier = VecDeque::from([start]);
    while let Some(point) = frontier.pop_front() {
        if !allowed.contains(&point) || !reached.insert(point) {
            continue;
        }
        frontier.extend(cardinal_points(point, width, height));
    }
    reached
}

pub(super) fn exterior_flood(tiles: &[TileCell], width: u16, height: u16) -> BTreeSet<Point> {
    let index = |point: Point| usize::from(point.y) * usize::from(width) + usize::from(point.x);
    let mut exterior = BTreeSet::new();
    let mut frontier = VecDeque::new();
    for x in 0..width {
        frontier.push_back(Point { x, y: 0 });
        frontier.push_back(Point { x, y: height - 1 });
    }
    for y in 0..height {
        frontier.push_back(Point { x: 0, y });
        frontier.push_back(Point { x: width - 1, y });
    }
    while let Some(point) = frontier.pop_front() {
        if tiles[index(point)].class != TileClass::Exterior || !exterior.insert(point) {
            continue;
        }
        frontier.extend(cardinal_points(point, width, height));
    }
    exterior
}

pub(super) fn bounds(points: &[Point]) -> Result<Rect, LayoutError> {
    let min_x = points
        .iter()
        .map(|point| point.x)
        .min()
        .ok_or_else(|| LayoutError("cannot bound an empty region".into()))?;
    let max_x = points
        .iter()
        .map(|point| point.x)
        .max()
        .expect("invariant: `min_x` above already rejected an empty `points`");
    let min_y = points
        .iter()
        .map(|point| point.y)
        .min()
        .expect("invariant: `min_x` above already rejected an empty `points`");
    let max_y = points
        .iter()
        .map(|point| point.y)
        .max()
        .expect("invariant: `min_x` above already rejected an empty `points`");
    Ok(Rect {
        x: min_x,
        y: min_y,
        width: max_x - min_x + 1,
        height: max_y - min_y + 1,
    })
}

pub(super) fn points_with_class(tiles: &[TileCell], width: u16, class: TileClass) -> Vec<Point> {
    tiles
        .iter()
        .enumerate()
        .filter(|(_, tile)| tile.class == class)
        .map(|(index, _)| Point {
            x: (index % usize::from(width)) as u16,
            y: (index / usize::from(width)) as u16,
        })
        .collect()
}

pub(super) fn cardinal_cells(point: CellPoint, width: u16, height: u16) -> Vec<CellPoint> {
    let mut result = Vec::with_capacity(4);
    if point.x > 0 {
        result.push(CellPoint {
            x: point.x - 1,
            y: point.y,
        });
    }
    if point.x + 1 < width {
        result.push(CellPoint {
            x: point.x + 1,
            y: point.y,
        });
    }
    if point.y > 0 {
        result.push(CellPoint {
            x: point.x,
            y: point.y - 1,
        });
    }
    if point.y + 1 < height {
        result.push(CellPoint {
            x: point.x,
            y: point.y + 1,
        });
    }
    result
}

pub(super) fn cardinal_points(point: Point, width: u16, height: u16) -> Vec<Point> {
    let mut result = Vec::with_capacity(4);
    if point.x > 0 {
        result.push(Point {
            x: point.x - 1,
            y: point.y,
        });
    }
    if point.x + 1 < width {
        result.push(Point {
            x: point.x + 1,
            y: point.y,
        });
    }
    if point.y > 0 {
        result.push(Point {
            x: point.x,
            y: point.y - 1,
        });
    }
    if point.y + 1 < height {
        result.push(Point {
            x: point.x,
            y: point.y + 1,
        });
    }
    result
}

pub(super) fn cell_distance(left: CellPoint, right: CellPoint) -> u16 {
    left.x.abs_diff(right.x) + left.y.abs_diff(right.y)
}

pub(super) fn hash_cell(seed: u64, point: CellPoint) -> u64 {
    mix(seed ^ (u64::from(point.x) << 32) ^ u64::from(point.y))
}

pub(super) fn mix(mut value: u64) -> u64 {
    value ^= value >> 30;
    value = value.wrapping_mul(0xbf58_476d_1ce4_e5b9);
    value ^= value >> 27;
    value = value.wrapping_mul(0x94d0_49bb_1331_11eb);
    value ^ (value >> 31)
}
