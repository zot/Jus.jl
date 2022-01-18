const fastTextField = document.createElement('fast-text-field').constructor;

export function init(Views) {
  Views.TEXT_FIELD_MATCHERS.push(node=> node instanceof fastTextField)
  Views.LIST_SELECT_EVENTS.push('selected');
  Views.addEventBinder('fast-listbox', 'selected', (node, handler)=> {
    node.selectedIndexChanged = handler;
  });
}
