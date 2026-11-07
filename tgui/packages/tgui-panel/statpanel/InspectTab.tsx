// The Inspect tab of the stat panel: examining anything fills it and switches to it
// (code/content/examine/inspect_panel.dm). Buttons go back as "Inspect-Act" messages.

import { memo, useState } from 'react';
import { HtmlRenderer } from 'tgui/interfaces/common/HtmlRenderer';
import {
  chipText,
  chipTone,
  type InspectData,
  inspectSubtitle,
  portraitScale,
  type Worn,
} from './inspect';

const act = (name: string, params: Record<string, string> = {}) =>
  Byond.sendMessage('Inspect-Act', { act: name, ...params });

/** The portrait, drawn at a whole-number multiple of its own size so pixels stay square. */
const Portrait = ({ src }: { src: string }) => {
  const [size, setSize] = useState<[number, number] | null>(null);
  const scale = size ? portraitScale(size[0], size[1]) : 1;
  return (
    <div className="inspect__portrait">
      <img
        alt=""
        src={`data:image/png;base64,${src}`}
        onLoad={(event) => {
          const img = event.currentTarget;
          setSize([img.naturalWidth, img.naturalHeight]);
        }}
        style={
          size
            ? { width: size[0] * scale, height: size[1] * scale }
            : { visibility: 'hidden' }
        }
      />
    </div>
  );
};

const WornRow = ({ row }: { row: Worn }) => (
  <>
    <span className="inspect__slot">{row.slot}</span>
    <button
      type="button"
      className="inspect__item"
      onClick={() => act('inspect', { ref: row.ref })}
    >
      {row.name}
    </button>
  </>
);

/** Memoized: a status or misc message does not re-render it. */
export const InspectTab = memo(({ data }: { data: InspectData | null }) => {
  if (!data) {
    return <div className="stat-empty">Examine something to inspect it.</div>;
  }
  const {
    target,
    kind,
    role,
    distance,
    description = [],
    notes = [],
    worn = [],
    body = [],
    tabs = [],
    portrait,
    flavor,
    show_flavor,
    has_ooc,
    primary,
  } = data;
  return (
    <div className="inspect">
      <div className="inspect__header">
        <div className="inspect__name">{target}</div>
        <div className="inspect__subtitle">
          {inspectSubtitle(kind, role, distance)}
        </div>
      </div>
      {tabs.length > 1 && (
        <div className="inspect__tabs">
          {tabs.map((tab) => (
            <button
              type="button"
              key={tab.ref}
              title={tab.name}
              className={`inspect__tab${tab.active ? ' inspect__tab--active' : ''}`}
              onClick={() => act('select', { ref: tab.ref })}
            >
              {tab.name.toUpperCase()}
            </button>
          ))}
        </div>
      )}
      <div className="inspect__body">
        <div className="inspect__main">
          {description.map((line, index) => (
            <div key={index} className="inspect__text">
              <HtmlRenderer html={line} />
            </div>
          ))}
          {notes.map(([title, text]) => (
            <div key={title} className="inspect__note">
              <span className="inspect__noteTitle">{`${title}: `}</span>
              <HtmlRenderer html={text} />
            </div>
          ))}
          {worn.length > 0 && (
            <>
              <div className="inspect__heading">&gt; WORN</div>
              <div className="inspect__worn">
                {worn.map((row) => (
                  <WornRow key={`${row.slot}:${row.ref}`} row={row} />
                ))}
              </div>
            </>
          )}
          {body.length > 0 && (
            <>
              <div className="inspect__heading">&gt; BODY</div>
              <div className="inspect__chips">
                {body.map((chip, index) => (
                  <span
                    key={index}
                    className={`inspect__chip inspect__chip--${chipTone(chip.tone)}`}
                  >
                    {chipText(chip)}
                  </span>
                ))}
              </div>
            </>
          )}
          {!!show_flavor && !!flavor && (
            <div className="inspect__note">
              <HtmlRenderer html={flavor} />
            </div>
          )}
        </div>
        {!!portrait && <Portrait key={portrait} src={portrait} />}
      </div>
      {(!!flavor || !!has_ooc || !!primary) && (
        <div className="inspect__buttons">
          {(!!flavor || !!has_ooc) && (
            <div className="inspect__row">
              {!!flavor && (
                <button
                  type="button"
                  className="inspect__button"
                  onClick={() => act('flavor')}
                >
                  ≡ Flavor Text
                </button>
              )}
              {!!has_ooc && (
                <button
                  type="button"
                  className="inspect__button"
                  onClick={() => act('ooc')}
                >
                  ≡ OOC Notes
                </button>
              )}
            </div>
          )}
          {!!primary && (
            <button
              type="button"
              className="inspect__button inspect__button--primary"
              onClick={() => act('primary', { id: primary.id })}
            >
              {`> ${primary.name}`}
            </button>
          )}
        </div>
      )}
    </div>
  );
});
