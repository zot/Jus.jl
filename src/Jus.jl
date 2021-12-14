using Match

import Base.Iterators.flatten

export exec

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

connection(cmd::JusCmd) = cmd.config.connections[cmd.ws]

function resolve(cmd::JusCmd, vars, str)
    if str == "?"
        ID(cmd)
    elseif (m = match(REF, str)) !== nothing
        vars[m[1]].id
    elseif match(r"^[0-9]+$", str) !== nothing
        parse(Int, str)
    elseif (m = match(PATH_COMPONENT, str)) !== nothing
        ID(m[1] == "@" ? cmd.namespace : m[1], parse(UInt, m[2]))
    else
        str
    end
end

const PATH_METADATA = r"^([^:]*)(?::(.*))$"

function findvar(cmd::JusCmd, create, vars, path, metadata::Union{Nothing, Dict{AbstractString}} = nothing)
    m = match(PATH_METADATA, path)
    if m[2] !== nothing
        path = m[1]
        metadata = parsemetadata(m[2], metadata)
    end
    path = split(path, '.')
    println("PATH: $(path)")
    components = map(c-> resolve(cmd, vars, c), path)
    println("COMPONENTS: $(components)")
    last = components[end]
    if length(components) > 1 && isa(components[1], ID)
        parent = components[1]
        components = components[2:end - 1]
    else
        parent = EMPTYID
        components = components[1:end - 1]
    end
    for (i, v) in enumerate(components) # path should only be names and numbers
        isemptyid(v) && throw("'?' in the middle of $(path)")
        isa(v, ID) && throw("ID in the middle of $(path)")
        parent == EMPTYID && throw("No parent variable for path $(path)")
        parent = cmd.config[parent][v].id
    end
    metadata === nothing && (metadata = Dict{AbstractString, Any}())
    if isemptyid(last)
        !create && throw("'?' without -c")
        parent != EMPTYID && throw("'?' at the end of path: $(path)")
        addvar(cmd, parent, "", last, "", metadata)
    elseif isa(last, ID)
        parent != EMPTYID && throw("ID at the end of path: $(path)")
        cmd.config[last]
    elseif parent == EMPTYID
        throw("Attempt to get path with no parent, path: $(path)")
    elseif create && isa(last, Union{AbstractString, Integer}) && !haskey(cmd.config[parent], last)
        addvar(cmd, parent, last, ID(cmd), "", metadata)
    else
        cmd.config[parent][last]
    end
end

function command(cmd::JusCmd{:set})
    vars = []
    created = []
    create = false
    metadata = Dict{AbstractString, Any}()
    function init()
        create = false
        metadata = Dict{AbstractString, Any}()
    end
    println("@ SET (FRED 6): $(cmd.args)")
    pos = 1
    while pos <= length(cmd.args)
        @match cmd.args[pos] begin
            "-c" => (create = true)
            "-m" => begin
                metadata[cmd.args[pos + 1]] = metadata[pos + 2]
                pos += 2
            end
            unknown => begin
                var = findvar(cmd, create, vars, cmd.args[pos], metadata)
                var.value = cmd.args[pos += 1]
                push!(vars, var)
                create && push!(created, var)
                init()
            end
        end
        pos += 1
    end
    output(cmd.ws, result = map(v-> json(cmd, v.id), created))
    for (_, connection) in cmd.config.connections
        vset = filter(v-> within(cmd.config, v, connection.observing), vars)
        println("VSET: $(vset)")
        observed = intersect(connection.observing, map(v-> v.id, vset))
        println("OBSERVED: $(observed)")
        if !isempty(observed)
            output(connection.ws, update = [flatten(map(id-> (json(cmd, id), cmd.config[id].value), [observed...]))...])
        end
    end
end

function command(cmd::JusCmd{:get})
    vars = []
    println("@ GET ARGS: $(cmd.args)")
    for path in cmd.args
        var = findvar(cmd, false, vars, path)
        push!(vars, var)
    end
    output(cmd.ws, result = [flatten(map(v-> (json(cmd, v.id), v.value), vars))...])
end

function command(cmd::JusCmd{:observe})
    vars = []
    for path in cmd.args
        push!(vars, findvar(cmd, false, vars, path).id)
    end
    println("@ OBSERVE ARGS: $(cmd.args)")
    union!(connection(cmd).observing, vars)
    println("OBSERVED VARS:", map(v-> v.id, allvars(cmd.config, connection(cmd).observing...)))
    observed = [flatten(map(id-> [json(id), cmd.config[id].value], [connection(cmd).observing...]))...]
    println("OBSERVED: ", observed)
    output(cmd.ws, result = [flatten(map(id-> (json(cmd, id), cmd.config[id].value), [connection(cmd).observing...]))...])
end

function serve(config::Config, ws)
    (; namespace, secret) = input(ws)
    if haskey(config.namespaces, namespace)
        if config.namespaces[namespace].secret !== secret
            println("Bad attempt to connect for $(namespace)")
            output(ws, error = "Wrong secret for $(namespace)")
            return
        end
    else
        config.namespaces[namespace] = Namespace(; name=namespace, secret)
    end
    config.connections[ws] = Connection(; ws, namespace)
    println("Connection for $(namespace)")
    while !eof(ws)
        string="unknown"
        try
            !isopen(ws) && break
            string = readavailable(ws)
            isempty(string) && continue
            cmd = JSON3.read(string, Vector)
            command(JusCmd(config, ws, namespace, cmd))
        catch err
            if !isa(err, Base.IOError) && !isa(err, HTTP.WebSockets.WebSocketError)
                !isa(err, ArgumentError) && println(err)
                @warn "Error handling command $(String(string))" exception=(err, catch_backtrace())
            end
            break
        end
    end
    close(ws)
    put!(config.connections[ws].stop, true)
    delete!(config.connections, ws)
    println("CLIENT CLOSED:", namespace)
end

function server(config::Config)
    println("SERVER ON $(config.host):$(config.port)")
    HTTP.WebSockets.listen(config.host, config.port) do ws
        config.serverfunc(config, ws)
    end
    println("HTTP SERVER FINISHED")
end

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
            "-v" => (config.verbose = log)
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
    handle(app::APP_CLASS, var::VarCommand{COMMAND, PATH})

Handle a variable command (get or set).

When a variable is set Jus attempts set_variable(ancestor, var_command)
for each ancestor, starting at the top
"""
handle(value, cmd) = PASS
