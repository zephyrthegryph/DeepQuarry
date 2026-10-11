# Strict root object iteration

Captured with pinned DreamMaker 516.1687 (SHA256 in capture.json), compile-only;
no DreamDaemon was launched. Complete source, DMB and decoded procedure words
are preserved. Original receipt and logs remain under the recorded E: root.

`for(var/obj/A in L)` uses IterLoad [5,2] followed by GetVar, PushVal /obj,
IsType, Test and JzLoop. The domain mask includes atom/movable instances and
cannot replace the exact /obj subtype check. The same capture retains the
/mob, /turf, /area and /atom/movable controls without asserting their current
native implementation parity. The Rust test checks complete root_obj words
and a lexical field named obj does not change the issued declaration path.
