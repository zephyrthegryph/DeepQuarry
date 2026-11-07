import {
  emphasize,
  type LanguageRules,
  type Preview,
  type Segment,
} from './parseLanguages';

export function renderSegment(segment: Segment, key: number) {
  let node = <>{segment.text}</>;
  if (segment.tags.includes('b')) node = <b>{node}</b>;
  if (segment.tags.includes('i')) node = <i>{node}</i>;
  if (segment.tags.includes('u')) node = <u>{node}</u>;
  if (segment.tags.includes('marker'))
    node = <span style={{ opacity: 0.4 }}>{node}</span>;
  return <span key={key}>{node}</span>;
}

/** The speaker's own message as it will read, language by language. Text only: React escapes it. Styled by .SpeechPreview (tgui/styles/dq). */
export function LanguagePreview(props: { preview: Preview }) {
  const { preview } = props;
  return (
    <div className="SpeechPreview">
      <span className="SpeechPreview__name">{preview.name}</span>{' '}
      {preview.emote ? (
        preview.pieces[0].segments.map(renderSegment)
      ) : (
        <>
          {preview.verb},{' '}
          {preview.pieces.map((piece, index) => (
            <span key={index}>
              <span className="SpeechPreview__language">{piece.language}</span>"
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
