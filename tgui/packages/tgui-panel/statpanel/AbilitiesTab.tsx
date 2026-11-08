// The Abilities tab of the stat panel: the mob's ability list as buttons, grouped by category, with its resources and the toggles that are
// on at the top (code/content/abilities/ability_panel.dm). A click uses the ability, a drag moves it live (the others reflow, the shared DQ gesture of tgui/dq useLiveGrid); both go back
// as "Abilities-Act" messages. The logic is in abilities.ts.

import { memo, useEffect, useState } from 'react';
import { useLiveGrid } from 'tgui/dq';
import {
  type AbilitiesData,
  type AbilityEntry,
  activeToggles,
  cooldownMs,
  cooldownText,
  hoverText,
  type Resource,
  refusalAt,
  resourceFill,
  sectionsOf,
} from './abilities';

const act = (name: string, params: Record<string, unknown> = {}) =>
  Byond.sendMessage('Abilities-Act', { act: name, ...params });

/** The time, refreshed while a countdown is running: the only timer the tab has, and it stops when nothing is recharging. */
function useNow(running: boolean): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    setNow(Date.now());
    if (!running) return;
    const timer = setInterval(() => setNow(Date.now()), 200);
    return () => clearInterval(timer);
  }, [running]);
  return now;
}

const ResourceBar = ({ resource }: { resource: Resource }) => (
  <div className="abilities__resource">
    <span className="abilities__resourceName">{resource.name}</span>
    {resource.max ? (
      <span className="abilities__bar">
        <span
          className="abilities__barFill"
          style={{
            width: `${resourceFill(resource) * 100}%`,
            background: resource.color || undefined,
          }}
        />
        <span className="abilities__barText">
          {`${resource.value} / ${resource.max}`}
        </span>
      </span>
    ) : (
      <span className="abilities__value">{resource.value}</span>
    )}
  </div>
);

type ButtonProps = {
  entry: AbilityEntry;
  receivedAt: number;
  now: number;
  dragging: string | null;
  /** The shared live-grid gesture's props for this button (tgui/dq useLiveGrid). */
  drag: ReturnType<ReturnType<typeof useLiveGrid>['itemProps']>;
  consumeClick: () => boolean;
};

const AbilityButton = (props: ButtonProps) => {
  const { entry, receivedAt, now, dragging, drag, consumeClick } = props;
  const refusal = refusalAt(entry, receivedAt, now);
  const left = cooldownMs(entry, receivedAt, now);
  const classes = ['abilities__button'];
  if (refusal) classes.push('abilities__button--refused');
  if (entry.toggled) classes.push('abilities__button--on');
  if (dragging === entry.ref) classes.push('abilities__button--dragged');
  return (
    <button
      type="button"
      className={classes.join(' ')}
      title={hoverText(entry, refusal)}
      {...drag}
      onClick={() => {
        if (!consumeClick()) act('use', { ref: entry.ref });
      }}
    >
      {!!entry.slot && <span className="abilities__slot">{entry.slot}</span>}
      {entry.icon_class ? (
        <span className="abilities__icon abilities__icon--sheet">
          <span className={entry.icon_class} />
        </span>
      ) : entry.icon ? (
        <img className="abilities__icon" alt="" src={entry.icon} />
      ) : (
        <span className="abilities__icon" />
      )}
      <span className="abilities__name">{entry.name}</span>
      {entry.toggled !== null && (
        <span className="abilities__state">{entry.toggled ? 'ON' : 'OFF'}</span>
      )}
      {!!entry.cost && <span className="abilities__cost">{entry.cost}</span>}
      {left > 0 && (
        <span className="abilities__cool">{cooldownText(left)}</span>
      )}
      {entry.channel !== null && (
        <span
          className="abilities__channel"
          style={{ width: `${Math.min(1, entry.channel) * 100}%` }}
        />
      )}
    </button>
  );
};

/** Memoized: a status or misc message does not re-render it. */
export const AbilitiesTab = memo(
  ({
    data,
    receivedAt,
  }: {
    data: AbilitiesData | null;
    receivedAt: number;
  }) => {
    const all = data?.abilities ?? [];
    const order = all.map((entry) => entry.ref);
    // The tab strips' gesture on a grid: the others reflow live, the order commits on release.
    const grid = useLiveGrid(order, (next) => act('reorder', { order: next }));
    const byRef = new Map(all.map((entry) => [entry.ref, entry]));
    const entries = grid.shown
      .map((ref) => byRef.get(ref))
      .filter((entry): entry is AbilityEntry => !!entry);
    const { dragging } = grid;
    const running = entries.some((entry) => entry.cooldown > 0);
    const now = useNow(running);
    if (!data) return <div className="stat-empty">No abilities.</div>;
    const toggles = activeToggles(entries);
    return (
      <div className="abilities" data-live-grid>
        {(data.resources.length > 0 || toggles.length > 0) && (
          <div className="abilities__status">
            {data.resources.map((resource) => (
              <ResourceBar key={resource.name} resource={resource} />
            ))}
            {toggles.length > 0 && (
              <div className="abilities__active">
                <span className="abilities__resourceName">On</span>
                {toggles.map((entry) => (
                  <span key={entry.ref} className="abilities__chip">
                    {entry.name}
                  </span>
                ))}
              </div>
            )}
          </div>
        )}
        {sectionsOf(entries).map((section, index) => (
          <div
            key={`${section.category}:${index}`}
            className="abilities__section"
          >
            <div className="abilities__heading">{section.category}</div>
            <div className="abilities__grid">
              {section.entries.map((entry) => (
                <AbilityButton
                  key={entry.ref}
                  entry={entry}
                  receivedAt={receivedAt}
                  now={now}
                  dragging={dragging}
                  drag={grid.itemProps(entry.ref)}
                  consumeClick={grid.consumeClick}
                />
              ))}
            </div>
          </div>
        ))}
      </div>
    );
  },
);
