import {Jus} from './jus.mjs'
import {View, Views} from './views.mjs'

const FULL_NAME = /^([^:]+)(:(.*))?$/;
const META_PROPERTY = /^([^,=]+)=([^,]*)(?:,(.*))?$/

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
    name && this.parseMetadata(name);
    if (parent) {
      this.parent = parent;
      this.parent.children[id] = this;
    }
  }

  get destroyed() {return !this.id;}

  get type() {return this.metadata.type}

  parseMetadata(name) {
    let m = name.match(FULL_NAME);

    this.name = m[1] == "@/0" ? "" : m[1];
    if (!m[2]) return;
    for (m = m[3].match(META_PROPERTY); m && m[3]; m = m[3].match(META_PROPERTY)) {
      this.metadata[m[1]] = m[2];
    }
  }

  observe(func) {this.observers.push(func);}

  update(info) {
    if ("set" in info) this.value = info.set;
    if ("metadata" in info) {
      for (const k of Object.keys(info.metadata)) {
        this.metadata[k] = info.metadata[k];
      }
    }
    for (const o of this.observers) o(info);
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

  async present(rootVar, namespace) {
    return new View(rootVar, namespace).fetchElement();
  }

  async createVar(name, parent) {
    const varPath = parent ? `${parent.id} ${name}` : name;
    const v = this.addVar(`@/${this.nextId++}`, name, parent);

    await this.jus.set('-c', varPath, 'true');
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
