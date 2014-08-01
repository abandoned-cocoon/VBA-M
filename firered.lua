require "bkpt"
require "stack"
snapshot = require "snapshot"

local gpu_alloc_log_cached = 0

local log__battle_dp15 = 1
local log__gpu_transfers = 0
local log__gpu_allocations = 0
local log__script_exec = 0
local log__task = 0

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

table.insert(snapshot.plugins, function()
	if task_current_index == 0xFF then return {} end
	return {string.format("%08x during execution of task #%d: %08x", task_enter_sp, task_current_index, task_current_func)}
end)

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

bkpts:enable()
