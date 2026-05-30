// Holowarrant viewer — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Data = {
  loaded: BooleanLike;
  kind?: string;
  name?: string;
  charges?: string;
  auth?: string;
  jurisdiction?: string;
  station?: string;
};

export const Holowarrant = () => {
  const { data } = useBackend<Data>();
  const { loaded, kind, name, charges, auth, jurisdiction, station } = data;
  if (!loaded) {
    return (
      <Window width={500} height={220} title="Holographic Warrant">
        <Window.Content>
          <Section>
            <EmptyState>No active warrant loaded.</EmptyState>
          </Section>
        </Window.Content>
      </Window>
    );
  }
  const isSearch = kind === 'search';
  return (
    <Window
      width={600}
      height={520}
      title={`${isSearch ? 'Search' : 'Arrest'} Warrant: ${name ?? ''}`}
    >
      <Window.Content scrollable>
        <Section title="Sol Central Government — Colonial Marshal Bureau">
          <Box color="label">
            in the jurisdiction of the {jurisdiction} in {station}
          </Box>
          <Box mt={1} bold textAlign="center">
            {isSearch ? 'SEARCH WARRANT' : 'ARREST WARRANT'}
          </Box>
        </Section>
        {isSearch ? (
          <Section>
            <Box italic color="label" mb={1}>
              The Security Officer(s) bearing this Warrant are hereby authorized
              by the Issuer to conduct a one-time lawful search of the Suspect's
              person, belongings, premises, and/or Department for any items and
              materials that could be connected to the suspected criminal act
              described below, pending an investigation in progress.
            </Box>
            <LabeledList>
              <LabeledList.Item label="Suspect/Location">
                {name}
              </LabeledList.Item>
              <LabeledList.Item label="Reasons">{charges}</LabeledList.Item>
              <LabeledList.Item label="Issued by">{auth}</LabeledList.Item>
              <LabeledList.Item label="Vessel/Habitat">
                {station}
              </LabeledList.Item>
            </LabeledList>
          </Section>
        ) : (
          <Section>
            <Box mb={1}>
              This document serves as authorization and notice for the arrest of{' '}
              <b>{name}</b> for the crime(s) of:
            </Box>
            <Box italic color="label" preserveWhitespace mb={2}>
              {charges}
            </Box>
            <LabeledList>
              <LabeledList.Item label="Vessel/Habitat">
                {station}
              </LabeledList.Item>
              <LabeledList.Item label="Authorizing Officer">
                {auth}
              </LabeledList.Item>
            </LabeledList>
          </Section>
        )}
      </Window.Content>
    </Window>
  );
};
