/*
import {
  provideFASTDesignSystem,
  fastTextField,
  fastListbox,
  fastOption,
  fastProgressRing,
} from '@microsoft/fast-components';

provideFASTDesignSystem()
  .register(
    fastTextField(),
    fastListbox(),
    fastOption(),
    fastProgressRing(),
  );
*/

export function init(Views) {
  Views.TEXT_FIELD_MATCHERS.push(node=> node instanceof fastTextField)
  Views.LIST_SELECT_EVENTS.push('selected');
  Views.addEventBinder('fast-list', 'selected', (node, handler)=> {
    node.selectedIndexChanged = handler;
  });
}
