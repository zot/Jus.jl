const NUM = r"^[0-9]+$"
const NAME = r"^\pL\p{Xan}*$"

export set_metadata

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
        Symbol(str)
    end
end

const PATH_METADATA = r"^([^:]*)(?::(.*))?$"

function findvar(cmd::JusCmd, create, vars, path, metadata::Union{Nothing, Dict{Symbol}} = nothing, value = nothing)
    m = match(PATH_METADATA, path)
    if m[2] !== nothing
        path = m[1]
        metadata = parsemetadata(m[2], metadata)
    end
    path = split(path)
    @debug("PATH: $(path)")
    components = map(c-> resolve(cmd, vars, c), path)
    @debug("COMPONENTS: $(components)")
    last = components[end]
    if length(components) > 1 && isa(components[1], ID)
        parent = components[1]
        components = components[2:end - 1]
    else
        parent = EMPTYID
        components = components[1:end - 1]
    end
    @debug("PARENT COMPONENTS: $(repr(components))")
    @debug("LAST: $(repr(last))")
    for (i, v) in enumerate(components) # path should only be names and numbers
        isemptyid(v) && throw("'?' in the middle of $(path)")
        isa(v, ID) && throw("ID in the middle of $(path)")
        parent == EMPTYID && throw("No parent variable for path $(path)")
        parent = cmd.config[parent][v].id
    end
    metadata === nothing && (metadata = Dict{Symbol, AbstractString}())
    @debug("PARENT: $(repr(parent))")
    @debug("CHECKING LAST...")
    if isemptyid(last)
        !create && throw("'?' without -c")
        parent != EMPTYID && throw("'?' at the end of path: $(path)")
        addvar(cmd, parent, Symbol(""), last, value, metadata), true
    elseif isa(last, ID)
        parent != EMPTYID && throw("ID at the end of path: $(path)")
        cmd.config[last], false
    elseif parent == EMPTYID
        throw("Attempt to get path with no parent, path: $(path)")
    elseif create && isa(last, Union{Symbol, Integer}) && !haskey(cmd.config[parent], last)
        addvar(cmd, parent, last, ID(cmd), value, metadata), true
    else
        @debug("PATH -> $(parent).$(repr(last))")
        @debug("PARENT: $(repr(cmd.config[parent]))")
        cmd.config[parent][last], false
    end
end

function command(cmd::JusCmd{:set})
    let new = [], vars = [], create, metadata
        function newset()
            create = false
            metadata = Dict{Symbol, AbstractString}()
        end
        @debug("@ SET (FRED 6): $(cmd.args)")
        pos = 1
        newset()
        while pos <= length(cmd.args)
            @match cmd.args[pos] begin
                "-c" => (create = true)
                "-m" => begin
                    metadata[cmd.args[pos + 1]] = metadata[pos + 2]
                    pos += 2
                end
                unknown => begin
                    value = cmd.args[pos + 1]
                    var, created = findvar(cmd, create, vars, cmd.args[pos], metadata, value)
                    @debug("FOUND VARIABLE: $(var)")
                    created && push!(new, var)
                    parentvalue = var.parent == EMPTYID ? nothing : cmd.config[var.parent].value
                    route(parentvalue, VarCommand(cmd, :set, (), var, arg = created ? var.value : value))
                    !cmd.cancel && push!(vars, var)
                    newset()
                    pos += 1
                end
            end
            pos += 1
        end
        output(cmd.ws, result = map(v-> json(cmd, v.id), new))
    end
end

function command(cmd::JusCmd{:get})
    vars = []
    @debug("@ GET ARGS: $(cmd.args)")
    for path in cmd.args
        var, _ = findvar(cmd, false, vars, path)
        push!(vars, var)
    end
    output(cmd.ws, result = [flatten(map(v-> (json(cmd, v.id), json(cmd, v.value)), vars))...])
end

function command(cmd::JusCmd{:observe})
    vars = []
    for path in cmd.args
        var, _ = findvar(cmd, false, vars, path)
        push!(vars, var.id)
    end
    @debug("@ OBSERVE ARGS: $(cmd.args)")
    union!(connection(cmd).observing, vars)
    @debug("OBSERVED VARS: $(repr(map(v-> v.id, allvars(cmd.config, connection(cmd).observing...))))")
    observed = [flatten(map(id-> [json(id), cmd.config[id].value], [connection(cmd).observing...]))...]
    @debug("OBSERVED: $(repr(observed))")
    output(cmd.ws, update = Dict(json(cmd, vid) => (
        set = json(cmd, cmd.config[vid].value),
        metadata = cmd.config[vid].metadata
    ) for vid in connection(cmd).observing))
end

function observe(config::Config)
    isempty(config.changes) && return
    for (_, connection) in config.connections
        @debug("CHECKING CONNECTION OBSERVING: $(repr(connection.observing))")
        changes = filter(e-> within(config, e[1], connection.observing), config.changes)
        if !isempty(changes)
            fmt = Dict()
            for (id, c) in changes
                (haskey(c, :set) || haskey(c, :metadata)) && (c = Dict(c...))
                fmt[json(connection, id)] = c
                if haskey(c, :set)
                    c[:set] = json(config, connection, config[id].value)
                end
                if haskey(c, :metadata)
                    @debug("ADDING METADATA $(config[id].metadata)")
                    c[:metadata] = Dict(m => config[id].metadata[m] for m in c[:metadata])
                end
            end
            output(connection.ws, update = fmt)
        end
    end
    config.changes = Dict()
end

function serve(config::Config, ws)
    (; namespace, secret) = input(ws)
    if haskey(config.namespaces, namespace)
        if config.namespaces[namespace].secret !== secret
            @debug("Bad attempt to connect for $(namespace)")
            output(ws, error = "Wrong secret for $(namespace)")
            return
        end
    else
        config.namespaces[namespace] = Namespace(; name=namespace, secret)
    end
    config.connections[ws] = Connection(; ws, namespace)
    @debug("Connection for $(namespace)")
    while !eof(ws)
        string="unknown"
        try
            !isopen(ws) && break
            string = readavailable(ws)
            isempty(string) && continue
            cmd = JSON3.read(string, Vector)
            command(JusCmd(config, ws, namespace, cmd))
            observe(config)
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
    @debug("CLIENT CLOSED: $(repr(namespace))")
end

function server(config::Config)
    println("SERVER ON $(config.host):$(config.port)")
    HTTP.WebSockets.listen(config.host, config.port) do ws
        config.serverfunc(config, ws)
    end
    @debug("HTTP SERVER FINISHED")
end
