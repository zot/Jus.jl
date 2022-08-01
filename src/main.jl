Base.exit_on_sigint(false)

using Comonicon

include("Jus.jl")

import Jus.Astr, Jus.Config

const ARGS = Base.ARGS

"""
Run Jus

# Args

- `namespace`: Jus namespace

# Options

- `-s, --server=<ADDR>`: [IP:]PORT
"""
@main function exec(namespace::Astr; interactive::Bool = false, exec::String = "",
                    d1::String = "", d2::String = "", verbose::Bool = false,
                    x::String = "", client::String = "", server::String = "",
                    browse::String = "", output::String = "")
    try
        output != "" && mkpath(output)
        config = Jus.Config()
        config.output_dir = output
        config.serverfunc = Jus.serve
        config.namespace.name = namespace
        config.verbose = verbose
        exec != "" && Main.eval(Meta.parse(exec))
        d1 != "" && Jus.add_file_dir(config, d1)
        d2 != "" && Jus.add_file_dir(config, d2)
        x != "" && (config.namespace.secret = x)
        client != "" && Jus.parseAddr(config, client)
        if server != ""
            Jus.parseAddr(config, server)
            config.server = true
        end
        #while i <= length(args)
        #    arg = args[i]
        #    @match args[i] begin
        #        "-i" => (interactive = true)
        #        "-e" => Main.eval(Meta.parse(args[i += 1]))
        #        "-d" => add_file_dir(args[i += 1])
        #        "-v" => (config.verbose = true)
        #        "-x" => (config.namespace.secret = args[i += 1])
        #        "-c" => parseAddr(config, args[i += 1])
        #        "-b" => (browse = args[i += 1])
        #        "-s" => begin
        #            parseAddr(config, args[i += 1])
        #            config.server = true
        #        end
        #        unknown => begin
        #            @debug("MATCHED DEFAULT: $(args[i:end])")
        #            push!(config.args, args[i:end]...)
        #            i = length(args)
        #            break
        #        end
        #    end
        #    i += 1
        #end
        interactive && return
        atexit(()-> Jus.shutdown(config))
        config.server && browse != "" && Jus.present(config, browse)
        (config.server ? Jus.server : Jus.client)(config)
        config
    catch err
        !(err isa InterruptException) && @warn "Error" exception=(err, catch_backtrace())
        exit(1)
    end
end
