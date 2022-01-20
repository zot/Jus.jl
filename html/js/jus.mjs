export class Jus {
  addr;
  namespace;
  secret;
  ready;
  handlers = [];
  disconnectAction = ()=>{};
  observer;

  constructor(addr, observer, namespace = crypto.randomUUID(), secret = crypto.randomUUID()) {
    this.addr = addr;
    this.namespace = namespace;
    this.secret = secret;
    this.observer = observer;
    this.ready = this.connect();
  }

  async connect() {
    this.ws = await new Promise((accept, reject)=> {
      const ws = new WebSocket(`ws://${this.addr}/ws`);

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
    console.log('>>> SENDING MESSAGE', cmd);
    return new Promise((accept, reject)=> {
      this.handlers.push([accept, reject]);
      this.ws.send(JSON.stringify(cmd));
    })
  }

  async set(...args) {
    const result = await this.simpleCmd(['set', ...args]);
    console.log("SET COMMAND RESULT:", result);
    return result
  }

  async get(...args) {
    return this.simpleCmd(['get', ...args]);
  }

  async observe(...args) {
    console.log("SENDING OBSERVE COMMAND")
    const result = await this.simpleCmd(['observe', ...args]);
    console.log("OBSERVE COMMAND RESULT:", result);
    return result
  }

  update(info) {
    for (const k of Object.keys(info)) {
      this.observer(k, info[k]);
    }
  }

  async handleMessage(msg) {
    const obj = JSON.parse(msg.data);

    console.log("<<< RECEIVED MESSAGE:", obj);
    if ('error' in obj) this.handlers.shift()[1](obj.error);
    else if ('result' in obj) this.handlers.shift()[0](obj.result);
    if ('update' in obj) setTimeout(()=> this.update(obj.update))
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
