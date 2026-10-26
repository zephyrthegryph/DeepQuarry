#!/usr/bin/env bash
# Keeps the disk use of everything the tooling writes outside git BOUNDED BY CONSTRUCTION. The manifest is tools/ci/disk_budget.toml:
# every directory under the cache root (E:/dq-cache) and every per-worktree growth path has a size cap, an age cap and an eviction
# policy there; the cache as a whole has a total cap (DQ_CACHE_BUDGET_GB, default 60); a directory under the cache root that the
# manifest does not name is unknown: reported, and removed (once idle) only when it is clearly a cache (a log, stamp, dmb-*/dmt-* probe dir...).
# A file git tracks is never deleted in a worktree.
#
#   bash tools/dq_disk_budget.sh enforce [--dry-run] [--force] [--aggressive] [--throttle MIN] [--quiet]
#   bash tools/dq_disk_budget.sh status                         # sizes against caps, free space against the floor; changes nothing
#   bash tools/dq_disk_budget.sh gate <what> [--throttle MIN] [--sync]   # refuse heavy work (exit 4) below the disk floor; above it,
#                                                         # enforce detached (--sync: now), throttled
#
# Eviction is least recently modified first, never a unit in use (modified within min_idle_min, the newest `keep`, a leased slot's own
# cargo target, a live analyzer key, the compiler version in dmb-bin/current) and never a file a running process holds open (its
# delete fails and it is reported as kept). Sizes come from `find -printf %s` stat listings, never `du`: a file-level table is ranked and
# sized from one listing (one find, one sort and one awk for ALL the file tables of a worktree or of the cache root, because every
# process start costs 100-200 ms on the dev machine), a directory-level table walks once and keeps the per-child sizes in
# <cache>/disk-budget/index.tsv for index_ttl_min.
#
# Run at every lease, release, train cycle start and dmbc daemon start (throttled to once per 10 minutes) and on demand. Below
# DQ_DISK_FLOOR_GB (default 50) free, every cap is scaled to aggressive_pct and idle protection drops to 5 minutes; if it is still
# under the floor, `gate` exits 4 and lease and train refuse heavy work with a clear message instead of filling the disk.
#
# Environment: DQ_CACHE_ROOT (E:/dq-cache), DQ_WT_ROOT (E:/projects/dq-wt), DQ_DISK_MANIFEST, DQ_CACHE_BUDGET_GB, DQ_DISK_FLOOR_GB,
# DQ_DISK_EXCLUDE_WT ("pool-1 play": worktree names whose growth dirs and cargo targets are never touched), DQ_DISK_BUDGET=off
# (do nothing), DQ_DISK_FREE_GB (tests: pretend this many GB are free), DQ_DISK_TOOLS=0 (skip the dmbc cache pass).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${DQ_DISK_MANIFEST:-$HERE/ci/disk_budget.toml}"
CACHE="${DQ_CACHE_ROOT:-E:/dq-cache}"; CACHE="${CACHE%/}"
WT_ROOT="${DQ_WT_ROOT:-E:/projects/dq-wt}"; WT_ROOT="${WT_ROOT%/}"
STATE="${DQ_DISK_STATE:-$CACHE/disk-budget}"
LEASE_DIR="${DQ_LEASE_DIR:-$CACHE/lane-pool}"
EXCLUDE=" ${DQ_DISK_EXCLUDE_WT:-} "
printf -v NOW '%(%s)T' -1

declare -A M=()                 # manifest: M[<section>.<key>]
CACHE_TABLES=(); WT_TABLES=()
declare -A IDX_T=() IDX_S=()    # size index: when a directory was walked, bytes (per path)
IDX_DIRTY=0
declare -A BEFORE=() AFTER=() NREMOVED=() KEPT_BUSY=()
DRY=0; FORCE=0; AGGR=0; QUIET=0; THROTTLE=0; PARSED=0; SYNC=0
SCR=""   # scratch directory of this run
TRACKED=""   # a file of absolute paths git tracks in the worktree being processed

log() { [ "$QUIET" -eq 1 ] || echo "$*"; }
mb() { MB_R=$(( ${1:-0} / 1048576 )); }

# ---- manifest ---------------------------------------------------------------------------------------------------------------------
parse_manifest() {
	local line sec="" k v
	[ "$PARSED" -eq 1 ] && return 0
	PARSED=1
	[ -f "$MANIFEST" ] || { echo "dq_disk_budget: manifest $MANIFEST not found" >&2; exit 2; }
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%%#*}"
		line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
		[ -n "$line" ] || continue
		if [[ "$line" =~ ^\[([A-Za-z0-9_.-]+)\]$ ]]; then
			sec="${BASH_REMATCH[1]}"
			case "$sec" in
				cache.*) CACHE_TABLES+=("${sec#cache.}") ;;
				worktree.*) WT_TABLES+=("${sec#worktree.}") ;;
			esac
		elif [[ "$line" =~ ^([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
			k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"
			M["$sec.$k"]="$v"
		fi
	done <"$MANIFEST"
}

# ---- numbers ----------------------------------------------------------------------------------------------------------------------
free_gb() {
	if [ -n "${DQ_DISK_FREE_GB:-}" ]; then FREE_R="$DQ_DISK_FREE_GB"; return; fi
	FREE_R="$(df -Pk "$CACHE" 2>/dev/null | awk 'NR==2 {print int($4/1048576)}')"; FREE_R="${FREE_R:-0}"
}
SCALE=100; MIN_IDLE_S=0; TOTAL_B=0; FLOOR_GB=50; TTL_S=1800
settings() {
	local total="${DQ_CACHE_BUDGET_GB:-${M[settings.total_gb]:-60}}" idle="${M[settings.min_idle_min]:-30}"
	FLOOR_GB="${DQ_DISK_FLOOR_GB:-${M[settings.floor_gb]:-50}}"
	TTL_S=$(( ${M[settings.index_ttl_min]:-30} * 60 ))
	SCALE=100
	if [ "$AGGR" -eq 1 ]; then SCALE="${M[settings.aggressive_pct]:-50}"; idle=5; fi
	MIN_IDLE_S=$(( idle * 60 ))
	TOTAL_B=$(( total * 1073741824 * SCALE / 100 ))
}
cap_bytes() { # <table> -> CAP_R (-1 = no size cap), scaled
	local t="$1"
	if [ -n "${M[$t.cap_gb]:-}" ]; then CAP_R=$(( ${M[$t.cap_gb]} * 1073741824 * SCALE / 100 ))
	elif [ -n "${M[$t.cap_mb]:-}" ]; then CAP_R=$(( ${M[$t.cap_mb]} * 1048576 * SCALE / 100 ))
	else CAP_R=-1; fi
}
idle_of() { # <table> -> IDLE_R seconds
	IDLE_R="$MIN_IDLE_S"
	[ -n "${M[$1.min_idle_min]:-}" ] && [ "$AGGR" -eq 0 ] && IDLE_R=$(( ${M[$1.min_idle_min]} * 60 ))
}
g2r() { # <glob, | separated> -> G_R: an anchored ERE over the file's base name
	local r="$1"
	[ -n "$r" ] || { G_R=""; return; }
	r="${r//\\/\\\\}"; r="${r//./\\.}"; r="${r//+/\\+}"; r="${r//(/\\(}"; r="${r//)/\\)}"; r="${r//\[/\\[}"; r="${r//\]/\\]}"
	r="${r//\{/\\{}"; r="${r//\}/\\}}"; r="${r//^/\\^}"; r="${r//\$/\\\$}"; r="${r//\*/.*}"; r="${r//\?/.}"
	G_R="^(${r})\$"
}

# ---- size index -------------------------------------------------------------------------------------------------------------------
index_load() {
	local t s p
	[ -f "$STATE/index.tsv" ] || return 0
	while IFS=$'\t' read -r t s p; do [ -n "$p" ] && { IDX_T["$p"]="$t"; IDX_S["$p"]="$s"; }; done <"$STATE/index.tsv"
}
index_save() {
	[ "$IDX_DIRTY" -eq 1 ] && [ "$DRY" -eq 0 ] || return 0
	mkdir -p "$STATE" 2>/dev/null || return 0
	local p
	for p in "${!IDX_T[@]}"; do printf '%s\t%s\t%s\n' "${IDX_T[$p]}" "${IDX_S[$p]:-0}" "$p"; done >"$STATE/index.tsv.$$" 2>/dev/null && mv -f "$STATE/index.tsv.$$" "$STATE/index.tsv"
}
index_drop() { unset 'IDX_T[$1]' 'IDX_S[$1]'; IDX_DIRTY=1; }
path_size() { # <path> -> SIZE_R (one stat walk, cached for the TTL)
	local p="$1" t="${IDX_T[$1]:-0}"
	if [ -f "$p" ]; then SIZE_R="$(stat -c %s "$p" 2>/dev/null || echo 0)"; return; fi
	if [ "$FORCE" -eq 0 ] && [ -n "${IDX_S[$p]:-}" ] && [ $(( NOW - t )) -lt "$TTL_S" ]; then SIZE_R="${IDX_S[$p]}"; return; fi
	SIZE_R="$(find "$p" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')"
	IDX_T["$p"]="$NOW"; IDX_S["$p"]="$SIZE_R"; IDX_DIRTY=1
}
newest_mtime() { # <path> -> MT_R: newest mtime among the directories to depth 4 and the files to depth 2 (an active build touches these)
	local m
	if [ -f "$1" ]; then MT_R="$(stat -c %Y "$1" 2>/dev/null || echo 0)"; return; fi
	m="$( { find "$1" -maxdepth 4 -type d -printf '%T@\n'; find "$1" -maxdepth 2 -type f -printf '%T@\n'; } 2>/dev/null | sort -rn | head -1)"
	MT_R="${m%.*}"; [ -n "$MT_R" ] || MT_R="$NOW"
}

# ---- protections (no process starts: this runs per unit) --------------------------------------------------------------------------
LIVE_KEYS=""
name_protected() { # <table> <unit path> -> 0 when a named protection applies
	local base="${2##*/}" prot=",${M[$1.protect]:-}," cur=""
	case "$EXCLUDE" in *" $base "*) return 0 ;; esac
	case "$prot" in *,leased-slot,*) [ -f "$LEASE_DIR/$base.lease" ] && return 0 ;; esac
	case "$prot" in
		*,analyze-keys,*)
			if [ -z "$LIVE_KEYS" ]; then
				LIVE_KEYS="$(ls "$WT_ROOT"/*/tools/analyze/target/*/analyze*.key 2>/dev/null | xargs -r cat 2>/dev/null | tr -d '\r')"$'\n'"none"
			fi
			[[ $'\n'"$LIVE_KEYS"$'\n' == *$'\n'"$base"$'\n'* ]] && return 0 ;;
	esac
	case "$prot" in
		*,dmb-current,*) read -r cur <"$CACHE/dmb-bin/current" 2>/dev/null; cur="${cur%$'\r'}"; [ "$base" = "$cur" ] && return 0 ;;
	esac
	return 1
}

# ---- selection and eviction -------------------------------------------------------------------------------------------------------
# One awk decides, for every table at once, what to delete. Input (stdin): mtime TAB size TAB path, ascending by mtime. Spec file rows:
# id, path prefix, max depth below it, name regex, protected-name regex, cap bytes (-1 none), age days, keep, idle seconds. A file belongs to
# the table with the longest matching prefix. Writes $SCR/del.small (paths, bulk-removed), $SCR/del.big (id, size, path: removed one by one,
# so a delete a running process blocks is seen) and $SCR/summary (id, bytes before, bytes after if every delete succeeds, count).
select_evictions() { # <spec file>
	: >"$SCR/del.small"; : >"$SCR/del.big"; : >"$SCR/summary"
	awk -F'\t' -v now="$NOW" -v trk="${TRACKED:-}" -v spec="$1" -v dels="$SCR/del.small" -v delb="$SCR/del.big" -v sum="$SCR/summary" '
		BEGIN {
			# files git tracks (a worktree pass): never deleted, whatever their age or the cap
			if (trk != "") while ((getline l < trk) > 0) T[l]=1
			while ((getline l < spec) > 0) {
				split(l, f, "\t"); ns++
				id[ns]=f[1]; pre[ns]=f[2]; md[ns]=f[3]; gre[ns]=f[4]; pg[ns]=f[5]; cap[ns]=f[6]+0; age[ns]=f[7]+0; keep[ns]=f[8]+0; idle[ns]=f[9]+0
				ord[ns]=ns
			}
			for (i=1;i<=ns;i++) for (j=i+1;j<=ns;j++) if (length(pre[ord[j]]) > length(pre[ord[i]])) { t=ord[i]; ord[i]=ord[j]; ord[j]=t }
		}
		{
			m=int($1); s=$2+0; path=$3
			for (oi=1; oi<=ns; oi++) {
				i=ord[oi]; p=pre[i]
				if (p != "") { if (index(path, p "/") != 1) continue; rel=substr(path, length(p)+2) } else rel=path
				if (gsub("/", "/", rel) + 1 > md[i]) continue
				base=rel; sub(/.*\//, "", base)
				if (gre[i] != "" && base !~ gre[i]) continue
				if (pg[i] != "" && base ~ pg[i]) continue
				c[i]++; TR[i,c[i]]=(path in T); MT[i,c[i]]=m; SZ[i,c[i]]=s; PA[i,c[i]]=path; tot[i]+=s
				break
			}
		}
		END {
			for (i=1;i<=ns;i++) {
				n=c[i]; total=tot[i]; before=total; nd=0
				for (k=1;k<=n;k++) { prot[k] = ((n-k+1) <= keep[i]) || (now - MT[i,k] < idle[i]) || TR[i,k]; dk[k]=0 }
				if (age[i] > 0) for (k=1;k<=n;k++) if (!prot[k] && (now - MT[i,k]) > age[i]*86400) { dk[k]=1; total-=SZ[i,k] }
				if (cap[i] >= 0) for (k=1;k<=n && total>cap[i];k++) if (!prot[k] && !dk[k]) { dk[k]=1; total-=SZ[i,k] }
				for (k=1;k<=n;k++) if (dk[k]) { nd++; if (SZ[i,k] >= 100000000) print id[i] "\t" SZ[i,k] "\t" PA[i,k] > delb; else print PA[i,k] > dels }
				print id[i] "\t" before "\t" total "\t" nd > sum
			}
		}'
}
apply_evictions() { # reads $SCR/*; fills BEFORE/AFTER/NREMOVED/KEPT_BUSY per id
	local id b a n sz path nsmall
	while IFS=$'\t' read -r id b a n; do
		[ -n "${BEFORE[$id]:-}" ] || BEFORE["$id"]="$b"
		AFTER["$id"]="$a"; NREMOVED["$id"]=$(( ${NREMOVED[$id]:-0} + n ))
	done <"$SCR/summary"
	if [ "$DRY" -eq 1 ]; then
		nsmall=0
		while IFS= read -r path; do nsmall=$((nsmall + 1)); [ "$nsmall" -le 8 ] && log "  would remove $path"; done <"$SCR/del.small"
		[ "$nsmall" -gt 8 ] && log "  ... and $((nsmall - 8)) more files"
		while IFS=$'\t' read -r id sz path; do mb "$sz"; log "  would remove $path ($MB_R MB)"; done <"$SCR/del.big"
		return
	fi
	if [ -s "$SCR/del.small" ]; then xargs -d '\n' -r rm -rf -- <"$SCR/del.small" 2>/dev/null; fi
	while IFS=$'\t' read -r id sz path; do
		rm -rf -- "$path" 2>/dev/null
		if [ -e "$path" ]; then
			KEPT_BUSY["$id"]=$(( ${KEPT_BUSY[$id]:-0} + 1 )); AFTER["$id"]=$(( ${AFTER[$id]:-0} + sz )); NREMOVED["$id"]=$(( ${NREMOVED[$id]:-0} - 1 ))
			mb "$sz"; log "  kept (in use): $path ($MB_R MB)"
		else
			mb "$sz"; log "  removed $path ($MB_R MB)"; index_drop "$path"
		fi
	done <"$SCR/del.big"
}

spec_row() { # <id> <prefix> <table> <depth> <override cap or empty>  -> a spec row on stdout
	local id="$1" prefix="$2" t="$3" depth="$4" ov="${5:-}" cap gre pre
	cap_bytes "$t"; cap="$CAP_R"
	if [ -n "$ov" ]; then if [ "$cap" -lt 0 ] || [ "$ov" -lt "$cap" ]; then cap="$ov"; fi; fi
	idle_of "$t"
	g2r "${M[$t.glob]:-}"; gre="$G_R"; g2r "${M[$t.protect_glob]:-}"; pre="$G_R"
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$prefix" "$depth" "$gre" "$pre" "$cap" "${M[$t.age_days]:-0}" "${M[$t.keep]:-0}" "$IDLE_R"
}

# The children of a directory as units: mtime TAB size TAB path into $SCR/units. Mtimes come from one listing of the directories (4 levels)
# and files (2 levels); sizes from one walk of the whole directory, kept per child in the index.
children_units() { # <dir> <table>
	local dir="$1" t="$2" c m walk=0
	local -A CMT=() CSZ=()
	: >"$SCR/units"
	[ -d "$dir" ] || return 0
	while IFS=$'\t' read -r c m; do CMT["$c"]="$m"; done < <( { find "$dir" -mindepth 1 -maxdepth 4 -type d -printf '%T@\t%P\n'; find "$dir" -mindepth 1 -maxdepth 2 -type f -printf '%T@\t%P\n'; } 2>/dev/null | awk -F'\t' '{ c=$2; i=index(c,"/"); if (i) c=substr(c,1,i-1); m=int($1); if (m > mx[c]) mx[c]=m; seen[c]=1 } END { for (c in seen) print c "\t" mx[c] }')
	if [ "$FORCE" -eq 1 ] || [ $(( NOW - ${IDX_T[$dir]:-0} )) -ge "$TTL_S" ]; then walk=1; fi
	for c in "${!CMT[@]}"; do [ -n "${IDX_S[$dir/$c]:-}" ] || walk=1; done
	if [ "$walk" -eq 1 ]; then
		for c in "${!CMT[@]}"; do CSZ["$c"]=0; done
		while IFS=$'\t' read -r c m; do CSZ["$c"]="$m"; done < <(find "$dir" -type f -printf '%s\t%P\n' 2>/dev/null | awk -F'\t' '{ c=$2; i=index(c,"/"); if (i) c=substr(c,1,i-1); s[c]+=$1 } END { for (c in s) print c "\t" s[c] }')
		for c in "${!CMT[@]}"; do IDX_S["$dir/$c"]="${CSZ[$c]:-0}"; done
		IDX_T["$dir"]="$NOW"; IDX_DIRTY=1
	fi
	for c in "${!CMT[@]}"; do
		m="${CMT[$c]}"
		name_protected "$t" "$dir/$c" && m="$NOW"
		printf '%s\t%s\t%s\n' "$m" "${IDX_S[$dir/$c]:-0}" "$dir/$c"
	done | sort -n >"$SCR/units"
}

# One children-lru table, plus trimming inside any child over sub_cap_gb (the cargo targets of one worktree): the child is cut down by its
# least recently modified FILES (stale rlib/pdb/incremental state first; cargo rebuilds only what is missing), not evicted whole.
process_children() { # <name> <table> <override>
	local name="$1" t="$2" ov="${3:-}" dir="$CACHE/$1" c csz sub_b total=0 id mt line any=0
	local -a top=()
	[ -d "$dir" ] || return 0
	[ -n "${M[$t.subdir]:-}" ] && dir="$dir/${M[$t.subdir]}"
	[ -d "$dir" ] || return 0
	children_units "$dir" "$t"
	mapfile -t top <"$SCR/units"
	spec_row "$name" "" "$t" 999 "$ov" >"$SCR/spec"
	select_evictions "$SCR/spec" <"$SCR/units"
	apply_evictions
	if [ -n "${M[$t.sub_cap_gb]:-}" ]; then sub_b=$(( ${M[$t.sub_cap_gb]} * 1073741824 * SCALE / 100 ))
	elif [ -n "${M[$t.sub_cap_mb]:-}" ]; then sub_b=$(( ${M[$t.sub_cap_mb]} * 1048576 * SCALE / 100 ))
	else return 0; fi
	: >"$SCR/sub.spec"; DEPTH_PATHS=()
	for line in ${top[@]+"${top[@]}"}; do
		IFS=$'\t' read -r mt csz c <<<"$line"
		[ -d "$c" ] || continue
		if ! name_protected "$t" "$c" && [ "$csz" -gt "$sub_b" ]; then
			spec_row "$name/${c##*/}" "$c" "sub" 14 "$sub_b" >>"$SCR/sub.spec"
			DEPTH_PATHS[14]+="${DEPTH_PATHS[14]:+$'\n'}$c"; any=1
		fi
	done
	[ "$any" -eq 1 ] && run_file_group "$SCR/sub.spec"
	for line in ${top[@]+"${top[@]}"}; do
		IFS=$'\t' read -r mt csz c <<<"$line"
		[ -d "$c" ] || continue
		id="$name/${c##*/}"
		if [ -n "${AFTER[$id]:-}" ]; then
			if [ "${NREMOVED[$id]:-0}" -gt 0 ]; then
				mb "$csz"; local was="$MB_R"; mb "${AFTER[$id]}"; log "  trimmed $c: $was MB -> $MB_R MB by least recently modified files (sub cap per worktree)"
				IDX_T["$c"]="$NOW"; IDX_S["$c"]="${AFTER[$id]}"; IDX_DIRTY=1
				NREMOVED["$name"]=$(( ${NREMOVED[$name]:-0} + 1 ))
			fi
			csz="${AFTER[$id]}"
		fi
		total=$((total + csz))
	done
	AFTER["$name"]="$total"
}

truncate_logs() { # <dir> <max MB>
	local dir="$1" maxmb="$2" f
	[ -d "$dir" ] || return 0
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		if [ "$DRY" -eq 1 ]; then log "  would truncate $f"; continue; fi
		case "$f" in
			*.log.1) rm -f "$f" ;;
			*.jsonl) tail -c 1048576 "$f" 2>/dev/null | sed 1d >"$f.tmp.$$" && mv -f "$f.tmp.$$" "$f" 2>/dev/null || rm -f "$f.tmp.$$" ;;
			*) # a log a daemon holds open as stderr: rotate it aside (the daemon's next start does the same at 1 MiB), else keep its tail
				if mv -f "$f" "$f.1" 2>/dev/null; then rm -f "$f.1"
				else tail -c 1048576 "$f" >"$f.tmp.$$" 2>/dev/null && mv -f "$f.tmp.$$" "$f" 2>/dev/null || rm -f "$f.tmp.$$"; fi ;;
		esac
		log "  truncated oversized log $f"
	done < <(find "$dir" -maxdepth 4 -type f \( -name '*.log' -o -name '*.log.1' -o -name '*.jsonl' \) -size +"$maxmb"M 2>/dev/null)
}

run_cache_tool() { # <table>
	local t="$1" bin cur="" exe gb
	[ "${DQ_DISK_TOOLS:-1}" = 0 ] && return 0
	[ "$DRY" -eq 1 ] && return 0
	case "${M[$t.tool]:-}" in
		dmbc-cache-gc)
			bin="${DQ_DMBC_BIN_DIR:-$CACHE/dmb-bin}"; read -r cur <"$bin/current" 2>/dev/null; cur="${cur%$'\r'}"
			[ -n "$cur" ] || return 0
			exe="$bin/v/$cur/dmbc.exe"; [ -f "$exe" ] || exe="$bin/v/$cur/dmbc"; [ -f "$exe" ] || return 0
			cap_bytes "$t"; gb=$(( (CAP_R > 0 ? CAP_R : 16 * 1073741824) / 1073741824 )); [ "$gb" -ge 1 ] || gb=1
			# the compiler's own pass: pair stores, spilled bases, and the lowering cache against the same budget
			DMB_CACHE_BUDGET_GB="$gb" DMB_CACHE_MAX_AGE_DAYS="${M[$t.age_days]:-14}" timeout 120 "$exe" --cache-gc 2>&1 | tail -3 | sed 's/^/  dmbc: /' ;;
	esac
}

# ---- passes -----------------------------------------------------------------------------------------------------------------------
# Every file-level table of one root (the cache root, or one worktree) in ONE find per depth, ONE sort and ONE awk.
declare -A DEPTH_PATHS=()
run_file_group() { # <spec file> (DEPTH_PATHS filled by the caller: depth -> newline-joined directories)
	local d
	local -a paths
	: >"$SCR/listing"
	for d in "${!DEPTH_PATHS[@]}"; do
		mapfile -t paths <<<"${DEPTH_PATHS[$d]}"
		find "${paths[@]}" -maxdepth "$d" -type f -printf '%T@\t%s\t%p\n' 2>/dev/null >>"$SCR/listing"
	done
	DEPTH_PATHS=()
	[ -s "$SCR/listing" ] || return 0
	sed -E 's/^([0-9]+)\.[0-9]+/\1/' "$SCR/listing" | sort -n >"$SCR/listing.sorted"
	select_evictions "$1" <"$SCR/listing.sorted"
	apply_evictions
}
add_file_table() { # <id> <dir> <table> <default depth> <override> : appends a spec row to $SCR/group.spec when the directory exists
	local id="$1" dir="${2%/.}" t="$3" depth="${M[$3.depth]:-$4}"
	[ -d "$dir" ] || return 0
	spec_row "$id" "$dir" "$t" "$depth" "${5:-}" >>"$SCR/group.spec"
	DEPTH_PATHS["$depth"]+="${DEPTH_PATHS[$depth]:+$'\n'}$dir"
}

worktrees() { # -> WTS array
	local d n
	WTS=()
	for d in "$WT_ROOT"/*/; do
		d="${d%/}"; n="${d##*/}"
		[ -e "$d/.git" ] || continue
		case "$EXCLUDE" in *" $n "*) continue ;; esac
		WTS+=("$d")
	done
}

enforce_once() { # <squeeze percent, 0 for the first pass>
	local squeeze="$1" t wt base name ov
	for name in "${CACHE_TABLES[@]}"; do   # directory-level tables first (a child over its sub cap runs a file pass of its own)
		t="cache.$name"
		[ "${M[$t.policy]:-}" = children-lru ] && [ -d "$CACHE/$name" ] || continue
		ov=""; [ "$squeeze" -gt 0 ] && ov=$(( ${AFTER[$name]:-0} * squeeze / 100 ))
		[ "$squeeze" -eq 0 ] && run_cache_tool "$t"
		process_children "$name" "$t" "$ov"
	done
	: >"$SCR/group.spec"; DEPTH_PATHS=()
	for name in "${CACHE_TABLES[@]}"; do
		t="cache.$name"
		if [ "${M[$t.policy]:-}" = state ]; then
			if [ "$squeeze" -eq 0 ] && [ -n "${M[$t.log_max_mb]:-}" ]; then truncate_logs "$CACHE/$name${M[$t.log_subdir]:+/${M[$t.log_subdir]}}" "${M[$t.log_max_mb]}"; fi
			continue
		fi
		[ "${M[$t.policy]:-}" = children-lru ] && continue
		[ -d "$CACHE/$name" ] || continue
		ov=""; [ "$squeeze" -gt 0 ] && ov=$(( ${AFTER[$name]:-0} * squeeze / 100 ))
		[ "$squeeze" -eq 0 ] && run_cache_tool "$t"
		add_file_table "$name" "$CACHE/$name" "$t" 8 "$ov"
	done
	[ -s "$SCR/group.spec" ] && run_file_group "$SCR/group.spec"
	[ "$squeeze" -eq 0 ] || return 0
	worktrees
	for wt in "${WTS[@]}"; do
		base="${wt##*/}"; : >"$SCR/group.spec"
		# a path git tracks is never eligible: fail closed (skip the worktree) when git cannot list it
		if ! git -C "$wt" ls-files -z 2>/dev/null | awk -v RS='\0' -v p="$wt/" '{ print p $0 }' >"$SCR/tracked" || [ "${PIPESTATUS[0]}" -ne 0 ]; then
			log "  skipping $wt: git ls-files failed, so tracked files cannot be told apart"; continue
		fi
		TRACKED="$SCR/tracked"
		for name in "${WT_TABLES[@]}"; do
			t="worktree.$name"
			add_file_table "wt:$base:$name" "$wt/${M[$t.path]:-.}" "$t" 1 ""
		done
		[ -s "$SCR/group.spec" ] && run_file_group "$SCR/group.spec"
		TRACKED=""
	done
}

cache_sum() { # -> SUM_R bytes: evictable tables after the pass, state tables as they are
	local name
	SUM_R=0
	for name in "${CACHE_TABLES[@]}"; do
		[ -d "$CACHE/$name" ] || continue
		if [ "${M[cache.$name.policy]:-}" = state ]; then path_size "$CACHE/$name"; SUM_R=$((SUM_R + SIZE_R)); else SUM_R=$((SUM_R + ${AFTER[$name]:-0})); fi
	done
}

enforce() {
	parse_manifest; settings
	if [ "${DQ_DISK_BUDGET:-}" = off ]; then log "dq_disk_budget: off"; return 0; fi
	mkdir -p "$STATE" 2>/dev/null
	if [ "$THROTTLE" -gt 0 ] && [ "$FORCE" -eq 0 ] && [ "$AGGR" -eq 0 ] && [ "$DRY" -eq 0 ] && [ -n "$(find "$STATE/enforce.stamp" -mmin -"$THROTTLE" 2>/dev/null)" ]; then return 0; fi
	if [ "$DRY" -eq 0 ]; then
		# one enforcement at a time; a lock left by a dead run goes after 30 minutes
		[ -n "$(find "$STATE/enforce.lock" -maxdepth 0 -mmin +30 2>/dev/null)" ] && rmdir "$STATE/enforce.lock" 2>/dev/null
		mkdir "$STATE/enforce.lock" 2>/dev/null || { log "dq_disk_budget: another enforcement is running"; return 0; }
		: >"$STATE/enforce.stamp"
	fi
	SCR="$(mktemp -d)"
	trap '[ "$DRY" -eq 1 ] || rmdir "$STATE/enforce.lock" 2>/dev/null; rm -rf "$SCR"' EXIT   # backup: the normal path releases both at the end
	index_load
	free_gb; local free_before="$FREE_R" f
	log "dq_disk_budget: cache $CACHE, $free_before GB free (floor $FLOOR_GB GB), total cap $(( TOTAL_B / 1073741824 )) GB, scale ${SCALE}%$([ "$DRY" -eq 1 ] && echo ' (dry run)')"
	enforce_once 0
	# unknown entries under the cache root: not in the manifest, so disposable; removed once idle
	local c n t known unknown_n=0 unknown_b=0
	shopt -s nullglob dotglob
	for c in "$CACHE"/*; do
		n="${c##*/}"; known=0
		for t in "${CACHE_TABLES[@]}"; do [ "$t" = "$n" ] && known=1; done
		[ "$known" -eq 1 ] && continue
		# coordination state is never an unknown, whatever the manifest says; anything else that is not clearly a cache is only reported
		case "$n" in train|lane-pool|slots|dmb-bin|dmb-daemon|flakes.tsv|worktree-keep.txt|ports|test-durations|disk-budget) continue ;; esac
		case "$n" in
			*.log|*.stamp|*.patch|*.jsonl|*.tmp|lane_*.sh|run-*|dm-*|dc-*|dmb-*|dmt-*|*fixture*|*-tests|shadow-*) ;;
			*) newest_mtime "$c"; path_size "$c"; mb "$SIZE_R"; log "  unknown $c ($MB_R MB) is not in tools/ci/disk_budget.toml and not clearly a cache: reported, not removed"; continue ;;
		esac
		newest_mtime "$c"; path_size "$c"; mb "$SIZE_R"
		if [ $(( NOW - MT_R )) -lt "$MIN_IDLE_S" ]; then log "  unknown $c ($MB_R MB) is busy; not removed"; continue; fi
		log "  $([ "$DRY" -eq 1 ] && echo 'would remove' || echo removed) unknown $c ($MB_R MB; not in tools/ci/disk_budget.toml)"
		unknown_n=$((unknown_n + 1)); unknown_b=$((unknown_b + SIZE_R))
		[ "$DRY" -eq 1 ] || { rm -rf -- "$c" 2>/dev/null; index_drop "$c"; }
	done
	shopt -u nullglob dotglob
	# the whole cache against its total: squeeze every evictable table in proportion to its size, least recently used first
	cache_sum
	if [ "$SUM_R" -gt "$TOTAL_B" ]; then
		local pct=$(( TOTAL_B * 100 / SUM_R )) sm
		[ "$pct" -ge 1 ] || pct=1
		mb "$SUM_R"; sm="$MB_R"; mb "$TOTAL_B"
		log "  cache is $sm MB over its total cap of $MB_R MB: squeezing every table to ${pct}% of its size"
		enforce_once "$pct"
		cache_sum
		if [ "$SUM_R" -gt "$TOTAL_B" ]; then mb "$SUM_R"; sm="$MB_R"; mb "$TOTAL_B"; log "  STILL OVER the total cap: $sm MB of $MB_R MB (units in use are protected)"; fi
	fi
	index_save
	log "dq_disk_budget: per table (MB before -> after, removed units):"
	if [ "$QUIET" -eq 0 ]; then
		for f in "${!BEFORE[@]}"; do
			case "$f" in wt:*) continue ;; esac
			mb "${BEFORE[$f]:-0}"; local b="$MB_R"; mb "${AFTER[$f]:-0}"
			printf '  %-34s %8s -> %-8s removed %s%s\n' "$f" "$b" "$MB_R" "${NREMOVED[$f]:-0}" "$([ "${KEPT_BUSY[$f]:-0}" -gt 0 ] && echo "  (${KEPT_BUSY[$f]} in use, kept)")"
		done | sort
	fi
	local wtb=0 wta=0 wtn=0 x y
	for f in "${!BEFORE[@]}"; do case "$f" in wt:*) wtb=$((wtb + BEFORE[$f])); wta=$((wta + ${AFTER[$f]:-0})); wtn=$((wtn + ${NREMOVED[$f]:-0})) ;; esac; done
	mb "$wtb"; x="$MB_R"; mb "$wta"; y="$MB_R"; mb "$unknown_b"
	log "  per-worktree growth dirs (all worktrees): $x -> $y MB, $wtn files removed; unknown cache entries removed: $unknown_n ($MB_R MB)"
	free_gb
	log "dq_disk_budget: $FREE_R GB free now (was $free_before GB)"
	[ "$DRY" -eq 1 ] || rmdir "$STATE/enforce.lock" 2>/dev/null
	rm -rf "$SCR"; trap - EXIT
}

status() {
	local name t s cs
	parse_manifest; settings
	SCR="$(mktemp -d)"; trap 'rm -rf "$SCR"' EXIT
	index_load; free_gb
	echo "cache root $CACHE: $FREE_R GB free, floor $FLOOR_GB GB, total cap $(( TOTAL_B / 1073741824 )) GB"
	for name in "${CACHE_TABLES[@]}"; do
		[ -d "$CACHE/$name" ] || continue
		t="cache.$name"; cap_bytes "$t"; path_size "$CACHE/$name"; mb "$SIZE_R"; s="$MB_R"; cs="none"
		if [ "$CAP_R" -ge 0 ]; then mb "$CAP_R"; cs="$MB_R MB"; fi
		printf '  %-26s %8s MB  cap %s  [%s]\n' "$name" "$s" "$cs" "${M[$t.policy]:-}"
	done
	index_save
}

gate() { # <what>
	local what="${1:-heavy work}"
	parse_manifest; settings
	[ "${DQ_DISK_BUDGET:-}" = off ] && return 0
	free_gb
	if [ "$FREE_R" -ge "$FLOOR_GB" ]; then
		# above the floor the enforcement is housekeeping: detached (unless --sync), at most once per throttle window
		if [ "$SYNC" -eq 1 ]; then enforce >/dev/null 2>&1
		else ( nohup bash "$HERE/dq_disk_budget.sh" enforce --quiet --throttle "$([ "$THROTTLE" -gt 0 ] && echo "$THROTTLE" || echo 10)" >/dev/null 2>&1 & ) >/dev/null 2>&1; fi
		return 0
	fi
	# below the floor: enforce now, then aggressively, before deciding
	enforce >/dev/null 2>&1
	free_gb
	if [ "$FREE_R" -lt "$FLOOR_GB" ]; then
		AGGR=1; FORCE=1; QUIET=1; settings
		enforce >/dev/null 2>&1
		free_gb
	fi
	if [ "$FREE_R" -lt "$FLOOR_GB" ]; then
		cat >&2 <<EOF
dq_disk_budget: REFUSED $what: only $FREE_R GB free on the disk of $CACHE (floor $FLOOR_GB GB, DQ_DISK_FLOOR_GB).
The cache was already trimmed to its aggressive budget (bash tools/dq_disk_budget.sh status shows what is left). Free space first: release finished
lanes (bash tools/dq_lane_pool.sh release <branch>), delete worktrees you no longer need, or empty the recycle bin; then retry. Do not delete files
under E:/dq-cache by hand while builds run.
EOF
		return 4
	fi
	return 0
}

cmd="${1:-enforce}"; [ $# -gt 0 ] && shift
what=""
while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) DRY=1 ;;
		--force) FORCE=1 ;;
		--aggressive) AGGR=1; FORCE=1 ;;
		--quiet) QUIET=1 ;;
		--sync) SYNC=1 ;;
		--throttle) shift; THROTTLE="${1:?--throttle needs minutes}" ;;
		-*) echo "dq_disk_budget: unknown option $1" >&2; exit 2 ;;
		*) what="$1" ;;
	esac
	shift
done
case "$cmd" in
	enforce) enforce ;;
	status) status ;;
	gate) gate "$what"; exit $? ;;
	*) echo "usage: dq_disk_budget.sh enforce|status|gate <what> [--dry-run] [--force] [--aggressive] [--throttle MIN] [--quiet]" >&2; exit 2 ;;
esac
