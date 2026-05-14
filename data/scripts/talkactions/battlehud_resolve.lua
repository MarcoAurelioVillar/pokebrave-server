local talk = TalkAction("/battlehud_resolve", "!battlehud_resolve")

function talk.onSay(player, words, param)
	local payload = {
		v = 1,
		op = "battle:resolve",
		id = tostring(os.time()),
		session = "test-session-" .. player:getId(),
		ts = os.time() * 1000,
		body = {
			turn = 1,
			events = {
				{
					kind = "choices_locked",
					seq = 1,
					order = {
						{ slot = "A", priority = 1, effectiveSpeed = 90 },
						{ slot = "B", priority = 0, effectiveSpeed = 45 }
					}
				},
				{
					kind = "action_start",
					seq = 2,
					slot = "A",
					action = { kind = "move", moveId = "Thunderbolt" }
				},
				{
					kind = "damage",
					seq = 3,
					target = "B:active",
					amount = 25,
					effectiveness = 2.0,
					crit = false
				},
				{
					kind = "action_start",
					seq = 4,
					slot = "B",
					action = { kind = "move", moveId = "Tackle" }
				},
				{
					kind = "damage",
					seq = 5,
					target = "A:active",
					amount = 15,
					effectiveness = 1.0,
					crit = false
				}
			},
			publicState = {
				["A:active"] = {
					hp = { current = 65, max = 100 },
					status = { name = "none" },
					fainted = false
				},
				["B:active"] = {
					hp = { current = 65, max = 100 },
					status = { name = "none" },
					fainted = false
				}
			},
			next = {
				kind = "awaiting_choices",
				choiceWindow = {
					valid = {
						slot = "A",
						actions = { "move", "switch", "surrender" }
					}
				}
			}
		}
	}

	player:sendExtendedOpcode(60, json.encode(payload))
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "[BattleHud] battle:resolve enviado via opcode 60.")
	return false
end

talk:separator(" ")
talk:register()
