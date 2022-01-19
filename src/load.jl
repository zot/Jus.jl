module Jus

using JSON3
using JSON3: StructTypes
using Base.Filesystem
using Match
using HTTP
using Generators
using Pkg
using DefaultApplication

import Base.@kwdef, Base.Iterators.flatten

include("types.jl")
include("vars.jl")
include("Jus.jl")
include("server.jl")

end
