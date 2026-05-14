local talk = TalkAction("/battlehud", "!battlehud")

function talk.onSay(player, words, param)
	local payload = {
		v = 1,
		op = "battle:start",
		id = tostring(os.time()),
		session = "test-session-" .. player:getId(),
		ts = os.time() * 1000,
		body = {
			session = "test-session-" .. player:getId(),
			turn = 1,
			you = { slot = "A", name = player:getName() },
			opponent = { slot = "B", name = "Trainer Blue" },
			arena = { name = "Test Arena" },
			rules = { format = "1v1" },
			participants = {
				{
					slot = "A",
					active = {
						speciesName = "Pikachu",
						level = 25,
						hp = { current = 80, max = 100 },
						status = { name = "none" },
						fainted = false
					}
				},
				{
					slot = "B",
					active = {
						speciesName = "Bulbasaur",
						level = 25,
						hp = { current = 90, max = 100 },
						status = { name = "none" },
						fainted = false
					}
				}
			},
			choiceWindow = {
				valid = {
					slot = "A",
					actions = { "move", "switch", "surrender" }
				}
			}
		}
	}

	player:sendExtendedOpcode(60, json.encode(payload))
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "[BattleHud] battle:start enviado via opcode 60.")
	return false
end

talk:separator(" ")
talk:register()
