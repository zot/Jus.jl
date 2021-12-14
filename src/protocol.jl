#     Protocol
# 
# [ID, CMD, ARG...]

function send(config::Config, cmd::Vector)
    c = Channel(1)
    insert!(cmd, 0, config.nextmsg)
    config.pending[config.nextmsg] = c
    config.nextmsg += 1
    @async begin
        write(config.ws, JSON3.write(data))
        flush(config.ws)
        result = JSON3.read(readavailable(config.ws)) # read one message
        put!(c, result)
    end
    take!(c)
end
