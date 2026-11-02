-- Układ jeziora: przeszkody mieszczą się w wodzie i nie blokują startu ani stref kolejki, a strefy są rozdzielone.

return function(t)
	local Config = require(t.shared.Config)
	local LakeLayout = require(t.shared.content.LakeLayout)

	t.describe("LakeLayout", function()
		t.it("start, strefy i przeszkody leżą w jeziorze", function()
			local edge = LakeLayout.radius
			t.expect((LakeLayout.spawn - LakeLayout.center).Magnitude < edge / 2).toBe(true)
			for _, zone in LakeLayout.zones do
				t.expect((zone.position - LakeLayout.center).Magnitude + zone.radius < edge).toBe(true)
			end
			for _, obstacle in LakeLayout.obstacles do
				t.expect((obstacle.position - LakeLayout.center).Magnitude + obstacle.radius < edge).toBe(true)
			end
		end)

		t.it("przeszkody są z dala od startu i stref, i nie nachodzą na siebie", function()
			for index, obstacle in LakeLayout.obstacles do
				t.expect((obstacle.position - LakeLayout.spawn).Magnitude > 15).toBe(true)
				for _, zone in LakeLayout.zones do
					t.expect((obstacle.position - zone.position).Magnitude > zone.radius + obstacle.radius).toBe(true)
				end
				for other = index + 1, #LakeLayout.obstacles do
					t.expect((obstacle.position - LakeLayout.obstacles[other].position).Magnitude > 10).toBe(true)
				end
			end
		end)

		t.it("są trzy strefy z kontraktu, a zone to alias strefy wyścigu", function()
			local modes = {}
			for _, zone in LakeLayout.zones do
				modes[zone.id] = zone.mode
			end
			t.expect(#LakeLayout.zones).toBe(3)
			t.expect(modes.race).toBe("race")
			t.expect(modes.battle).toBe("battle")
			t.expect(modes.arena).toBe("arena")
			t.expect(LakeLayout.zone).toBe(LakeLayout.zones[1])
			t.expect(LakeLayout.zone.id).toBe("race")
		end)

		t.it("strefy leżą na północy i są wyraźnie rozdzielone", function()
			for index, zone in LakeLayout.zones do
				t.expect(zone.position.Y < LakeLayout.center.Y).toBe(true)
				for other = index + 1, #LakeLayout.zones do
					local second = LakeLayout.zones[other]
					-- Pudełka QueueZone mają bok 1,7 × promień, więc wolny pas między ringami wyklucza też ich nakładanie się.
					t.expect((zone.position - second.position).Magnitude > zone.radius + second.radius + 15).toBe(true)
				end
			end
		end)

		t.it("tablice stref stoją poza wodą, za swoim ringiem, i nie zasłaniają plansz", function()
			local boards = {
				{ position = Vector2.new(Config.VILLAGE_RIVER_BOARD_X, Config.VILLAGE_BOARD_Z), width = Config.VILLAGE_RIVER_BOARD_WIDTH },
				{ position = Vector2.new(Config.VILLAGE_RESULTS_BOARD_X, Config.VILLAGE_BOARD_Z), width = Config.VILLAGE_RESULTS_BOARD_WIDTH },
			}
			for index, zone in LakeLayout.zones do
				t.expect((zone.sign - LakeLayout.center).Magnitude > LakeLayout.radius).toBe(true)
				t.expect((zone.sign - zone.position).Magnitude > zone.radius).toBe(true)
				for _, board in boards do
					t.expect((zone.sign - board.position).Magnitude > (LakeLayout.signWidth + board.width) / 2).toBe(true)
				end
				for other = index + 1, #LakeLayout.zones do
					t.expect((zone.sign - LakeLayout.zones[other].sign).Magnitude > LakeLayout.signWidth).toBe(true)
				end
			end
		end)

		t.it("szafka: ring w jeziorze, z dala od startu, stref, przeszkód i tablic, budka na plaży", function()
			local locker = LakeLayout.locker
			t.expect((locker.position - LakeLayout.center).Magnitude + locker.radius < LakeLayout.radius).toBe(true)
			t.expect((locker.position - LakeLayout.spawn).Magnitude > locker.radius + 30).toBe(true) -- 20 miejsc startu ma zapas
			for _, zone in LakeLayout.zones do
				t.expect((locker.position - zone.position).Magnitude > locker.radius + zone.radius + 15).toBe(true)
				t.expect((locker.sign - zone.sign).Magnitude > LakeLayout.signWidth).toBe(true)
			end
			for _, obstacle in LakeLayout.obstacles do
				t.expect((locker.position - obstacle.position).Magnitude > locker.radius + obstacle.radius + 5).toBe(true)
			end
			t.expect((locker.sign - LakeLayout.center).Magnitude > LakeLayout.radius).toBe(true)
			t.expect((locker.sign - LakeLayout.center).Magnitude < LakeLayout.radius + Config.VILLAGE_BEACH_WIDTH).toBe(true)
		end)

		t.it("dziób na starcie patrzy na strefę", function()
			local forward = Vector2.new(math.cos(LakeLayout.heading), math.sin(LakeLayout.heading))
			local toZone = (LakeLayout.zone.position - LakeLayout.spawn).Unit
			t.expect(forward:Dot(toZone) > 0.999).toBe(true)
		end)
	end)
end
