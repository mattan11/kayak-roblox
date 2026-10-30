-- Kamera za kajakiem. Pozycja jest przyklejona do Hull bez wygładzania (kajak nie drży na ekranie), wygładzone są
-- tylko kierunek patrzenia i oddalenie. Kierunek to środek między kursem kajaka a biegiem rzeki: widać, dokąd płyniesz
-- i dokąd niesie woda.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Client = script.Parent.Parent
local KayakPose = require(Client.logic.KayakPose)
local Session = require(Client.Session)

local CameraController = {}

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

local yaw: number? = nil -- nil = ustaw od razu, bez obrotu (start, Reset)
local speedFactor = 0
local shake = 0
local reach = 1 -- ułamek odległości kamery; <1 = ściana przysunęła ją do kajaka
local following = false

local function aimAngle(state: any): number
	local q = state.lastQuery
	if q == nil then
		return state.heading
	end
	return KayakPose.lerpAngle(state.heading, math.atan2(q.tangent.Y, q.tangent.X), Config.CAMERA_RIVER_BLEND)
end

local function frame(dt: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local state = Session.state
	local hull = Session.ownHull
	if state == nil or hull == nil then
		if following then
			following = false
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = Config.CAMERA_FOV
		end
		return
	end
	following = true
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable -- respawn postaci potrafi to zresetować
	end

	local aim = aimAngle(state)
	local current = if yaw then KayakPose.lerpAngle(yaw, aim, KayakPose.smoothing(Config.CAMERA_TURN_SMOOTH, dt)) else aim
	yaw = current

	local targetSpeed = math.min(state.velocity.Magnitude / Config.POSE_FULL_SPEED, 1)
	speedFactor += (targetSpeed - speedFactor) * KayakPose.smoothing(Config.CAMERA_SPEED_SMOOTH, dt)

	local forward = Vector3.new(math.cos(current), 0, math.sin(current))
	local position = hull.Position
	local focus = position
	local distance = Config.CAMERA_DISTANCE + Config.CAMERA_DISTANCE_SPEED * speedFactor
	local eye = focus - forward * distance + Vector3.new(0, Config.CAMERA_HEIGHT, 0)

	-- W kanionie kamera na zakręcie weszłaby w skałę: przysuwamy ją do kajaka, jeśli po drodze jest teren
	local origin = focus + Vector3.new(0, 3, 0)
	local toEye = eye - origin
	local hit = workspace:Raycast(origin, toEye, terrainOnly)
	local wanted = if hit then math.max(hit.Distance - 1, 2) / toEye.Magnitude else 1
	-- Do ściany od razu (bez wejścia w skałę), od ściany powoli (bez szarpania, gdy kajak się od niej odbija)
	reach = if wanted < reach then wanted else reach + (wanted - reach) * KayakPose.smoothing(Config.CAMERA_PULL_OUT_SMOOTH, dt)
	eye = origin + toEye * reach + Vector3.new(0, Config.CAMERA_PULL_RISE * (1 - reach), 0)
	local look = focus + forward * Config.CAMERA_LOOK_AHEAD + Vector3.new(0, 1, 0)

	if shake > 0.01 then
		local clock = os.clock()
		local amount = shake * Config.CAMERA_SHAKE
		eye += Vector3.new(math.noise(clock * 23, 1.5) * amount, math.noise(clock * 27, 7.5) * amount, 0)
		shake *= math.exp(-Config.CAMERA_SHAKE_DECAY * dt)
	end

	camera.CFrame = CFrame.lookAt(eye, look)
	camera.FieldOfView = Config.CAMERA_FOV + Config.CAMERA_FOV_SPEED * speedFactor
end

function CameraController.start()
	Session.on("reset", function()
		yaw = nil
		speedFactor = 0
	end)
	Session.on("hit", function(strength: number)
		shake = math.max(shake, math.min(strength / Config.HIT_FULL_STRENGTH, 1))
	end)
	RunService:BindToRenderStep("KayakCamera", Enum.RenderPriority.Camera.Value, frame)
end

return CameraController
