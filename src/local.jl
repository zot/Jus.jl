# support for single-process Jus apps, where the program is a client of itself

@kwdef struct ClientVar
    config
    id
    value
    metadata
end

"""
    local_server(namespace)

Start a server running in a new task.
Returns (config::Config, task::Task, ws::FakeWS)
"""
function local_server(namespace::AbstractString)
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

