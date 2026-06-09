// Job-Ban Panel — structured TGUI for admin role-banning.
//
// Each department block is a typed record from the server; click a job
// title to toggle that ban (DM still routes the click through the existing
// jobban3 Topic handler so the ban editor prompt sequence is reused).

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Job = {
  title: string;
  display?: string;
  is_banned: BooleanLike;
};

type Dept = {
  title: string;
  color: string;
  dept_bantype: string | null;
  is_dept_banned: BooleanLike;
  jobs: Job[];
};

type Data = {
  target_name: string;
  target_ref: string;
  departments: Dept[];
};

const JobButton = (props: { job: Job; onClick: (title: string) => void }) => {
  const { job, onClick } = props;
  return (
    <Button
      compact
      color={job.is_banned ? 'bad' : 'default'}
      onClick={() => onClick(job.title)}
    >
      {job.display ?? job.title}
    </Button>
  );
};

export const JobBanPanel = () => {
  const { data, act } = useBackend<Data>();
  const { target_name, departments } = data;

  return (
    <Window width={760} height={680} title={`Job-Ban Panel: ${target_name}`}>
      <Window.Content scrollable>
        {departments.map((d) => (
          <Section
            key={d.title}
            title={
              <Box style={{ backgroundColor: d.color, padding: '2px 4px' }}>
                <Button
                  compact
                  color={d.is_dept_banned ? 'bad' : 'default'}
                  disabled={!d.dept_bantype}
                  onClick={() =>
                    d.dept_bantype &&
                    act('toggle_dept', { bantype: d.dept_bantype })
                  }
                >
                  <Box inline bold>
                    {d.title}
                  </Box>
                </Button>
              </Box>
            }
          >
            <Stack wrap>
              {d.jobs.map((j) => (
                <Stack.Item key={j.title}>
                  <JobButton
                    job={j}
                    onClick={(title) => act('toggle_job', { title })}
                  />
                </Stack.Item>
              ))}
            </Stack>
          </Section>
        ))}
      </Window.Content>
    </Window>
  );
};
