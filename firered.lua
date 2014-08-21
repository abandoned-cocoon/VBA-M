require "bkpt"
require "stack"
bit = require "bit"
snapshot = require "snapshot"

local gpu_alloc_log_cached = 0

local log__battle_dp15 = 0
local log__gpu_transfers = 0
local log__gpu_allocations = 0
local log__script_exec = 0
local log__task = 0

local freespace = 0x0871B1C8

local malloc = function(bytes)
	freespace = freespace + bytes
	return freespace - bytes
end

local h__battle_dp15_trace = function ()
	if log__battle_dp15 == 0 then return end

	local cursor = gba.reg(0)
	local instruction = gba.mem8(cursor)
	print (string.format("%04d battle/dp15/trace %08x: %02x", snapshot:make(), cursor, instruction))
end

local pal_slot_name = function (n)
	if n == 0xFF then
		return "XX"
	else
		return string.format("%02d", n)
	end
end

local h__gpu_pal_allocator_reset = function ()
	if log__gpu_allocations == 0 then return end

	print (string.format("%04d gpu/alloc/pal RESET", snapshot:make()))
end

local h__gpu_pal_alloc_and_load = function ()
	if log__gpu_allocations == 0 then return end

	local r5 = gba.reg(5)

	local comment
	if gba.reg(15) < 0x08008940 then
		if gpu_alloc_log_cached then
			comment = "(cached)"
		else
			return
		end
	else
		if gpu_alloc_log_cached then
			comment = "(first load)"
		else
			comment = ""
		end
	end

	print (string.format("%04d gpu/alloc/pal %s: [addr=%08x/tag=%04x] %s", snapshot:make(),
		pal_slot_name(gba.reg(4)), gba.mem32(r5), gba.mem16(r5+4), comment))
end

local h__gpu_pal_alloc_new = function ()
	if log__gpu_allocations == 0 then return end

	print (string.format("%04d gpu/alloc/pal %s: [tag=%04x]", snapshot:make(),
		pal_slot_name(gba.reg(2)), gba.reg(4)))
end

local h__gpu_pal_free_by_tag = function ()
	if log__gpu_allocations == 0 then return end

	print (string.format("%04d gpu/alloc/pal ??: [tag=%04x] -> [tag=UNUSED]", snapshot:make(), gba.reg(0)))
end

local script_current_op_info = function (env)
	local cmd = gba.mem8(gba.mem32(env+8))
	local impl = gba.mem32(gba.mem32(env+0x5C)+cmd*4)
	return string.format("%02x (%08x)", cmd, impl)
end

local script_stack_line = function (env)
	local line = ""
	local n = gba.mem8(env)
	for i=0, n-1 do
		line = line .. string.format("%08x ", gba.mem32(env+0xC+i*4))
	end
	return line .. string.format("%08x", gba.mem32(env+8))
end


local h__script_main_handler = function ()
	if log__script_exec == 0 then return end
	local env = gba.reg(4)
	local mode = gba.mem8(env+1)
	print (string.format("---- script/exec op=%s stack=[%s]", --snapshot:make(),
		script_current_op_info(env), script_stack_line(env)))
end

local h__gpu_pal_apply = function ()
	if log__gpu_transfers == 0 then return end

	print (string.format("%04d gpu/pal/apply src=%08x dst=%04x len=%04x", snapshot:make(),
		gba.reg(0), gba.reg(1), gba.reg(2)))
end

local h__task_add = function()
	if log__task == 0 then return end

	print(string.format("%04d task/add [#%02x] func=%08x prio=%02x", snapshot:make(),
		gba.reg(6), gba.reg(2), gba.reg(1)))
end

local h__task_del = function()
	if log__task == 0 then return end

	print(string.format("%04d task/del [#%02x]", snapshot:make(),
		gba.reg(0)))
end

local task_current_index = 0xFF
local task_current_func = 0xFF
local task_enter_sp = 0

local h__task_exec = function()
	task_current_index = gba.reg(0)
	task_current_func  = gba.mem32(gba.reg(4))
	task_enter_sp = gba.reg(13)
end

local p__walkrun = 0x02037078
local p__npc_states = 0x02036E38

local player_npc = function()
	local npcid = gba.mem8(p__walkrun+5)
	return p__npc_states + 0x24 * npcid
end

local h__navigation_direction_sidechannel_in = function()
	gba.mem8(player_npc()+0x23, gba.mem8(gba.reg(6)+2))
end

local gen_h__navigation_direction_sidechannel_out = function(reg1, reg2)
	return function()
		local npc = gba.reg(reg2)
		if npc == player_npc() then
			local override = gba.mem8(npc+0x23)
			if override > 0 then
				gba.reg(reg1, override)
			end
		end
	end
end

h__navigation_direction_sidechannel_out   = gen_h__navigation_direction_sidechannel_out(2, 0)
h__navigation_direction_sidechannel_out_0 = gen_h__navigation_direction_sidechannel_out(0, 4)

local t__navigation_diagonal = function()
	local table_copy_and_extend = function(ptr, padding)
		local from = gba.mem32(ptr)
		local to = malloc(32)
		gba.mem32(ptr, to)
		gba.mem32(to+ 0, gba.mem32(from+ 0))
		gba.mem32(to+ 4, gba.mem32(from+ 4))
		gba.mem32(to+ 8, gba.mem32(from+ 8))
		gba.mem32(to+12, gba.mem32(from+12))
		gba.mem32(to+16, padding)
		gba.mem32(to+20, padding)
		gba.mem32(to+24, padding)
		gba.mem32(to+28, padding)
	end
	local ret0 = 0x0805A0ED
	table_copy_and_extend(0x080638F4, ret0)
	table_copy_and_extend(0x080638F8, ret0)
	table_copy_and_extend(0x0805C4F0, ret0)
end

local h__navigation_diagonal = function()
	local directionbits = bit.band(15, bit.rshift(gba.mem8(gba.reg(4)), 4))
	local directioncodes = {0, 4, 3, 0,
	                        2, 8, 7, 2,
	                        1, 6, 5, 1,
	                        0, 4, 3, 0}
	local directioncode = directioncodes[directionbits+1]
	gba.mem8(gba.reg(5)+2, directioncode)
	gba.reg(15, 0x806CA3E)
end

local h__call_by_verify = function()
	local regnum = (gba.ip()-0x081E3BA8) / 4
	local target = gba.reg(regnum)
	local targetregion = bit.rshift(target, 24)
	local invalid = (targetregion ~= 0x08 and targetregion ~= 0x02 and targetregion ~= 0x03)
	if invalid then
		print(string.format("%04d bx/r%d invalid target %08x", snapshot:make(), regnum, target))
		repl:run()
	end
end

table.insert(snapshot.plugins, function()
	if task_current_index == 0xFF then return {} end
	return {string.format("%08x during execution of task #%d: %08x", task_enter_sp, task_current_index, task_current_func)}
end)

patch_all = function()
	t__navigation_diagonal()
end

bkpts:add(0x080C70D0, h__battle_dp15_trace)

bkpts:add(0x080088F0, h__gpu_pal_allocator_reset)
bkpts:add(0x0800893A, h__gpu_pal_alloc_and_load)
bkpts:add(0x08008948, h__gpu_pal_alloc_and_load)
bkpts:add(0x080089C8, h__gpu_pal_alloc_new)
bkpts:add(0x08008A30, h__gpu_pal_free_by_tag)

bkpts:add(0x08069842, h__script_main_handler)

bkpts:add(0x080703EC, h__gpu_pal_apply)

bkpts:add(0x08077436, h__task_add)
bkpts:add(0x08077508, h__task_del)
bkpts:add(0x08077590, h__task_exec)
bkpts:add(0x0807759C, h__task_exec)

bkpts:add(0x08056480, h__navigation_direction_sidechannel_in)
bkpts:add(0x080645F4, h__navigation_direction_sidechannel_out)
bkpts:add(0x08064904, h__navigation_direction_sidechannel_out)
bkpts:add(0x08064830, h__navigation_direction_sidechannel_out)
bkpts:add(0x08064BD8, h__navigation_direction_sidechannel_out)
bkpts:add(0x08064EF8, h__navigation_direction_sidechannel_out)
bkpts:add(0x080646FC, h__navigation_direction_sidechannel_out)
bkpts:add(0x08063440, h__navigation_direction_sidechannel_out_0)
bkpts:add(0x080656C4, h__navigation_direction_sidechannel_out)
bkpts:add(0x0806CA04, h__navigation_diagonal)

bkpts:add(0x081E3BA8, h__call_by_verify)
bkpts:add(0x081E3BAC, h__call_by_verify)
bkpts:add(0x081E3BB0, h__call_by_verify)
bkpts:add(0x081E3BB4, h__call_by_verify)

bkpts:add(0x081E3BB8, h__call_by_verify)
bkpts:add(0x081E3BBC, h__call_by_verify)
bkpts:add(0x081E3BC0, h__call_by_verify)
bkpts:add(0x081E3BC4, h__call_by_verify)

bkpts:add(0x081E3BC8, h__call_by_verify)
bkpts:add(0x081E3BCC, h__call_by_verify)
bkpts:add(0x081E3BD0, h__call_by_verify)
bkpts:add(0x081E3BD4, h__call_by_verify)

bkpts:add(0x081E3BD8, h__call_by_verify)
bkpts:add(0x081E3BDC, h__call_by_verify)
bkpts:add(0x081E3BE0, h__call_by_verify)

bkpts:enable()

patch_all()
