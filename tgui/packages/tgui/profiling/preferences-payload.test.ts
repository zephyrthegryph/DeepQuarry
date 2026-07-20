import { describe, expect, test } from 'bun:test';

const WIDGETS = 180;
const CHOICES_PER_WIDGET = 80;

function makeLegacyCategories() {
  return [
    {
      category: 'appearance',
      groups: [
        {
          group: 'catalogs',
          items: Array.from({ length: WIDGETS }, (_, index) => ({
            type: 'widget',
            key: `preference_${index}`,
            label: `Preference ${index}`,
            widget: 'dropdown',
            value: `choice_${index % CHOICES_PER_WIDGET}`,
            props: {},
            choices: Array.from(
              { length: CHOICES_PER_WIDGET },
              (_, choice) => `choice_${choice}`,
            ),
          })),
        },
      ],
    },
  ];
}

describe('Preferences payload shape', () => {
  test('recurring updates do not resend static widget catalogs', () => {
    const categories = makeLegacyCategories();
    const legacyUpdate = { data: { dq_categories: categories } };
    const splitUpdate = {
      data: {
        dq_values: Object.fromEntries(
          categories[0].groups[0].items.map((item) => [item.key, item.value]),
        ),
        dq_editor_data: {},
      },
    };
    const legacyBytes = JSON.stringify(legacyUpdate).length;
    const splitBytes = JSON.stringify(splitUpdate).length;
    console.info(
      `[preferences payload] recurring ${legacyBytes}B legacy â†’ ${splitBytes}B split`,
    );
    expect(splitBytes).toBeLessThan(legacyBytes * 0.08);
  });
});
