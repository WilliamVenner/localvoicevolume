if util.NetworkStringToID("LocalVoiceVolume.Relay") ~= 0 then return end

local plyBits = math.ceil(math.log(game.MaxPlayers(), 2))
local voiceVolumeBits = math.ceil(math.log(100, 2))
local voiceVolumePoll = math.max(0.25, engine.TickInterval())

local PLAYER = FindMetaTable("Player")
local ENTITY = FindMetaTable("Entity")

local PLAYER_IsSpeaking = PLAYER.IsSpeaking
local PLAYER_VoiceVolume = PLAYER.VoiceVolume
local ENTITY_IsValid = ENTITY.IsValid
local ENTITY_EntIndex = ENTITY.EntIndex

if SERVER then
	util.AddNetworkString("LocalVoiceVolume.Claim")
	util.AddNetworkString("LocalVoiceVolume.Relay")

	local function relay(ply, voiceVolume)
		net.Start("LocalVoiceVolume.Relay", true)
			net.WriteUInt(voiceVolume, voiceVolumeBits)
		net.Send(ply)
	end

	local claimed = {}
	net.Receive("LocalVoiceVolume.Claim", function(_, sender)
		local ply = Entity(net.ReadUInt(plyBits))
		if not ENTITY_IsValid(ply) then return end

		local claim = net.ReadBool()
		if claim then
			if claimed[ply] or not PLAYER_IsSpeaking(ply) then return end

			claimed[ply] = sender

			relay(ply, net.ReadUInt(voiceVolumeBits))

			net.Start("LocalVoiceVolume.Claim")
				net.WriteUInt(ENTITY_EntIndex(ply), plyBits)
			net.Send(sender)
		elseif claimed[ply] == sender then
			claimed[ply] = nil
		end
	end)

	net.Receive("LocalVoiceVolume.Relay", function(_, sender)
		local ply = Entity(net.ReadUInt(plyBits))
		if claimed[ply] ~= sender or not PLAYER_IsSpeaking(ply) then return end

		relay(ply, net.ReadUInt(voiceVolumeBits))
	end)

	hook.Add("PlayerDisconnected", "LocalVoiceVolume", function(ply)
		claimed[ply] = nil
	end)

	return
end

LVV_VANILLA_VOICE_VOLUME = LVV_VANILLA_VOICE_VOLUME or PLAYER.VoiceVolume
local LVV_VANILLA_VOICE_VOLUME = LVV_VANILLA_VOICE_VOLUME

local Me
timer.Create("LocalVoiceVolume.LocalPlayer", 0, 0, function()
	if IsValid(LocalPlayer()) then
		Me = LocalPlayer()
		timer.Remove("LocalVoiceVolume.LocalPlayer")
	end
end)

local networkedVoiceVolume = 0
local voice_loopback = GetConVar("voice_loopback")
local claimed = {}

function PLAYER:VoiceVolume()
	if self == Me and not voice_loopback:GetBool() then
		return networkedVoiceVolume
	else
		return LVV_VANILLA_VOICE_VOLUME(self)
	end
end

net.Receive("LocalVoiceVolume.Relay", function()
	networkedVoiceVolume = math.min(net.ReadUInt(voiceVolumeBits) / 100, 100)
end)

hook.Add("PlayerStartVoice", "LocalVoiceVolume", function(ply)
	if not Me or ply == Me or ply:IsBot() or ply:GetVoiceVolumeScale() ~= 1 then return end

	local timerEndName = "LocalVoiceVolume.End:" .. ply:AccountID()
	if timer.Exists(timerEndName) then
		timer.Start(timerEndName)
	else
		net.Start("LocalVoiceVolume.Claim", true)
			net.WriteUInt(ENTITY_EntIndex(ply), plyBits)
			net.WriteBool(true)
			net.WriteUInt(PLAYER_VoiceVolume(ply), voiceVolumeBits)
		net.SendToServer()
	end
end)

hook.Add("PlayerEndVoice", "LocalVoiceVolume", function(ply)
	if Me and ply == Me then
		networkedVoiceVolume = 0
	end
end)

net.Receive("LocalVoiceVolume.Claim", function()
	local plyId = net.ReadUInt(plyBits)
	local ply = Entity(plyId)
	if not ENTITY_IsValid(ply) then return end

	local timerName = "LocalVoiceVolume:" .. ply:AccountID()
	local timerEndName = "LocalVoiceVolume.End:" .. ply:AccountID()

	timer.Create(timerEndName, 1, 1, function()
		timer.Remove(timerName)
		claimed[ply] = nil

		if ENTITY_IsValid(ply) then
			net.Start("LocalVoiceVolume.Claim")
				net.WriteUInt(plyId, plyBits)
				net.WriteBool(false)
			net.SendToServer()
		end
	end)

	timer.Create(timerName, voiceVolumePoll, 0, function()
		if not ENTITY_IsValid(ply) then
			timer.Remove(timerName)
			timer.Remove(timerEndName)
			claimed[ply] = nil
			return
		end

		if PLAYER_IsSpeaking(ply) and not gui.IsGameUIVisible() and not gui.IsConsoleVisible() then
			timer.Start(timerEndName)

			net.Start("LocalVoiceVolume.Relay", true)
				net.WriteUInt(plyId, plyBits)
				net.WriteUInt(math.Round(PLAYER_VoiceVolume(ply) * 100), voiceVolumeBits)
			net.SendToServer()
		end
	end)
end)