module Shell
using UUIDs
using JSON3
using REPL

export inspect

import ..Jus
import ..Jus: Presenter, Config

const SHELL_HTML = read("$(dirname(@__DIR__))/html/vscode-shell.html", String)
const JUS_DIR = "$(haskey(ENV, "HOME") ? ENV["HOME"] : "/tmp")/.julia/jus"
const JUS_CONFIG = "$JUS_DIR/repl.json"

"""
    CONFIG_DEFAULTS

Default values for the Jus config.
You can set them in ~/,julia/jus/repl.json
"""
const CONFIG_DEFAULTS =
    (;
     views = "$JUS_DIR/repl",
     verbose = true,
     namespace = "REPL",
     secret = "",
     server_addr = "localhost:18080",
     extra_dirs = [],
     )

settings = CONFIG_DEFAULTS

replconfig = nothing

change_setting(; kw...) = settings = (; CONFIG_DEFAULTS..., kw...)::typeof(CONFIG_DEFAULTS)

function get_jus_settings!()
    #println("JUS CONFIG: $(JUS_CONFIG)")
    #println("JUS CONFIG: $(read(JUS_CONFIG, String))")
    config = isfile(JUS_CONFIG) ? Dict([pairs(JSON3.read(read(JUS_CONFIG, String), typeof(CONFIG_DEFAULTS)))...]) : Dict()
    global settings
    settings = (; (k => get(config, k, v) for (k, v) in pairs(settings))...)
    settings[:secret] == "" && change_setting(secret = string(uuid4()))
    mkpath(dirname(JUS_CONFIG))
    settings != config && write(JUS_CONFIG, JSON3.write(settings))
    settings
end    

function repl_line()
    replconfig === nothing && return
    Jus.refresh(replconfig; force = true)
end

function patchRepl()
    eval(:(function REPL.prepare_next(repl::LineEditREPL)
               println(REPL.terminal(repl))
               Jus.Shell.repl_line()
           end))
end

function ensure_server()
    global replconfig
    replconfig !== nothing && return replconfig
    global settings = get_jus_settings!()
    patchRepl()
    replconfig = Config()
    replconfig.output_dir = settings.views
    mkpath(replconfig.output_dir)
    #replconfig.namespace.name = settings.namespace
    replconfig.namespace.secret = settings.secret
    replconfig.verbose = settings.verbose
    Jus.parseAddr(replconfig, settings.server_addr)
    replconfig.server = true
    for dir in [settings.views, settings.extra_dirs...]
        Jus.add_file_dir(replconfig, dir)
    end
    @async try
        Jus.server(replconfig)
    catch err
        @error "Error in Jus server" exception=(err, catch_backtrace())
    end
end

function in_vscode()
    try
        eval(:(Main.VSCodeServer))
        true
    catch
        false
    end
end

function inspect(item)
    in_vscode() && return Presenter(item)
    ensure_server()
    Jus.present(replconfig, item)
end
                        
Base.showable(::MIME"juliavscode/html",::Presenter) = true
function Base.show(io::IO, ::MIME"juliavscode/html", p::Presenter)
    ensure_server()
    var = Jus.addvar(replconfig, p)
    replconfig.init_connection = con-> Jus.addvar(con, var)
    println(var)
    print("""VAR: $(var.id)""")
    print(io, replace(replace(SHELL_HTML, "<body" => """<body onload='init("$(var.id)")'"""),
                      "<head>" =>
                      """
                      <head>
                      <base href="http://$(replconfig.hostname):$(replconfig.port)">
                      """))
end
end
