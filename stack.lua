local bit = require "bit"
local snapshot = require "snapshot"

stack_ns = {}
stack_ns.over = {}

function stacktrace()
    local sp = gba.reg(13)
    local trace = {}
    trace[sp-2] = gba.ip()
    trace[sp-1] = gba.reg(14)-1
    while sp < 0x03007FA0 do
        local ptr = gba.mem32(sp)-1
        if 0x08000000 <= ptr then 
            local op = gba.mem16(ptr-2)
            if bit.band(op, 0xE800) == 0xE800 then
                trace[sp] = ptr
            end
        end
        sp = sp+4
    end
    return trace
end

local stacktrace_snapshot_plugin = function ()
    contrib = {}
    for sp, addr in pairs(stacktrace()) do
        table.insert(contrib, string.format("%08x %08x call", sp, addr))
    end
    return contrib
end

table.insert(snapshot.plugins, stacktrace_snapshot_plugin)

function printtrace()
    -- expects sorted list from stacktrace() (no longer given)
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
