const fastTextField = document.createElement('fast-text-field').constructor;

export function init(Views) {
  document.head.parentElement.setAttribute('data-theme', 'light');
  Views.TEXT_FIELD_MATCHERS.push(node=> node instanceof fastTextField)
  Views.LIST_SELECT_EVENTS.add('selected');
  Views.handleConfigure(`fast-listbox`, (view, node)=> {
    let active = 0;

    if (!node.jus_events) node.jus_events = {};
    node.jus_events.selectionHandler = {
      disable() { // only called when the list size changes
        active++;
        view.top().disablingSelection++;
      },
      enable() {}, // this is done in the slottedOptions subscription
    };
    node.$fastController.subscribe({
      handleChange: ()=> {
        const event = new Event('selected');

        node.dispatchEvent(event);
      }
    }, "selectedIndex");
    node.$fastController.subscribe({
      handleChange: ()=> {
        if (active) {
          active--;
          view.top().disablingSelection--;
          !view.top().disablingSelection && view.top().restoreSelections();
        }
      }
    }, "slottedOptions");
  })
}
