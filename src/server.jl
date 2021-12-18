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

const PATH_METADATA = r"^([^:]*)(?::(.*))?$"

function findvar(cmd::JusCmd, create, vars, path, metadata::Union{Nothing, Dict{Symbol}} = nothing, value = nothing)
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
    metadata === nothing && (metadata = Dict{Symbol, AbstractString}())
    if isemptyid(last)
        !create && throw("'?' without -c")
        parent != EMPTYID && throw("'?' at the end of path: $(path)")
        addvar(cmd, parent, "", last, value, metadata)
    elseif isa(last, ID)
        parent != EMPTYID && throw("ID at the end of path: $(path)")
        cmd.config[last]
    elseif parent == EMPTYID
        throw("Attempt to get path with no parent, path: $(path)")
    elseif create && isa(last, Union{AbstractString, Integer}) && !haskey(cmd.config[parent], last)
        addvar(cmd, parent, last, ID(cmd), value, metadata)
    else
        cmd.config[parent][last]
    end
end

function command(cmd::JusCmd{:set})
    let created = [], vars = [], create, metadata
        function newset()
            create = false
            metadata = Dict{Symbol, AbstractString}()
        end
        println("@ SET (FRED 6): $(cmd.args)")
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
                    var = findvar(cmd, create, vars, cmd.args[pos], metadata, value)
                    create && push!(created, var)
                    parentvalue = var.parent == EMPTYID ? nothing : cmd.config[var.parent].value
                    route(parentvalue, VarCommand(cmd, :set, (), var, arg = create ? var.value : value))
                    !cmd.cancel && push!(vars, var)
                    newset()
                    pos += 1
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
                output(connection.ws, update = [flatten(map(id-> (json(cmd, id), safe(cmd.config[id].value)), [observed...]))...])
            end
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
    output(cmd.ws, result = [flatten(map(v-> (json(cmd, v.id), json(cmd, v.value)), vars))...])
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
    output(cmd.ws, result = [flatten(map(id-> (json(cmd, id), json(cmd, cmd.config[id].value)), [connection(cmd).observing...]))...])
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
