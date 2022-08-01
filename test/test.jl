import Base.@kwdef
include("../src/Jus.jl")
include("../samples/src/example1.jl")
using .Jus
using .Jus: local_server, output, input
using HTTP
using Logging
using JSON3

test_equal(expc, actual) = expc == actual
test_equal(expc::Union{AbstractDict, NamedTuple}, actual::Union{AbstractDict, NamedTuple}) =
    test_equal_parts(expc, actual)
test_equal(expc::AbstractArray, actual::AbstractArray) = test_equal_parts(expc, actual)
test_equal(expc::Union{AbstractString, Symbol}, actual::Union{AbstractString, Symbol}) =
    string(expc) == string(actual)

str_keys(d) = Dict(map(k-> string(k) => k, [keys(d)...]))

function str_keys(a, b)
    k1 = str_keys(a)
    k2 = str_keys(b)
    keys(k1) != keys(k2) && return nothing
    Dict(k => [k1[k], k2[k]] for k in keys(k1))
end

function test_equal_parts(expc, actual)
    if Set(keys(expc)) != Set(keys(actual))
        @debug "DIFFERENT KEYS, $(keys(expc)) != $(keys(actual))"
        @debug "DIFFERENT KEYS for $(expc) and $(actual)"
    end
    strk = str_keys(expc, actual)
    strk === nothing && @debug "DIFFERENT KEYS"
    strk === nothing && return false
    for k in keys(strk)
        !test_equal(expc[strk[k][1]], actual[strk[k][2]]) && @debug "DIFFERENT VALUES"
        !test_equal(expc[strk[k][1]], actual[strk[k][2]]) && return false
    end
    true
end

expect(ws; expc...) = expect(ws, (; expc...)) do input
    @debug "COMPARING $(typeof((;expc...))) AND $(typeof(input))"
    result = test_equal((;expc...), input)
    if !result
        @debug "COMPARING $(repr((;expc...))) with $(repr(input))"
        @debug "ABSTRACT DICTS: $((;expc...) isa AbstractDict) $(input isa AbstractDict)"
        @debug "JSON: $(JSON3.write((;expc...))) == $(JSON3.write(input))"
    end
    result
end

expect(ws, command, result) = expect(ws; command, result)

expect(ws, command, result, update) = expect(ws; command, result, update)

function expect(test::Function, ws, expc)
    @debug "@@@ EXPECTING $(repr(expc))"
    result = input(ws)
    #@debug "@@@ @@@ TESTING $(repr(result))"
    if !test(result)
        throw(join(["Error, expected <", JSON3.write(expc), "> but got <", JSON3.write(result), ">\n"]))
    else
        @debug "- - @@ - -> GOT EXPECTED RESULT <$(expc)>"
    end
end

function assert_equal(expc, result)
    if !test_equal(expc, result)
        throw(join(["Error, expected <", JSON3.write(expc), "> but got <", JSON3.write(result), ">\n"]))
    else
        @debug "- - @@ - -> GOT EXPECTED RESULT <$(expc)>"
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
        s != "" && @debug s
    end
end

function test1()
    server = local_server("TEST")
    config = server.config
    task = server.task
    ws = server.con
    var(n) = config[ID("TEST", n)]
    output(ws, ["set", "-c", "@/0:create=PersonApp", "true"])
    expect(ws, :set, ["@/1"])
    assert_type(var(1), PersonApp)
    app = var(1).value
    output(ws, ["observe", "@/1"])
    expect(ws, :observe, [],
           (; Symbol("@/1") => (;
                                  set = (; ref = 1),
                                  metadata = (;
                                              type = "Main.PersonApp",
                                              create = :PersonApp,
                                              )
                                  ),
              ))
    output(ws, ["set", "-c", "@/1 new_person:path=new_person(),access=action", "true"])
    expect(ws, :set, ["@/2"],
           (;
              Symbol("@/2") =>
                  (;
                   set = "true",
                   metadata = (;
                               path = "new_person()",
                               access = "action",
                               type = "Core.String"
                               ),
                   )))
    output(ws, ["set", "-c", "@/1 namefield:path=namefield()", "true"])
    expect(ws, :set, ["@/3"],
           (;
            Symbol("@/3") =>
                (;
                 set = "",
                 metadata =
                     (;
                      path = "namefield()",
                      type = "Core.String",
                      ),
                 )))
    output(ws, ["set", "@/3", ""])
    expect(ws, :set, [],
           (;
            Symbol("@/3") =>
                (;
                 set = "",
                 ),
            ))
    output(ws, ["set", "-c", "@/1 address:path=addressfield", "true"])
    expect(ws, :set, ["@/4"],
           (;
            Symbol("@/4") =>
                (;
                 set = "",
                 metadata =
                     (;
                      path = "addressfield",
                      type = "Core.String",
                      ),
                 ),
            ))
    output(ws, ["set", "@/4", "1234 Elm St"])
    expect(ws, :set, [],
           (;
            Symbol("@/4") =>
                (;
                 set = "1234 Elm St",
                 ),
            ))
    output(ws, ["set", "@/3", "fred"])
    expect(ws, :set, [],
           (;
            Symbol("@/3") =>
                (;
                 set = "fred",
                 ),
            ))
    output(ws, ["set", "-c", "@/1 people:path=people,access=r", "true"])
    expect(ws, :set, ["@/5"],
           (;
            Symbol("@/5") =>
                (;
                 set = [],
                 metadata = (;
                             path = "people",
                             access = "r",
                             type = "Core.Vector{Person}"
                             ),
                 )))
    # make a person
    output(ws, ["set", "@/2", "true"])
    expect(ws, :set, [],
           (;
            Symbol("@/5") =>
                (;
                 set = [(;ref = 2)],)
            ))
    output(ws, ["set", "@/3", "joe"])
    expect(ws, :set, [],
           (;
            Symbol("@/3") =>
                (;
                 set = "joe",
                 ),
            ))
    output(ws, ["set", "@/4", "1234 Elm St"])
    expect(ws, :set, [],
           (;
            Symbol("@/4") =>
                (;
                 set = "1234 Elm St",
                 ),
            ))
    # make a person
    output(ws, ["set", "@/2", "true"])
    expect(ws, :set, [],
           (;
            Symbol("@/5") =>
                (;
                 set = [(;ref = 2), (;ref = 3)],
                 ),
            ))
    try
        close(ws)
    catch err
        !(err isa HTTP.WebSockets.WebSocketError && lowercase(err.message) == "closed") && rethrow(err)
    end
    fetch(task)
end

function run_tests(func...)
    io = IOBuffer()
    with_logger(ConsoleLogger(stderr)) do
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
    isempty(err) && @debug "SUCCESS"
    isempty(err) && exit(0)
    while !isempty(err)
        println(err)
        err = String(take!(io))
    end
    exit(1)
end

run_tests(test1)
