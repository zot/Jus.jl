import {last, defer} from './jus.mjs'

export const DEFAULT_METADATA = /(^.*):(?:(.*),)?defaults(?:,(.*))?$|^([^:]+)$/;
export const EVENT_BINDING = /^data-on-(.*)$/;
export const BIND_METADATA = /(^.*):(?:(.*),)?(get|set|prop)=([^,]+)(?:,(.*))?$/;
export const ADJUST_METADATA = /(^.*):(?:(.*),)?(adjustIndex())(?:,(.*))?$/;
export const PRIORITY_METADATA = /(^.*):(?:(.*),)?(priority)=([^,]+)(?:,(.*))?$/;

let disableInst = 1;

function clean(word) {
  return last(word.match(/^[. ]*([^:()]*)(\(\))?$/)[1].split(" "))
}

function findall(el, sel) {
  let result = [...el.querySelectorAll(sel)]

  if (el.matches(sel)) result.unshift(el);
  return result;
}

function updateFromEvent(node, get, set, variable) {
  let value = variable.adjustIndex ? variable.value - 1 : variable.value;

  if (value != node[get]) {
    if (node[set] instanceof Function) {
      node[set](value);
    } else {
      node[set] = value;
    }
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
  disablingSelection = 0;
  defaultNodeType;

  constructor(rootVar, namespace, parent, defaultNodeType = 'div') {
    this.rootVar = rootVar;
    this.namespace = namespace;
    this.type = rootVar.type;
    rootVar.observe(()=> this.update());
    this.views.activeViews.add(this);
    this.defaultNodeType = defaultNodeType;
    if (parent) {
      this.parent = parent
      parent.children.push(this)
    }
  }

  get env() {return this.rootVar.env;}

  get jus() {return this.env.jus;}

  get views() {return this.env.views;}

  async fetchElement() {
    const viewdef = await this.views.fetchViewdef(this.rootVar, this.namespace, this.defaultNodeType);

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
    return await this.env.createVar(varName, this.rootVar);
  }

  async scanAttr(el, attr, defaults, action) {
    for (const node of findall(el, `[${attr}]`)) {
      if (!node.isConnected) continue;
      this.nodes.add(node);
      if (defaults instanceof Function) defaults = defaults(node);
      action(await this.prepVar(node, node.getAttribute(attr), defaults), node);
    }
  }

  top() {return this.parent ? this.parent.top() : this;}

  async disableSelections(func, ctx) {
    this.top().handleDisableSelections(func, ctx);
  }

  async handleDisableSelections(func, ctx) {
    // NOTE: this only happens in the top node
    const inst = disableInst++;
    this.disablingSelection++;
    //console.log(`>> INC disabling selection[${inst}]: ${this.disablingSelection}`, this);
    ctx?.jus_events?.selectionHandler && ctx.jus_events?.selectionHandler.disable()
    try {
      const result = func();

      if (result instanceof Promise) await result;
    } finally {
      ctx?.jus_events?.selectionHandler && ctx.jus_events?.selectionHandler.enable()
      this.disablingSelection--;
      //console.log(`<< DEC disabling selection[${inst}]: ${this.disablingSelection}`, this);
      !this.disablingSelection && this.restoreSelections();
    }
  }

  restoreSelection(node) {
    if (!node.jus_events) return;
    for (const evt of Views.LIST_SELECT_EVENTS) {
      const evtInfo = node.jus_events[evt];

      if (!evtInfo) continue;
      updateFromEvent(node, evtInfo.get, evtInfo.set, evtInfo.variable)
    }
  }

  restoreSelections() {
    const t = this.top();

    if (t.disablingSelection) return;
    t.handleRestoreSelections();
  }
  
  handleRestoreSelections() {
    for (const node of this.selectableNodes) {
      this.restoreSelection(node);
    }
    for (const child of this.children) {
      child.handleRestoreSelections();
    }
  }

  async createList(v, node) {
    let oldLen = Array.isArray(v.value) ? v.value.length : 0;
    let views = [];

    this.selectableNodes.push(node);
    Views.configure(this, node);
    v.observe(()=> {
      let newLen = Array.isArray(v.value) ? v.value.length : 0;

      this.disableSelections(async ()=> {
        for (; newLen < oldLen; oldLen--) { // the list shrunk
          const view = views.pop();

          view.element.remove();
          view.rootVar.destroy();
        }
        for (; oldLen < newLen; oldLen++) { // the list grew
          let newVar = await this.env.createVar(`${oldLen + 1}:path=${oldLen + 1},access=r`, v);
          let view = await this.env.present(newVar, node.getAttribute('data-namespace'), this);

          views.push(view);
          node.appendChild(view.element);
        }
        oldLen = newLen;
      }, newLen != oldLen ? node : null);
    });
  }

  async scan(el) {
    await this.scanAttr(el, 'data-view', 'access=r', (v, node)=> {
      const namespace = node.getAttribute('data-namespace') || undefined;

      new View(v, namespace, this)
    })
    await this.scanAttr(el, 'data-text', 'access=r', (v, node)=> v.observe(()=> node.textContent = v.value));
    await this.scanAttr(el, 'data-value', node=> Views.isTextField(node) ? 'access=rw,blur' : 'access=rw', (v, node)=> {
      v.observe(()=> {
        if ('value' in node) {
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
    const [n3, adjust, v3] = extractMetadata(varName, ADJUST_METADATA);
    if (adjust) varName = n3;
    const [n4,, priority] = extractMetadata(varName, PRIORITY_METADATA);
    if (n4) varName = n4;
    const v = await this.prepVar(node, varName, 'access=rw');
    if (adjust) v.adjustIndex = true;
    v.priority = priority ? Number(priority) : -1;
    if (!node.jus_events) node.jus_events = {};
    node.jus_events[evt] = {get, set, variable: v};
    await v.observe(()=> {
      this.disableSelections(()=> updateFromEvent(node, get, set, v));
    });
    node.addEventListener(evt, ()=> {
      if (this.top().disablingSelection) return;
      let value = node[get];
      if (v.adjustIndex) value++;
      v.value != value && v.set(value);
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
    }, this.element.parentElement);
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

function emptySelectionPreserver(node, func) {
  return func()
}

export class Views {
  viewdefs = {};
  activeViews = new Set();

  static configHandlers = {};

  static handleConfigure(nodeName, func) {
    Views.configHandlers[nodeName.toLocaleLowerCase()] = func;
  }

  static configure(view, node) {
    const func = Views.configHandlers[node.nodeName.toLocaleLowerCase()];

    func && func(view, node);
  }

  /**
   * list of functions that return true if a node is a text field
   */
  static TEXT_FIELD_MATCHERS = [node=> node instanceof HTMLInputElement];

  /**
   * event names that indicate list selection changes
   */
  static LIST_SELECT_EVENTS = new Set(['change', 'selected']);


  static isTextField(node) {
    return Views.TEXT_FIELD_MATCHERS.findIndex(m=> m(node)) > -1
  }

  async fetchViewdef(rootVar, namespace, defaultNodeType) {
    const type = rootVar.type;
    const name = namespace ? `${type}-${namespace}` : type;
    let def;
    
    namespace = namespace || "";
    if (this.viewdefs[name]) return this.viewdefs[name];
    if (!type) return this.registerViewdef(name, parseHtml(`<${defaultNodeType}></${defaultNodeType}>`));
    if (def = this.parseGenViewdef(rootVar, name)) return def;
    if (namespace && (def = await this.fetchViewdefNamed(name))) return def;
    if (def = await this.fetchViewdefNamed(type)) return def;
    if (!rootVar.metadata.genview) {
      await rootVar.setmeta("genview", namespace);
      await defer(); // wait until after handling the update
      console.log("GENERATED VIEW FOR", rootVar);
      if (def = this.parseGenViewdef(rootVar, name)) return def;
    }
    console.error(`Could not fetch viewdef for ${name}`);
    return this.registerViewdef(name, parseHtml(`<${defaultNodeType}></${defaultNodeType}>`));
  }

  parseGenViewdef(rootVar, name) {
    if (rootVar.metadata.viewdef) return this.registerViewdef(name, parseHtml(rootVar.metadata.viewdef));
  }

  registerViewdef(name, node) {
    console.log(`REGISTERING ${name}`, node);
    this.viewdefs[name] = node;
    return node;
  }

  async fetchViewdefNamed(name) {
    try {
      const result = await fetch(`viewdefs/${name}.html`);

      return this.registerViewdef(name, parseHtml(await result.text()));
    } catch (err) {}
    return;
  }
}
