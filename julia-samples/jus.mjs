export class Jus {
  addr;
  namespace;
  secret;
  ready;
  handlers;
  disconnectAction;
  observer;

  constructor(addr, observer, namespace = crypto.randomUUID(), secret = crypto.randomUUID()) {
    this.addr = addr;
    this.namespace = namespace;
    this.secret = secret;
    this.ready = this.connect();
    this.handlers = [];
    this.disconnectAction = ()=>{};
    this.observer = observer;
  }

  async connect() {
    this.ws = await new Promise((accept, reject)=> {
      const ws = new WebSocket(`ws://${this.addr}`);

      ws.addEventListener('open', ()=> accept(ws));
      ws.addEventListener('error', ()=> {
        reject();
        this.disconnectAction();
      });
      ws.addEventListener('message', (msg)=> this.handleMessage(msg));
    })
    this.ws.send(JSON.stringify({namespace: this.namespace, secret: this.secret}));
  }
  
  simpleCmd(cmd) {
    return new Promise((accept, reject)=> {
      this.handlers.push([accept, reject]);
      this.ws.send(JSON.stringify(cmd));
    })
  }

  async set(...args) {
    return this.simpleCmd(['set', ...args]);
  }

  async get(...args) {
    return this.simpleCmd(['get', ...args]);
  }

  async observe(...args) {
    this.simpleCmd(['observe', ...args]);
  }

  update(items) {
    for (let i = 0; i < items.length; i += 2) {
      this.observer(items[i], items[i + 1]);
    }
  }

  async handleMessage(msg) {
    const obj = JSON.parse(msg.data);

    console.log("RECEIVED MESSAGE:", obj);
    if ('result' in obj) this.handlers.shift()[0](obj.result);
    else if ('error' in obj) this.handlers.shift()[1](obj.error);
    else if ('update' in obj) this.update(obj.update);
  }

  ondisconnect(func) {
    this.disconnectAction = func;
  }
}

export function onload(func) {
  if (document.readyState == 'complete') return func();
  function loaded() {
    if (document.readyState == 'complete') {
      func();
      document.removeEventListener('readystatechange', loaded);
    }
  }
  document.addEventListener('readystatechange', loaded);
}
