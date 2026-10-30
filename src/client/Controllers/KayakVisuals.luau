-- Wygląd kajaków „na oko”: kołysanie własnego (cel AlignOrientation ustawia KayakController, tu tylko liczymy pozę)
-- i animacja wioseł wszystkich kajaków przez PaddleJoint. Transform Motor6D nie replikuje się, więc każdy klient
-- animuje cudze wiosła sam, na podstawie PaddleEcho. Cudzy przechył dociera razem z fizyką kajaka.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local KayakPose = require(Client.logic.KayakPose)
local Session = require(Client.Session)

local KayakVisuals = {}

local player = Players.LocalPlayer

type Record = {
	joint: Motor6D?,
	yaw: number,
	roll: number,
	strokeSide: number?, -- trwające machnięcie cudzego kajaka
	strokeTime: number,
	brace: number?,
	braceTime: number,
}

local records: { [Model]: Record } = {}
local waist: Motor6D? = nil

local ownPitch, ownRoll = 0, 0

-- Poza własnego kajaka na tę klatkę: (pitch, roll, bob). Woła ją KayakController.
function KayakVisuals.ownPose(dt: number, state: any): (number, number, number)
	local q = state.lastQuery
	local strokePower = 0
	if state.strokeSide then
		strokePower = math.sin(math.pi * state.strokeTime / Config.STROKE_TIME)
	end
	local speed = state.velocity.Magnitude
	local pitch, roll, bob = KayakPose.target(os.clock(), speed, state.spin, state.strokeSide, strokePower, if q then q.speed else 0)
	local alpha = KayakPose.smoothing(Config.POSE_SMOOTH, dt)
	ownPitch += (pitch - ownPitch) * alpha
	ownRoll += (roll - ownRoll) * alpha
	return ownPitch, ownRoll, bob
end

local function recordFor(model: Model): Record
	local record = records[model]
	if record == nil then
		record = { joint = nil, yaw = 0, roll = 0, strokeSide = nil, strokeTime = 0, brace = nil, braceTime = 0 }
		records[model] = record
	end
	return record
end

local function findWaist(): Motor6D?
	if waist and waist.Parent then
		return waist
	end
	local character = player.Character
	local torso = character and character:FindFirstChild("UpperTorso")
	local joint = torso and torso:FindFirstChild("Waist")
	waist = if joint and joint:IsA("Motor6D") then joint else nil -- R6 nie ma talii: po prostu bez skrętu
	return waist
end

local function onPaddle(model: Model, kind: string, side: number)
	if model == Session.ownModel then
		return -- własne wiosło czyta stan fizyki, bez czekania na zdarzenia
	end
	local record = recordFor(model)
	if kind == "stroke" then
		record.strokeSide, record.strokeTime, record.brace = side, 0, nil
	elseif kind == "brace" then
		record.brace, record.braceTime, record.strokeSide = side, 0, nil
	elseif kind == "release" then
		record.brace = nil
	end
end

-- Zegary cudzego wiosła: wiemy tylko, kiedy ruch się zaczął, więc koniec liczymy sami.
local function advanceRemote(record: Record, dt: number)
	if record.strokeSide then
		record.strokeTime += dt
		if record.strokeTime >= Config.STROKE_TIME then
			record.strokeSide = nil
		end
	end
	if record.brace then
		record.braceTime += dt
		if record.braceTime >= Config.PADDLE_BRACE_TIMEOUT then
			record.brace = nil
		end
	end
end

local function jointOf(hull: BasePart, record: Record): Motor6D?
	local joint = record.joint
	if joint == nil then
		local found = hull:FindFirstChild("PaddleJoint")
		joint = if found and found:IsA("Motor6D") then found else nil
		record.joint = joint
	end
	return joint
end

local function animate(dt: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local cameraPosition = camera.CFrame.Position
	local alpha = KayakPose.smoothing(Config.PADDLE_SMOOTH, dt)
	local state = Session.state

	for _, model in Session.kayaks do
		local hull = model.PrimaryPart
		if hull and (hull.Position - cameraPosition).Magnitude <= Config.FX_RADIUS then
			local record = recordFor(model)
			local joint = jointOf(hull, record)
			if joint then
				local own = model == Session.ownModel and state ~= nil
				if not own then
					advanceRemote(record, dt)
				end
				local strokeSide = if own then state.strokeSide else record.strokeSide
				local strokeTime = if own then state.strokeTime else record.strokeTime
				local brace = if own then state.brace else record.brace

				local targetYaw, targetRoll = 0, 0
				if brace then
					targetYaw, targetRoll = KayakPose.paddleBrace(brace)
				elseif strokeSide then
					targetYaw, targetRoll = KayakPose.paddleStroke(strokeSide, math.clamp(strokeTime / Config.STROKE_TIME, 0, 1))
				end
				record.yaw += (targetYaw - record.yaw) * alpha
				record.roll += (targetRoll - record.roll) * alpha
				joint.Transform = CFrame.Angles(0, record.yaw, record.roll)

				if own then
					local body = findWaist()
					if body then
						body.Transform = CFrame.Angles(0, record.yaw * Config.TORSO_TWIST, 0)
					end
				end
			end
		end
	end
end

function KayakVisuals.start()
	Session.on("paddle", onPaddle)
	Session.on("kayakRemoved", function(model: Model)
		records[model] = nil
	end)
	Remotes.get("PaddleEcho").OnClientEvent:Connect(function(userId: number, kind: string, side: number)
		local name = tostring(userId)
		for _, model in Session.kayaks do
			if model.Name == name then
				Session.emit("paddle", model, kind, side)
				return
			end
		end
	end)
	-- Transform Motor6D ustawia się przed symulacją (tak robi Animator)
	RunService.PreSimulation:Connect(animate)
end

return KayakVisuals
