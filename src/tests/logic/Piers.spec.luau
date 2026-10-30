-- Dane pomostów: układ 7 stanowisk, rzeki istnieją, gracz dojdzie do każdego pomostu w ok. 10 s.

return function(t)
	local Config = require(t.shared.Config)
	local Piers = require(t.shared.content.Piers)

	local WALK_SPEED = 16 -- domyślna prędkość postaci w Robloxie
	local WALK_LIMIT = 10

	t.describe("Piers", function()
		t.it("ma 7 stanowisk o różnych id: 3 łatwe, 2 średnie, 2 trudne", function()
			t.expect(#Piers).toBe(7)
			local seen, counts = {}, {}
			for _, pier in Piers do
				t.expect(seen[pier.id]).toBe(nil)
				seen[pier.id] = true
				counts[pier.difficulty] = (counts[pier.difficulty] or 0) + 1
			end
			t.expect(counts["Łatwa"]).toBe(3)
			t.expect(counts["Średnia"]).toBe(2)
			t.expect(counts["Trudna"]).toBe(2)
		end)

		t.it("otwarte są Test i Mountain, reszta to zaślepki", function()
			local open = {}
			for _, pier in Piers do
				if pier.river then
					t.expect(t.shared.content.rivers:FindFirstChild(pier.river) ~= nil).toBe(true)
					table.insert(open, pier.river)
				else
					t.expect(pier.label).toBe("Wkrótce")
				end
			end
			table.sort(open)
			t.expect(table.concat(open, ",")).toBe("Mountain,Test")
		end)

		t.it("pomost startuje na plaży i biegnie w stronę środka jeziora", function()
			local center = Vector2.new(0, Config.VILLAGE_LAKE_Z)
			for _, pier in Piers do
				local fromCenter = (pier.position - center).Magnitude
				t.expect(fromCenter > Config.VILLAGE_LAKE_RADIUS).toBe(true)
				t.expect(fromCenter < Config.VILLAGE_LAKE_RADIUS + Config.VILLAGE_BEACH_WIDTH).toBe(true)
				t.expect(pier.direction:Dot((center - pier.position).Unit) > 0.999).toBe(true)
			end
		end)

		t.it("do wejścia każdego pomostu idzie się najwyżej ok. 10 s", function()
			local spawn = Vector2.new(0, Config.VILLAGE_SPAWN_Z)
			for _, pier in Piers do
				local entrance = pier.position + pier.direction * Config.PIER_QUEUE_START
				t.expect((entrance - spawn).Magnitude <= WALK_SPEED * WALK_LIMIT).toBe(true)
			end
		end)

		t.it("pomosty nie nachodzą na siebie na końcach", function()
			for index = 2, #Piers do
				for other = 1, index - 1 do
					local tipA = Piers[index].position + Piers[index].direction * Config.PIER_LENGTH
					local tipB = Piers[other].position + Piers[other].direction * Config.PIER_LENGTH
					t.expect((tipA - tipB).Magnitude > Config.PIER_WIDTH * 2).toBe(true)
				end
			end
		end)
	end)
end
