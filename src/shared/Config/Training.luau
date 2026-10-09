--[[
	Training
	Server-validated training challenges at the Training Grounds.

	Each challenge has a Goal the server measures itself (it never trusts a client "done").
	Rewards: XP scales gently with level; TrainingPoints feed the training bonus for one
	attribute (capped by GameConfig.Training.MaxTrainingBonusPerAttribute and DailyPointCap).
	Cooldown prevents repeated farming.
]]

local Training = {
	weightlifting = {
		Name = "Weightlifting", Description = "Press E (or tap) in rhythm: one rep every 0.7-2.0s. 12 reps.",
		Kind = "Reps", Reps = 12, MinInterval = 0.7, MaxInterval = 2.0, StaminaPerRep = 8,
		Attribute = "Strength", Points = 2, Xp = 60, Cooldown = 180,
	},
	dummy_dps = {
		Name = "Weapon Practice", Description = "Land 15 valid hits on the training dummy within 20 seconds.",
		Kind = "Hits", Hits = 15, TimeLimit = 20,
		Attribute = "Dexterity", Points = 2, Xp = 60, Cooldown = 180,
	},
	dodge_drill = {
		Name = "Dodge Drill", Description = "The drill master attacks 6 times. Avoid at least 5 hits.",
		Kind = "Avoid", Attacks = 6, Required = 5, Interval = 2.4, Windup = 0.9,
		Attribute = "Endurance", Points = 2, Xp = 80, Cooldown = 240,
	},
	parry_drill = {
		Name = "Parry Drill", Description = "Parry 3 of the sparring knight's slow attacks.",
		Kind = "Parry", Attacks = 6, Required = 3, Interval = 2.8, Windup = 1.1,
		Attribute = "Dexterity", Points = 3, Xp = 100, Cooldown = 300,
	},
	stamina_run = {
		Name = "Endurance Run", Description = "Sprint around the training track: pass all 6 posts within 45 seconds.",
		Kind = "Course", Posts = 6, TimeLimit = 45,
		Attribute = "Endurance", Points = 2, Xp = 70, Cooldown = 240,
	},
	sparring = {
		Name = "Sparring Match", Description = "Defeat the sparring partner without dying.",
		Kind = "Spar", Enemy = "hollow_thrall", HealthMult = 2.5,
		Attribute = "Vigor", Points = 3, Xp = 120, Cooldown = 300,
	},
}

for id, t in Training do
	t.Id = id
end

return Training
