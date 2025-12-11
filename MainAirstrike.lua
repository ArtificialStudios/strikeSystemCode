local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

-- Templates and remote events
local jetModelTemplate = ReplicatedStorage:WaitForChild("Jet")
local jetClickEvent = ReplicatedStorage:WaitForChild("JetClickEvent")
local explosionRemote = ReplicatedStorage:FindFirstChild("Explosion")

-- Ensure required folders exist in Workspace (create 'em if missing)
local function ensureFolder(parent, name)
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then return f end
	f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local soundsFolder = ensureFolder(Workspace, "Sounds")
local explosionsFolder = ensureFolder(Workspace, "Explosions")
local airstrikeParts = ensureFolder(Workspace, "AirstrikeParts")



-- Config block
local CONFIG = {
	jetCount = 5,
	jetDelay = 2.5,
	jetSpeed = 180,
	jetHeightRange = {250, 350},
	tweenTime = 4,

	strafeLength = 150,
	roundsPer100 = 30,
	firingPace = 0.03,
	firingMaxDuration = 3.0,

	explosionRadiusRange = {5, 15},
	explosionPressureRange = {80000, 120000},

	bulletSpeed = 0.05,

	soundsFlyby = {
		"rbxassetid://137641311111873",
		"rbxassetid://132663956012566",
		"rbxassetid://116181526950437"
	},
	soundsFire = {
		"rbxassetid://115129230164885",
		"rbxassetid://96523715121792"
	},
	soundsExit = {
		"rbxassetid://128430600903264"
	},
	soundVolume = 0.8,
	startDelay = 5,
	maxConcurrentJets = 8,
	uiTemplateName = "AirstrikeLocation"
}

--

-- UTILITY: safe random int in range
local function randInt(min, max)
	return math.random(min, max)
end
-- UTILITY: clamp
local function clamp(val, a, b)
	if val < a then return a end
	if val > b then return b end
	return val
end
-- UTILITY: shallow copy table
local function shallowCopy(t)
	local out = {}
	for k, v in pairs(t) do out[k] = v end
	return out
end

-- Sound: create, play, and loop a sound; returns sound instance after that for latrr
local function playRandomSound(list, parent, looped)
	if not list or #list == 0 then return nil end
	local soundId = list[math.random(1, #list)]
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = CONFIG.soundVolume
	sound.Looped = looped or false
	sound.Parent = parent
	-- quick safety: ensure parent still exists before playing just in case
	if sound.Parent then
		pcall(function() sound:Play() end)
	end
	if not looped then
		sound.Ended:Connect(function()
			if sound and sound.Parent then
				sound:Destroy()
			end
		end)
	end
	return sound
end

-- Create bullet visual between two points
local function createBulletVisual(fromPos, toPos, parent)
	local bullet = Instance.new("Part")
	bullet.Size = Vector3.new(0.2, 0.2, 6)
	bullet.Material = Enum.Material.Neon
	bullet.Color = Color3.fromRGB(255, 240, 120)
	bullet.Anchored = true
	bullet.CanCollide = false
	bullet.CFrame = CFrame.new(fromPos, toPos)
	bullet.Position = fromPos
	bullet.Parent = parent
	return bullet
end

-- Create a default explosion and parent it
local function createExplosionAt(position)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = randInt(CONFIG.explosionRadiusRange[1], CONFIG.explosionRadiusRange[2])
	explosion.BlastPressure = randInt(CONFIG.explosionPressureRange[1], CONFIG.explosionPressureRange[2])
	explosion.Parent = explosionsFolder
	return explosion
end

-- Fire event for cam shake explosion
local function fireExplosionRemote()
	if explosionRemote and explosionRemote:IsA("RemoteEvent") then
		pcall(function() explosionRemote:FireAllClients() end)
	end
end


-- Cancel token fac
local function newCancelToken()
	return { cancelled = false }
end
-- Clean up UI marker if present
local function cleanupAirstrikeMarker()
	local marker = airstrikeParts:FindFirstChild(CONFIG.uiTemplateName)
	if marker then marker:Destroy() end
end


-- Compute strafe path endpoints centered on clickedPosition
local function computeStrafeEndpoints(center)
	local half = CONFIG.strafeLength / 2
	local startPos = center - Vector3.new(half, 0, 0)
	local endPos = center + Vector3.new(half, 0, 0)
	return startPos, endPos
end

--	 Compute number of explosions based on distance and roundsPer100
local function computeTotalExplosions(startPos, endPos)
	local distance = (endPos - startPos).Magnitude
	local total = math.max(1, math.floor((distance / 100) * CONFIG.roundsPer100))
	return total, distance
end

--strafe routine: spawns explosions and bullet visuals along a line
local function triggerStrafe(mainPart, clickedPosition, cancelToken)
	-- small delay so jet is visible before firing starts
	task.wait(0.6)

	if not mainPart or not mainPart.Parent then return end

	local startPos, endPos = computeStrafeEndpoints(clickedPosition)
	local totalExplosions, distance = computeTotalExplosions(startPos, endPos)

	-- Play continuous firing sound loop while strafe is active
	local fireLoop = playRandomSound(CONFIG.soundsFire, soundsFolder, true)

	-- Spawn a dedicated task for the firing loop so it doesn't block
	task.spawn(function()
		local startTime = os.clock()
		for i = 1, totalExplosions do
			-- safety checks
			if cancelToken.cancelled then break end
			if os.clock() - startTime >= CONFIG.firingMaxDuration then break end
			if not mainPart or not mainPart.Parent then break end

			local t = i / totalExplosions
			local explosionPos = startPos:Lerp(endPos, t)

			-- create explosion and bullet visual
			createExplosionAt(explosionPos)
			fireExplosionRemote()

			local bullet = createBulletVisual(mainPart.Position, explosionPos, airstrikeParts)

			-- Tween bullet to explosion position
			local tween = TweenService:Create(bullet, TweenInfo.new(CONFIG.bulletSpeed, Enum.EasingStyle.Linear), { Position = explosionPos })
			tween:Play()
			tween.Completed:Connect(function()
				if bullet and bullet.Parent then bullet:Destroy() end
			end)

			-- pace the firing
			task.wait(CONFIG.firingPace)
		end

		-- stop the firing sound loop
		if fireLoop and fireLoop.Parent then
			fireLoop:Destroy()
		end
	end)

	-- remove any lingering UI marker
	cleanupAirstrikeMarker()
end

-- creeate and launch a single jet instance that performs a pass and triggers strafe
local function createJet(clickedPosition)
	-- clone template
	if not jetModelTemplate then return end
	local jetModel = jetModelTemplate:Clone()
	if not jetModel then return end

	local mainPart = jetModel:FindFirstChild("Main")
	if not mainPart then
		jetModel:Destroy()
		return
	end

	-- compute randomized height and start/target positions
	local jetHeight = randInt(CONFIG.jetHeightRange[1], CONFIG.jetHeightRange[2])
	local startPos = clickedPosition + Vector3.new(-3000, jetHeight, 0)
	local targetPos = Vector3.new(clickedPosition.X + 2000, jetHeight, clickedPosition.Z)
	local exitPos = targetPos + Vector3.new(0, 0, 7000)

	-- prepare model
	mainPart.Position = startPos
	mainPart.Anchored = true
	jetModel.Parent = Workspace

	-- play flyby sound once
	playRandomSound(CONFIG.soundsFlyby, soundsFolder, false)

	-- cancel token for this jet's strafe
	local cancelToken = newCancelToken()

	-- move jet to targetPos using Tween
	local tween = TweenService:Create(mainPart, TweenInfo.new(CONFIG.tweenTime, Enum.EasingStyle.Linear), { Position = targetPos })
	tween:Play()

	-- start strafe routine in parallel
	task.spawn(function()
		-- small guard: ensure mainPart still exists
		if mainPart and mainPart.Parent then
			triggerStrafe(mainPart, clickedPosition, cancelToken)
		end
	end)

	-- when tween completes, mark cancelled and send jet off
	tween.Completed:Connect(function()
		cancelToken.cancelled = true

		-- exit sound
		playRandomSound(CONFIG.soundsExit, soundsFolder, false)

		-- unanchor and give velocity to simulate leaving
		if mainPart and mainPart.Parent then
			mainPart.Anchored = false
			local direction = (exitPos - mainPart.Position)
			if direction.Magnitude > 0 then
				mainPart.Velocity = direction.Unit * CONFIG.jetSpeed
			end
			mainPart.Transparency = 1
		end

		-- schedule model cleanup
		task.delay(5, function()
			if jetModel and jetModel.Parent then
				jetModel:Destroy()
			end
		end)
	end)
end

	-- orchestrator: spawn multiple jets with spacing and concurrency guard
local function moveJetAndExplode(clickedPosition)
	-- initial delay so UI can show up
	task.wait(CONFIG.startDelay)

	-- concurrency guard: limit number of jets spawned at once
	local spawnCount = clamp(CONFIG.jetCount, 1, CONFIG.maxConcurrentJets)
	for i = 1, spawnCount do
		createJet(clickedPosition)
		task.wait(CONFIG.jetDelay)
	end
end

-- UI marker creation: clones a template from ReplicatedStorage and places it
local function createAirstrikeMarker(clickedPosition)
	local template = ReplicatedStorage:FindFirstChild(CONFIG.uiTemplateName)
	if not template then return nil end
	local uiBlock = template:Clone()
	uiBlock.Parent = airstrikeParts
	uiBlock.Position = clickedPosition
	return uiBlock
end

-- Main event handler for remote event
jetClickEvent.OnServerEvent:Connect(function(player, clickedPosition)
	-- basic validation
	if not player or not clickedPosition or typeof(clickedPosition) ~= "Vector3" then return end

	-- create UI marker for the strike
	local uiBlock = createAirstrikeMarker(clickedPosition)

	-- spawn jets and explosions
	task.spawn(function()
		moveJetAndExplode(clickedPosition)
	end)

	-- cleanup: remove marker and clear airstrikeParts after a short delay
	task.delay(0.1, function()
		-- clear children safely
		for _, child in ipairs(airstrikeParts:GetChildren()) do
			if child ~= uiBlock then
				child:Destroy()
			end
		end
		if uiBlock and uiBlock.Parent then
			uiBlock:Destroy()
		end
	end)
end)

function AirstrikeAPI.TriggerAt(position)
	if typeof(position) ~= "Vector3" then return false end
	-- create marker and start sequence
	local marker = createAirstrikeMarker(position)
	moveJetAndExplode(position)
	-- clean that stuff out
	task.delay(3, function()
		if marker and marker.Parent then marker:Destroy() end
	end)
	return true
end
