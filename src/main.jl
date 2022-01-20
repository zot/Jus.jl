Base.exit_on_sigint(false)

try
    include("Jus.jl")

    Jus.exec(Jus.serve, ARGS)
catch err
    !(err isa InterruptException) && @warn "Error" exception=(err, catch_backtrace())
    exit(1)
end
