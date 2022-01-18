import {Env} from './vars.mjs';
export {Views} from './views.mjs';

export class Shell {
  jus;
  namespace;
  secret;
  root;

  async init(element, vardef) {
    this.env = new Env();
    this.namespace = crypto.randomUUID();
    this.secret = crypto.randomUUID();
    await this.env.connect('localhost:7777', this.namespace, this.secret);
    console.log("JUS IS READY");
    this.root = await this.env.createVar(vardef)
    console.log(`CREATED ROOT: ${this.root}`);
    await this.env.observe(this.root);
    console.log(`OBSERVING ROOT`, this.root);
    console.log(`presenting people`);
    const view = await this.env.present(this.root);
    console.log(`Got View`, view);
    element.remove();
    document.body.appendChild(view.element);
  }
}
