// DQAdd — Compact job priority editor modelled on the Bay-prefs Occupation tab.
//
// Layout:
//   ┌── header: counts + fallback dropdown ──────────────────────────────────┐
//   │ HIGH 1 · MED 3 · LOW 5             If none: [Be Assistant ▾]          │
//   ├──────── two columns ───────────────────────────────────────────────────┤
//   │ COMMAND                              CIVILIAN                          │
//   │ ▌Captain 0/1     [Off|Low|Med|High]                                    │
//   │ ▌HoS    0/1                                                            │
//   │ ...                                                                    │
//   └────────────────────────────────────────────────────────────────────────┘
//
// One job = one tight row. Dept color appears as a 4px left bar on each row.

import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  Dropdown,
  Stack,
  Tooltip,
} from 'tgui-core/components';
import type { EditorProps } from './index';

type Priority = 'off' | 'low' | 'med' | 'high';

type JobEntry = {
  title: string;
  desc: string;
  supervisors: string | null;
  selection_color: string;
  sorting_order: number;
  whitelist_only: boolean;
  min_age: number;
  total_positions: number;
  current_positions: number;
};

type Department = {
  label: string;
  color: string;
  sort: number;
  jobs: JobEntry[];
};

type Data = {
  job_priority: Record<string, Priority>;
  availability: Record<string, string>;
  alternate_option: number;
  alt_titles: Record<string, string>;
  counts: { high: number; med: number; low: number };
};

type Static = {
  departments: Record<string, Department>;
  alt_options: Array<{ value: number; label: string }>;
  alt_titles_by_job: Record<string, string[]>;
};

const PRIORITY_ORDER: Priority[] = ['off', 'low', 'med', 'high'];
const PRIORITY_LABEL: Record<Priority, string> = {
  off: 'Off',
  low: 'Low',
  med: 'Med',
  high: 'High',
};
const PRIORITY_COLOR: Record<Priority, string | undefined> = {
  off: undefined,
  low: 'orange',
  med: 'yellow',
  high: 'green',
};

const nextPriority = (current: Priority, backward = false): Priority => {
  const idx = PRIORITY_ORDER.indexOf(current);
  const delta = backward ? -1 : 1;
  return PRIORITY_ORDER[(idx + delta + PRIORITY_ORDER.length) % PRIORITY_ORDER.length];
};

const send = (
  act: ReturnType<typeof useBackend>['act'],
  action: string,
  params: Record<string, unknown>,
) => act('dq_editor_action', { editor: 'occupation', action, params });

export const OccupationEditor = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = data as Data;
  const s = (staticData ?? {}) as Static;
  const altOptions = s.alt_options ?? [];
  const altOpts = altOptions.map((o) => ({
    value: String(o.value),
    displayText: o.label,
  }));
  const altVal = String(d.alternate_option ?? 1);
  // tgui-core Dropdown won't translate `selected` -> displayText; override explicitly.
  const altLabel =
    altOpts.find((o) => o.value === altVal)?.displayText ?? altVal;

  // Sort departments by their sorting_order (Command first, then Security, …).
  const depts = Object.values(s.departments ?? {}).sort(
    (a, b) => (b.sort ?? 0) - (a.sort ?? 0),
  );

  // Distribute roughly evenly across two columns by job count (so Civilian alone doesn't
  // dominate one side).
  const totalJobs = depts.reduce((sum, d) => sum + (d.jobs?.length ?? 0), 0);
  const halfway = totalJobs / 2;
  const leftCol: Department[] = [];
  const rightCol: Department[] = [];
  let running = 0;
  for (const dept of depts) {
    if (running < halfway) {
      leftCol.push(dept);
    } else {
      rightCol.push(dept);
    }
    running += dept.jobs?.length ?? 0;
  }

  return (
    <Box>
      {/* Header bar: counts + fallback */}
      <Box
        mb={0.5}
        px={1}
        py={0.5}
        style={{
          backgroundColor: 'rgba(255,255,255,0.05)',
          borderRadius: '2px',
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
        }}
      >
        <Box inline color="green" bold>
          HIGH {d.counts?.high ?? 0}
        </Box>
        <Box inline color="label">·</Box>
        <Box inline color="yellow" bold>
          MED {d.counts?.med ?? 0}
        </Box>
        <Box inline color="label">·</Box>
        <Box inline color="orange" bold>
          LOW {d.counts?.low ?? 0}
        </Box>
        <Box style={{ flex: '1 1 auto' }} />
        <Box inline color="label" fontSize="0.85em">
          If none available:
        </Box>
        <Dropdown
          width="220px"
          selected={altVal}
          displayText={altLabel}
          options={altOpts}
          onSelected={(v) =>
            send(act, 'set_alternate_option', { value: String(v) })
          }
        />
      </Box>

      {/* Two columns of department blocks */}
      <Stack>
        <Stack.Item grow basis={0}>
          {leftCol.map((dept) => (
            <DepartmentBlock
              key={dept.label}
              dept={dept}
              d={d}
              altTitlesByJob={s.alt_titles_by_job}
            />
          ))}
        </Stack.Item>
        <Stack.Item grow basis={0}>
          {rightCol.map((dept) => (
            <DepartmentBlock
              key={dept.label}
              dept={dept}
              d={d}
              altTitlesByJob={s.alt_titles_by_job}
            />
          ))}
        </Stack.Item>
      </Stack>
    </Box>
  );
};

const DepartmentBlock = ({
  dept,
  d,
  altTitlesByJob,
}: {
  dept: Department;
  d: Data;
  altTitlesByJob: Record<string, string[]>;
}) => (
  <Box mb={0.5}>
    <Box
      px={1}
      py={0.25}
      bold
      fontSize="0.85em"
      style={{
        backgroundColor: dept.color ? `${dept.color}33` : 'rgba(0,0,0,0.25)',
        borderLeft: dept.color ? `3px solid ${dept.color}` : undefined,
        borderRadius: '2px',
        textTransform: 'uppercase',
        letterSpacing: '0.5px',
      }}
    >
      {dept.label}
    </Box>
    {dept.jobs.map((job) => (
      <JobRow
        key={job.title}
        job={job}
        deptColor={dept.color}
        priority={d.job_priority?.[job.title] ?? 'off'}
        blockReason={d.availability?.[job.title]}
        altTitle={d.alt_titles?.[job.title]}
        altChoices={altTitlesByJob?.[job.title]}
      />
    ))}
  </Box>
);

const JobRow = ({
  job,
  deptColor,
  priority,
  blockReason,
  altTitle,
  altChoices,
}: {
  job: JobEntry;
  deptColor: string;
  priority: Priority;
  blockReason?: string;
  altTitle?: string;
  altChoices?: string[];
}) => {
  const { act } = useBackend();
  const blocked = !!blockReason;
  const barColor = job.selection_color || deptColor || '#555';

  const cycleTo = (backward: boolean) => {
    if (blocked) {
      if (priority !== 'off') {
        send(act, 'set_priority', { job: job.title, priority: 'off' });
      }
      return;
    }
    send(act, 'set_priority', {
      job: job.title,
      priority: nextPriority(priority, backward),
    });
  };

  const tipParts: string[] = [];
  if (blocked) tipParts.push(`Locked: ${blockReason}`);
  if (job.desc) tipParts.push(job.desc);
  if (job.supervisors) tipParts.push(`Reports to: ${job.supervisors}`);
  // Position count lives in the visible row already; don't duplicate it in the tooltip.

  // Build the altTitle dropdown opts up here so we can compute its display label.
  const altOpts = altChoices?.map((t) => ({ value: t, displayText: t })) ?? [];
  const altSel = altTitle ?? job.title;

  return (
    <Box
      style={{
        display: 'flex',
        alignItems: 'center',
        padding: '0 4px',
        borderLeft: `4px solid ${barColor}`,
        backgroundColor:
          priority !== 'off' && !blocked
            ? `${barColor}22`
            : blocked
              ? '#80000022'
              : 'transparent',
        opacity: blocked ? 0.65 : 1,
        cursor: 'pointer',
        userSelect: 'none',
        marginBottom: '1px',
        minHeight: '20px',
        fontSize: '0.9em',
      }}
      onClick={() => cycleTo(false)}
      onContextMenu={(e: React.MouseEvent) => {
        e.preventDefault();
        cycleTo(true);
      }}
    >
      {/* Title: either an inline dropdown (alt-titled jobs) or plain text. The Tooltip
          wraps ONLY the plain-text title — clicking the dropdown moves the cursor off
          the tooltip's hover target so it dismisses on its own. */}
      {altChoices && !blocked ? (
        <Box
          inline
          style={{ flex: '0 0 auto' }}
          onClick={(e: React.MouseEvent) => e.stopPropagation()}
          onContextMenu={(e: React.MouseEvent) => e.stopPropagation()}
        >
          <Dropdown
            width="150px"
            selected={altSel}
            displayText={altSel}
            options={altOpts}
            onSelected={(v) =>
              send(act, 'set_alt_title', { job: job.title, alt: String(v) })
            }
          />
        </Box>
      ) : (
        <Tooltip content={tipParts.join('\n') || job.title}>
          <Box
            inline
            style={{
              flex: '0 0 auto',
              textDecoration: blocked ? 'line-through' : undefined,
            }}
          >
            {job.title}
          </Box>
        </Tooltip>
      )}
      {job.total_positions > 0 && (
        <Box
          inline
          ml={0.5}
          color="label"
          fontSize="0.78em"
          style={{
            flex: '0 0 auto',
            fontVariantNumeric: 'tabular-nums',
            whiteSpace: 'nowrap',
          }}
        >
          {job.current_positions}/{job.total_positions}
        </Box>
      )}
      {blockReason && (
        <Box
          inline
          ml={0.5}
          px={0.5}
          backgroundColor="bad"
          color="white"
          fontSize="0.7em"
          style={{ flex: '0 0 auto', borderRadius: '2px' }}
        >
          {blockReason}
        </Box>
      )}
      {!blockReason && job.whitelist_only && (
        <Box
          inline
          ml={0.5}
          px={0.5}
          backgroundColor="good"
          color="white"
          fontSize="0.7em"
          style={{ flex: '0 0 auto', borderRadius: '2px' }}
        >
          WL
        </Box>
      )}
      {!blockReason && job.min_age > 0 && (
        <Box
          inline
          ml={0.5}
          px={0.5}
          backgroundColor="average"
          color="white"
          fontSize="0.7em"
          style={{ flex: '0 0 auto', borderRadius: '2px' }}
        >
          AGE {job.min_age}+
        </Box>
      )}
      <Box style={{ flex: '1 1 auto' }} />
      <Box
        inline
        style={{ flex: '0 0 auto' }}
        onClick={(e: React.MouseEvent) => e.stopPropagation()}
        onContextMenu={(e: React.MouseEvent) => e.stopPropagation()}
      >
        {PRIORITY_ORDER.map((p) => {
          const isSelected = priority === p;
          const disabled = blocked && p !== 'off';
          return (
            <Button
              key={p}
              compact
              selected={isSelected}
              color={isSelected ? PRIORITY_COLOR[p] : undefined}
              disabled={disabled}
              tooltip={disabled ? `Locked: ${blockReason}` : undefined}
              onClick={() =>
                send(act, 'set_priority', { job: job.title, priority: p })
              }
            >
              {PRIORITY_LABEL[p]}
            </Button>
          );
        })}
      </Box>
    </Box>
  );
};
