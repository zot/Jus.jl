module Jus

using JSON3
using JSON3: StructTypes
using Base.Filesystem
using Match
using HTTP
using Generators

import Base.@kwdef
import Base.Iterators.flatten

include("types.jl")
include("vars.jl")
include("Jus.jl")
include("server.jl")

end

include("example1.jl")
