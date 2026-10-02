const x = () => {
  act('go', { force: 1 });
  act('raw', { when: 1, extra: 2, kind: 3 });
};
