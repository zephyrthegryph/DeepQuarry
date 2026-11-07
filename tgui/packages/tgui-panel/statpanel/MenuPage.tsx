import { useEffect, useState } from 'react';
import { Button, Section } from 'tgui-core/components';
import {
  CHAT_ITEMS,
  GAME_ITEMS,
  HELP_ITEMS,
  ICON_SIZES,
  iconSizeCommand,
  LINK_ITEMS,
  type MenuItem,
  textModeCommand,
  ZOOM_MODES,
  zoomModeCommand,
} from './menu';

function run(command: string) {
  setTimeout(() => Byond.command(command), 0);
}

function Items({ items }: { items: MenuItem[] }) {
  return (
    <div className="menu-row">
      {items.map((item) => (
        <Button key={item.command} onClick={() => run(item.command)}>
          {item.label}
        </Button>
      ))}
    </div>
  );
}

/** winget answers by property, or by element.property on some client builds. */
function prop(props: Record<string, any>, name: string) {
  return `${props?.[name] ?? props?.[`map.${name}`] ?? props?.[`mapwindow.map.${name}`] ?? ''}`;
}

export function MenuPage() {
  const [iconSize, setIconSize] = useState('');
  const [zoomMode, setZoomMode] = useState('');
  const [textMode, setTextMode] = useState(false);
  const [fullscreen, setFullscreen] = useState(false);

  useEffect(() => {
    Byond.winget('mapwindow.map', ['icon-size', 'zoom-mode', 'text-mode']).then(
      (props: Record<string, any>) => {
        setIconSize(prop(props, 'icon-size'));
        setZoomMode(prop(props, 'zoom-mode'));
        setTextMode(prop(props, 'text-mode') === 'true');
      },
    );
    Byond.winget('mainwindow', ['is-fullscreen']).then(
      (props: Record<string, any>) => {
        setFullscreen(prop(props, 'is-fullscreen') === 'true');
      },
    );
  }, []);

  // The server owns the choice (a saved preference, borderless fullscreen by default).
  function toggleFullscreen() {
    setFullscreen(!fullscreen);
    run('toggle-fullscreen');
  }

  return (
    <>
      <Section title="Game">
        <Items items={GAME_ITEMS} />
        <div className="menu-row">
          <Button selected={fullscreen} onClick={toggleFullscreen}>
            Fullscreen (no title bar)
          </Button>
        </div>
      </Section>
      <Section title="Chat window">
        <Items items={CHAT_ITEMS} />
      </Section>
      <Section title="Icon size">
        <div className="menu-row">
          {ICON_SIZES.map((size) => (
            <Button
              key={size.value}
              selected={iconSize === size.value}
              onClick={() => {
                setIconSize(size.value);
                run(iconSizeCommand(size.value));
              }}
            >
              {size.label}
            </Button>
          ))}
          <Button
            selected={textMode}
            onClick={() => {
              setTextMode(!textMode);
              run(textModeCommand(!textMode));
            }}
          >
            Text
          </Button>
        </div>
      </Section>
      <Section title="Scaling">
        <div className="menu-row">
          {ZOOM_MODES.map((mode) => (
            <Button
              key={mode.value}
              selected={zoomMode === mode.value}
              onClick={() => {
                setZoomMode(mode.value);
                run(zoomModeCommand(mode.value));
              }}
            >
              {mode.label}
            </Button>
          ))}
        </div>
      </Section>
      <Section title="Help and preferences">
        <Items items={HELP_ITEMS} />
      </Section>
      <Section title="Links">
        <Items items={LINK_ITEMS} />
      </Section>
    </>
  );
}
