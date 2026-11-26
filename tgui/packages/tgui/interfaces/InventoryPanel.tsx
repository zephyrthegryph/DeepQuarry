import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Data = {
  slots: { name: string; item: string; act: string }[];
  internalsValid: BooleanLike;
};

export const InventoryPanel = (props) => {
  const { act, data } = useBackend<Data>();

  // No op answers a non-human panel's actions (stripping is human-only); the Set Internals button that sent one is gone.
  const { slots } = data;

  return (
    <Window width={400} height={200}>
      <Window.Content scrollable>
        <Section>
          <LabeledList>
            {slots?.length &&
              slots.map((slot) => (
                <LabeledList.Item key={slot.name} label={slot.name}>
                  <Button
                    mb={-1}
                    icon={slot.item ? 'hand-paper' : 'gift'}
                    onClick={() => act(slot.act)}
                  >
                    {slot.item || 'Nothing'}
                  </Button>
                </LabeledList.Item>
              ))}
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
};
