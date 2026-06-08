import dateformat from 'dateformat';
import yaml from 'js-yaml';
import { Fragment, useCallback, useEffect, useState } from 'react';
import { resolveAsset } from 'tgui/assets';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  Dropdown,
  Icon,
  Section,
  Stack,
  Table,
} from 'tgui-core/components';
import { classes } from 'tgui-core/react';

const icons = {
  add: { icon: 'check-circle', color: 'green' },
  admin: { icon: 'user-shield', color: 'purple' },
  balance: { icon: 'balance-scale-right', color: 'yellow' },
  bugfix: { icon: 'bug', color: 'green' },
  code_imp: { icon: 'code', color: 'green' },
  config: { icon: 'cogs', color: 'purple' },
  expansion: { icon: 'check-circle', color: 'green' },
  experiment: { icon: 'radiation', color: 'yellow' },
  image: { icon: 'image', color: 'green' },
  imageadd: { icon: 'tg-image-plus', color: 'green' },
  imagedel: { icon: 'tg-image-minus', color: 'red' },
  qol: { icon: 'hand-holding-heart', color: 'green' },
  refactor: { icon: 'tools', color: 'green' },
  rscadd: { icon: 'check-circle', color: 'green' },
  rscdel: { icon: 'times-circle', color: 'red' },
  server: { icon: 'server', color: 'purple' },
  sound: { icon: 'volume-high', color: 'green' },
  soundadd: { icon: 'tg-sound-plus', color: 'green' },
  sounddel: { icon: 'tg-sound-minus', color: 'red' },
  spellcheck: { icon: 'spell-check', color: 'green' },
  tgs: { icon: 'toolbox', color: 'purple' },
  tweak: { icon: 'wrench', color: 'green' },
  unknown: { icon: 'info-circle', color: 'label' },
  wip: { icon: 'hammer', color: 'orange' },
};

type Data = { dates: string[] };

export const Changelog = (props) => {
  const { act, data } = useBackend<Data>();
  const { dates = [] } = data;

  const dateChoices = dates.map((d) => dateformat(d, 'mmmm yyyy', true));

  const [changelogData, setChangelogData] = useState<unknown>(
    'Loading changelog data...',
  );
  const [selectedDate, setSelectedDate] = useState<string>(
    dateChoices[0] ?? '',
  );
  const [selectedIndex, setSelectedIndex] = useState(0);

  const getData = useCallback(
    (date: string, attemptNumber = 1) => {
      const maxAttempts = 6;

      if (attemptNumber > maxAttempts) {
        setChangelogData(`Failed to load data after ${maxAttempts} attempts`);
        return;
      }

      act('get_month', { date });

      fetch(resolveAsset(`${date}.yml`)).then(async (response) => {
        const result = await response.text();
        const errorRegex = /^Cannot find/;

        if (errorRegex.test(result)) {
          const timeout = 50 + attemptNumber * 50;
          setChangelogData(
            `Loading changelog data${'.'.repeat(attemptNumber + 3)}`,
          );
          setTimeout(() => {
            getData(date, attemptNumber + 1);
          }, timeout);
        } else {
          setChangelogData(yaml.load(result, { schema: yaml.CORE_SCHEMA }));
        }
      });
    },
    [act],
  );

  useEffect(() => {
    if (!dates.length) {
      return;
    }
    setSelectedDate(dateChoices[0]);
    setSelectedIndex(0);
    getData(dates[0]);
    // dateChoices is derived from dates; depend on dates for stable identity
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dates.join(',')]);

  const handleSelectIndex = (index: number) => {
    setChangelogData('Loading changelog data...');
    setSelectedIndex(index);
    setSelectedDate(dateChoices[index]);
    window.scrollTo(
      0,
      document.body.scrollHeight || document.documentElement.scrollHeight,
    );
    getData(dates[index]);
  };

  const dateDropdown =
    dateChoices.length > 0 ? (
      <Stack mb={1}>
        <Stack.Item>
          <Button
            className="Changelog__Button"
            disabled={selectedIndex === 0}
            icon="chevron-left"
            onClick={() => handleSelectIndex(selectedIndex - 1)}
          />
        </Stack.Item>
        <Stack.Item>
          <Dropdown
            displayText={selectedDate}
            options={dateChoices}
            onSelected={(value) => {
              const index = dateChoices.indexOf(value);
              handleSelectIndex(index);
            }}
            selected={selectedDate}
            width="150px"
          />
        </Stack.Item>
        <Stack.Item>
          <Button
            className="Changelog__Button"
            disabled={selectedIndex === dateChoices.length - 1}
            icon="chevron-right"
            onClick={() => handleSelectIndex(selectedIndex + 1)}
          />
        </Stack.Item>
      </Stack>
    ) : null;

  const header = (
    <Section>
      <h1>DeepQuarry Changelist</h1>
      <p>
        {'The GitHub repository can be found '}
        <a href="https://github.com/CHOMPStation2/CHOMPStation2">here</a>
        {'.'}
      </p>
      {dateDropdown}
    </Section>
  );

  const footer = (
    <Section>
      {dateDropdown}
      <h3>DeepQuarry License</h3>
      <p>
        {'All code is licensed under '}
        <a href="https://www.gnu.org/licenses/agpl-3.0.html">GNU AGPL v3</a>
        {'. See '}
        <a href="https://github.com/CHOMPStation2/CHOMPStation2/blob/master/LICENSE">
          LICENSE
        </a>
        {' for more details.'}
      </p>
      <p>
        {'All assets including icons and sound are under a '}
        <a href="https://creativecommons.org/licenses/by-sa/3.0/">
          Creative Commons 3.0 BY-SA license
        </a>
        {' unless otherwise indicated.'}
      </p>
    </Section>
  );

  const changes =
    typeof changelogData === 'object' &&
    changelogData !== null &&
    Object.keys(changelogData).length > 0 &&
    Object.entries(changelogData as Record<string, unknown>)
      .reverse()
      .map(([date, authors]) => (
        <Section key={date} title={dateformat(date, 'd mmmm yyyy', true)}>
          <Box ml={3}>
            {Object.entries(authors as Record<string, unknown>).map(
              ([name, authorChanges]) => (
                <Fragment key={name}>
                  <h4>{name} changed:</h4>
                  <Box ml={3}>
                    <Table>
                      {(authorChanges as string[]).map((change) => {
                        const changeType = Object.keys(change)[0];
                        return (
                          <Table.Row key={changeType + change[changeType]}>
                            <Table.Cell
                              className={classes([
                                'Changelog__Cell',
                                'Changelog__Cell--Icon',
                              ])}
                            >
                              <Icon
                                color={
                                  icons[changeType]
                                    ? icons[changeType].color
                                    : icons.unknown.icon
                                }
                                name={
                                  icons[changeType]
                                    ? icons[changeType].icon
                                    : icons.unknown.icon
                                }
                              />
                            </Table.Cell>
                            <Table.Cell className="Changelog__Cell">
                              {change[changeType]}
                            </Table.Cell>
                          </Table.Row>
                        );
                      })}
                    </Table>
                  </Box>
                </Fragment>
              ),
            )}
          </Box>
        </Section>
      ));

  return (
    <Window title="Changelog" width={675} height={650}>
      <Window.Content scrollable>
        {header}
        {changes}
        {typeof changelogData === 'string' && <p>{changelogData}</p>}
        {footer}
      </Window.Content>
    </Window>
  );
};
