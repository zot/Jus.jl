import {Jus} from './jus.mjs'
import {View, Views} from './views.mjs'

const FULL_NAME = /^([^:]+)(:(.*))?$/;
const META_PROPERTY = /^([^,=]+)(?:=([^,]*)(?:,(.*))?)?$/

function last(x) {return x[x.length - 1]}

export class Var {
  id;
  value;
  name;
  metadata = {};
  observers = [];
  children = {};
  env;

  constructor(id, name, parent, env) {
    this.id = id;
    this.env = env;
    if (parent) {
      const siblingNames = new Set(Object.values(parent.children).map(c=> c.name));
      const nameParts = name.match(FULL_NAME)
      const baseName = last(nameParts[1].split(/ +/));
      let tmpName = baseName;
      let counter = 0;

      this.parent = parent;
      if (name) {
        while (siblingNames.has(tmpName)) tmpName = `${baseName}-${++counter}`
        this.parent.children[id] = this;
        if (tmpName != baseName) {
          const pathParts = name.match(FULL_NAME)[1].split(/ +/);

          pathParts.pop();
          pathParts.push(tmpName);
          name = pathParts.join(' ')
          if (nameParts[2]) {
            name += nameParts[2]
          }
        }
      }
    }
    name && this.parseMetadata(name);
  }

  get destroyed() {return !this.id;}

  get type() {return this.metadata.type}

  metadataString() {return Object.entries(this.metadata).map(e=> `${e[0]}=${e[1]}`).join(',');}

  parseMetadata(name) {
    let m = name.match(FULL_NAME);

    this.name = m[1] == '@/0' ? '' : m[1];
    if (!m[2]) return;
    for (m = m[3].match(META_PROPERTY); m && m[1]; m = (m[3] || '').match(META_PROPERTY)) {
      this.metadata[m[1]] = (m[2] || '');
    }
  }

  observe(func) {this.observers.push(func);}

  update(info) {
    if ('set' in info) this.value = info.set;
    if ('metadata' in info) {
      for (const k of Object.keys(info.metadata)) {
        this.metadata[k] = info.metadata[k];
      }
    }
    for (const o of this.observers) {
      try {
        o(info);
      } catch (err) {
        console.error(err);
      }
    }
  }

  addChild(name) {
    return this.env.createVar(name, this.id)
  }

  destroy() {
    this.destroyChildren();
    this.id = null;
    console.error(`destroy not yet implemented`);
  }

  destroyChildren() {
    for (const child of Object.values(this.children)) {
      child.destroy();
    }
  }

  set(value) {
    if (this.value != value) {
      this.env.jus.set(this.id, value);
    }
  }
}

export class Env {
  jus;
  vars = {};
  nextId = 1;
  observing = new Set();
  views = new Views();

  connect(addr, namespace, secret) {
    this.jus = new Jus(addr, this.update.bind(this), namespace, secret);
    return this.jus.ready;
  }

  async present(rootVar, namespace, parent) {
    return new View(rootVar, namespace, parent).fetchElement();
  }

  async createVar(name, parent) {
    const v = this.addVar(`@/${this.nextId++}`, name, parent);
    const nameParts = name.match(FULL_NAME)
    let varPath = parent ? `${parent.id} ` : ''

    varPath += v.name || nameParts[1]
    if (Object.keys(v.metadata).length) varPath += `:${v.metadataString()}`
    console.log('CREATING', v);
    await this.jus.set('-c', varPath, null);
    return v;
  }

  addVar(id, name, parent) {
    const v = new Var(id, name, parent, this);

    this.vars[id] = v;
    return v;
  }

  async observe(id, func) {
    const v = id instanceof Var ? id : this.vars[id] || this.addVar(id);

    func && v.observe(func);
    if (!this.isObserving(v.id)) {
      this.observing.add(v.id);
      return this.jus.observe(v.id);
    }
  }

  isObserving(id) {
    let v = this.vars[id];

    while (v) {
      if (v.id in this.observing) return true;
      v = this.vars[v.parent];
    }
  }

  update(id, info) {this.vars[id]?.update(info);}
}
