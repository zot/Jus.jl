export addvar, within, allvars, REF, UNKNOWN, PATH_COMPONENT, isemptyid, json

const REF = r"^\?([0-9]+)$"
const LOCAL_ID = r"^@/([0-9]+)$"
const UNKNOWN = "?"
const PATH_COMPONENT = r"^([-[:alnum:]]+|@)/([0-9]+)$"
const VAR_NAME = r"^([0-9]+|\pL\p{Xan}*)(?::((\pL\p{Xan}*)(?:=((?:[^,]|\\,)*))?(?:,(\pL\p{Xan}*)(?:=((?:[^,]|\\,)*))?)*))?$"
const METAPROP = r"(\pL\p{Xan}*)(?:=((?:[^,]|\\,)*))?(,|$)"

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

isemptyid(id) = isa(id, ID) && id.number == 0

function parsemetadata(meta::AbstractString, original_meta = nothing)
    metadata = Dict{Symbol, AbstractString}()
    if original_meta !== nothing
        merge!(metadata, original_meta)
    end
    while meta !== ""
        (m = match(METAPROP, meta)) === nothing && throw("Bad metaproperty format: $(meta)")
        metadata[Symbol(m[1])] = m[2]
        if length(meta) > length(m.match)
            meta[length(m.match) + 1] != ',' && throw("Bad metaproperty format: $(meta)")
            meta = meta[length(m.match) + 1:end]
        else
            break
        end
    end
    @debug("USING METADATA: $(repr(metadata))")
    metadata
end

function Var(cmd::JusCmd; id::ID, name = Symbol(""), args...)
    args = (;args...)
    if isa(name, Union{Symbol, AbstractString}) && string(name) != ""
        m = match(VAR_NAME, string(name))
        if m !== nothing && m[2] !== nothing
            name = m[1]
            metadata = parsemetadata(m[2], haskey(args, :metadata) ? args.metadata : Dict())
            args = (;args..., metadata, name)
        end
    end
    if isa(name, AbstractString)
        name = Symbol(name)
    end
    ns = cmd.config.namespaces[id.namespace]
    id.number == 0 && (id = ID(id.namespace, ns.curid += 1))
    ns.curid = max(ns.curid, id.number)
    v = cmd.config[id] = Var(; args..., id, name = isa(name, Number) ? Symbol("") : name)
    v.parent !== EMPTYID && name != Symbol("") && (cmd.config[v.parent][name] = v)
    v.parent !== EMPTYID && name != Symbol("") && @debug("ADDED CHILD OF $(v.parent) NAMED $(name) = $(cmd.config[v.parent][name])")
    !isempty(v.metadata) && @debug("VAR $(v.name) metadata: $(v.metadata)")
    for (mk, mv) in v.metadata
        vcmd = VarCommand(cmd, :metadata, (mk,), v, creating = true)
        m = methods(handle, (typeof(v.value), typeof(vcmd)))
        if length(m) === 1 && m[1].sig !== Tuple{typeof(Main.Jus.handle), Any, Any}
            @debug("CALLING HANDLER FOR $(vcmd)")
            route(v.value, vcmd)
        elseif length(m) > 1
            throw("More than one possible handler for $(vcmd)")
        else
            @debug("No handler for $(vcmd)")
        end
    end
    route(v.value, VarCommand(cmd, :create, (), v, creating = true))
    v
end

function addvar(cmd::JusCmd, parent::ID, name::Union{Integer, Symbol}, id::ID, value, metadata::Dict{Symbol, AbstractString})
    realname = name == Symbol("") && parent != EMPTYID ? length(cmd.config[parent]) + 1 : name
    v = Var(cmd; id, name = realname, value, metadata, parent)
    cmd.config.changes[v.id] = Dict(
        :set => true,
        :metadata => Set(keys(v.metadata))
    )
    v
end
