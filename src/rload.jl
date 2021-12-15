using Revise
Revise.async_steal_repl_backend()
includet("load.jl")
map(f-> Revise.track(Jus, f),
    ["types.jl", "protocol.jl", "vars.jl", "commands.jl", "Jus.jl", "server.jl", "example1.jl"])
