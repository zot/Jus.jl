export addvar, within, allvars, REF, UNKNOWN, PATH_COMPONENT, isemptyid, json

const REF = r"^\?([0-9]+)$"
const LOCAL_ID = r"^@/([0-9]+)$"
const UNKNOWN = "?"
const PATH_COMPONENT = r"^([-[:alnum:]]+|@)/([0-9]+)$"
const VAR_NAME = r"^([0-9]+|\pL\p{Xan}*)(?::((\pL\p{Xan}*)(?:=((?:[^,]|\\,)*))?(?:,(\pL\p{Xan}*)(?:=((?:[^,]|\\,)*))?)*))?$"
const METAPROP = r"(\pL\p{Xan}*)(?:=((?:[^,]|\\,)*))?(,|$)"

json(cmd::JusCmd, id::ID) = "$(id.namespace === cmd.namespace ? "@" : id.namespace)/$(id.number)"
json(id::ID) = "$(id.namespace)/$(id.number)"

Base.haskey(cfg::Config, id::ID) = haskey(cfg.vars, id)
Base.getindex(cfg::Config, id::ID) = cfg.vars[id]
Base.setindex!(cfg::Config, var::Var, id::ID) = cfg.vars[id] = var

Base.haskey(var::Var, name::AbstractString) = haskey(var.namedchildren, name)
function Base.getindex(var::Var, name::AbstractString)
    get(var.namedchildren, name, ()-> throw("No variable for name $(name)"))
end
Base.setindex!(var::Var, value::Var, name::AbstractString) = var.namedchildren[name] = value
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

function within(cfg::Config, var::Var, ids::Set{ID})
    (var.id in ids) || (var.parent != EMPTYID && within(cfg, cfg[var.parent], ids))
end

Base.get(cfg::Config, key::ID, default) = get(cfg.vars, key, default)

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
    println("USING METADATA: ", metadata)
    metadata
end

function Var(cmd::JusCmd; id::ID, name = "", args...)
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
    v = cmd.config[id] = Var(; args..., id, name)
    for (mk, mv) in v.metadata
        vcmd = VarCommand(cmd, :metadata, (mk,), v)
        m = methods(handle, (typeof(v.value), typeof(vcmd)))
        if length(m) === 1 && m[1].sig !== Tuple{typeof(Main.Jus.handle), Any, Any}
            println("CALLING HANDLER FOR $(vcmd)")
            route(v.value, vcmd)
        elseif length(m) > 1
            throw("More than one possible handler for $(vcmd)")
        else
            println("No handler for $(vcmd)")
        end
    end
    route(v.value, VarCommand(cmd, :create, (), v))
    v
end

function newvar(cmd::JusCmd, var::Var)
    var.parent !== EMPTYID && var.name != "" && (cmd.config[parent][var.name] = var)
    changes = get(()-> Set{Tuple{Symbol, Any}}(), cmd.config.changes, var)
    push!(changes, (:set, keys(var.metadata)))
    var
end

function addvar(cmd::JusCmd, parent::ID, name::Integer, id::ID, value::AbstractString, metadata::Dict{Symbol, AbstractString})
    v = Var(cmd; id, name, value, metadata, parent)
    newvar(cmd, v)
end

function addvar(cmd::JusCmd, parent::ID, name::AbstractString, id::ID, value::AbstractString, metadata::Dict{Symbol, AbstractString})
    name == "" && parent != EMPTYID && return addvar(cmd, parent, length(cmd.config[parent]) + 1, id, value, metadata)
    v = Var(cmd; id, name, value, metadata, parent)
    newvar(cmd, v)
end
