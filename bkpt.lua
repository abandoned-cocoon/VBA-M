bkpts = bkpts or {["active"]={}, ["inactive"]={}, ["callback"]={}}

-- function new(proto)
--     n = {}
--     setmetatable(n, { ["__index"]=proto })
--     return n
-- do

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
    bkpts:disable()
    r = bkpts.callback[gba.ip()]
    if r == nil then
        repl:run()
    else
        r()
    end
    gba.emulate(1)
    bkpts:enable()
end

function watchpoint_cb(a, b, c, d, e)
    print("a:", a)
    print("b:", b)
    print("c:", c)
    print("d:", d)
    print("e:", e)
    return false
end
