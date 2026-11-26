// DQAdd — Renders the registered editor for a key the server sent, with that editor's slice of
// the window's data and catalogs.

import {
  type EditorDataCache,
  type EditorKey,
  type EditorStaticCache,
  type EditorStaticKey,
  getEditor,
} from './index';
import { PlaceholderEditor } from './PlaceholderEditor';

export const PrefEditor = ({
  editorKey,
  editorData,
  staticData,
}: {
  editorKey: string;
  editorData: EditorDataCache;
  staticData?: EditorStaticCache;
}) => {
  const data = editorData[editorKey as EditorKey];
  const Editor = getEditor(editorKey);
  if (!Editor) return <PlaceholderEditor data={data} />;
  // Data arrives with the first answer for the editor's category.
  if (!data) return null;
  return (
    <Editor
      data={data}
      staticData={staticData?.[editorKey as EditorStaticKey]}
    />
  );
};
