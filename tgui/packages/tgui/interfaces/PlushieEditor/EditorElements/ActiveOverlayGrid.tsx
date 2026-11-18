import type React from 'react';
import { memo } from 'react';
import { ImageButton, Stack } from 'tgui-core/components';
import { EmptyState } from '../../common/EmptyState';
import type { Overlay } from '../types';

type ActiveOverlaysGridProps = {
  icon: string;
  overlays: Overlay[];
  selectedOverlay: string | null;
  onSelect: React.Dispatch<React.SetStateAction<string | null>>;
};

export const ActiveOverlaysGrid = memo<ActiveOverlaysGridProps>(
  ({ icon, overlays, selectedOverlay, onSelect }) => (
    <Stack wrap="wrap" justify="center">
      {overlays.length === 0 && (
        <EmptyState>No overlays yet: add one with the picker above.</EmptyState>
      )}
      {overlays.map((ov) => (
        <Stack.Item key={ov.icon_state}>
          <ImageButton
            dmIcon={icon}
            dmIconState={ov.icon_state}
            onClick={() => onSelect(ov.icon_state)}
            color={selectedOverlay === ov.icon_state ? 'green' : undefined}
          >
            {ov.name}
          </ImageButton>
        </Stack.Item>
      ))}
    </Stack>
  ),
);
