import '@material/mwc-list';
import '@material/mwc-button';
import '@material/mwc-textfield';
import '@material/mwc-circular-progress';
import {Var, Env} from './vars.mjs';

const $ = (sel)=> document.querySelector(sel)

export class People {
  jus;
  namespace;
  secret;
  root;

  constructor() {
    this.init();
  }

  async init() {
    const progress = document.createElement('mwc-circular-progress');

    progress.setAttribute('indeterminate', '');
    document.body.append(progress);
    console.log("Contacting Jus");
    this.env = new Env();
    this.namespace = crypto.randomUUID();
    this.secret = crypto.randomUUID();
    await this.env.connect('localhost:7777', this.namespace, this.secret);
    console.log("JUS IS READY");
    this.root = await this.env.createVar('@/0:create=PersonApp')
    console.log(`CREATED ROOT: ${this.root}`);
    await this.env.observe(this.root);
    console.log(`OBSERVING ROOT`, this.root);
    console.log(`presenting people`);
    const view = await this.env.present(this.root);
    console.log(`Got View`, view);
    progress.remove();
    document.body.appendChild(view.element);
  }
}
