import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import { formatPower } from 'tgui-core/format';
import { decodeHtmlEntities } from 'tgui-core/string';
import type { ICCircuitActions, ICCircuitData } from './generated/ICCircuit';

type pin = ICCircuitData['inputs'][number];

export const ICCircuit = (props) => {
  const { act, data } = useBackend<ICCircuitData, ICCircuitActions>();

  const {
    desc,
    displayed_name,
    complexity,
    power_draw_idle,
    power_draw_per_use,
    extended_desc,
    inputs = [],
    outputs = [],
    activators = [],
  } = data;

  return (
    <Window width={600} height={400} title={displayed_name}>
      <Window.Content scrollable>
        <Section
          title="Stats"
          buttons={
            <Stack>
              <Stack.Item>
                <Button onClick={() => act('rename')}>Rename</Button>
              </Stack.Item>
              <Stack.Item>
                <Button onClick={() => act('scan')}>Scan with Device</Button>
              </Stack.Item>
              <Stack.Item>
                <Button onClick={() => act('remove')}>Remove</Button>
              </Stack.Item>
            </Stack>
          }
        >
          <LabeledList>
            <LabeledList.Item label="Complexity">{complexity}</LabeledList.Item>
            {(power_draw_idle && (
              <LabeledList.Item label="Power Draw (Idle)">
                {formatPower(power_draw_idle)}
              </LabeledList.Item>
            )) ||
              null}
            {(power_draw_per_use && (
              <LabeledList.Item label="Power Draw (Active)">
                {formatPower(power_draw_per_use)}
              </LabeledList.Item>
            )) ||
              null}
          </LabeledList>
          {extended_desc}
        </Section>
        <Section title="Circuit">
          <Stack textAlign="center">
            {(inputs.length && (
              <Stack.Item grow>
                <Section title="Inputs">
                  <ICIODisplay list={inputs} />
                </Section>
              </Stack.Item>
            )) ||
              null}
            <Stack.Item
              basis={
                inputs.length && outputs.length
                  ? '33%'
                  : inputs.length || outputs.length
                    ? '45%'
                    : '100%'
              }
            >
              <Section title={displayed_name} mb={1}>
                <Box>{desc}</Box>
              </Section>
            </Stack.Item>
            {(outputs.length && (
              <Stack.Item grow>
                <Section title="Outputs">
                  <ICIODisplay list={outputs} />
                </Section>
              </Stack.Item>
            )) ||
              null}
          </Stack>
          <Section title="Triggers">
            {activators.map((activator) => (
              <LabeledList.Item key={activator.name} label={activator.name}>
                <Button onClick={() => act('pin_name', { pin: activator.ref })}>
                  {decodeHtmlEntities(activator.type)}
                </Button>
                <ICLinkDisplay pin={activator} />
              </LabeledList.Item>
            ))}
          </Section>
        </Section>
      </Window.Content>
    </Window>
  );
};

const ICIODisplay = (props: { list: pin[] }) => {
  const { act } = useBackend<ICCircuitData, ICCircuitActions>();

  const { list } = props;

  return list.map((iopin) => (
    <Box key={iopin.ref}>
      <Button onClick={() => act('pin_name', { pin: iopin.ref })}>
        {decodeHtmlEntities(iopin.type)}: {iopin.name}
      </Button>
      <Button onClick={() => act('pin_data', { pin: iopin.ref })}>
        {iopin.data}
      </Button>
      <ICLinkDisplay pin={iopin} />
    </Box>
  ));
};

const ICLinkDisplay = (props: { pin: pin }) => {
  const { act } = useBackend<ICCircuitData, ICCircuitActions>();

  const { pin } = props;

  return pin.linked.map((link) => (
    <Box inline key={link.ref}>
      <Button
        onClick={() => act('pin_unwire', { pin: pin.ref, link: link.ref })}
      >
        {link.name}
      </Button>
      @&nbsp;
      <Button onClick={() => act('examine', { ref: link.holder_ref })}>
        {link.holder_name}
      </Button>
    </Box>
  ));
};
