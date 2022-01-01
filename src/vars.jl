export addvar, within, allvars, REF, UNKNOWN, PATH_COMPONENT, isemptyid, json

const REF = r"^\?([0-9]+)$"
const LOCAL_ID = r"^@/([0-9]+)$"
const UNKNOWN = "?"
const PATH_COMPONENT = r"^([-[:alnum:]]+|@)/([0-9]+)$"
const VAR_NAME = r"^([0-9]+|\pL\p{Xan}*)(?::((\pL\p{Xan}*)(?:=((?:[^,]|\\,)*))?(?:,(\pL\p{Xan}*)(?:=((?:[^,]|\\,)*))?)*))?$"
const METAPROP = r"(\pL\p{Xan}*)(?:=((?:[^,]|\\,)*))?(,|$)"
const JPATH_COMPONENT = r"^([\p{Lu}\p{Ll}\p{Lt}\p{Lm}\p{Lo}\p{Nl}\p{Sc}\p{So}_][\p{Lu}\p{Ll}\p{Lt}\p{Lm}\p{Lo}\p{Nl}\p{Sc}\p{So}_!\p{Nd}\p{No}\p{Mn}\p{Mc}\p{Me}\p{Sk}\p{Pc}]*)(?:((?:\.[\p{Lu}\p{Ll}\p{Lt}\p{Lm}\p{Lo}\p{Nl}\p{Sc}\p{So}_][\p{Lu}\p{Ll}\p{Lt}\p{Lm}\p{Lo}\p{Nl}\p{Sc}\p{So}_!\p{Nd}\p{No}\p{Mn}\p{Mc}\p{Me}\p{Sk}\p{Pc}]*)*)\(\))?$"

oid(cmd::JusCmd, obj) = oid(connection(cmd), obj)
function oid(con::Connection, obj)
    get!(con.data2oid, obj) do
        oid = con.nextOid += 1
        con.oid2data[oid] = WeakRef(obj)
        oid
    end
end

json(cmd::JusCmd, id::ID) = "$(id.namespace === cmd.namespace ? "@" : id.namespace)/$(id.number)"
json(con::Connection, id::ID) = "$(id.namespace === con.namespace ? "@" : id.namespace)/$(id.number)"
json(id::ID) = "$(id.namespace)/$(id.number)"
json(cmd::JusCmd, data) = json(cmd.config, connection(cmd), data)
function json(cfg::Config, con::Connection, data)
    try
        JSON3.write(data)
        data
    catch
        cfg.verbose ? (; ref = oid(con, data), repr = repr(data)) : (; ref = oid(con, data))
    end
end

Base.haskey(cfg::Config, id::ID) = haskey(cfg.vars, id)
Base.getindex(cfg::Config, id::ID) = cfg.vars[id]
Base.setindex!(cfg::Config, var::Var, id::ID) = cfg.vars[id] = var

Base.haskey(var::Var, name::Symbol) = haskey(var.namedchildren, name)
function Base.getindex(var::Var, name::Symbol)
    get(var.namedchildren, name, ()-> throw("No variable for name $(name)"))
end
Base.setindex!(var::Var, value::Var, name::Symbol) = var.namedchildren[name] = value
Base.haskey(var::Var, index::Integer) = 0 <= index <= length(var.indexedchildren)
Base.length(var::Var) = length(var.indexedchildren)
function Base.getindex(var::Var, index::Integer)
    get(var.indexedchildren, index, ()-> throw("No variable for index $(index)"))
end
function Base.setindex!(var::Var, value::Var, index::Integer)
    if length(var) == index - 1
        push!(var.indexedchildren, value)
    elseif index < 0 || length(var) < index
        throw("Attempt to add variable $(index), when there are only $(length(var))")
    else
        var.indexedchildren[index] = value
    end
end

within(cfg::Config, id::ID, ids::Set{ID}) = within(cfg, get(cfg.vars, id, EMPTYID), ids)

function within(cfg::Config, var::Var, ids::Set{ID})
    (var.id in ids) || ((var.parent != EMPTYID) && within(cfg, cfg[var.parent], ids))
end

function allvars(cfg::Config, vars...)
    generate() do yield
        traverse(id::ID) = traverse(cfg[id])
        function traverse(var::Var)
            yield(var)
            for (_, v) in var.namedchildren
                traverse(v)
            end
            for v in var.indexedchildren
                traverse(v)
            end
        end
        for v in vars
            traverse(v)
        end
    end
end

isemptyid(id) = id isa ID && id.number == 0

function parsemetadata(meta::AbstractString, original_meta = nothing)
    metadata = Dict{Symbol, AbstractString}()
    if original_meta !== nothing
        merge!(metadata, original_meta)
    end
    while meta !== ""
        (m = match(METAPROP, meta)) === nothing && throw("Bad metaproperty format: $(meta)")
        println("@@@@@@ METAPROP $(m[1]) = $(m[2])")
        metadata[Symbol(m[1])] = m[2]
        length(meta) == length(m.match) && break
        meta[length(m.match)] != ',' && throw("Bad metaproperty format: $(meta)")
        meta = meta[length(m.match) + 1:end]
    end
    @debug("USING METADATA: $(repr(metadata))")
    metadata
end

function Var(cmd::JusCmd; id::ID, name = Symbol(""), args...)
    args = (;args...)
    if name isa Union{Symbol, AbstractString} && string(name) != ""
        m = match(VAR_NAME, string(name))
        if m !== nothing && m[2] !== nothing
            name = m[1]
            metadata = parsemetadata(m[2], haskey(args, :metadata) ? args.metadata : Dict())
            args = (;args..., metadata, name)
        end
    end
    if name isa AbstractString
        name = Symbol(name)
    end
    ns = cmd.config.namespaces[id.namespace]
    id.number == 0 && (id = ID(id.namespace, ns.curid += 1))
    ns.curid = max(ns.curid, id.number)
    v = cmd.config[id] = Var(; args..., id, name = name isa Number ? Symbol("") : name)
    v.parent !== EMPTYID && name != Symbol("") && (cmd.config[v.parent][name] = v)
    v.parent !== EMPTYID && name != Symbol("") && @debug("ADDED CHILD OF $(v.parent) NAMED $(name) = $(cmd.config[v.parent][name])")
    !isempty(v.metadata) && @debug("VAR $(v.name) metadata: $(v.metadata)")
    for (mk, _) in v.metadata
        vcmd = VarCommand(cmd, :metadata, (mk,), v, creating = true)
        if hasmethod(handle, typeof.((v.value, vcmd)))
            println("CALLING META HANDLER FOR $(vcmd)")
            route(v.value, vcmd)
        else
            println("NO META HANDLER FOR $(vcmd)")
        end
    end
    route(v.value, VarCommand(cmd, :create, (), v, creating = true))
    v
end

function addvar(cmd::JusCmd, parent::ID, name::Union{Integer, Symbol}, id::ID, value, metadata::Dict{Symbol, AbstractString})
    realname = name == Symbol("") && parent != EMPTYID ? length(cmd.config[parent]) + 1 : name
    v = Var(cmd; id, name = realname, value, metadata, parent)
    cmd.config.changes[v.id] = Dict(:set => true)
    println("@@@@@@ VAR $(v.id) METADATA: $(v.metadata)")
    if !isempty(v.metadata)
        cmd.config.changes[v.id][:metadata] = Set(keys(v.metadata))
    end
    println("@@@@@@ VAR $(v.id) CHANGES: $(cmd.config.changes[v.id])")
    v
end

function set_access_from_metadata(var::Var)
    var.call = var.metadata[:access] === "call"
    var.readable = var.metadata[:access] in ["rw", "r"]
    var.writeable = var.metadata[:access] in ["rw", "w"]
end

function set_path_from_metadata(var::Var)
    println("@@@@@@ SETTING PATH FROM METADATA $(var.metadata[:path])")
    var.path = []
    path = var.path
    for el in split(var.metadata[:path])
        m = match(JPATH_COMPONENT, el)
        m === nothing && throw("Bad path component in $(var): $(el)")
        println("@@@@@@ PATH COMPONENT: $(m[1]), $(m[2])")
        if m[2] !== nothing
            push!(path, Main.eval(Meta.parse(m[1] * m[2])))
        else
            push!(path, Symbol(m[1]))
        end
        println("@@@@@@ PATH COMPONENT VALUE: $(path[end])")
    end
    println("@@@@@@ PATH: $(path)")
    println("@@@@@@ VAR PATH: $(var.path)")
end

function basic_get_path(cmd::VarCommand, path)
    println("@@@\n@@@ GETTING PATH")
    cmd.var.parent == EMPTYID && throw(CmdException(:path, cmd, "no parent"))
    cur = cmd.config[cmd.var.parent].value
    for el in path
        if el isa Symbol
            try
                cur = getfield(cur, el)
            catch err
                throw(CmdException(:path, cmd, "error getting field $(el)", err))
            end
        elseif hasmethod(el, typeof.((cmd, cur)))
            try
                cur = el(cmd, cur)
            catch err
                throw(CmdException(:program, cmd, "error calling getter function $(el)", err))
            end
        elseif hasmethod(el, typeof.((cur,)))
            try
                cur = el(cur)
            catch err
                throw(CmdException(:program, cmd, "error calling getter function $(el)", err))
            end
        else
            throw(CmdException(:path, cmd, "No getter method $(el) for $(typeof.((cur)))"))
        end
    end
    cur
end

function set_path(cmd::VarCommand, value)
    cmd.creating && return
    println("@@@\n@@@ SETTING PATH")
    !cmd.var.writeable && throw(CmdException(:writeable_error, cmd, "variable $(cmd.var.id) is not writeable"))
    cur = basic_get_path(cmd, cmd.var.path[1:end - 1])
    el = cmd.var.path[end]
    if el isa Symbol
        try
            cur = setfield!(cur, el, value)
        catch err
            throw(CmdException(:path, cmd, "error setting $(cmd.var.id) field $(el)", err))
        end
    elseif hasmethod(el, typeof.((cmd, cur, value)))
        try
            cur = el(cmd, cur, value)
        catch err
            throw(CmdException(:program, cmd, "error calling $(cmd.var.id) setter function $(el)", err))
        end
    elseif hasmethod(el, typeof.((cur, value)))
        try
            cur = el(cur, value)
        catch err
            throw(CmdException(:program, cmd, "error calling $(cmd.var.id) setter function $(el)", err))
        end
    else
        throw(CmdException(:path, cmd, "no $(cmd.var.id) setter function $(el) for $(typeof.((cur, value)))"))
    end
end

function get_path(cmd::VarCommand)
    !cmd.var.writeable && throw(CmdException(:readable_error, cmd, "variable $(cmd.var.id) is not readable"))
    basic_get_path(cmd, cmd.var.path)
end
