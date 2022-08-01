using Jus, Jus.Shell

# warm up
mutable struct Warmup
    x::Int
end

w = Warmup(4)
Shell.inspect(w)
