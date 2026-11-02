const PANE_SPLITTERS = {
  info_button_child: 2,
  input_buttons_child: 80,
  output_input_child: 96,
};

export function setEditPaneSplitters(editing: boolean) {
  const toSet: { [element: string]: any } = {};

  for (const pane of Object.keys(PANE_SPLITTERS)) {
    toSet[`${pane}.show-splitter`] = editing;
  }

  Byond.winset(null, toSet);
}

export function resetPaneSplitters() {
  const toSet: { [element: string]: any } = {};

  for (const default_obj of Object.entries(PANE_SPLITTERS)) {
    toSet[`${default_obj[0]}.splitter`] = default_obj[1];
  }

  Byond.winset(null, toSet);
}
