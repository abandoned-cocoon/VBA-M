sss = {["archive"] = {}, ["plugins"] = {}}

function sss:make()
	local snap = {}

	for i, plugin in pairs(self.plugins) do
		for _,line in ipairs(plugin(self)) do
			table.insert(snap, line)
		end
	end

	local arc = self.archive
	table.insert(arc, snap)
	table.sort(snap)
	return #arc
end

function sss:recall(i)
	for _, line in ipairs(self.archive[i]) do
		print(line)
	end
end

return sss
