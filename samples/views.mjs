function clean(word) {
  return word.match(/^([^:()]*)(\(\))?$/)[1]
}

export class View {
  element;
  rootVar;
  type;
  namespace;
  children = [];

  constructor(rootVar, namespace) {
    this.rootVar = rootVar;
    this.namespace = namespace;
    this.type = rootVar.type;
    rootVar.observe(()=> this.update());
    this.views.activeViews.add(this);
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

  async prepVar(attr) {
    if (attr.indexOf(':') == -1) attr = `${clean(attr)}:path=${attr},access=action`;
    return await this.env.createVar(attr, this.rootVar);
  }

  async scan(el) {
    for (const node of el.querySelectorAll('[data-text],[data-html],[data-value],[data-click],[data-views]')) {
      let attr;

      if (attr = node.getAttribute('data-text')) {
        const v = await this.prepVar(attr);
        v.observe(()=> node.textContent = v.value);
      }
      if (attr = node.getAttribute('data-click')) {
        const v = await this.prepVar(attr);
        node.onclick = ()=> this.jus.set(v.id, 'true');
      }
      if (attr = node.getAttribute('data-views')) {
        const v = await this.prepVar(attr);
        v.observe(()=> this.newVarList(v))
      }
    }
  }

  newVarList(aVar) {
    const oldLen = aVar.oldLen || 0;
    const newLen = aVar.value?.length || 0;

    if (oldLen !== newLen) {
      console.log(`Length of ${aVar.name}(${aVar.id}) changed from ${oldLen} to ${newLen}`);
    }
  }

  async update() {
    if (this.rootVar.type == this.type) return;
    this.rootVar.destroyChildren();
    this.destroyChildren();
    const oldElement = this.element;
    await this.fetchElement();
    oldElement.replaceWith(this.element);
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
