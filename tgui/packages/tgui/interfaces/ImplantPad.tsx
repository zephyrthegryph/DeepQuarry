// Implant pad — TGUI.
//
// Reads the implant in the inserted case (if any) and lets tracking
// implants be re-IDed.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';
import { HtmlRenderer } from './common/HtmlRenderer';

type Data = {
  has_case: BooleanLike;
  has_implant: BooleanLike;
  implant_info: string;
  is_tracking: BooleanLike;
  tracking_id: number;
};

export const ImplantPad = () => {
  const { data, act } = useBackend<Data>();
  const { has_case, has_implant, implant_info, is_tracking, tracking_id } =
    data;

  return (
    <Window width={420} height={300}>
      <Window.Content>
        <Section title="Implant Mini-Computer">
          {!has_case ? (
            <EmptyState>Please insert an implant casing.</EmptyState>
          ) : !has_implant ? (
            <EmptyState>The implant casing is empty.</EmptyState>
          ) : (
            <>
              <HtmlRenderer html={implant_info} />
              {is_tracking ? (
                <LabeledList>
                  <LabeledList.Item label="ID (1-100)">
                    <Button onClick={() => act('tracking_id', { delta: -10 })}>
                      -10
                    </Button>{' '}
                    <Button onClick={() => act('tracking_id', { delta: -1 })}>
                      -1
                    </Button>{' '}
                    <Box inline bold mx={1}>
                      {tracking_id}
                    </Box>
                    <Button onClick={() => act('tracking_id', { delta: 1 })}>
                      +1
                    </Button>{' '}
                    <Button onClick={() => act('tracking_id', { delta: 10 })}>
                      +10
                    </Button>
                  </LabeledList.Item>
                </LabeledList>
              ) : null}
            </>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
