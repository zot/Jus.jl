import Base.@kwdef
include("../src/load.jl")
using .Jus
using HTTP

config = Config()
config.namespace = "Test"

@kwdef struct FakeWS
    input::Channel = Channel(10)
    output::Channel = Channel(10)
end

other(ws::FakeWS) = FakeWS(input = ws.output, output = ws.input)

Base.isopen(ws::FakeWS) = isopen(ws.input)
Base.eof(ws::FakeWS) = !isopen(ws)

function setup(namespace::AbstractString)
    c = Config()
    ws = FakeWS()
    t = @task serve(c, ws)
    bind(ws.input, t)
    bind(ws.output, t)
    schedule(t)
    other_ws = other(ws)
    output(other_ws, (namespace, secret = ""))
    t, other_ws
end

#Base.write(ws::FakeWS, data) = put!(ws.output, data)
Base.write(ws::FakeWS, data) = (@debug("FAKE WRITING: $(repr(data))"); put!(ws.output, data))

Base.flush(ws::FakeWS) = nothing

#Base.readavailable(com::FakeWS) = take!(com.input)
Base.readavailable(com::FakeWS) = (str = take!(com.input); @debug("FAKE READING: $(repr(str))"); str)

function Base.close(com::FakeWS)
    close(com.input, HTTP.WebSockets.WebSocketError(1005, "Closed"))
    close(com.output, HTTP.WebSockets.WebSocketError(1005, "Closed"))
end

test_equal(expc, actual) = expc == actual
test_equal(expc::Union{AbstractDict, NamedTuple}, actual::AbstractDict) = test_equal_parts(expc, actual)
test_equal(expc::AbstractArray, actual::AbstractArray) = test_equal_parts(expc, actual)
function test_equal_parts(expc, actual)
    if Set(keys(expc)) != Set(keys(actual))
        @debug("DIFFERENT KEYS, $(keys(expc)) != $(keys(actual))")
        @debug("DIFFERENT KEYS for $(expc) and $(actual)")
    end
    Set(keys(expc)) != Set(keys(actual)) && return false
    for k in keys(expc)
        !test_equal(expc[k], actual[k]) && @debug("DIFFERENT VALUES")
        !test_equal(expc[k], actual[k]) && return false
    end
    true
end

expect(ws; expc...) = expect(ws, (; expc...)) do input
    @debug("COMPARING $(typeof((;expc...))) AND $(typeof(input))")
    result = test_equal((;expc...), input)
    if !result
        @debug("COMPARING $(repr((;expc...))) with $(repr(input))")
        @debug("ABSTRACT DICTS: $(isa((;expc...), AbstractDict)) $(isa(input, AbstractDict))")
        @debug("JSON: $(JSON3.write((;expc...))) == $(JSON3.write(input))")
    end
    result
end

function expect(test::Function, ws, expc)
    result = input(ws)
    @debug("@@@ @@@ TESTING $(repr(result))")
    if !test(result)
        throw(join(["Error, expected <", JSON3.write(expc), "> but got <", JSON3.write(result), ">\n"]))
    else
        @debug("- - @@ - -> GOT EXPECTED RESULT <$(expc)>")
    end
end

function test1()
    task, ws = setup("TEST")
    output(ws, ["set", "-c", "@/0:create=PersonApp", "true"])
    expect(ws, result = ["@/1"])
    output(ws, ["observe", "@/1"])
    expect(ws, update = Dict(Symbol("@/1") => (; set = (; ref = 1), metadata = (; create = "PersonApp"))))
    output(ws, ["set", "-c", "@/1 new_person:path=new_person", "true"])
    expect(ws, result = ["@/2"])
    expect(ws, update = Dict(Symbol("@/2") => (; set = "true", metadata = (; path = "new_person"))))
    output(ws, ["set", "-c", "@/1 namefield:path=namefield", "true"])
    expect(ws, result = ["@/3"])
    expect(ws, update = Dict(
        Symbol("@/3") =>
            (;
             set = "true",
             metadata = (; path = "namefield"),
             ),
        Symbol("@/2") =>
            (;
             metadata =
                 (;
                  note = "A new person needs a name",
                  enabled = "false",
                  )
             )
    ))
    close(ws)
    fetch(task)
end

function run(f::Function)
    try
        f()
        print(".")
    catch err
        print("E")
    end
end

for f in [test1]
    run(f)
end
println()
@debug("SUCCESS")
