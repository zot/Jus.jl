using Revise
using Pkg

Base.exit_on_sigint(false)

try
    Revise.async_steal_repl_backend()
    includet("Jus.jl")
    dir=joinpath(dirname(Pkg.project().path), "src")
    map(f-> Revise.track(Jus, joinpath(dir, f)),
        ["types.jl", "vars.jl", "Jus.jl", "server.jl"])
    Jus.exec(ARGS) do config, ws
        Revise.revise()
        Base.invokelatest(Jus.serve, config, ws)
    end
catch err
    !(err isa InterruptException) && @warn "Error" exception=(err, catch_backtrace())
    exit(1)
end
