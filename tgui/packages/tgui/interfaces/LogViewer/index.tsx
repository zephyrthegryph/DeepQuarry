import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Stack } from 'tgui-core/components';
import type { LogViewerActions, LogViewerData } from '../generated/LogViewer';
import { CategoryBar } from './CategoryBar';
import { CategoryViewer } from './CategoryViewer';
import { CATEGORY_ALL } from './constants';
import type { LogViewerCategoryData } from './types';

export const LogViewer = (_: any) => {
  const { data } = useBackend<LogViewerData, LogViewerActions>();

  const [activeCategory, setActiveCategory] = useState('');

  let viewerData: LogViewerCategoryData = {
    entry_count: 0,
    entries: [],
  };

  if (activeCategory) {
    if (activeCategory !== CATEGORY_ALL) {
      viewerData = data.categories[activeCategory];
    } else {
      for (const category in data.categories) {
        const categoryData = data.categories[category];
        for (const entry of categoryData.entries) {
          viewerData.entries.push(entry);
        }
        viewerData.entry_count += categoryData.entry_count;
      }
      viewerData.entries.sort((a, b) => a.id - b.id);
    }
  }

  return (
    <Window width={720} height={720}>
      <Window.Content>
        <Stack vertical fill>
          <Stack.Item>
            <CategoryBar
              options={data.tree?.enabled ?? []}
              active={activeCategory}
              setActive={setActiveCategory}
            />
          </Stack.Item>
          <Stack.Item grow>
            <CategoryViewer activeCategory={activeCategory} data={viewerData} />
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
