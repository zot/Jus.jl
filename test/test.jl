import Base.@kwdef
include("../src/load.jl")
using .Jus
using HTTP
using Logging

config = Config()
config.namespace = "Test"

@kwdef mutable struct FakeWS
    isopen = true
    input::Channel = Channel(10)
    output::Channel = Channel(10)
end

other(ws::FakeWS) = FakeWS(input = ws.output, output = ws.input)

Base.isopen(ws::FakeWS) = ws.isopen
Base.eof(ws::FakeWS) = !isopen(ws)

#Base.write(ws::FakeWS, data) = put!(ws.output, data)
Base.write(ws::FakeWS, data) = (@debug("FAKE WRITING: $(repr(data))"); put!(ws.output, data))

Base.flush(ws::FakeWS) = nothing

#Base.readavailable(com::FakeWS) = take!(com.input)
Base.readavailable(com::FakeWS) = (str = take!(com.input); @debug("FAKE READING: $(repr(str))"); str)

function Base.close(com::FakeWS)
    com.isopen = false
    close(com.input, HTTP.WebSockets.WebSocketError(1005, "Closed"))
    close(com.output, HTTP.WebSockets.WebSocketError(1005, "Closed"))
end

function setup(namespace::AbstractString)
    c = Config()
    ws = FakeWS()
    other_ws = other(ws)
    t = @task try
        serve(c, ws)
    catch err
        println("@@@@@@@@\n@@@@@@@@ CAUGHT SERVER ERROR")
        println(typeof(err))
        println(!isopen(other_ws))
        if err isa HTTP.WebSockets.WebSocketError && !isopen(other_ws)
            println("@@@@@@@@\n@@@@@@@@ OK CLOSE")
        else
            @error join(["$(err)", stacktrace(catch_backtrace())...], "\n")
        end
    end
    bind(ws.input, t)
    bind(ws.output, t)
    schedule(t)
    output(other_ws, (namespace, secret = ""))
    c, t, other_ws
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
        @debug("ABSTRACT DICTS: $((;expc...) isa AbstractDict) $(input isa AbstractDict)")
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

function assert_equal(expc, result)
    if !test_equal(expc, result)
        throw(join(["Error, expected <", JSON3.write(expc), "> but got <", JSON3.write(result), ">\n"]))
    else
        @debug("- - @@ - -> GOT EXPECTED RESULT <$(expc)>")
    end
end

assert_type(var::Var, type) = assert_type(var.value, type)
function assert_type(value, type)
    assert(value isa type, "Expected $(value) to be a $(type) but it is a $(typeof(value))")
end

assert(condition::Bool, msg, success = "") = assert(condition, ()-> msg, ()-> success)
function assert(condition::Bool, msg::Function, success::Function = ()-> "")
    if !condition
        throw(msg())
    else
        s = success()
        s != "" && @debug(s)
    end
end

function test1()
    config, task, ws = setup("TEST")
    var(n) = config[ID("TEST", n)]
    output(ws, ["set", "-c", "@/0:create=PersonApp", "true"])
    expect(ws, result = ["@/1"])
    assert_type(var(1), PersonApp)
    app = var(1).value
    output(ws, ["observe", "@/1"])
    expect(ws, update = Dict(Symbol("@/1") => (; set = (; ref = 1), metadata = (; create = "PersonApp"))))
    output(ws, ["set", "-c", "@/1 new_person:path=new_person(),access=action", "true"])
    expect(ws, result = ["@/2"])
    expect(ws, update = Dict(Symbol("@/2") =>
        (;
         set = "true",
         metadata = (;
                     path = "new_person()",
                     access = "action",
                     ),
         )))
    output(ws, ["set", "-c", "@/1 namefield:path=namefield()", "true"])
    expect(ws, result = ["@/3"])
    expect(ws, update = Dict(
        Symbol("@/3") =>
            (;
             set = "true",
             metadata = (; path = "namefield()"),
             ),
    ))
    output(ws, ["set", "@/3", ""])
    expect(ws, result = [])
    expect(ws, update = Dict(
        Symbol("@/3") =>
            (;
             set = "true",
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
    output(ws, ["set", "-c", "@/1 address:path=addressfield", "true"])
    expect(ws, result = ["@/4"])
    expect(ws, update = Dict(
        Symbol("@/4") =>
            (;
             set = "true",
             metadata = (; path = "addressfield"),
             ),
    ))
    output(ws, ["set", "@/4", "1234 Elm St"])
    expect(ws, result = [])
    println("APP: $(app)")
    expect(ws, update = Dict(
        Symbol("@/4") =>
            (;
             set = "1234 Elm St",
             ),
    ))
    output(ws, ["set", "@/3", "fred"])
    expect(ws, result = [])
    expect(ws, update = Dict(
        Symbol("@/3") =>
            (;
             set = "fred",
             ),
    ))
    close(ws)
    fetch(task)
end

function run_tests(func...)
    io = IOBuffer()
    with_logger(SimpleLogger(io)) do
        for f in [test1]
            try
                f()
                print(".")
            catch err
                print("E")
                @error join(["$(err)", stacktrace(catch_backtrace())...], "\n")
            end
        end
    end
    println()
    err = String(take!(io))
    isempty(err) && @debug("SUCCESS")
    isempty(err) && exit(0)
    println(err)
    exit(1)
end

run_tests(test1)
