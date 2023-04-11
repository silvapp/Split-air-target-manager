function widget:GetInfo()
	return {
		name = "CoRoutine Test",
		desc = "",
		author = "[MOL]Silver",
		version = "",
		date = "",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = false
	}
end

local maxIterations = 2
local counter = 0

local myFunctionBla = function()
	for i, v in pairs(UnitDefs) do
		Spring.Echo(i,v.name)

		if counter % maxIterations == 0 then
			coroutine.yield()
		end

		counter = counter + 1
	end
end

local myTask = coroutine.create(myFunctionBla)

function widget:GameFrame(f)
	if f % 10 == 0 then
		coroutine.resume(myTask) -- resume task after 10 frames

		Spring.Echo(coroutine.status(myTask))
		if coroutine.status(myTask) == "dead" then
			myTask = coroutine.create(myFunctionBla) -- start over
		end
	end
end