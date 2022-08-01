export addvar, within, allvars, REF, UNKNOWN, PATH_COMPONENT, isemptyid, json

import Base.@invokelatest

const REF = r"^\?([0-9]+)$"
const LOCAL_ID = r"^@/([0-9]+)$"
const UNKNOWN = "?"
const PATH_COMPONENT = r"^([-[:alnum:]]+|@)/([0-9]+)$"
const VAR_NAME = r"^([0-9]+|\pL\p{Xan}*)(?::((\pL\p{Xan}*)(?:=((?:[^,]|\\,)*))?(?:,(\pL\p{Xan}*)(?:=((?:[^,]|\\,)*))?)*))?$"
const METAPROP = r"(\pL\p{Xan}*)(?:=((?:[^,]|\\,)*))?(,|$)"
const ARRAY_INDEX = r"[1-9][0-9]*"
const JPATH_COMPONENT = r"^([\p{Lu}\p{Ll}\p{Lt}\p{Lm}\p{Lo}\p{Nl}\p{Sc}\p{So}_][\p{Lu}\p{Ll}\p{Lt}\p{Lm}\p{Lo}\p{Nl}\p{Sc}\p{So}_!\p{Nd}\p{No}\p{Mn}\p{Mc}\p{Me}\p{Sk}\p{Pc}]*|[1-9][0-9]*)(?:((?:\.[\p{Lu}\p{Ll}\p{Lt}\p{Lm}\p{Lo}\p{Nl}\p{Sc}\p{So}_][\p{Lu}\p{Ll}\p{Lt}\p{Lm}\p{Lo}\p{Nl}\p{Sc}\p{So}_!\p{Nd}\p{No}\p{Mn}\p{Mc}\p{Me}\p{Sk}\p{Pc}]*)*)(?:\(\))?)?$"

oid(cmd::JusCmd, obj) = oid(connection(cmd), obj)
function oid(con::Connection, obj)
    get!(con.data2oid, obj) do
        oid = con.nextOid += 1
        con.oid2data[oid] = obj
        oid
    end
end

json(cmd::VarCommand, id::ID) = json(cmd.connection, value)
json(cmd::JusCmd, id::ID) = "$(id.namespace === cmd.namespace ? "@" : id.namespace)/$(id.number)"
json(con::Connection, id::ID) = "$(id.namespace === con.namespace ? "@" : id.namespace)/$(id.number)"
json(id::ID) = "$(id.namespace)/$(id.number)"
json(cmd::JusCmd, data) = json(cmd.config, connection(cmd), data)
json(cmd::VarCommand, value) = json(cmd.config, cmd.connection, value)
function json(cfg::Config, con::Connection, data)
    try
        JSON3.read(JSON3.write(data))
    catch
        if data isa AbstractArray
            map(d-> json(cfg, con, d), data)
        elseif data isa AbstractDict
            for (k, _) in data
                if !(k isa Symbol || k isa AbstractString)
                    throw("Cannot encode object property $(k)")
                end
            end
            Dict([k => json(cfg, con, v) for (k,v) in data]...)
        else
            cfg.verbose ? (; ref = oid(con, data), repr = repr(data)) : (; ref = oid(con, data))
        end
    end
end

isref(json) = json isa NamedTuple && haskey(json, :ref)

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
    results = []
    traverse(id::ID) = traverse(cfg[id])
    function traverse(var::Var)
        push!(results, var)
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
    results
end

isemptyid(id) = id isa ID && id.number == 0

function parsemetadata(meta::AbstractString, original_meta = nothing)
    metadata = Dict{Symbol, AbstractString}()
    if original_meta !== nothing
        merge!(metadata, original_meta)
    end
    while meta !== ""
        (m = match(METAPROP, meta)) === nothing && throw("Bad metaproperty format: $(meta)")
        metadata[Symbol(m[1])] = m[2] === nothing ? "" : m[2]
        length(meta) == length(m.match) && break
        meta[length(m.match)] != ',' && throw("Bad metaproperty format: $(meta)")
        meta = meta[length(m.match) + 1:end]
    end
    @debug("USING METADATA: $(repr(metadata))")
    metadata
end

function initial_route_meta(cmd::JusCmd, prop::Symbol, var::Var)
    route(var.value, VarCommand(cmd, :metadata, (prop,), var, creating = true))
end

function Var(cmd::JusCmd; id::ID, name = Symbol(""), args...)
    args = (;args...)
    if haskey(args, :value) && !haskey(args, :internal_value)
        args = (; args..., internal_value = args.value)
    end
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
    # route handle high priority metadata first
    haskey(v.metadata, :create) && initial_route_meta(cmd, :create, v)
    haskey(v.metadata, :access) && initial_route_meta(cmd, :access, v)
    haskey(v.metadata, :path) && initial_route_meta(cmd, :path, v)
    # route remaining metadata
    for (mk, _) in v.metadata
        mk in (:access, :path, :create) && continue
        initial_route_meta(cmd, mk, v)
    end
    route(v.value, VarCommand(cmd, :create, (), v, creating = true))
    v
end

function next_id(config::Config)
    config.namespace.curid += 1
    ID(config.namespace.name, config.namespace.curid)
end

addvar(parent::Var, value) = addvar(parent, "", next_id(parent.config), value)

addvar(parent::Var, name::Union{Integer, Symbol}, id::ID, value, metadata::Dict{Symbol, AbstractString} = Dict{Symbol, AbstractString}()) =
    addvar(parent.config, parent.id, name, id, value, metadata)

addvar(config::Config, value) = addvar(config, EMPTYID, Symbol(""), next_id(config), value)

addvar(config::Config, parent::ID, name::Union{Integer, Symbol}, id::ID, value, metadata::Dict{Symbol, AbstractString} = Dict{Symbol, AbstractString}()) =
    addvar(JusCmd(config, nothing, config.namespace.name, ["set"]), parent, name, id, value, metadata)

function addvar(cmd::JusCmd, parent::ID, name::Union{Integer, Symbol}, id::ID, value, metadata::Dict{Symbol, AbstractString})
    realname = name == Symbol("") && parent != EMPTYID ? length(cmd.config[parent]) + 1 : name
    v = Var(cmd; id, name = realname, value, metadata, parent)
    metadata[:type] = typename(value)
    changed(cmd.config, v)
    changed(cmd.config, v, keys(v.metadata)...)
    cmd.ws !== nothing && addvar(connection(cmd), v)
    v
end

addvar(con::Connection, var::Var) = push!(con.vars, var)

typename(value) = typename(typeof(value))

typename(type::Type) = "$(Base.parentmodule(type)).$(split(string(type), ".")[end])"

function set_type(cmd::VarCommand)
    name = typename(cmd.var.internal_value)
    if name != get(cmd.var.metadata, :type, "")
        set_metadata(cmd, :type, name)
    end
end

qualify(args) = length(args) == 1 ? Symbol(args[1]) : :($(qualify(args[1:end-1])).$(Symbol(args[end])))

function create_from_metadata(cmd::VarCommand)
    type = cmd.var.metadata[:create]
    match(JPATH_COMPONENT, type) === nothing && throw("bad type for create: $type for $(cmd.var)")
    # safe to eval because type is just "ident(.ident)*"
    cmd.var.internal_value = cmd.var.value = Main.eval(:($(qualify(split(type, ".")))()))
    @debug("@@@ CREATED: $(repr(cmd.var.value))")
    VarCommand(cmd, arg = cmd.var.value)
    set_type(cmd)
end

function set_access_from_metadata(var::Var)
    var.action = var.metadata[:access] == "action"
    var.readable = var.metadata[:access] in ["rw", "r"]
    var.writeable = var.metadata[:access] in ["rw", "w", "action"]
end

function set_path_from_metadata(cmd::VarCommand)
    cmd.var.path = []
    path = cmd.var.path
    for el in split(cmd.var.metadata[:path])
        el == ".." && !isempty(filter(x-> x != :.., path)) &&
            throw("'..' not allowed in the middle of a path in $(cmd.var): $(el)")
        if el == ".."
            push!(path, :..)
        else
            m = match(JPATH_COMPONENT, el)
            m === nothing && throw("Bad path component in $(cmd.var): $(el)")
            if endswith(el, "()")
                try
                    # safe to eval because m[1] * m[2] is just "ident(.ident)*"
                    push!(path, Main.eval(Meta.parse(m[1] * m[2])))
                catch err
                    rethrow(CmdException(:path, cmd, "Bad path for variable $(cmd.var.name): '$(m[1] * m[2])'"))
                end
            elseif match(ARRAY_INDEX, m[1]) !== nothing
                push!(path, parse(Int, m[1]))
            else
                push!(path, Symbol(m[1]))
            end
        end
    end
end

dicty(::Union{AbstractDict, NamedTuple}) = true
dicty(x::T) where T = hasmethod(haskey, Tuple{T, Symbol}) && hasmethod(get, Tuple{T, Symbol})

function basic_get_path(cmd::VarCommand, path)
    var = cmd.var
    var.parent == EMPTYID && throw(CmdException(:path, cmd, "no parent"))
    cur = cmd.config[var.parent].internal_value
    for el in path
        if el == :..
            var = cmd.config[var.parent]
            var.parent == EMPTYID && throw(CmdException(:path, cmd, "error going up in path with no parent"))
            cur = cmd.config[var.parent].internal_value
        elseif cur === nothing
            throw(CmdException(:path, cmd, "error getting $(cmd.var) field $(el) in path $path"))
        elseif el isa Symbol
            try
                if dicty(cur) && haskey(cur, el)
                    cur = get(cur, el)
                elseif cur isa AbstractDict && haskey(cur, string(el))
                    cur = get(cur, string(el))
                else
                    cur = getproperty(cur, el)
                end
            catch err
                rethrow(CmdException(:path, cmd, "error getting $(cmd.var) field $(el) in path $path", err))
            end
        elseif el isa Number
            try
                cur = getindex(cur, el)
            catch err
                rethrow(CmdException(:path, cmd, "error getting $(cmd.var) field $(el) in path $path", err))
            end
        elseif hasmethod(el, typeof.((cmd, cur)))
            try
                cur = el(cmd, cur)
            catch err
                rethrow(CmdException(:program, cmd, "error calling $(cmd.var) getter function $(el) in path $path", err))

            end
        elseif hasmethod(el, typeof.((cur,)))
            try
                cur = el(cur)
            catch err
                rethrow(CmdException(:program, cmd, "error calling $(cmd.var) getter function $(el) in path $path", err))
            end
        else
            throw(CmdException(:program, cmd, "No $(cmd.var) getter method $(el) for $(typeof.((cur,))) in path $path"))
        end
    end
    cur
end

function set_path(cmd::VarCommand)
    cmd.creating && (haskey(cmd.var.metadata, :create) || cmd.var.action || !isempty(cmd.var.path)) && return
    !cmd.var.writeable && throw(CmdException(:writeable_error, cmd, "variable $(cmd.var) is not writeable"))
    cur = basic_get_path(cmd, cmd.var.path[1:end - 1])
    el = cmd.var.path[end]
    cmd.arg = cmd.var.value_conversion(cmd.arg)
    if cur === nothing
        throw(CmdException(:path, cmd, "error setting field $(el) in path $(cmd.var.path) for $(cmd.var)"))
    elseif el isa Symbol
        try
            setproperty!(cur, el, cmd.arg)
        catch err
            rethrow(CmdException(:path, cmd, "error setting $(cmd.var) field $(el)", err))
        end
    elseif el isa Number
        if el == length(cur) + 1
            push!(cur, cmd.arg)
        else
            setindex!(cur, el, cmd.arg)
        end
    elseif cmd.var.action
        parent = cmd.config[cmd.var.parent].internal_value
        if :.. in cmd.var.path && hasmethod(el, typeof.((cmd, cur, parent)))
            try
                el(cmd, cur, parent)
            catch err
                rethrow(CmdException(:program, cmd, "error calling $(cmd.var) action function $(el) for $(typeof.((cmd, cur, cmd.var.internal_value))): $(err)", err))
            end
        elseif hasmethod(el, typeof.((cmd, cur)))
            try
                el(cmd, cur)
            catch err
                rethrow(CmdException(:program, cmd, "error calling $(cmd.var) action function $(el) for $(typeof.((cmd, cur,))): $(err)", err))
            end
        elseif :.. in cmd.var.path && hasmethod(el, typeof.((cur, parent)))
            try
                el(cur, parent)
            catch err
                rethrow(CmdException(:program, cmd, "error calling $(cmd.var) action function $(el) for $(typeof.((cur, cmd.var.internal_value))): $(err)", err))
            end
        elseif hasmethod(el, typeof.((cur,)))
            try
                el(cur)
            catch err
                rethrow(CmdException(:program, cmd, "error calling $(cmd.var) action function $(el) for $(typeof.((cur,))): $(err)", err))
            end
        else
            throw(CmdException(:path, cmd, "no $(cmd.var) action function $(el) for $(typeof.((cur,)))"))
        end
    elseif hasmethod(el, typeof.((cmd, cur, cmd.arg)))
        try
            el(cmd, cur, cmd.arg)
        catch err
            rethrow(CmdException(:program, cmd, "error calling $(cmd.var) setter function $(el): $(err)", err))
        end
    elseif hasmethod(el, typeof.((cur, cmd.arg)))
        try
            el(cur, cmd.arg)
        catch err
            rethrow(CmdException(:program, cmd, "error calling $(cmd.var) setter function $(el): $(err)", err))
        end
    else
        throw(CmdException(:path, cmd, "no $(cmd.var) setter function $(el) for $(typeof.((cur, cmd.arg)))"))
    end
end

function get_path(cmd::VarCommand)
    !cmd.var.readable && throw(CmdException(:readable_error, cmd, "variable $(cmd.var) is not readable"))
    cmd.var.value = cmd.var.internal_value = basic_get_path(cmd, cmd.var.path)
    json_value = json(cmd, cmd.var.value)
    cmd.var.json_value = JSON3.write(json_value)
    cmd.var.ref = isref(json_value)
    set_type(cmd)
end
