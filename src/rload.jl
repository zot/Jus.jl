using Revise
Revise.async_steal_repl_backend()
map(f-> Revise.track(Jus, f),
    ["types.jl", "protocol.jl", "vars.jl", "commands.jl", "Jus.jl", "server.jl", "example1.jl"])
includet("load.jl")
