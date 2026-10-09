--[[
	PlayerStateService
	Owns each player's runtime state: loaded profile, derived stats, combat state, region,
	encounter membership. Spawns characters at checkpoints, mirrors health into the Humanoid,
	regenerates stamina/mana, applies status damage over time and syncs a sanitized profile
	snapshot to the owning client.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local World = require(Shared.Config.World)
local Stats = require(Shared.Logic.Stats)
local Signal = require(Shared.Util.Signal)
local Net = require(Shared.Net)
local CombatCore = require(script.Parent.Parent.Core.CombatCore)
local DeathCore = require(script.Parent.Parent.Core.DeathCore)

local PlayerStateService = {
	CharacterReady = Signal.new(), -- (player, runtime)
	StatsChanged = Signal.new(), -- (player, runtime)
}

local S -- services
local runtimes: { [Player]: any } = {}
local profileRemote: RemoteEvent

local TICK = 0.1

local function toVector(t)
	return Vector3.new(t[1], t[2], t[3])
end

function PlayerStateService.Init(services)
	S = services
	profileRemote = Net.event("Profile")
end

function PlayerStateService.Get(player: Player)
	return runtimes[player]
end

function PlayerStateService.All()
	return runtimes
end

function PlayerStateService.Profile(player: Player)
	local rt = runtimes[player]
	return rt and rt.Profile
end

-- Sanitized snapshot for the owning client (nothing secret; the client never writes it back).
function PlayerStateService.Sync(player: Player)
	local rt = runtimes[player]
	if not rt then
		return
	end
	local p = rt.Profile
	profileRemote:FireClient(player, {
		Class = p.Class,
		Level = p.Level,
		Xp = p.Xp,
		UnspentPoints = p.UnspentPoints,
		Attributes = p.Attributes,
		TrainingBonus = p.TrainingBonus,
		TrainingPoints = p.TrainingPoints,
		Currency = p.Currency,
		Inventory = p.Inventory,
		Equipped = p.Equipped,
		Abilities = p.Abilities,
		Flask = p.Flask,
		Tower = { HighestCleared = p.Tower.HighestCleared, Clears = p.Tower.Clears },
		Checkpoints = p.Checkpoints,
		Discovered = p.Discovered,
		OpenedChests = p.OpenedChests,
		Quests = p.Quests,
		Stats = p.Stats,
		Achievements = p.Achievements,
		Titles = p.Titles,
		ActiveTitle = p.ActiveTitle,
		Cosmetics = p.Cosmetics,
		Settings = p.Settings,
		LostCurrency = p.LostCurrency,
		ShopPurchases = p.ShopPurchases,
		BuildPresets = p.BuildPresets,
		Derived = rt.Stats,
		HasWardrobePass = rt.HasWardrobePass == true,
		ServerTime = workspace:GetServerTimeNow(),
	})
end

function PlayerStateService.RecomputeStats(player: Player)
	local rt = runtimes[player]
	if not rt then
		return
	end
	rt.Stats = Stats.compute(rt.Profile)
	if rt.Combat then
		CombatCore.refreshMax(rt.Combat, rt.Stats)
		PlayerStateService.PushVitals(player)
	end
	local hum = rt.Humanoid
	if hum then
		hum.WalkSpeed = GameConfig.Stamina.WalkSpeed * rt.Stats.SpeedMult
	end
	PlayerStateService.StatsChanged:Fire(player, rt)
end

-- Mirrors combat vitals into the Humanoid and player attributes (replicated to all clients).
function PlayerStateService.PushVitals(player: Player)
	local rt = runtimes[player]
	if not rt or not rt.Combat then
		return
	end
	local c = rt.Combat
	local hum = rt.Humanoid
	if hum and hum.Parent then
		hum.MaxHealth = c.MaxHealth
		if not c.Dead then
			hum.Health = math.max(1, c.Health)
		end
	end
	player:SetAttribute("Health", math.floor(c.Health))
	player:SetAttribute("MaxHealth", c.MaxHealth)
	player:SetAttribute("Stamina", math.floor(c.Stamina))
	player:SetAttribute("MaxStamina", c.MaxStamina)
	player:SetAttribute("Mana", math.floor(c.Mana))
	player:SetAttribute("MaxMana", c.MaxMana)
	player:SetAttribute("FlaskCharges", rt.Profile.Flask.Charges)
	player:SetAttribute("FlaskMax", rt.Profile.Flask.MaxCharges)
	player:SetAttribute("Currency", rt.Profile.Currency)
	player:SetAttribute("Level", rt.Profile.Level)
	player:SetAttribute("Poisoned", workspace:GetServerTimeNow() < c.Status.PoisonUntil)
	player:SetAttribute("Burning", workspace:GetServerTimeNow() < c.Status.BurnUntil)
end

function PlayerStateService.RespawnPosition(player: Player): Vector3
	local rt = runtimes[player]
	local cpId = rt and rt.Profile.Checkpoints.Last or "sanctuary"
	for _, cp in World.Checkpoints do
		if cp.Id == cpId then
			return toVector(cp.Position) + Vector3.new(0, 4, 6)
		end
	end
	return toVector(World.SpawnPoint)
end

local function onCharacter(player: Player, character: Model)
	local rt = runtimes[player]
	if not rt then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	rt.Character = character
	rt.Humanoid = humanoid
	rt.Root = root
	rt.Stats = Stats.compute(rt.Profile)
	local now = workspace:GetServerTimeNow()
	rt.Combat = CombatCore.newPlayerState(rt.Stats, now)
	rt.Sprinting = false
	rt.Encounter = nil
	rt.DeathHandled = false
	humanoid.BreakJointsOnDeath = false
	humanoid.WalkSpeed = GameConfig.Stamina.WalkSpeed * rt.Stats.SpeedMult
	humanoid.MaxHealth = rt.Combat.MaxHealth
	humanoid.Health = rt.Combat.Health

	-- place at checkpoint
	task.defer(function()
		if character.Parent then
			local pos = PlayerStateService.RespawnPosition(player)
			pcall(function()
				player:RequestStreamAroundAsync(pos, 5)
			end)
			character:PivotTo(CFrame.new(pos))
		end
	end)

	humanoid.Died:Connect(function()
		-- falls into the void or other engine deaths route through the same death logic
		if rt.Character == character and not rt.DeathHandled then
			rt.Combat.Dead = true
			S.DeathService.OnPlayerDeath(player, "Engine")
		end
	end)

	PlayerStateService.PushVitals(player)
	PlayerStateService.CharacterReady:Fire(player, rt)
end

local function onPlayerAdded(player: Player)
	local profile = S.DataService.Load(player)
	if not profile or not player.Parent then
		return
	end
	runtimes[player] = {
		Player = player,
		Profile = profile,
		Stats = Stats.compute(profile),
		Region = "sanctuary",
		JoinedAt = os.time(),
	}
	DeathCore.expire(profile, os.time())
	PlayerStateService.Sync(player)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	player:LoadCharacter()
end

function PlayerStateService.Start()
	Players.CharacterAutoLoads = false
	Players.RespawnTime = 4
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		local rt = runtimes[player]
		if rt and rt.Encounter then
			S.BossService.OnParticipantLeft(player)
		end
		runtimes[player] = nil
	end)

	-- Regeneration / status / sprint loop
	task.spawn(function()
		local acc = 0
		while true do
			local dt = task.wait(TICK)
			acc += dt
			local now = workspace:GetServerTimeNow()
			for player, rt in runtimes do
				local c = rt.Combat
				if c and not c.Dead and rt.Humanoid then
					-- sprint drain
					local moving = rt.Humanoid.MoveDirection.Magnitude > 0.1
					if rt.Sprinting and moving then
						if c.Stamina > 0 then
							c.Stamina = math.max(0, c.Stamina - GameConfig.Stamina.SprintCostPerSecond * dt)
							c.LastStaminaSpend = now
							rt.Humanoid.WalkSpeed = GameConfig.Stamina.SprintSpeed * rt.Stats.SpeedMult
						else
							rt.Sprinting = false
							rt.Humanoid.WalkSpeed = GameConfig.Stamina.WalkSpeed * rt.Stats.SpeedMult
						end
					end
					CombatCore.regen(c, dt, now, rt.Stats)
					local dotFraction = CombatCore.tickStatus(c.Status, dt, now, "Player")
					if dotFraction > 0 then
						local died = CombatCore.applyDamage(c, math.max(1, math.floor(c.MaxHealth * dotFraction)))
						if died then
							S.DeathService.OnPlayerDeath(player, "Status")
						end
					end
					PlayerStateService.PushVitals(player)
				end
			end
		end
	end)
end

function PlayerStateService.SetSprinting(player: Player, on: boolean)
	local rt = runtimes[player]
	if not rt or not rt.Humanoid or not rt.Combat then
		return
	end
	rt.Sprinting = on and rt.Combat.Stamina > 0 and not rt.Combat.Blocking
	rt.Humanoid.WalkSpeed = (if rt.Sprinting then GameConfig.Stamina.SprintSpeed else GameConfig.Stamina.WalkSpeed) * rt.Stats.SpeedMult
end

-- Restores HP/stamina/mana/flask (checkpoint rest).
function PlayerStateService.FullRestore(player: Player)
	local rt = runtimes[player]
	if not rt or not rt.Combat or rt.Combat.Dead then
		return
	end
	local c = rt.Combat
	c.Health, c.Stamina, c.Mana = c.MaxHealth, c.MaxStamina, c.MaxMana
	c.Status = CombatCore.newStatus()
	rt.Profile.Flask.Charges = rt.Profile.Flask.MaxCharges
	PlayerStateService.PushVitals(player)
end

return PlayerStateService
