# support for single-process Jus apps, where the program is a client of itself

mutable struct ClientVar
    server
    id::ID
    update::Function
end

@kwdef mutable struct LocalServer
    config
    task
    con
    vars::WeakKeyDict{Var, ClientVar} = WeakKeyDict()
    pending = nothing
    observing::Set{ID} = Set()
end

struct LocalJusException
    message::AbstractString
end

ClientVar(srv::LocalServer, var::Var, update::Function) = ClientVar(srv, var.id, update)

refresh(server::LocalServer) = refresh(server.config)

var(v::ClientVar) = v.server.config.vars[v.id]

var(srv::LocalServer, id::ID) =  srv.config.vars[srv.config.vars[id]]

ignore_update(a, b) = nothing

function observing(srv::LocalServer, id::ID)
    id in srv.observing && return true
    v = var(var(srv, id))
    v.parent != EMPTYID && observing(srv, v.parent)
end

run(func::Function, srv::LocalServer, wait = false) = run(func, srv.config, wait)

"""
    local_server(namespace)

Start a server running in a new task.
Returns a LocalServer
"""
function local_server(namespace::AbstractString; debug = false)
    config = Config()
    con = FakeWS()
    other_con = other(con)
    f = ()-> try
        serve(config, con)
    catch err
        println("@@@@@@@@\n@@@@@@@@ CAUGHT SERVER ERROR")
        println(typeof(err))
        println(!isopen(other_con))
        if err isa HTTP.WebSockets.WebSocketError && !isopen(other_con)
            println("@@@@@@@@\n@@@@@@@@ OK CLOSE")
        else
            @error err exception=err,catch_backtrace()
        end
    end
    if debug
        g = f
        f = ()-> with_logger(g, ConsoleLogger(stderr, Logging.Debug))
    end
    task = @task f()
    bind(con.input, task)
    bind(con.output, task)
    schedule(task)
    output(other_con, (namespace, secret = ""))
    LocalServer(; config, task, con = other_con)
end

"""
    get_result(srv, cmd)

Get the result for a command, processing any incoming intervening updates. The special cmd,
:none, means to process an update if there is one available and buffer a command result if
one arrives.
"""
function get_result(srv::LocalServer, cmd::Symbol)
    while true
        if srv.pending !== nothing
            cmd == :none && return nothing
            packet = srv.pending
        else
            packet = input(srv.con)
            haskey(packet, :update) && handle_update(srv, packet.update)
        end
        if haskey(packet, :command)
            if packet.command == cmd
                srv.pending = nothing
                return packet
            elseif cmd == :none
                srv.pending = packet
            else
                throw(LocalJusException("Attempt to get result for $cmd while a $(srv.pending.command) result is pending"))
            end
        end
        cmd == :none && return nothing
    end
end

updates = []

function handle_update(srv::LocalServer, update)
    global updates
    push!(updates, update)
    for (var_id, upd) in update
        !haskey(srv.config.vars, var_id) && continue
        var = srv.config.vars[var_id]
        !haskey(srv.vars, var) && continue
        srv.vars[var].update(get(upd, :set, nothing), get(upd, :metadata, nothing))
    end
end

"""
    cmd(srv::LocalServer, command)

send a command to the local server and return the result
"""
function cmd(srv::LocalServer, cmd)
    output(srv.con, string.(cmd))
    get_result(srv, Symbol(cmd[1]))
end

function ID(srv::LocalServer, str::AbstractString)
    ns, id = split(str, "/")
    if ns == "@"
        ns = srv.config.namespace
    end
    ID(ns, parse(UInt, id))
end

create(srv::LocalServer, name, value = nothing) = create(ignore_update, srv, name, value)
function create(update::Function, srv::LocalServer, name, value = nothing; meta...)
    packet = cmd(srv, [:set, "-c", add_metadata(name; meta...), value])
    var_id = ID(srv, packet.result[1])
    !haskey(srv.config.vars, var_id) && return
    var = srv.config.vars[var_id]
    cvar = srv.vars[var] = ClientVar(srv, var, update)
    update != ignore_update && !observing(srv, var_id) && observe(srv, var_id)
    if haskey(packet, :update)
        # process the update here since the variable was just created
        upd = packet.update
        cvar.update(get(upd, :set, nothing), get(upd, :metadata, nothing))
    end
    srv.vars[var], packet
end

observe(srv::LocalServer, id::AbstractString, func = nothing) = observe(srv, ID(srv, id), func)
observe(srv::LocalServer, var::Union{ClientVar, Var}, func = nothing) = observe(srv, var.id, func)
function observe(srv::LocalServer, id::ID, func = nothing)
    push!(srv.observing, id)
    cmd(srv, [:observe, string(id)])
    var = srv.config.vars[id]
    cvar = get(srv.vars, var, nothing)
    if func !== nothing && cvar !== nothing
        if cvar.update !== ignore_update
            old = cvar.update
            new = func
            func = (value, metadata)-> begin
                old(value, metadata)
                new(value, metadata)
            end
        end
        cvar.update = func
    end
end

function add_metadata(name; meta...)
    if !haskey(meta, :path)
        meta = (; meta..., path = split(name)[end])
    end
    p = ["$k=$v" for (k, v) in pairs(meta) if v !== nothing]
    isempty(p) && return name
    "$name:$(join(p, ","))"
end

function set(update_func::Function, srv::LocalServer, name, value = nothing, update = ignore_update)
    cmd(srv, [:set, name, value])
end
