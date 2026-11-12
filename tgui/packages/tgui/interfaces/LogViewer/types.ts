import type { LogViewerData } from '../generated/LogViewer';

export type LogViewerCategoryData = LogViewerData['categories'][string];

export type LogEntryData = LogViewerCategoryData['entries'][number];

export type CategoryBarProps = {
  options: string[];
  active: string;
  setActive: (active: string) => void;
};

export type CategoryViewerProps = {
  activeCategory: string;
  data?: LogViewerCategoryData;
};
