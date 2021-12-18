import {Jus} from './jus.mjs';

const $ = (sel)=> document.querySelector(sel)

export class Ex1 {
  jus;
  values;
  namespace;
  secret;
  root;

  constructor() {
    this.init();
    this.values = {};
  }

  async init() {
    this.jus = new Jus('localhost:7777', (variable, value)=> this.update(variable, value));
    this.namespace = crypto.randomUUID();
    this.secret = crypto.randomUUID();
    $('#get').addEventListener('click', ()=> this.get())
    $('#set').addEventListener('click', ()=> this.set())
    $('#observe').addEventListener('click', ()=> this.observe())
    $('#variable').addEventListener('keydown', ()=> $('#id').innerHTML = '')
    await this.jus.ready;
    this.root = (await this.jus.set('-c', `@/0:app=PersonApp`, 'true'))[0];
    $('#variable').value = this.root
    console.log("JUS IS READY");
    console.log(`CREATED ROOT: ${this.root}`);
  }

  async get() {
    console.log(`GET ${$('#variable').value}`);
    const result = await this.jus.get($('#variable').value)
    $('#id').innerHTML = result[0];
    $('#value').value = result[1];
  }
  
  async set() {
    console.log(`SET ${$('#variable').value} to ${$('#value').value}`);
    const result = await this.jus.set('-c', $('#variable').value, $('#value').value);
    $('#id').innerHTML = result[0];
  }

  async observe() {
    console.log(`OBSERVE ${$('#variable').value}`);
    await this.jus.observe($('#variable').value);
  }

  update(variable, value) {
    console.log("UPDATE:", variable, "=", value)
    
    if (!(variable in this.values)) {
      const update = $('#update-template').content.cloneNode(true);

      console.log('update', update);
      update.querySelector('[name=variable]').innerHTML = variable;
      this.values[variable] = {div: update, value: update.querySelector('[name=value]')};
      $('#observations').appendChild(update);
    }
    this.values[variable].value.innerHTML = value;
  }
}
