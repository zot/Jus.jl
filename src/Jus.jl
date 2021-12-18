using Match

import Base.Iterators.flatten

export exec, serve

verbose = false

strdefault(str, default) = str == "" ? default : str

function usage()
    print("""Usage: jus NAMESPACE [-v] [-s ADDR | -c ADDR [-x SECRET]] [CMD [ARGS...]]

NAMESPACE is this jus instance's namespace

-s ADDR     run server on ADDR if ADDR starts with '/', use a UNIX domain socket
-c ADDR     connect to ADDR using NAMESPACE
-x SECRET   use secret to prove ownership of NAMESPACE. If NAMESPACE does not yet exist,
            the server creates it and associates SECRET with it.
-v          verbose

COMMANDS
set [[-c] [PATH VALUE] | [-m PATH]]...
  Set a variable, optionally creating it if it does not exist. NAMESPACE defaults to the
  current namespace.

  -c    create a variable
  -m    set only metadata for a variable (PATH should contain META -- see below)

  The format of PATH (without spaces) is
    NAME ['.' NAME]... [: META]
    or
    NAMESPACE '/' ID ['.' NAME]... [: META]

  NAMESPACE '/' ID defaults to ROOT/0.
  The name '?' means to create a new numbered child of NAMESPACE '/' ID.
  The name '?N' refers to the Nth variable created in this command (to help create trees)

  The format of META is
    NAME [',' META]...
    or
    NAME '=' VALUE [',' META]...

  Set returns a JSON list of ids the variables that were created:
    {"result": [id1, id2, ...]}

  COMMON META VALUE NAMES
  app       create an instance of the named application's object model
  path      the path from the parent's value to the corresponding value in the object model
            an empty path refers to the parent
  monitor   whether to monitor the value in the object model value is yes/no/true/false/on/off
  call      call a function on the value, optionally with a context object

get PATH...
  See set command for PATH format.

  returns values of requested variables:
    {"result": [value1, value2, ...]}

delete ID
  Remove a variable and all of its children

observe ID...
  receive updates whenever variables or their children change. Update format is
    {"update": [id1, name1, id2, name2, ...]}

  returns the ids and values for the given paths plus all of their descendants
    {"result": [id1, value1, id2, value2, ...]}
""")
    exit(1)
end

log(args...) = @info join(args)

function shutdown(config)
    println("SHUTTING DOWN")
end

function parseAddr(config::Config, s)
    m = match(r"^(([^:]+):)?([^:]+)$", s)
    config.host == m[2] ? "127.0.0.1" : m[2]
    config.port = parse(UInt16, m[3])
end

function abort(msg...)
    println(Base.stderr, msg...)
    exit(1)
end

output(ws; args...) = output(ws, args)
function output(ws, data)
    write(ws, JSON3.write(data))
    flush(ws)
    println("WROTE: ", JSON3.write(data))
end

input(ws) = JSON3.read(readavailable(ws))

function client(config::Config)
    if config.secret === "" abort("Secret required") end
    println("CLIENT $(config.namespace) connecting to ws//$(config.host):$(config.port)")
    HTTP.WebSockets.open("ws://$(config.host):$(config.port)") do ws
        output(ws, (namespace = config.namespace, secret = config.secret))
        output(ws, config.args)
        result = JSON3.read(readavailable(ws)) # read one message
        println("RESULT: $(result)")
        if config.args[1] == "observe"
            println("READING UPDATES")
            while true
                result = JSON3.read(readavailable(ws))
                println("RESULT: $(result)")
            end
        end
    end
end

function exec(serverfunc, args::Vector{String}; config = Config())
    if length(args) === 0 || match(r"^-.*$", args[1]) !== nothing
        usage()
    end # name required -- only one instance per name allowed
    config.serverfunc = serverfunc
    config.namespace = args[1]
    requirements = []
    i = 2
    while i <= length(args)
        @match args[i] begin
            "-v" => (config.verbose = true)
            "-x" => (config.secret = args[i += 1])
            "-c" => begin
                parseAddr(config, args[i += 1])
            end
            "-s" => begin
                parseAddr(config, args[i += 1])
                config.server = true
            end
            unknown => begin
                println("MATCHED DEFAULT: $(args[i:end])")
                push!(config.args, args[i:end]...)
                i = length(args)
                break
            end
        end
        i += 1
    end
    atexit(()-> shutdown(config))
    (config.server ? server : client)(config)
    config
end

set_metadata(cmd::VarCommand, name::Symbol, value) = set_metadata(cmd, cmd.var, name, value)
set_metadata(cmd::VarCommand, varname::Symbol, name::Symbol, value) =
    set_metadata(cmd, cmd.var[varname], name, value)
function set_metadata(cmd::VarCommand, var::Var, name::Symbol, value)
    var.metadata[name] = value
    push!(app.connection.metadata_sets, (var.id, name))
end

"""
    route(value, cmd)

Route a command, calling handle_child for each ancestor of the variable, starting with the root
See handle() for details on commands.
"""
function route(value, cmd::VarCommand)
    path = []
    cur = cmd.var.id
    while cur !== EMPTYID
        push!(path, cmd.config[cur])
        cur = cmd.var.parent
    end
    route(value, cmd, reverse(path))
end

function route(value, cmd::VarCommand, path)
    cmd.cancel && return cmd
    if length(path) === 1
        handle(value, cmd)
    else
        result = handle_child(path[1], path[end], value, cmd, path)
        if isa(result, VarCommand)
            # only replace it if the developer returns a replacement command
            cmd = result
        end
        route(value, cmd, @view path[2:end])
    end
end

"""
    handle_child(var, value, cmd, path)

Allows ancestor variables to alter or cancel commands.
See handle() for details on commands.
"""
handle_child(ancestor, var, value, cmd, path) = cmd

"""
    handle(value, var::VarCommand{Command, Arg})

Handle a variable command.

COMMANDS

  :metadata Set metadata for a variable. Arg will be a tuple with the metadata's name
            sent before the :create command

  :create   The variable has just been created

  :get      Determine the new value for a variable. By default, variables retain their values
            but handlers can change this behavior.

  :set      Change the value of a variable

  :observe  A connection is starting to observe this variable
"""
function handle(value, cmd)
    println("@@@ DEFAULT COMMAND HANDLER: $(cmd)")
end

function handle(value, cmd::VarCommand{:metadata, (:create,)})
    if cmd.creating
        cmd.var.value = Main.eval(:($(Symbol(cmd.var.metadata[:create]))()))
        println("@@@ CREATED: ", cmd.var.value)
        VarCommand(cmd, arg = cmd.var.value)
    end
end

function handle(value, cmd::VarCommand{:metadata, (:path,)})
    println("@@@ PATH METADATA: ", cmd)
    cmd.var.properties[:path] = split(cmd.var.metadata[:path])
end

writeable(var::Var) =
    !haskey(var.properties, :access) ||
    var.properties[:access] === :w ||
    var.properties[:access] === :rw

function handle(value, cmd::VarCommand{:set, ()})
    println("@@@ BASIC SET: ", cmd)
    if haskey(cmd.var.properties, :path) && writeable(cmd.var)
        handle(value, VarCommand{:set, (:path, cmd.var.properties[:path]...)}(cmd))
    else
        cmd.var.value = cmd.arg
    end
end

readable(var::Var) =
    !haskey(var.properties, :access) ||
    var.properties[:access] === :r ||
    var.properties[:access] === :rw

"""
    handle(...{:get})

called during refreshes
"""
function handle(value, cmd::VarCommand{:get, ()})
    println("@@@ BASIC GET: ", cmd)
    if cmd.var.parent !== EMPTYID && haskey(cmd.var.properties, :path) && readable(cmd.var)
        handle(value, VarCommand{:get, (:path, cmd.var.properties[:path]...)}(cmd))
    end
end
