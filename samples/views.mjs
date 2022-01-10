import {TextField} from '@material/mwc-textfield';

console.log("MWC TEXT FIELD:", TextField);

export const DEFAULT_METADATA = /(^.*):(?:(.*),)?defaults(?:,(.*))?$|^([^:]+)$/
export const EVENT_BINDING = /^data-on-(.*)$/
export const BIND_METADATA = /(^.*):(?:(.*),)?(get|set|prop)=([^,]+)(?:,(.*))?$/
// known event names for list selection changes (in select and mwc-list elements)
const LIST_SELECT_EVENTS = ['change', 'selected']

function clean(word) {
  return word.match(/^([^:()]*)(\(\))?$/)[1]
}

function findall(el, sel) {
  let result = [...el.querySelectorAll(sel)]

  if (el.matches(sel)) result.unshift(el);
  return result;
}

function isTextField(node) {
  return node instanceof HTMLInputElement || node instanceof TextField
}

function updateFromEvent(node, set, variable) {
  if (node[set] instanceof Function) {
    node[set](variable.value);
  } else {
    node[set] = variable.value;
  }
}

/**
 * Takes a 5-group expression: (varname) (preceding md) (name) (value) (trailing md)
 * returns [newVarName, name, value]
 */
function extractMetadata(varName, regexp) {
  const m = varName.match(regexp)
  let newName = ''

  if (!m) return [false, false, false];
  newName += m[1]
  if (m[2] || m[5]) newName += ':';
  if (m[2]) newName += m[2];
  if (m[2] && m[5]) newName += ',';
  if (m[5]) newName += m[5];
  return [newName, m[3], m[4]];
}

export class View {
  element;
  rootVar;
  type;
  namespace;
  parent;
  children = [];
  nodes = new Set();
  selectableNodes = [];
  disablingSelection = false;

  constructor(rootVar, namespace, parent) {
    this.rootVar = rootVar;
    this.namespace = namespace;
    this.type = rootVar.type;
    rootVar.observe(()=> this.update());
    this.views.activeViews.add(this);
    if (parent) {
      this.parent = parent
      parent.children.push(this)
    }
  }

  get env() {return this.rootVar.env;}

  get jus() {return this.env.jus;}

  get views() {return this.env.views;}

  async fetchElement() {
    const viewdef = await this.views.fetchViewdef(this.rootVar, this.namespace);

    this.element = viewdef.cloneNode(true);
    this.scan(this.element);
    return this;
  }

  async prepVar(node, varName, defaults) {
    const m = varName.match(DEFAULT_METADATA);

    if (m && m[4]) { // no metadata
      varName = `${clean(varName)}:path=${varName},${defaults}`;
    } else if (m && m[1]) { // metadata containing "defaults"
      varName = `${clean(m[1])}:path=${m[1]},${defaults}`
      if (m[2]) varName += `,${m[2]}`
      if (m[3]) varName += `,${m[3]}`
    }
    return await this.env.createVar(varName, this.rootVar, true);
  }

  async scanAttr(el, attr, defaults, action) {
    for (const node of findall(el, `[${attr}]`)) {
      this.nodes.add(node);
      if (defaults instanceof Function) defaults = defaults(node);
      action(await this.prepVar(node, node.getAttribute(attr), defaults), node);
    }
  }

  async disableSelections(func) {
    this.parent ? this.parent.handleDisableSelections(func) : func();
  }

  async handleDisableSelections(func) {
    this.disablingSelection++;
    try {
      const result = func();

      if (result instanceof Promise) await result;
    } finally {
      this.disablingSelection--;
      this.restoreSelections();
    }
  }

  restoreSelections() {
    for (const evt of LIST_SELECT_EVENTS) {
      for (const node of this.selectableNodes) {
        const evtInfo = node.jus_events && node.jus_events[evt];

        if (evtInfo) {
          updateFromEvent(node, evtInfo.set, evtInfo.variable)
        }
      }
    }
  }

  async createList(v, node) {
    let oldLen = Array.isArray(v.value) ? v.value.length : 0;
    let views = [];

    this.selectableNodes.push(node);
    v.observe(async ()=> {
      let newLen = Array.isArray(v.value) ? v.value.length : 0;

      console.log(`Length of ${v.name}(${v.id}) changed from ${oldLen} to ${newLen}`, v);
      for (; newLen < oldLen; oldLen--) { // the list shrunk
        const view = views.pop();

        view.parentElement.remote();
        view.var.delete();
      }
      for (; oldLen < newLen; oldLen++) { // the list grew
        let newVar = await this.env.createVar(`${oldLen + 1}:path=${oldLen + 1},access=r`, v, true);
        let view = await this.env.present(newVar, node.getAttribute('data-namespace'), this);

        views.push(view);
        node.appendChild(view.element);
      }
      oldLen = newLen;
    });
  }

  async scan(el) {
    await this.scanAttr(el, 'data-text', 'access=r', (v, node)=> v.observe(()=> node.textContent = v.value));
    await this.scanAttr(el, 'data-value', node=> isTextField(node) ? 'access=rw,blur' : 'access=rw', (v, node)=> {
      v.observe(()=> {
        if (isTextField(node)) {
          node.value = v.value;
        } else {
          node.textContent = v.value;
        }
      });
      if ('blur' in v.metadata) {
        node.addEventListener('blur', ()=> v.set(node.value));
      }
    });
    await this.scanAttr(el, 'data-click', 'access=action', (v, node)=> node.onclick = ()=> this.jus.set(v.id, 'true'));
    await this.scanAttr(el, 'data-list', 'access=r', (v, node)=> this.createList(v, node));
    await this.scanAttr(el, 'data-tooltip', 'access=r', (v, node)=> v.observe(()=> node.setAttribute('title', v.value)));
    await this.scanAttr(el, 'data-enabled', 'access=r', (v, node)=> v.observe(()=> node.disabled = !v.value));
    for (const node of this.nodes) {
      for (const attr of node.attributes) {
        const m = attr.name.match(EVENT_BINDING);

        if (!m) continue;
        await this.bindEvent(m[1], node, attr.value);
      }
    }
  }

  async bindEvent(evt, node, varName) {
    const [n1, p1, v1] = extractMetadata(varName, BIND_METADATA);
    if (!p1) throw new Error("Bad event binding ${varName}");
    let get, set
    if (p1 == 'prop') {
      get = set = v1;
      varName = n1
    } else {
      const [n2, p2, v2] = extractMetadata(n1, BIND_METADATA);
      if (!((p1 == 'set' && p2 == 'get') || (p1 == 'get' && p2 == 'set'))) {
        throw new Error("Bad event binding ${varName}");
      }
      get = p1 == 'get' ? v1 : v2;
      set = p1 == 'set' ? v1 : v2;
      varName = n2
    }
    const v = await this.prepVar(node, varName, 'access=rw');
    if (!node.jus_events) node.jus_events = {};
    node.jus_events[evt] = {set, variable: v};
    await v.observe(()=> {
      updateFromEvent(node, set, v)
    });
    node.addEventListener(evt, ()=> {
      if (this.disablingSelection) return;
      const value = node[get];
      if (v.value != value) {
        v.set(value);
      }
    });
  }

  async update() {
    if (this.rootVar.type == this.type) return;
    this.disableSelections(async ()=> {
      this.selectableNodes = [];
      this.rootVar.destroyChildren();
      this.destroyChildren();
      const oldElement = this.element;
      await this.fetchElement();
      oldElement.replaceWith(this.element);
    });
  }

  destroy() {
    this.destroyChildren();
    console.log('destroy not yet implemented');
  }

  destroyChildren() {
    for (const child of this.children) {
      child.destroy();
    }
  }
}

const parser = document.createElement('div');

export function parseHtml(html) {
  parser.innerHTML = html;
  let sibling = parser.firstChild.nextSibling;

  while (sibling instanceof Text && sibling.data.match(/^(\w|\n)$/)) {
    sibling = sibling.nextSibling;
  }
  if (!sibling) {
    const result = parser.firstChild;

    result.remove();
    return result;
  }
  const result = document.createDocumentFragment()

  while (parser.firstChild) {
    result.appendChild(parser.firstChild);
  }
  return result;
}

export class Views {
  viewdefs = {};
  activeViews = new Set();

  async fetchViewdef(rootVar, namespace) {
    const type = rootVar.type;
    
    if (!type) return parseHtml('<div></div>');
    const req = namespace ? `${type}-${namespace}` : type;
    if (namespace) {
      const viewdef = await this.fetchViewdefNamed(req, req)
      if (viewdef) return viewdef;
    }
    const viewdef = await this.fetchViewdefNamed(req, type)
    if (viewdef) return viewdef;
    console.error(`No viewdef for ${req}`);
    return this.viewdefs[req] = parseHtml('<div></div>');
  }

  async fetchViewdefNamed(reqName, name) {
    try {
      const result = await fetch(`viewdefs/${name}.html`);

      return this.viewdefs[name] = parseHtml(await result.text());
    } catch (err) {}
    return;
  }
}
