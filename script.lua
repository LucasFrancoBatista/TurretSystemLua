
--[[ -- Opens the multi-line header comment block
Advanced Turret & Projectile System Demo -- Script title / description
Author: Lucas Franco Batista -- IRL Script author name
Roblox Username: SLKDOIDINN2 -- Roblox account username
]] -- Closes the multi-line header comment block

-- SERVICES -------------------------------------------------------------- -- Section: Roblox services used

local Players = game:GetService("Players") -- Gets Players service (for Players:GetPlayers())
local RunService = game:GetService("RunService") -- Gets RunService (for Heartbeat loop)
local CollectionService = game:GetService("CollectionService") -- Gets CollectionService (for tags)
local Debris = game:GetService("Debris") -- Gets Debris (auto-destroy after time)
local Workspace = game:GetService("Workspace") -- Gets Workspace (world reference + Raycast)

-- CONFIG ---------------------------------------------------------------- -- Section: balancing/tuning values

local TURRET_RANGE = 20 -- Max detection range (studs)
local FIRE_RATE = 0.5 -- Seconds between shots
local PROJECTILE_SPEED = 180 -- Projectile speed used by LinearVelocity
local PROJECTILE_LIFETIME = 5 -- Seconds before projectile is removed
local DAMAGE = 25 -- Damage per hit
local ROTATION_SPEED = 25 -- How fast the head aims (higher = faster)
local TARGET_REFRESH_RATE = 0.2 -- Seconds between target scans

-- IDLE CONFIG ----------------------------------------------------------- -- Section: idle rotation values

local IDLE_ROTATION_SPEED = 2.5 -- Idle spin speed (radians per second)
local FULL_ROTATION = math.pi * 2 -- Full 360° in radians (2π)

-- PROJECTILE CONFIG ----------------------------------------------------- -- Section: projectile appearance values

local PROJECTILE_SIZE = 3 -- Projectile size (bigger shots)

-- PROJECTILE FOLDER ----------------------------------------------------- -- Section: container to store projectiles

local projectileFolder = Instance.new("Folder") -- Creates a Folder to keep projectiles organized
projectileFolder.Name = "Projectiles" -- Sets folder name shown in Explorer
projectileFolder.Parent = Workspace -- Parents folder to Workspace so it exists in the world

-- RAYCAST PARAMS (reused) ---------------------------------------------- -- Section: reusable RaycastParams to avoid re-creating each cast

local raycastParams = RaycastParams.new() -- Creates RaycastParams object
raycastParams.FilterType = Enum.RaycastFilterType.Exclude -- Exclude listed instances (old "Blacklist")
raycastParams.FilterDescendantsInstances = { projectileFolder } -- Ignore projectile folder descendants
raycastParams.IgnoreWater = true -- Prevent water from blocking the raycast

-- HELPER FUNCTIONS ------------------------------------------------------ -- Section: small utility functions

local function clamp(value, min, max) -- Declares clamp helper function
	if value < min then return min end -- If below min, return min (closes this if immediately)
	if value > max then return max end -- If above max, return max (closes this if immediately)
	return value -- Otherwise return original value
end -- Closes function clamp

local function safeUnit(vector) -- Declares safeUnit helper function (safe normalization)
	if vector.Magnitude == 0 then -- Checks for zero-length vector
		return Vector3.zero -- Returns zero vector to avoid invalid normalization
	end -- Closes "if vector.Magnitude == 0 then"
	return vector.Unit -- Returns normalized unit direction
end -- Closes function safeUnit

-- PROJECTILE CREATION --------------------------------------------------- -- Section: projectile spawning and velocity setup

local function createProjectile(origin, direction) -- Declares projectile creation function
	local projectile = Instance.new("Part") -- Creates the projectile Part
	projectile.Size = Vector3.new(PROJECTILE_SIZE, PROJECTILE_SIZE, PROJECTILE_SIZE) -- Sets projectile size
	projectile.Shape = Enum.PartType.Ball -- Makes it a sphere
	projectile.Material = Enum.Material.Neon -- Neon for visibility
	projectile.Color = Color3.fromRGB(255, 120, 0) -- Orange color
	projectile.CFrame = CFrame.new(origin) -- Places projectile at origin position
	projectile.Anchored = false -- Allows physics simulation
	projectile.CanCollide = false -- No physical collisions (prevents bouncing/stopping)
	projectile.Massless = true -- Reduces physics side effects
	projectile.Parent = projectileFolder -- Stores projectile in the folder

	local attachment = Instance.new("Attachment") -- Creates attachment for physics constraint
	attachment.Parent = projectile -- Parents attachment to projectile

	local velocity = Instance.new("LinearVelocity") -- Creates a LinearVelocity constraint
	velocity.Attachment0 = attachment -- Binds constraint to the attachment
	velocity.VectorVelocity = direction * PROJECTILE_SPEED -- Sets projectile velocity vector
	velocity.MaxForce = math.huge -- Allows enough force to maintain velocity
	velocity.Parent = projectile -- Parents constraint to projectile

	Debris:AddItem(projectile, PROJECTILE_LIFETIME) -- Schedules projectile cleanup after lifetime
end -- Closes function createProjectile

-- RAYCAST ---------------------------------------------------------------- -- Section: raycast helper

local function performRaycast(origin, direction) -- Declares raycast function
	return Workspace:Raycast(origin, direction * 6, raycastParams) -- Casts a short ray (6 studs) using params
end -- Closes function performRaycast

-- DAMAGE ----------------------------------------------------------------- -- Section: damage application

local function applyDamage(hitPart) -- Declares damage function
	local model = hitPart:FindFirstAncestorOfClass("Model") -- Finds a parent Model (likely a character)
	if not model then return end -- If no Model, stop here
	local humanoid = model:FindFirstChildOfClass("Humanoid") -- Finds Humanoid in the model
	if not humanoid then return end -- If no Humanoid, stop here
	if humanoid.Health <= 0 then return end -- If already dead, stop here
	humanoid:TakeDamage(DAMAGE) -- Applies damage
end -- Closes function applyDamage

-- TURRET CLASS ----------------------------------------------------------- -- Section: turret class/object

local Turret = {} -- Creates table used as a class
Turret.__index = Turret -- Enables method lookups via metatable

function Turret.new(model) -- Declares constructor Turret.new
	local self = setmetatable({}, Turret) -- Creates instance and assigns Turret as metatable

	self.Model = model -- Stores model reference
	self.Base = model:FindFirstChild("Base") -- Stores base part reference (optional usage)
	self.Head = model:FindFirstChild("Head") -- Stores head part reference (aiming)

	self.LastShotTime = 0 -- Last shot time (cooldown)
	self.LastTargetCheck = 0 -- Last target scan time (scan throttling)
	self.CurrentTarget = nil -- Current target character model

	self.IdleAngle = 0 -- Idle yaw angle in radians (0..2π loop)

	if self.Model:GetAttribute("Active") == nil then -- If attribute doesn't exist yet
		self.Model:SetAttribute("Active", true) -- Default turret to active
	end -- Closes "if Active attribute is nil" block

	return self -- Returns the new turret instance
end -- Closes function Turret.new

function Turret:isActive() -- Declares method: checks enabled state
	return self.Model:GetAttribute("Active") == true -- True means turret runs; false means disabled
end -- Closes function Turret:isActive

function Turret:canFire() -- Declares method: checks cooldown
	return os.clock() - self.LastShotTime >= FIRE_RATE -- True if cooldown has passed
end -- Closes function Turret:canFire

function Turret:isTargetValid(character) -- Declares method: validates a target
	if not character then return false end -- Invalid if nil
	if not character.PrimaryPart then return false end -- Invalid if no PrimaryPart
	local distance = (character.PrimaryPart.Position - self.Head.Position).Magnitude -- Computes distance to target
	return distance <= TURRET_RANGE -- Valid if within turret range
end -- Closes function Turret:isTargetValid

function Turret:findNearestPlayer() -- Declares method: finds nearest player within range
	local closestCharacter = nil -- Holds nearest character found
	local closestDistance = TURRET_RANGE -- Starts at max allowed distance
	for _, player in ipairs(Players:GetPlayers()) do -- Loops all players
		local character = player.Character -- Gets their character
		if character and character.PrimaryPart then -- Must exist and have PrimaryPart
			local distance = (character.PrimaryPart.Position - self.Head.Position).Magnitude -- Distance to head
			if distance < closestDistance then -- If closer than current best
				closestDistance = distance -- Update best distance
				closestCharacter = character -- Update best character
			end -- Closes "if distance < closestDistance then"
		end -- Closes "if character and character.PrimaryPart then"
	end -- Closes loop "for _, player in ipairs(...) do"
	return closestCharacter -- Returns nearest character (or nil)
end -- Closes function Turret:findNearestPlayer

function Turret:updateTarget() -- Declares method: refreshes/updates target
	if os.clock() - self.LastTargetCheck < TARGET_REFRESH_RATE then return end -- Skip if refreshed too recently
	self.LastTargetCheck = os.clock() -- Save timestamp of this scan
	if not self:isTargetValid(self.CurrentTarget) then -- If current target is invalid/out of range
		self.CurrentTarget = self:findNearestPlayer() -- Acquire nearest valid player target
	end -- Closes "if not self:isTargetValid(...) then"
end -- Closes function Turret:updateTarget

-- IDLE ROTATION (0..360) ------------------------------------------------ -- Section: idle spin behavior

function Turret:idleRotate(deltaTime) -- Declares method: idle rotation update
	self.IdleAngle = (self.IdleAngle + IDLE_ROTATION_SPEED * deltaTime) % FULL_ROTATION -- Advances and wraps angle to 0..2π
	self.Head.CFrame = -- Assigns new CFrame to turret head
		CFrame.new(self.Head.Position) * -- Keeps same position
		CFrame.Angles(0, self.IdleAngle, 0) -- Applies yaw rotation around Y-axis
end -- Closes function Turret:idleRotate

function Turret:rotateTowards(position, deltaTime) -- Declares method: smoothly aims toward a position
	local current = self.Head.CFrame -- Stores current head CFrame
	local target = CFrame.new(self.Head.Position, position) -- Creates "look at" CFrame (head -> target position)
	self.Head.CFrame = current:Lerp( -- Smoothly interpolates current to target
		target, -- Target CFrame
		clamp(deltaTime * ROTATION_SPEED, 0, 1) -- Lerp alpha clamped to [0,1]
	) -- Closes the current:Lerp(...) call
end -- Closes function Turret:rotateTowards

function Turret:fire() -- Declares method: fires a projectile
	if not self.CurrentTarget then return end -- No target => do not fire
	if not self:canFire() then return end -- Cooldown not finished => do not fire
	self.LastShotTime = os.clock() -- Stores time to enforce cooldown
	local origin = self.Head.Position -- Projectile spawn position
	local direction = safeUnit(self.CurrentTarget.PrimaryPart.Position - origin) -- Direction from head to target
	createProjectile(origin, direction) -- Spawns projectile moving toward target
end -- Closes function Turret:fire

function Turret:update(deltaTime) -- Declares method: main turret per-frame update
	if not self:isActive() then return end -- If turret disabled, do nothing
	self:updateTarget() -- Updates/refreshes current target
	if not self.CurrentTarget then -- If no target found
		self:idleRotate(deltaTime) -- Perform idle rotation
		return -- Stop update here (no aiming/firing)
	end -- Closes "if not self.CurrentTarget then"
	self.IdleAngle = 0 -- Reset idle angle when actively tracking a target
	self:rotateTowards(self.CurrentTarget.PrimaryPart.Position, deltaTime) -- Aim at target
	self:fire() -- Attempt to fire
end -- Closes function Turret:update

-- REGISTRY --------------------------------------------------------------- -- Section: turret registration via CollectionService tag

local turrets = {} -- Table storing turret instances by model key

local function registerTurret(model) -- Declares function to register a turret model
	if turrets[model] then return end -- If already registered, do nothing
	turrets[model] = Turret.new(model) -- Create and store a new Turret instance
end -- Closes function registerTurret

local function unregisterTurret(model) -- Declares function to unregister a turret model
	turrets[model] = nil -- Remove turret instance reference
end -- Closes function unregisterTurret

for _, model in ipairs(CollectionService:GetTagged("Turret")) do -- Registers all already-tagged turrets at startup
	registerTurret(model) -- Register this turret model
end -- Closes loop "for _, model in ipairs(...) do"

CollectionService:GetInstanceAddedSignal("Turret"):Connect(registerTurret) -- When a turret is tagged/added, register it
CollectionService:GetInstanceRemovedSignal("Turret"):Connect(unregisterTurret) -- When removed/untagged, unregister it

-- PROJECTILE HIT LOOP ---------------------------------------------------- -- Section: projectile collision via raycast stepping

RunService.Heartbeat:Connect(function() -- Connects a function to Heartbeat (runs every frame tick)
	for _, projectile in ipairs(projectileFolder:GetChildren()) do -- Loop all active projectiles
		local v = projectile.AssemblyLinearVelocity -- Reads current projectile velocity
		if v.Magnitude > 0 then -- Only process if projectile is moving
			local result = performRaycast(projectile.Position, v.Unit) -- Raycast forward along velocity direction
			if result then -- If something was hit
				applyDamage(result.Instance) -- Apply damage to hit instance (if humanoid)
				projectile:Destroy() -- Destroy projectile on hit
			end -- Closes "if result then"
		end -- Closes "if v.Magnitude > 0 then"
	end -- Closes loop "for _, projectile in ipairs(...) do"
end) -- Closes Heartbeat connection callback (function() ... end)

-- TURRET UPDATE LOOP ----------------------------------------------------- -- Section: updates all turrets each Heartbeat

RunService.Heartbeat:Connect(function(deltaTime) -- Connects a function that receives deltaTime each Heartbeat
	for _, turret in pairs(turrets) do -- Loop through all registered turret instances
		turret:update(deltaTime) -- Update turret logic (targeting/aiming/firing/idle)
	end -- Closes loop "for _, turret in pairs(turrets) do"
end) -- Closes Heartbeat connection callback (function(deltaTime) ... end)
