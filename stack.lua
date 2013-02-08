local bit = require "bit"

stack_ns = {}
stack_ns.over = {}

function stacktrace()
    local sp = gba.reg(13)
    local trace = {gba.ip(), gba.reg(14)-1}
    while sp < 0x03007FA0 do
        local ptr = gba.mem32(sp)-1
        if 0x08000000 <= ptr then 
            local op = gba.mem16(ptr-2)
            if bit.band(op, 0xE800) == 0xE800 then
                table.insert(trace, ptr)
            end
        end
        sp = sp+4
    end
    return trace
end

function printtrace()
    local trace = stacktrace()
    for i, k in ipairs(trace) do
        local n = stack_ns.over[k]
        if n == nil then
            io.write(string.format(" %08x", k))
        else
            io.write(" "..n)
        end
    end
    io.write("\n")
end

return stack_ns
