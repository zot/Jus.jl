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
    var url = new URL(document.baseURI)
    await this.env.connect(url.host, this.namespace, this.secret);
    console.log("JUS IS READY");
    if (vardef.startsWith('@')) {
      if (!vardef.match(/:/)) {
        vardef += ':observe'
      } else {
        vardef += ',observe'
      }
      this.root = await this.env.createVar(vardef)
    } else {
      this.root = this.env.addVar(vardef)
      await this.env.observe(this.root);
    }
    const view = await this.env.present(this.root);
    console.log(`Got View`, view);
    element.remove();
    document.body.appendChild(view.element);
  }
}
