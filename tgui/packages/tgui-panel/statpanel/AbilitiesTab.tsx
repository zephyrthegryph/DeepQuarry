// The Abilities tab of the stat panel: the mob's ability list as buttons, grouped by category, with its resources and the toggles that are
// on at the top (code/content/abilities/ability_panel.dm). A click uses the ability, a drag onto another button moves it there; both go back
// as "Abilities-Act" messages. The logic is in abilities.ts.

import { useEffect, useState } from 'react';
import {
  type AbilitiesData,
  type AbilityEntry,
  activeToggles,
  cooldownMs,
  cooldownText,
  hoverText,
  moveBefore,
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
  onDragStart: (ref: string) => void;
  onDrop: (ref: string) => void;
  onDragEnd: () => void;
};

const AbilityButton = (props: ButtonProps) => {
  const { entry, receivedAt, now, dragging, onDragStart, onDrop, onDragEnd } =
    props;
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
      draggable
      onClick={() => act('use', { ref: entry.ref })}
      onDragStart={(event) => {
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/plain', entry.ref);
        onDragStart(entry.ref);
      }}
      onDragOver={(event) => {
        if (dragging && dragging !== entry.ref) event.preventDefault();
      }}
      onDrop={(event) => {
        event.preventDefault();
        onDrop(entry.ref);
      }}
      onDragEnd={onDragEnd}
    >
      {!!entry.slot && <span className="abilities__slot">{entry.slot}</span>}
      {entry.icon ? (
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

export const AbilitiesTab = ({
  data,
  receivedAt,
}: {
  data: AbilitiesData | null;
  receivedAt: number;
}) => {
  const [dragging, setDragging] = useState<string | null>(null);
  const entries = data?.abilities ?? [];
  const running = entries.some((entry) => entry.cooldown > 0);
  const now = useNow(running);
  if (!data) return <div className="stat-empty">No abilities.</div>;
  const toggles = activeToggles(entries);
  const reorder = (target: string) => {
    if (!dragging) return;
    const order = entries.map((entry) => entry.ref);
    const next = moveBefore(order, dragging, target);
    setDragging(null);
    if (next !== order) act('reorder', { order: next });
  };
  return (
    <div className="abilities">
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
                onDragStart={setDragging}
                onDrop={reorder}
                onDragEnd={() => setDragging(null)}
              />
            ))}
          </div>
        </div>
      ))}
    </div>
  );
};
