// AdminReport — generic structured TGUI for one-shot admin reports.
// See modular_dq/code/modules/admin/admin_report_panel.dm for the three
// rendering modes (lines / table / body_html). All three may be combined.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Section, Stack, Table } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';
import { HtmlRenderer } from './common/HtmlRenderer';

type Data = {
  title: string;
  intro_html: string;
  lines: string[];
  columns: string[];
  rows: string[][];
  body_html: string;
  has_host: BooleanLike;
};

export const AdminReport = () => {
  const { data, act } = useBackend<Data>();
  const { title, intro_html, lines, columns, rows, body_html, has_host } = data;
  return (
    <Window width={720} height={620} title={title}>
      <Window.Content scrollable>
        <Section title={title}>
          {intro_html ? (
            <Box mb={1}>
              <HtmlRenderer
                html={intro_html}
                act={act}
                forwardTopic={!!has_host}
              />
            </Box>
          ) : null}
          {lines.length > 0 ? (
            <Stack vertical>
              {lines.map((line, i) => (
                <Stack.Item key={i}>
                  <HtmlRenderer
                    html={line}
                    act={act}
                    forwardTopic={!!has_host}
                  />
                </Stack.Item>
              ))}
            </Stack>
          ) : null}
          {columns.length > 0 ? (
            <Table>
              <Table.Row header>
                {columns.map((c) => (
                  <Table.Cell key={c}>{c}</Table.Cell>
                ))}
              </Table.Row>
              {rows.map((row, ri) => (
                <Table.Row key={ri}>
                  {row.map((cell, ci) => (
                    <Table.Cell key={ci}>
                      <HtmlRenderer
                        html={cell}
                        act={act}
                        forwardTopic={!!has_host}
                      />
                    </Table.Cell>
                  ))}
                </Table.Row>
              ))}
            </Table>
          ) : null}
          {body_html ? (
            <Box mt={1}>
              <HtmlRenderer
                html={body_html}
                act={act}
                forwardTopic={!!has_host}
              />
            </Box>
          ) : null}
          {!intro_html && !lines.length && !columns.length && !body_html ? (
            <EmptyState>(empty report)</EmptyState>
          ) : null}
        </Section>
      </Window.Content>
    </Window>
  );
};
