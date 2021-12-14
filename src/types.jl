using HTTP

import Base.@kwdef
import JSON3.StructTypes

export Config, State, UnknownVariable, ID, Var, JusCmd, ROOT, EMPTYID, Namespace, Connection, VarCommand
export PASS, FAIL, SUBSTITUTE

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

const ROOT = ID("ROOT", UInt(0))
const EMPTYID = ID("", UInt(0))

"""
    Var

A variable:
    id: the variable's unique ID, used in the protocol
    name: the variable's human-readable name, used in UIs and diagnostics
"""
@kwdef mutable struct Var
    parent::ID
    id::ID = ROOT # root is just the default value and will most likely be changed
    name::Union{Symbol, Integer} = ""
    value::String = ""
    metadata::Dict{Symbol, AbstractString} = Dict()
    namedchildren::Dict{Symbol, Var} = Dict()
    indexedchildren::Vector{Var} = []
end

@kwdef mutable struct Namespace
    name::String
    secret::String
    curid::Int = 0
end

@kwdef struct Connection
    ws::HTTP.WebSockets.WebSocket
    namespace::String
    observing::Set{ID} = Set()
    stop::Channel = Channel(1)
    apps::Dict = Dict()
    sets::Set{ID} = Set()
    deletes::Set{ID} = Set()
    metadata_sets::Set{Tuple{ID, Symbol}} = Set()
end

"""
    Config

Singleton for this program's state.
    namespace: this program's unique namespace, assigned by the server
    nextId: the next available id in this namespace
    vars: all known variables
    changes: pending changes to the state to be broadcast to observers
"""
@kwdef mutable struct Config
    namespace = ""
    vars::Dict{ID, Var} = Dict()
    host = "0.0.0.0"
    port = UInt16(8181)
    server = false
    diag = false
    proxy = false
    verbose = (args...)-> nothing
    cmd = ""
    args = String[]
    client = ""
    pending::Dict{Int, Function} = Dict()
    nextmsg = 0
    namespaces::Dict{String, Namespace} = Dict() # namespaces and their secrets
    secret::String = ""
    serverfunc = (cfg, ws)-> nothing
    connections::Dict{HTTP.WebSockets.WebSocket, Connection} = Dict()
    changes::Dict{Var, Set} = Dict()
end

@kwdef struct JusCmd{NAME}
    config::Config
    ws::HTTP.WebSockets.WebSocket
    namespace::AbstractString
    args::Vector
    JusCmd(cfg, ws, ns, args::Vector) = new{Symbol(lowercase(args[1]))}(cfg, ws, ns, args[2:end])
end

ID(cmd::JusCmd{T}) where T = ID(cmd.namespace, UInt(0))

"""
    VarCommand{Cmd, Path}

Handlers should return a value: PASS, FAIL, SUBSTITUTE.

* PASS: indicates that processing should continue
* FAIL: indicates that processing has failed and should stop
* SUBSTITUTE: indicates that processing has succeeded and should return immediately

Handlers can alter var during processing.


COMMANDS

Set: set a variable
Get: retrieve a value for a variable
"""
struct VarCommand{Cmd, Path}
    var::Var
    config::Config
    connection::Connection
    function VarCommand(cmd::Symbol, path::Tuple{Vararg{Symbol}}, var, config, con)
        new{cmd, path}(var, config, con)
    end
end

function VarCommand(jcmd::JusCmd, cmd::Symbol, path::Tuple{Vararg{Symbol}}, var)
    VarCommand(cmd, path, var, jcmd.config, jcmd.config.connections[jcmd.ws])
end

Base.show(io::IO, cmd::VarCommand{Cmd, Path}) where {Cmd, Path} = print(io, "VarCommand{$(repr(Cmd)), $(Path)}()")
