bkpts = bkpts or {["active"]={}, ["inactive"]={}, ["callback"]={}}
watch = watch or {}

function bkpts:enable()
    for id, loc in pairs(self.inactive) do
        self.active[loc] = gba.mem16(loc)
        gba.mem16(loc, 0xbe00)
    end
    self.inactive = {}
end

function bkpts:disable()
    for loc, orig in pairs(self.active) do
        gba.mem16(loc, orig)
        table.insert(self.inactive, loc)
    end
    self.active = {}
end

function breakpoint_cb()
    -- called by the emulator
    loc = gba.ip()
    r = bkpts.callback[loc]
    if r == nil then
        print(string.format("breakpoint @ %08x", loc))
        bkpts:disable()
        repl:run()
        gba.emulate(1)
        bkpts:enable()
    else
        r()
        gba.mem16(loc, bkpts.active[loc])
        gba.emulate(1)
        gba.mem16(loc, 0xbe00)
    end
end

function bkpts:add(addr, callback)
    table.insert(self.inactive, addr)
    self.callback[addr] = callback
end

function add_tracepoint(addr, msg, reg)
    if reg == nil then
        error("no reg specified")
    end
    function traceprint()
        print(string.format("%s %08x", msg, gba.reg(reg)))
        printtrace()
    end
    table.insert(bkpts.inactive, addr)
    bkpts.callback[addr] = traceprint
end

function watchpoint_cb(a, b, c, d)
    for id, watch in pairs(watch) do
        if watch.start <= a and a < watch.stop then
            watch:trigger(a-watch.start, b, c)
        end
    end
end
