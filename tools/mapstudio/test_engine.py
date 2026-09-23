import shutil
import tempfile
import unittest
import io
from unittest.mock import patch
from pathlib import Path
from PIL import Image

from engine import ROOT, MapStudio, Coordinate, ports, route_atom
import mcp
import server
from sprites import sprites


class MapStudioTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT / "maps", prefix="mapstudio-test-")
        self.path = Path(self.tmp.name) / "test.dmm"
        shutil.copyfile(ROOT / "maps/templates/unit_tests.dmm", self.path)
        self.relative = str(self.path.relative_to(ROOT)).replace("\\", "/")
        self.studio = MapStudio()

    def tearDown(self):
        self.tmp.cleanup()

    def test_preview_then_commit_round_trip(self):
        _, m, _ = self.studio.load(self.relative)
        c = Coordinate(1, 1, 1)
        turf = next(a for a in m.get_tile(c) if a.startswith("/turf/"))
        alternate = next(p for p in self.studio.catalog(m, layer="turf") if p != turf)
        operation = {"action": "paint", "layer": "turf", "at": c._asdict(), "atom": alternate}
        preview = self.studio.preview(self.relative, [operation])
        self.assertEqual(self.studio.load(self.relative)[1].get_tile(c), m.get_tile(c))
        self.assertEqual(preview["changed_tiles"], 1)
        saved = self.studio.commit(preview["preview_id"])
        self.assertIn(alternate, self.studio.load(self.relative)[1].get_tile(c))
        self.assertTrue((ROOT / saved["backup"]).exists())
        self.studio.undo()
        self.assertEqual(self.studio.load(self.relative)[1].get_tile(c), m.get_tile(c))

    def test_stale_preview_rejected(self):
        _, m, _ = self.studio.load(self.relative)
        c = Coordinate(1, 1, 1)
        alternate = next(p for p in self.studio.catalog(m, layer="turf") if p not in m.get_tile(c))
        preview = self.studio.preview(self.relative, [{"action": "paint", "layer": "turf", "at": c._asdict(), "atom": alternate}])
        self.path.write_bytes(self.path.read_bytes() + b"\n")
        with self.assertRaisesRegex(ValueError, "changed since preview"):
            self.studio.commit(preview["preview_id"])

    def test_erase_keeps_floor_and_area(self):
        _, m, _ = self.studio.load(self.relative)
        with self.assertRaisesRegex(ValueError, "replacement"):
            self.studio.preview(self.relative, [{"action": "erase", "layer": "turf", "at": {"x": 1, "y": 1, "z": 1}}])

    def test_move_relocates_full_stack(self):
        _, m, _ = self.studio.load(self.relative)
        source = next(c for raw in m.grid if (c := Coordinate(*raw)).x < m.size.x and
                      m.get_tile(c) != m.get_tile(Coordinate(c.x + 1, c.y, c.z)))
        dest = Coordinate(source.x + 1, source.y, source.z)
        source_atoms = m.get_tile(source)
        dest_atoms = m.get_tile(dest)
        preview = self.studio.preview(self.relative, [{"action": "move", "source": {"x1": source.x, "y1": source.y, "x2": source.x, "y2": source.y, "z": source.z},
                                                       "dx": 1, "dy": 0, "replace": True}])
        self.assertEqual(preview["changed_tiles"], 2)
        self.studio.commit(preview["preview_id"])
        _, moved, _ = self.studio.load(self.relative)
        self.assertEqual(moved.get_tile(dest), source_atoms)
        self.assertEqual(moved.get_tile(source), tuple(a for a in dest_atoms if a.startswith(("/turf/", "/area/"))))

    def test_network_segment_directions(self):
        cable = route_atom("/obj/structure/cable", "power", {1, 4})
        atmos = route_atom("/obj/machinery/atmospherics/pipe/simple/hidden/supply", "atmos", {1, 4})
        disposal = route_atom("/obj/structure/disposalpipe/segment", "disposals", {1, 4})
        self.assertEqual(ports(cable, "power"), {1, 4})
        self.assertEqual(ports(atmos, "atmos"), {1, 4})
        self.assertEqual(ports(disposal, "disposals"), {1, 4})
        self.assertEqual(ports('/obj/machinery/atmospherics/pipe/cap/hidden/fuel{dir = 2}', "atmos"), {2})
        self.assertEqual(ports('/obj/machinery/atmospherics/binary/circulator{dir = 1}', "atmos"), {1, 2})
        self.assertIn('icon_state = "pipe-c"', disposal)

    def test_pipe_and_disposal_drags_make_bends_and_branches(self):
        for layer, atom, junction in (
            ("atmos", "/obj/machinery/atmospherics/pipe/simple/hidden/supply", "/pipe/manifold/"),
            ("disposals", "/obj/structure/disposalpipe/segment", "/disposalpipe/junction/yjunction"),
        ):
            with self.subTest(layer=layer):
                bend = {"action": "route", "layer": layer, "atom": atom,
                        "points": [{"x": 1, "y": 1, "z": 1}, {"x": 2, "y": 1, "z": 1},
                                   {"x": 2, "y": 2, "z": 1}],
                        "snap_start": False, "snap_end": False, "auto_join_neighbors": False}
                preview = self.studio.preview(self.relative, [bend])
                center = next(d for d in preview["diff"] if d["x"] == 2 and d["y"] == 1)
                self.assertTrue(any(ports(a, layer) == {1, 8} for a in center["after"]))
                horizontal = {"action": "route", "layer": layer, "atom": atom,
                              "points": [{"x": 1, "y": 2, "z": 1}, {"x": 2, "y": 2, "z": 1},
                                         {"x": 3, "y": 2, "z": 1}],
                              "snap_start": False, "snap_end": False, "auto_join_neighbors": False}
                branch = {"action": "route", "layer": layer, "atom": atom,
                          "points": [{"x": 2, "y": 2, "z": 1}, {"x": 2, "y": 3, "z": 1}],
                          "snap_start": False, "snap_end": False, "auto_join_neighbors": False}
                preview = self.studio.preview(self.relative, [horizontal, branch])
                center = next(d for d in preview["diff"] if d["x"] == 2 and d["y"] == 2)
                fitting = next(a for a in center["after"] if junction in a and
                               ports(a, layer) == {1, 4, 8})
                component = self.studio.network_component(
                    self.relative, {"x": 2, "y": 2, "z": 1}, fitting, [horizontal, branch])
                self.assertTrue({(1, 2), (2, 2), (3, 2), (2, 3)} <=
                                {(member["x"], member["y"]) for member in component["members"]})

    def test_turf_sprite_resolves_and_renders(self):
        self.assertTrue(sprites.url("/turf/simulated/floor/tiled").startswith("/sprite?atom="))
        self.assertTrue(sprites.png("/turf/simulated/floor/tiled").startswith(b"\x89PNG"))

    def test_atlas_contains_exact_sprite_frame(self):
        atom = "/turf/simulated/floor/tiled"
        atlas = sprites.atlas({atom})
        sheet = Image.open(io.BytesIO(sprites.atlas_bytes(atlas["url"].split("=")[1])))
        x, y, width, height = atlas["frames"][atom]
        self.assertEqual(sheet.crop((x, y, x + width, y + height)).tobytes(), sprites.frame(atom).tobytes())

    def test_route_writes_connected_cable_states(self):
        _, m, _ = self.studio.load(self.relative)
        m.get_or_generate_key(("/obj/structure/cable", "/turf/space", "/area/space"))
        m.to_file(self.path)
        preview = self.studio.preview(self.relative, [{"action": "route", "layer": "power", "atom": "/obj/structure/cable",
                                                     "points": [{"x": 1, "y": 1, "z": 1}, {"x": 2, "y": 1, "z": 1}]}])
        self.assertEqual(preview["changed_tiles"], 2)
        self.assertEqual(ports(next(a for a in preview["diff"][0]["after"] if a.startswith("/obj/structure/cable")), "power"), {4})
        self.assertEqual(ports(next(a for a in preview["diff"][1]["after"] if a.startswith("/obj/structure/cable")), "power"), {8})

    def test_sequential_cable_strokes_remain_in_one_preview(self):
        first = {"action": "route", "layer": "power", "atom": "/obj/structure/cable/green",
                 "points": [{"x": 1, "y": 1, "z": 1}, {"x": 2, "y": 1, "z": 1}]}
        second = {"action": "route", "layer": "power", "atom": "/obj/structure/cable/blue",
                  "points": [{"x": 2, "y": 1, "z": 1}, {"x": 3, "y": 1, "z": 1}]}
        preview = self.studio.preview(self.relative, [first, second])
        self.assertEqual(preview["operations"], [first, second])
        by_x = {item["x"]: item["after"] for item in preview["diff"]}
        self.assertTrue(any(a.startswith("/obj/structure/cable/green") for a in by_x[1]))
        self.assertTrue(any(a.startswith("/obj/structure/cable/blue") for a in by_x[3]))
        self.assertTrue(any(a.startswith("/obj/structure/cable/green") for a in by_x[2]))

    def test_network_selection_follows_reciprocal_ports(self):
        _, m, _ = self.studio.load(self.relative)
        green = '/obj/structure/cable/green'
        first, second, isolated = Coordinate(1, 1, 1), Coordinate(2, 1, 1), Coordinate(3, 1, 1)
        m.set_tile(first, tuple(m.get_tile(first)) + (f'{green}{{icon_state = "0-4"}}',))
        m.set_tile(second, tuple(m.get_tile(second)) + (f'{green}{{icon_state = "0-8"}}',))
        m.set_tile(isolated, tuple(m.get_tile(isolated)) + (f'{green}{{icon_state = "0-1"}}',))
        self.path.write_bytes(m.to_bytes(tgm=True))
        result = self.studio.network_component(self.relative, first._asdict(), f'{green}{{icon_state = "0-4"}}')
        self.assertEqual({(item['x'], item['y']) for item in result['members']}, {(1, 1), (2, 1)})

    def test_network_selection_includes_unsaved_route(self):
        operation = {"action": "route", "layer": "power", "atom": "/obj/structure/cable/green",
                     "points": [{"x": 1, "y": 1, "z": 1}, {"x": 2, "y": 1, "z": 1},
                                {"x": 3, "y": 1, "z": 1}]}
        preview = self.studio.preview(self.relative, [operation])
        start = next(d for d in preview['diff'] if d['x'] == 1 and d['y'] == 1)
        atom = next(a for a in start['after'] if a.startswith('/obj/structure/cable/green'))
        result = self.studio.network_component(self.relative, {"x": 1, "y": 1, "z": 1}, atom, [operation])
        self.assertEqual({(m['x'], m['y']) for m in result['members']}, {(1, 1), (2, 1), (3, 1)})
        self.assertFalse(any(a.startswith('/obj/structure/cable/green') for a in
                             self.studio.load(self.relative)[1].get_tile(Coordinate(2, 1, 1))))

    def test_crossed_cables_remain_separate_selections(self):
        _, m, _ = self.studio.load(self.relative)
        point = Coordinate(2, 2, 1)
        horizontal = '/obj/structure/cable/green{icon_state = "4-8"}'
        vertical = '/obj/structure/cable/blue{icon_state = "1-2"}'
        m.set_tile(point, tuple(m.get_tile(point)) + (horizontal, vertical))
        m.to_file(self.path)
        result = self.studio.network_component(self.relative, point._asdict(), horizontal)
        self.assertEqual([item['atom'] for item in result['members']], [horizontal])

    def test_route_straight_across_cable_keeps_crossing_separate(self):
        _, m, _ = self.studio.load(self.relative)
        center = Coordinate(3, 3, 1)
        horizontal = '/obj/structure/cable/green{icon_state = "4-8"}'
        vertical = '/obj/structure/cable/blue{icon_state = "1-2"}'
        m.set_tile(center, tuple(m.get_tile(center)) + (horizontal,))
        m.to_file(self.path)
        points = [Coordinate(3, y, 1)._asdict() for y in (2, 3, 4)]
        operation = {"action": "route", "layer": "power", "atom": "/obj/structure/cable/blue",
                     "points": points}
        result = self.studio.preview(self.relative, [operation])
        crossing = next(d for d in result['diff'] if (d['x'], d['y']) == (3, 3))
        self.assertEqual({a for a in crossing['after'] if '/cable/' in a}, {horizontal, vertical})
        component = self.studio.network_component(self.relative, center._asdict(), horizontal, [operation])
        self.assertEqual([item['atom'] for item in component['members']], [horizontal])

    def test_route_opposite_corners_share_tile_without_merging(self):
        _, m, _ = self.studio.load(self.relative)
        center = Coordinate(3, 3, 1)
        northwest = '/obj/structure/cable/green{icon_state = "1-8"}'
        southeast = '/obj/structure/cable/blue{icon_state = "2-4"}'
        m.set_tile(center, tuple(m.get_tile(center)) + (northwest,))
        m.to_file(self.path)
        points = [Coordinate(x, y, 1)._asdict() for x, y in [(3, 2), (3, 3), (4, 3)]]
        operation = {"action": "route", "layer": "power", "atom": "/obj/structure/cable/blue",
                     "points": points}
        result = self.studio.preview(self.relative, [operation])
        corner = next(d for d in result['diff'] if (d['x'], d['y']) == (3, 3))
        self.assertEqual({a for a in corner['after'] if '/cable/' in a}, {northwest, southeast})
        component = self.studio.network_component(self.relative, center._asdict(), northwest, [operation])
        self.assertEqual([item['atom'] for item in component['members']], [northwest])

    def test_diagonal_cables_select_byond_side_connections(self):
        _, m, _ = self.studio.load(self.relative)
        start, north, east = (Coordinate(x, y, 1) for x, y in [(2, 2), (2, 3), (3, 2)])
        atoms = ['/obj/structure/cable/green{icon_state = "0-5"}',
                 '/obj/structure/cable/blue{icon_state = "0-6"}',
                 '/obj/structure/cable/yellow{icon_state = "0-9"}']
        for point, atom in zip((start, north, east), atoms):
            m.set_tile(point, tuple(m.get_tile(point)) + (atom,))
        m.to_file(self.path)
        component = self.studio.network_component(self.relative, start._asdict(), atoms[0])
        self.assertEqual({item['atom'] for item in component['members']}, set(atoms))

    def test_network_draft_does_not_replace_pending_preview(self):
        first = {"action": "route", "layer": "power", "atom": "/obj/structure/cable/green",
                 "points": [{"x": 1, "y": 1, "z": 1}, {"x": 2, "y": 1, "z": 1}]}
        second = {"action": "route", "layer": "power", "atom": "/obj/structure/cable/blue",
                  "points": [{"x": 2, "y": 1, "z": 1}, {"x": 3, "y": 1, "z": 1}]}
        preview = self.studio.preview(self.relative, [first])
        draft = self.studio.draft(self.relative, [first, second])
        self.assertEqual(self.studio.activity()['preview_id'], preview['preview_id'])
        self.assertTrue(any(item['x'] == 3 for item in draft['diff']))

    def test_static_system_check(self):
        result = self.studio.check_systems(self.relative, {"x1": 1, "y1": 1, "x2": 4, "y2": 4, "z": 1})
        self.assertEqual(result["counts"]["apc"], 0)
        self.assertIn("game boot", result["scope"])

    def test_read_cache_refreshes_after_commit_and_undo(self):
        _, original, old_revision = self.studio.read(self.relative)
        c = Coordinate(1, 1, 1)
        replacement = next(p for p in self.studio.catalog(original, layer="turf") if p not in original.get_tile(c))
        preview = self.studio.preview(self.relative, [{"action": "paint", "layer": "turf", "at": c._asdict(), "atom": replacement}])
        self.studio.commit(preview["preview_id"])
        _, changed, new_revision = self.studio.read(self.relative)
        self.assertNotEqual(new_revision, old_revision)
        self.assertIn(replacement, changed.get_tile(c))
        self.studio.undo()
        _, restored, restored_revision = self.studio.read(self.relative)
        self.assertEqual(restored_revision, old_revision)
        self.assertEqual(restored.get_tile(c), original.get_tile(c))

    def test_paint_disconnected_selected_points(self):
        _, original, _ = self.studio.load(self.relative)
        points = [Coordinate(1, 1, 1), Coordinate(3, 1, 1)]
        replacement = next(p for p in self.studio.catalog(original, layer="turf")
                           if all(p not in original.get_tile(c) for c in points))
        preview = self.studio.preview(self.relative, [{"action": "paint", "layer": "turf",
                                                       "points": [c._asdict() for c in points], "atom": replacement}])
        self.assertEqual(preview["changed_tiles"], 2)
        self.assertEqual({(d["x"], d["y"]) for d in preview["diff"]}, {(1, 1), (3, 1)})

    def test_dismiss_removes_activity_without_editing_map(self):
        _, original, revision = self.studio.load(self.relative)
        c = Coordinate(1, 1, 1)
        replacement = next(p for p in self.studio.catalog(original, layer="turf") if p not in original.get_tile(c))
        preview = self.studio.preview(self.relative, [{"action": "paint", "layer": "turf", "at": c._asdict(), "atom": replacement}])
        self.assertEqual(self.studio.activity()["preview_id"], preview["preview_id"])
        self.assertTrue(self.studio.dismiss(preview["preview_id"])["dismissed"])
        self.assertIsNone(self.studio.activity()["preview_id"])
        self.assertEqual(self.studio.load(self.relative)[2], revision)

    def test_edit_remove_and_paste_one_atom(self):
        c = Coordinate(1, 1, 1)
        atom = '/obj/structure/cable'
        placed = self.studio.preview(self.relative, [{'action': 'paste_atom', 'at': c._asdict(), 'atom': atom}])
        self.studio.commit(placed['preview_id'])
        edited = self.studio.preview(self.relative, [{'action': 'edit_atom', 'at': c._asdict(), 'atom': atom,
                                                       'vars': {'color': '#00ff00', 'pixel_x': 3}}])
        replacement = '/obj/structure/cable{color = "#00ff00"; pixel_x = 3}'
        self.assertIn(replacement, edited['diff'][0]['after'])
        self.studio.commit(edited['preview_id'])
        saved_atom = next(a for a in self.studio.load(self.relative)[1].get_tile(c) if a.startswith(atom))
        removed = self.studio.preview(self.relative, [{'action': 'remove_atom', 'at': c._asdict(), 'atom': saved_atom}])
        self.assertNotIn(saved_atom, removed['diff'][0]['after'])
        self.assertTrue(any(a.startswith('/turf/') for a in removed['diff'][0]['after']))

    def test_color_and_offset_appearance(self):
        atom = '/obj/structure/cable/yellow{pixel_x = 4; pixel_y = -2}'
        appearance = sprites.appearance(atom)
        self.assertEqual(appearance['color'].lower(), '#ffff00')
        self.assertEqual((appearance['pixel_x'], appearance['pixel_y']), (4, -2))

    def test_diagonal_cable_route_and_crossing(self):
        _, m, _ = self.studio.load(self.relative)
        route = self.studio.preview(self.relative, [{"action": "route", "layer": "power", "atom": "/obj/structure/cable/blue",
                                                    "points": [{"x": 1, "y": 1, "z": 1}, {"x": 2, "y": 2, "z": 1}]}])
        self.assertEqual(ports(next(a for a in route['diff'][0]['after'] if a.startswith('/obj/structure/cable')), 'power'), {5})
        self.assertEqual(ports(next(a for a in route['diff'][1]['after'] if a.startswith('/obj/structure/cable')), 'power'), {10})
        c = Coordinate(2, 2, 1)
        m.set_tile(c, tuple(m.get_tile(c)) + ('/obj/structure/cable{icon_state = "1-2"}',))
        m.to_file(self.path)
        cross = self.studio.preview(self.relative, [{"action": "network_cross", "at": c._asdict(),
                                                    "layer": "power", "atom": "/obj/structure/cable/blue"}])
        self.assertEqual(len([a for a in cross['diff'][0]['after'] if a.startswith('/obj/structure/cable')]), 2)

    def test_network_split_removes_only_selected_segment(self):
        _, m, _ = self.studio.load(self.relative)
        c = Coordinate(1, 1, 1)
        atom = '/obj/structure/cable{icon_state = "1-2"}'
        m.set_tile(c, tuple(m.get_tile(c)) + (atom,))
        m.to_file(self.path)
        saved = next(a for a in self.studio.load(self.relative)[1].get_tile(c) if a.startswith('/obj/structure/cable'))
        preview = self.studio.preview(self.relative, [{"action": "network_split", "at": c._asdict(),
                                                      "layer": "power", "atom": saved}])
        self.assertFalse(any(a.startswith('/obj/structure/cable') for a in preview['diff'][0]['after']))

    def test_place_with_appearance_and_join_ends(self):
        c = Coordinate(2, 2, 1)
        placed = self.studio.preview(self.relative, [{"action": "place_atom", "layer": "objects", "at": c._asdict(),
                                                      "atom": "/obj/item/stack/cable_coil", "vars": {"pixel_x": 3}}])
        self.assertTrue(any('pixel_x = 3' in a for a in placed['diff'][0]['after']))
        _, m, _ = self.studio.load(self.relative)
        left, right = Coordinate(1, 2, 1), Coordinate(3, 2, 1)
        m.set_tile(left, tuple(m.get_tile(left)) + ('/obj/structure/cable{icon_state = "0-4"}',))
        m.set_tile(right, tuple(m.get_tile(right)) + ('/obj/structure/cable{icon_state = "0-8"}',))
        m.to_file(self.path)
        joined = self.studio.preview(self.relative, [{"action": "network_join", "at": c._asdict(),
                                                      "layer": "power", "atom": "/obj/structure/cable"}])
        self.assertTrue(any('icon_state = "4-8"' in a for a in joined['diff'][0]['after']))

    def test_route_joins_existing_compatible_ends(self):
        _, m, _ = self.studio.load(self.relative)
        left, middle, right = Coordinate(1, 2, 1), Coordinate(2, 2, 1), Coordinate(3, 2, 1)
        atom = '/obj/structure/cable/blue'
        m.set_tile(left, tuple(m.get_tile(left)) + (f'{atom}{{icon_state = "0-8"}}',))
        m.set_tile(right, tuple(m.get_tile(right)) + (f'{atom}{{icon_state = "0-4"}}',))
        m.to_file(self.path)
        preview = self.studio.preview(self.relative, [{"action": "route", "layer": "power", "atom": atom,
            "points": [left._asdict(), middle._asdict(), right._asdict()]}])
        self.assertEqual(preview['changed_tiles'], 3)
        for tile in preview['diff']:
            cable = next(a for a in tile['after'] if a.startswith(atom))
            self.assertIn(4 if tile['x'] == 1 else 8 if tile['x'] == 3 else 4, ports(cable, 'power'))

    def test_route_joins_different_cable_colors_and_adjacent_start(self):
        _, m, _ = self.studio.load(self.relative)
        left, middle, right = Coordinate(1, 2, 1), Coordinate(2, 2, 1), Coordinate(3, 2, 1)
        m.set_tile(left, tuple(m.get_tile(left)) + ('/obj/structure/cable/blue{icon_state = "0-8"}',))
        m.set_tile(right, tuple(m.get_tile(right)) + ('/obj/structure/cable/yellow{icon_state = "0-4"}',))
        m.to_file(self.path)
        preview = self.studio.preview(self.relative, [{"action": "route", "layer": "power",
            "atom": "/obj/structure/cable", "points": [middle._asdict(), right._asdict()]}])
        self.assertEqual(preview['changed_tiles'], 3)
        by_x = {d['x']: d for d in preview['diff']}
        self.assertIn('/obj/structure/cable/blue{icon_state = "4-8"}', by_x[1]['after'])
        self.assertIn('/obj/structure/cable/yellow{icon_state = "4-8"}', by_x[3]['after'])
        self.assertIn('/obj/structure/cable{icon_state = "4-8"}', by_x[2]['after'])

    def test_route_extends_same_color_multi_segment_junction(self):
        _, m, _ = self.studio.load(self.relative)
        left, middle = Coordinate(1, 2, 1), Coordinate(2, 2, 1)
        green = '/obj/structure/cable/green'
        m.set_tile(left, tuple(m.get_tile(left)) +
                   (f'{green}{{icon_state = "0-1"}}', f'{green}{{icon_state = "0-2"}}'))
        m.to_file(self.path)
        preview = self.studio.preview(self.relative, [{"action": "route", "layer": "power", "atom": green,
            "points": [left._asdict(), middle._asdict()]}])
        by_x = {d['x']: d for d in preview['diff']}
        cables = [a for a in by_x[1]['after'] if a.startswith(green)]
        self.assertEqual(len(cables), 3)
        self.assertTrue(any(4 in ports(a, 'power') for a in cables))
        self.assertTrue(any(8 in ports(a, 'power') for a in by_x[2]['after'] if a.startswith(green)))

    def test_route_branches_off_same_color_straight_cable(self):
        _, m, _ = self.studio.load(self.relative)
        junction, north = Coordinate(2, 2, 1), Coordinate(2, 3, 1)
        green = '/obj/structure/cable/green'
        m.set_tile(junction, tuple(m.get_tile(junction)) + (f'{green}{{icon_state = "4-8"}}',))
        m.to_file(self.path)
        preview = self.studio.preview(self.relative, [{"action": "route", "layer": "power", "atom": green,
            "points": [junction._asdict(), north._asdict()]}])
        changed = next(d for d in preview['diff'] if d['y'] == 2)
        cables = [a for a in changed['after'] if a.startswith(green)]
        self.assertEqual(len(cables), 2)
        self.assertIn(f'{green}{{icon_state = "4-8"}}', cables)
        self.assertTrue(any(1 in ports(a, 'power') and ports(a, 'power') & {4, 8} for a in cables))

    def test_route_branch_uses_port_chosen_near_pointer(self):
        _, m, _ = self.studio.load(self.relative)
        junction, north = Coordinate(2, 2, 1), Coordinate(2, 3, 1)
        green = '/obj/structure/cable/green'
        m.set_tile(junction, tuple(m.get_tile(junction)) + (f'{green}{{icon_state = "4-8"}}',))
        m.to_file(self.path)
        route = {"action": "route", "layer": "power", "atom": green,
                 "points": [junction._asdict(), north._asdict()]}
        for preferred, state in ((4, '1-4'), (8, '1-8')):
            result = self.studio.preview(self.relative, [{**route, "anchor_port": preferred}])
            changed = next(d for d in result['diff'] if d['y'] == junction.y)
            self.assertIn(f'{green}{{icon_state = "{state}"}}', changed['after'])

    def test_route_up_left_down_left_joins_through_left_port(self):
        _, m, _ = self.studio.load(self.relative)
        green = '/obj/structure/cable/green'
        for x in (3, 4, 5):
            point = Coordinate(x, 2, 1)
            m.set_tile(point, tuple(m.get_tile(point)) + (f'{green}{{icon_state = "4-8"}}',))
        m.to_file(self.path)
        points = [Coordinate(x, y, 1)._asdict() for x, y in
                  [(5, 2), (5, 3), (4, 3), (4, 2), (3, 2)]]
        result = self.studio.preview(self.relative, [{"action": "route", "layer": "power",
            "atom": green, "points": points, "anchor_port": 4}])
        turn = next(d for d in result['diff'] if (d['x'], d['y']) == (4, 2))
        self.assertIn(f'{green}{{icon_state = "1-8"}}', turn['after'])
        self.assertNotIn(f'{green}{{icon_state = "1-4"}}', turn['after'])

    def test_route_end_uses_port_nearest_release_pointer(self):
        _, m, _ = self.studio.load(self.relative)
        green = '/obj/structure/cable/green'
        end = Coordinate(3, 2, 1)
        m.set_tile(end, tuple(m.get_tile(end)) + (f'{green}{{icon_state = "4-8"}}',))
        m.to_file(self.path)
        points = [Coordinate(3, 3, 1)._asdict(), end._asdict()]
        result = self.studio.preview(self.relative, [{"action": "route", "layer": "power",
            "atom": green, "points": points, "end_port": 8}])
        changed = next(d for d in result['diff'] if (d['x'], d['y']) == (3, 2))
        self.assertIn(f'{green}{{icon_state = "1-8"}}', changed['after'])

    def test_route_can_end_as_separate_stub_on_network_center(self):
        _, m, _ = self.studio.load(self.relative)
        green = '/obj/structure/cable/green'
        end = Coordinate(3, 2, 1)
        straight = f'{green}{{icon_state = "4-8"}}'
        m.set_tile(end, tuple(m.get_tile(end)) + (straight,))
        m.to_file(self.path)
        points = [Coordinate(3, 3, 1)._asdict(), end._asdict()]
        result = self.studio.preview(self.relative, [{"action": "route", "layer": "power",
            "atom": green, "points": points, "snap_end": False, "end_stub": True}])
        changed = next(d for d in result['diff'] if (d['x'], d['y']) == (3, 2))
        self.assertIn(straight, changed['after'])
        self.assertIn(f'{green}{{icon_state = "0-1"}}', changed['after'])
        self.assertNotIn(f'{green}{{icon_state = "1-8"}}', changed['after'])

    def test_pointer_route_only_joins_explicit_end_target(self):
        _, m, _ = self.studio.load(self.relative)
        green = '/obj/structure/cable/green'
        network = Coordinate(4, 2, 1)
        m.set_tile(network, tuple(m.get_tile(network)) + (f'{green}{{icon_state = "4-8"}}',))
        m.to_file(self.path)
        points = [Coordinate(x, 3, 1)._asdict() for x in (2, 3, 4)]
        route = {"action": "route", "layer": "power", "atom": green,
                 "points": points, "snap_end": False}
        unsnapped = self.studio.preview(self.relative, [route])
        self.assertFalse(any((d['x'], d['y']) == (4, 2) for d in unsnapped['diff']))
        snapped = self.studio.preview(self.relative, [{**route,
            "points": points + [network._asdict()], "end_port": 8}])
        join = next(d for d in snapped['diff'] if (d['x'], d['y']) == (4, 2))
        self.assertIn(f'{green}{{icon_state = "1-8"}}', join['after'])

    def test_unselected_route_starts_as_nub_next_to_network(self):
        _, m, _ = self.studio.load(self.relative)
        green = '/obj/structure/cable/green'
        network = Coordinate(1, 2, 1)
        m.set_tile(network, tuple(m.get_tile(network)) + (f'{green}{{icon_state = "4-8"}}',))
        m.to_file(self.path)
        points = [Coordinate(x, 2, 1)._asdict() for x in (2, 3)]
        route = {"action": "route", "layer": "power", "atom": "/obj/structure/cable/blue",
                 "points": points, "snap_start": False, "snap_end": False,
                 "auto_join_neighbors": False}
        result = self.studio.preview(self.relative, [route])
        self.assertFalse(any((d['x'], d['y']) == (1, 2) for d in result['diff']))
        start = next(d for d in result['diff'] if (d['x'], d['y']) == (2, 2))
        self.assertIn('/obj/structure/cable/blue{icon_state = "0-4"}', start['after'])

    def test_cable_route_can_loop_over_earlier_tile(self):
        points = [Coordinate(x, y, 1)._asdict() for x, y in
                  [(2, 2), (3, 2), (3, 3), (2, 3), (2, 2)]]
        route = {"action": "route", "layer": "power", "atom": "/obj/structure/cable/blue",
                 "points": points, "snap_start": False, "snap_end": False,
                 "auto_join_neighbors": False}
        result = self.studio.preview(self.relative, [route])
        origin = next(d for d in result['diff'] if (d['x'], d['y']) == (2, 2))
        cables = [atom for atom in origin['after'] if atom.startswith('/obj/structure/cable/blue')]
        self.assertTrue(any(4 in ports(atom, 'power') for atom in cables))
        self.assertTrue(any(1 in ports(atom, 'power') for atom in cables))

    def test_new_three_way_cable_junction_keeps_all_bridges(self):
        _, m, _ = self.studio.load(self.relative)
        green = '/obj/structure/cable/green'
        left, center, right, north = (Coordinate(x, y, 1) for x, y in
                                       [(1, 2), (2, 2), (3, 2), (2, 3)])
        for point, direction in [(left, 4), (right, 8), (north, 2)]:
            m.set_tile(point, tuple(m.get_tile(point)) +
                       (f'{green}{{icon_state = "0-{direction}"}}',))
        m.to_file(self.path)
        preview = self.studio.preview(self.relative, [{"action": "route", "layer": "power", "atom": green,
            "points": [left._asdict(), center._asdict(), right._asdict()]}])
        junction = next(item for item in preview['diff'] if (item['x'], item['y']) == (2, 2))
        segments = [a for a in junction['after'] if a.startswith(green)]
        self.assertEqual(len(segments), 2)
        self.assertEqual(set().union(*(ports(a, 'power') for a in segments)), {1, 4, 8})
        self.assertTrue(all(1 in ports(a, 'power') for a in segments))

    def test_leftward_cable_extension_uses_existing_right_port(self):
        _, m, _ = self.studio.load(self.relative)
        junction, left = Coordinate(3, 2, 1), Coordinate(2, 2, 1)
        green = '/obj/structure/cable/green'
        m.set_tile(junction, tuple(m.get_tile(junction)) +
                   (f'{green}{{icon_state = "1-4"}}',))
        m.to_file(self.path)
        preview = self.studio.preview(self.relative, [{"action": "route", "layer": "power", "atom": green,
            "points": [junction._asdict(), left._asdict()]}])
        by_x = {item['x']: item['after'] for item in preview['diff']}
        self.assertIn(f'{green}{{icon_state = "4-8"}}', by_x[3])
        self.assertTrue(any(4 in ports(a, 'power') for a in by_x[2] if a.startswith(green)))

    def test_room_and_fill_are_preview_only(self):
        _, original, _ = self.studio.load(self.relative)
        floor = '/turf/simulated/floor/tiled'
        wall = '/turf/simulated/wall'
        area = '/area/space'
        for atom in (floor, wall, area):
            self.assertIn(atom, self.studio.catalog(original))
        region = {"x1": 1, "y1": 1, "x2": 4, "y2": 4, "z": 1}
        preview = self.studio.preview(self.relative, [{"action": "room", "rect": region,
            "floor": floor, "wall": wall, "area": area}])
        self.assertTrue(preview['diff'])
        self.assertEqual(self.studio.load(self.relative)[1].get_tile(Coordinate(2, 2, 1)),
                         original.get_tile(Coordinate(2, 2, 1)))
        self.assertIn(floor, next(d for d in preview['diff'] if d['x'] == 2 and d['y'] == 2)['after'])
        fill = self.studio.preview(self.relative, [{"action": "fill", "layer": "turf",
            "at": {"x": 1, "y": 1, "z": 1}, "atom": floor}])
        self.assertGreater(fill['changed_tiles'], 0)

    def test_agent_route_tool_uses_transactional_preview(self):
        captured = {}
        class Response:
            def __enter__(self):
                return self
            def __exit__(self, *_args):
                return False
        def fake_open(request, timeout):
            captured.update(__import__('json').loads(request.data))
            return Response()
        with patch.object(mcp, 'urlopen', fake_open), patch.object(mcp.json, 'load', return_value={'preview_id': 'test'}):
            result = mcp.call('map_route', {'map': self.relative, 'layer': 'power',
                'atom': '/obj/structure/cable', 'points': [{'x': 1, 'y': 1, 'z': 1}, {'x': 2, 'y': 1, 'z': 1}]})
        self.assertEqual(result['preview_id'], 'test')
        self.assertEqual(captured['method'], 'preview')
        self.assertEqual(captured['args']['operations'][0]['action'], 'route')

    def test_catalog_request_primes_fast_route_preview(self):
        result = server.dispatch('catalog', {'map': self.relative, 'layer': 'power', 'query': 'cable'})
        self.assertTrue(result['paths'])
        self.assertTrue(all('/cable' in path and path.startswith('/obj/structure/cable')
                            for path in result['paths']))
        _, m, revision = server.studio.read(self.relative)
        self.assertIn(revision, server.studio.catalog_cache)
        self.assertIs(server.studio.catalog_cache[revision], server.studio.catalog_for_revision(m, revision))


if __name__ == "__main__":
    unittest.main()
