# Area instance identity runtime contract

`world.area = /area/space` plus a map whose templates repeat `/area/space`,
`/area/space{}`, `/area/room` and `/area/room{name = "x"}`. BYOND 516.1687
creates one area object per distinct (type, overrides): unmapped cells and every
unedited `/area/space` cell share one object, and `DQ_AREA count 3` is printed.
The native compiler previously emitted one area instance per map template, so
`get_area()` of a landmark differed from a neighbouring turf's `loc`
(`dq_shuttle_repeated_moves_preserve_air`). Unit coverage:
`map_projection::tests::equal_area_atoms_share_one_instance_with_the_world_default`.

Expected (both compilers, DreamDaemon `-trusted -close`):

```
DQ_AREA 1,1 /turf/floor /area/room other idx=1
DQ_AREA 2,1 /turf/floor /area/room other idx=1
DQ_AREA 3,1 /turf/floor /area/space first idx=2
DQ_AREA 4,1 /turf/floor /area/space first idx=2
DQ_AREA 1,2 /turf/floor /area/space first idx=2
DQ_AREA 2,2 /turf/space /area/space first idx=2
DQ_AREA 3,2 /turf/floor /area/room other idx=3
DQ_AREA 4,2 /turf/floor /area/room other idx=3
DQ_AREA count 3
```

Native compile: `dmbc compile probe.dme --engine-template ../../native_template.bin
--bootstrap-catalog --no-daemon --no-cache --output-store <dir>`.
