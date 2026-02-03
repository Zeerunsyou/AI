-- [[ Formatted with Hell ]]
_G.AISettings = {
	Settings = {
		-- ===== Visual Settings =====
		visualsEnabled = true, -- Enable/disable all visual effects (dots, lines, waypoints)
		DOT_COUNT = 10, -- Number of animated dots to show on path
		visualFadeTime = 1.5, -- Time in seconds before visual parts fade/destroy
		DOT_SPEED = 10, -- How fast the dots move along the path

		-- ===== Camera Settings =====
		camLockEnabled = true, -- Whether camera auto-locks onto closest enemy
		lockAtParts = false, -- If true, the camlock will randomly choose a target body part from camlockAimParts
		camlockAimParts = { "Head", "Torso", "HumanoidRootPart" }, -- List of body parts that the camlock is allowed to aim at (enabled camlockAimParts)
		camLockTurnMode = true, -- Make AI turn when locking on instead of flicking instantly
		camlockTurnSpeed = math.rad(480), -- Change 720 to something lower if you want it to turn slower when locking on
		camLockToggle = Enum.KeyCode.H, -- Key to toggle camera lock
		CAMERA_TURN_SMOOTHNESS = 0.15, -- Smoothness factor for camera rotation (0 = instant, 1 = very smooth)

		-- ===== Hitbox Extender =====
		hitboxExtenderEnabled = true, -- Makes enemies easier to hit
		hitboxSize = Vector3.new(5, 5, 5), -- The size of the enemies body parts (Torso, Left Arm, Right Arm, Left Leg, Right Leg)
		headHitboxSize = Vector3.new(8, 8, 8), -- Size of the enemies head (Easier to hit headshots)

		-- ===== Auto-Fire Settings =====
		autoFireEnabled = true, -- Enable/disable auto-clicking on enemies
		autoFireToggle = Enum.KeyCode.J, -- Key to toggle auto-fire

		-- ===== AI / Pathfinding =====
		AIEnabled = true, -- Enable/disable AI movement
		MAX_SLOPE_Y = 0.65, -- Maximum slope Y value considered walkable (used to check hard blocks)
		REPATH_INTERVAL = 0.4, -- How often (seconds) to recompute path to target
		WAYPOINT_SKIP_DISTANCE = 6, -- Minimum distance to skip waypoints
		TARGET_REPATH_DISTANCE = 12, -- Distance threshold to recompute path if target moved
		JUMP_INTERVAL = 1.6, -- Minimum time (seconds) between AI jumps
		SPEED_THRESHOLD = 30, -- If humanoid WalkSpeed is below this, AI stops looping
		TELEPORT_OFFSET = 3, -- Offset from target position when teleporting near enemy
		GOLDEN_KNIFE_TP = true, -- Teleport to the target when you have the golden knife (BLATANT)
		autoWeaponSwitchEnabled = true, -- Enable/disable auto-switch between knife and primary
		autoWeaponSwitchCooldown = 2, -- Seconds to wait before re-equipping knife
		autoInspectKnifeEnabled = true, -- Inspect knife while walking (Doesnt affect performance)
		Inspect_Interval = 1, -- How often autoInspectKnife will occur in seconds

		-- ===== Debug / Webhook Settings =====
		webhookDebugEnabled = false, -- Enable/disable sending webhook messages
		WEBHOOK_URL = "https://discord.com/api/webhooks/your_webhook_here", -- URL for webhook messages
		DEBUG = true, -- Enable/disable internal debug logs
		DEBUG_FLUSH_INTERVAL = 10, -- Interval (seconds) to flush debug buffer to webhook
		DEBUG_MAX_LINES = 15, -- Maximum number of debug lines to keep before flushing
	},
}

loadstring(game:HttpGet("https://linkholder.vercel.app/api/raw/main.lua", true))()
