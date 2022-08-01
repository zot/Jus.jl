export function last(x) {
  return x[x.length - 1];
}

export function defer() {
  return new Promise((accept) => setTimeout(accept, 1));
}

export class Jus {
  addr;
  namespace;
  secret;
  ready;
  handlers = [];
  disconnectAction = () => {};
  observer;

  constructor(
    addr,
    observer,
    namespace = crypto.randomUUID(),
    secret = crypto.randomUUID()
  ) {
    this.addr = addr;
    this.namespace = namespace;
    this.secret = secret;
    this.observer = observer;
    this.ready = this.connect();
  }

  async connect() {
    this.ws = await new Promise((accept, reject) => {
      const ws = new WebSocket(`ws://${this.addr}/ws`);

      console.log("WebSocket", ws);
      ws.addEventListener("open", () => accept(ws));
      ws.addEventListener("error", () => {
        reject();
        this.disconnectAction();
      });
      ws.addEventListener("message", (msg) => this.handleMessage(msg));
    });
    this.ws.send(
      JSON.stringify({ namespace: this.namespace, secret: this.secret })
    );
  }

  simpleCmd(cmd, filter) {
    console.info(`>>> SENDING MESSAGE ${JSON.stringify(cmd)}`, cmd);
    return new Promise((accept, reject) => {
      this.handlers.push({ accept, reject, filter: filter || ((x) => x) });
      this.ws.send(JSON.stringify(cmd));
    });
  }

  async set(...args) {
    const result = await this.simpleCmd(["set", ...args], (response) => {
      if (args[0] == "-c") return;
      const [id, value] = args;
      if (
        response.update &&
        response.update[id] &&
        "set" in response.update[id]
      )
        return;
      if (!response.update) response.update = {};
      if (!response.update[id]) response.update[id] = {};
      response.update[id].set = value;
    });
    return result;
  }

  async setmeta(varId, name, value) {
    return await this.simpleCmd(["setmeta", varId, name, value]);
  }

  async get(...args) {
    return this.simpleCmd(["get", ...args]);
  }

  async observe(...args) {
    const result = await this.simpleCmd(["observe", ...args]);
    return result;
  }

  update(info) {
    this.observer(info);
  }

  async handleMessage(msg) {
    const obj = JSON.parse(msg.data);
    const handler = obj.command && this.handlers.shift();

    console.info("<<< RECEIVED MESSAGE:", obj);
    handler?.filter(obj);
    "update" in obj && setTimeout(() => this.update(obj.update));
    if (handler) {
      if ("error" in obj) handler.reject(obj.error);
      else if ("result" in obj) handler.accept(obj.result, obj);
    }
  }

  ondisconnect(func) {
    this.disconnectAction = func;
  }
}

export function onload(func) {
  if (document.readyState == "complete") return func();
  function loaded() {
    if (document.readyState == "complete") {
      func();
      document.removeEventListener("readystatechange", loaded);
    }
  }
  document.addEventListener("readystatechange", loaded);
}
