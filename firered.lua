require "bkpt"
require "stack"
snapshot = require "snapshot"

local gpu_alloc_log_cached = 0
local gpu_alloc_pal_log = 1

local pal_slot_name = function (n)
	if n == 0xFF then
		return "XX"
	else
		return string.format("%02d", n)
	end
end

local h__gpu_pal_allocator_reset = function ()
	if gpu_alloc_pal_log == 0 then return end

	print (string.format("%04d gpu/alloc/pal RESET", snapshot:make()))
end

local h__gpu_pal_alloc_and_load = function ()
	if gpu_alloc_pal_log == 0 then return end

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
	if gpu_alloc_pal_log == 0 then return end

	print (string.format("%04d gpu/alloc/pal %s: [tag=%04x]", snapshot:make(),
		pal_slot_name(gba.reg(2)), gba.reg(4)))
end

local h__gpu_pal_free_by_tag = function ()
	if gpu_alloc_pal_log == 0 then return end

	print (string.format("%04d gpu/alloc/pal ??: [tag=%04x] -> [tag=UNUSED]", snapshot:make(), gba.reg(0)))
end

local h__gpu_pal_apply = function ()
	print (string.format("%04d gpu/pal/apply src=%08x dst=%04x len=%04x", snapshot:make(),
		gba.reg(0), gba.reg(1), gba.reg(2)))
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

bkpts:add(0x080088F0, h__gpu_pal_allocator_reset)
bkpts:add(0x0800893A, h__gpu_pal_alloc_and_load)
bkpts:add(0x08008948, h__gpu_pal_alloc_and_load)
bkpts:add(0x080089C8, h__gpu_pal_alloc_new)
bkpts:add(0x08008A30, h__gpu_pal_free_by_tag)

bkpts:add(0x080703EC, h__gpu_pal_apply)

bkpts:add(0x08077590, h__task_exec)
bkpts:add(0x0807759C, h__task_exec)

bkpts:enable()
