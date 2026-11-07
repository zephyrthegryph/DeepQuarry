import { classes } from 'tgui-core/react';

import {
  emphasize,
  type LanguageRules,
  type Preview,
  type Segment,
} from './parseLanguages';

const LINE_HEIGHT = 15;
const MAX_LINES = 6;
const CHAR_WIDTH = 6;

/** Extra window height for this preview, estimated so the window resizes before layout. */
export function previewHeight(preview: Preview, width: number): number {
  let length = preview.name.length + preview.verb.length + 3;
  for (const piece of preview.pieces) {
    length += preview.emote ? 1 : piece.language.length + 6;
    for (const segment of piece.segments) length += segment.text.length;
  }
  const lines = Math.ceil((length * CHAR_WIDTH) / Math.max(width - 12, 60));
  return Math.min(lines, MAX_LINES) * LINE_HEIGHT + 2;
}

export function renderSegment(segment: Segment, key: number) {
  let node = <>{segment.text}</>;
  if (segment.tags.includes('b')) node = <b>{node}</b>;
  if (segment.tags.includes('i')) node = <i>{node}</i>;
  if (segment.tags.includes('u')) node = <u>{node}</u>;
  if (segment.tags.includes('marker'))
    node = <span style={{ opacity: 0.4 }}>{node}</span>;
  return <span key={key}>{node}</span>;
}

type Props = {
  preview: Preview;
  height: number;
  lightMode: boolean;
  zoom: string;
};

/** The speaker's own message as it will read, language by language. Text only: React escapes it. */
export function LanguagePreview(props: Props) {
  const { preview, height, lightMode, zoom } = props;
  return (
    <div
      className={classes(['preview', lightMode && 'preview-lightMode'])}
      style={{ height: height - 2, zoom }}
    >
      <span className="preview-name">{preview.name}</span>{' '}
      {preview.emote ? (
        preview.pieces[0].segments.map(renderSegment)
      ) : (
        <>
          {preview.verb},{' '}
          {preview.pieces.map((piece, index) => (
            <span key={index}>
              <span className="preview-language">{piece.language}</span>"
              {piece.segments.map(renderSegment)}"{' '}
            </span>
          ))}
        </>
      )}
    </div>
  );
}

/** Text with the chat's emphasis markers applied (the same parse and rendering as the say preview); line breaks kept. */
export function FormattedText(props: {
  text: string;
  markers: Record<string, string>;
}) {
  const { text, markers } = props;
  const [segments] = emphasize([text], { markers } as LanguageRules);
  return (
    <span style={{ whiteSpace: 'pre-wrap' }}>
      {segments.map(renderSegment)}
    </span>
  );
}

/** The markers in place (dimmed) and the rest formatted: an editor's backdrop under the text being typed. */
export function FormattedBackdrop(props: {
  text: string;
  markers: Record<string, string>;
}) {
  const { text, markers } = props;
  const [segments] = emphasize([text], { markers } as LanguageRules, true);
  return <>{segments.map(renderSegment)}</>;
}
