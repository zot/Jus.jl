using HTTP

import Base.@kwdef, Base.WeakRef
import JSON3.StructTypes

export Config, State, UnknownVariable, ID, Var, JusCmd, ROOT, EMPTYID, Namespace, Connection, VarCommand
export parent, cancel, arg
export PASS, FAIL, SUBSTITUTE

const MODULEDIR = pathof(parentmodule(eval))
const PKGDIR = MODULEDIR !== nothing ? dirname(dirname(MODULEDIR)) : pwd()
const PASS = :pass
const FAIL = :fail
const SUBSTITUTE = :substitute

struct UnknownVariable <:Exception
    name
end

@kwdef mutable struct State
    servers::Dict{String, @NamedTuple{host::String,port::UInt16,pid::Int32}} = Dict()
end

StructTypes.StructType(::Type{State}) = StructTypes.Mutable()

@kwdef struct ID
    namespace::String
    number::UInt = 0
end

Base.show(io::IO, id::ID) = print(io, "$(id.namespace)/$(id.number)")

const ROOT = ID("ROOT", UInt(0))
const EMPTYID = ID("", UInt(0))

"""
    Var

A variable:
    id: the variable's unique ID, used in the protocol
    name: the variable's human-readable name, used in UIs and diagnostics
"""
@kwdef mutable struct Var
    parent::ID = EMPTYID
    id::ID = ROOT # root is just the default value and will most likely be changed
    name::Union{Symbol, Integer} = ""
    value = nothing
    metadata::Dict{Symbol, AbstractString} = Dict()
    namedchildren::Dict{Symbol, Var} = Dict()
    indexedchildren::Vector{Var} = []
    properties::Dict{Symbol, Any} = Dict() # misc properties of any type
    active = true # controls refreshing
    internal_value = nothing
    readable::Bool = true
    writeable::Bool = true
    action::Bool = false
    path::Vector{Union{Number, Symbol, Function}} = []
    json_value = nothing
    refresh_exception = nothing
    error_count = 0
    value_conversion = identity
end

@kwdef mutable struct Namespace
    name::String
    secret::String
    curid::Int = 0
end

@kwdef mutable struct Connection
    ws #::HTTP.WebSockets.WebSocket
    namespace::String
    observing::Set{ID} = Set()
    stop::Channel = Channel(1)
    apps::Dict = Dict()
    oid2data::Dict{Int, WeakRef} = Dict()
    data2oid::WeakKeyDict{Any, Int} = WeakKeyDict()
    nextOid::Int = 0
    refresh_queued::Bool = false
    pending_result::NamedTuple = (;)
    vars::Set{Var} = Set{Var}()
    requests::Set = Set()
    sequence::Int = 1
end

"""
    Config

Singleton for this program's state.
    namespace:      this program's unique namespace, assigned by the server
    nextId:         the next available id in this namespace
    vars:           all known variables
    changes:        pending changes to the state to be broadcast to observers
    templates_dir:  directory for looking up viewdef generation templates
    output_dir:     optional path of directory in which to place generated viewdefs
"""
@kwdef mutable struct Config
    namespace::Namespace = Namespace("ROOT", "", 0)
    vars::Dict{ID, Var} = Dict{ID, Var}()
    host::IPv4 = ip"0.0.0.0"
    hostname::AbstractString = "localhost"
    port::UInt16 = UInt16(8181)
    server::Bool = false
    diag::Bool = false
    proxy::Bool = false
    verbose::Bool = false
    cmd::AbstractString = ""
    args::Vector{<: AbstractString} = String[]
    client::AbstractString = ""
    nextmsg::Int = 0
    namespaces::Dict{AbstractString, Namespace} = Dict(namespace.name => namespace)
    serverfunc::Function = serve
    connections::Dict{Any, Connection} = Dict{Any, Connection}()
    changes::Dict{ID, Dict{Symbol, Any}} = Dict{ID, Dict{Symbol, Any}}()
    init_connection::Function = con-> ()
    output_dir::AbstractString = ""
    templates_dir::AbstractString = joinpath(PKGDIR, "templates")
    templates::Dict{Tuple{Symbol, Symbol}, AbstractString} =
        Dict{Tuple{Symbol, Symbol}, AbstractString}()
end

@kwdef mutable struct JusCmd{NAME}
    config::Config
    ws #::HTTP.WebSockets.WebSocket
    namespace::AbstractString
    args::Vector
    cancel::Bool = false
    JusCmd(config, ws, namespace, args::Vector) =
        new{Symbol(lowercase(args[1]))}(config, ws, namespace, args[2:end], false)
end
JusCmd(cfg::Config, con::Connection, name::AbstractString) = JusCmd(cfg, con, [name])
JusCmd(cfg::Config, con::Connection, args::Vector) = JusCmd(cfg, con.ws, con.namespace, args)

connection(cmd::JusCmd) = get(cmd.config.connections, cmd.ws, nothing)

ID(cmd::JusCmd{T}) where T = ID(cmd.namespace, UInt(0))

"""
    VarCommand{Cmd, Path}

Handlers should return a command, either the given one or a new one.
Handlers can alter var during processing.
Each command triggers a refresh.

COMMANDS

Set: set a variable
Get: retrieve a value for a variable
Observe: observe variables
"""
@kwdef mutable struct VarCommand{Cmd, Arg}
    var::Var
    config::Config
    connection::Union{Connection, Nothing}
    cancel::Bool = false
    creating::Bool = false
    arg = nothing
    data = nothing
    path = ()
end

has_path(var::Var) = var.parent != EMPTYID && !isempty(var.path)
internal_value(var::Var) = has_path(var) ? var.internal_value : var.value
parent_value(cfg::Config, var::Var) = var.parent == EMPTYID ? nothing : internal_value(cfg[var.parent])

function VarCommand(cmd::Symbol, path::Union{Tuple{}, Tuple{Vararg{Symbol}}}; args...)
    VarCommand{cmd, path}(; args...)
end
function VarCommand(cmd::VarCommand{Cmd, Arg}; args...) where {Cmd, Arg}
    #VarCommand{Cmd, Arg}(; cmd.var, cmd.config, cmd.connection, cmd.cancel, cmd.creating, cmd.arg, cmd.data, args...)
    VarCommand{Cmd, Arg}(cmd; args...)
end
function VarCommand{Cmd, Arg}(cmd::VarCommand; args...) where {Cmd, Arg}
    VarCommand{Cmd, Arg}(; cmd.var, cmd.config, cmd.connection, cmd.cancel, cmd.creating, cmd.arg, cmd.data, args...)
end
function VarCommand(jcmd::JusCmd, cmd::Symbol, path::Tuple{Vararg{Symbol}}, var; args...)
    VarCommand(cmd, path; var, jcmd.config, connection = connection(jcmd), args...)
end

cancel(cmd::VarCommand) = VarCommand(cmd; cancel = true)

arg(cmd::VarCommand, arg) = VarCommand(cmd; arg)

function parent_var(cmd::VarCommand)
    cmd.var.parent == EMPTYID && throw("No parent for variable $(cmd.var.id)")
    cmd.config[cmd.var.parent]
end

parent(cmd::VarCommand) = VarCommand(cmd; var = parent_var(cmd))

Base.show(io::IO, cmd::VarCommand{Cmd, Path}) where {Cmd, Path} = print(io, "VarCommand{$(repr(Cmd)), $(Path)}($(cmd.creating ? "creating" : "not creating"))")

Base.show(io::IO, var::Var) = print(io, "Var($(var.parent), $(var.id), $(var.name), $(var.path))")

struct NoCause <: Exception end

"""
    CmdException

Error while executing a command

- type: Symbol for the type of exception:
  - path: error using a path
  - not_writeable: variable is not writeable
  - not_readable: variable is not readable
  - refresh: error while refreshing
  - program: error in program
- cmd: the command that caused the problem
- msg: description of the problem
- cause: cause of the problem (if any)
"""
struct CmdException{T} <: Exception
    type::Symbol
    cmd::VarCommand
    msg::AbstractString
    cause::Exception
    CmdException(type, cmd, msg, cause = NoCause()) = new{type}(type, cmd, msg, cause)
end
