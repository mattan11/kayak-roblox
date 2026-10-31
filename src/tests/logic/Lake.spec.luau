return function(t)
	local Config = require(t.shared.Config)
	local KayakPhysics = require(t.shared.KayakPhysics)
	local Lake = require(t.shared.Lake)
	local LakeLayout = require(t.shared.content.LakeLayout)
	local RiverSampler = require(t.client.logic.RiverSampler)

	-- Własny układ: spec nie zależy od strojenia prawdziwego jeziora.
	local lake = Lake.new({
		center = Vector2.new(10, -20),
		radius = 60,
		spawn = Vector2.new(10, 20),
		heading = -math.pi / 2,
		obstacles = { { position = Vector2.new(10, -20), radius = 6 } },
	})

	local function run(state, seconds: number, each: (() -> ())?)
		for _ = 1, math.floor(seconds * 60) do
			if each then
				each()
			end
			KayakPhysics.step(state, lake, nil, 1 / 60)
		end
	end
	local function paddle(state)
		if state.queued == nil then
			KayakPhysics.requestStroke(state, if state.strokes % 2 == 0 then 1 else -1)
		end
	end

	t.describe("Lake", function()
		t.it("query ma interfejs River: stojąca woda, promieniowy brzeg", function()
			local q = lake:query(Vector2.new(40, -20))
			t.expect(q.lateral).toBeCloseTo(30)
			t.expect(q.halfWidth).toBe(60)
			t.expect(q.normal.X).toBeCloseTo(1)
			t.expect(q.speed + q.curvature + q.level + q.overshoot + q.s).toBe(0)
			-- Ta sama zależność styczna → normal co w River
			t.expect(-q.tangent.Y).toBeCloseTo(q.normal.X)
			t.expect(q.tangent.X).toBeCloseTo(q.normal.Y)
			t.expect(lake:currentAt(q)).toBe(Vector2.zero)
			t.expect(#lake.falls).toBe(0)
		end)
		t.it("zapytanie dokładnie w środku nie daje NaN", function()
			local q = lake:query(lake.center)
			t.expect(q.normal.Magnitude).toBeCloseTo(1)
		end)
		t.it("RiverSampler i pointAt trafiają na jezioro", function()
			local point, q = RiverSampler.atFraction(lake, lake.length / 2, 0.5)
			t.expect(q.lateral).toBeLessThan(lake.radius)
			t.expect((point - lake.center).Magnitude).toBeCloseTo(30)
			t.expect((lake:pointAt(lake.length / 2) - lake.center).Magnitude).toBeCloseTo(0)
		end)
		t.it("kajak stoi bez wiosłowania i trzyma kurs", function()
			local state = KayakPhysics.new(lake.spawn, 1)
			run(state, 20)
			t.expect((state.position - lake.spawn).Magnitude).toBeLessThan(0.001)
			t.expect(state.heading).toBeCloseTo(1)
		end)
		t.it("wiosłowanie porusza, a potem kajak zwalnia", function()
			local from = lake.center + Vector2.new(-30, 30)
			local state = KayakPhysics.new(from, 0)
			run(state, 3, function()
				paddle(state)
			end)
			t.expect((state.position - from).Magnitude).toBeGreaterThan(15)
			local speed = state.velocity.Magnitude
			t.expect(speed).toBeGreaterThan(1)
			run(state, 5)
			t.expect(state.velocity.Magnitude).toBeLessThan(speed * 0.1)
		end)
		t.it("kajak nie wypływa za brzeg, z żadnego kierunku", function()
			for heading = 0, 5 do
				local state = KayakPhysics.new(lake.center + Vector2.new(0, 20), heading)
				local hits, worst = 0, 0
				run(state, 25, function()
					paddle(state)
					worst = math.max(worst, (state.position - lake.center).Magnitude)
					if state.lastHit > 0 then
						hits += 1
						state.lastHit = 0
					end
				end)
				t.expect(worst).toBeLessThan(lake.radius)
				t.expect(hits).toBeGreaterThan(0)
			end
		end)
		t.it("przeszkoda odbija kajak", function()
			local rock = lake.rocks[1]
			local state = KayakPhysics.new(rock.position + Vector2.new(-20, 0), 0)
			state.velocity = Vector2.new(25, 0)
			local nearest = math.huge
			run(state, 2, function()
				nearest = math.min(nearest, (state.position - rock.position).Magnitude)
			end)
			t.expect(nearest).toBeGreaterThan(rock.radius)
			t.expect(state.position.X).toBeLessThan(rock.position.X)
			t.expect(state.lastHit).toBeGreaterThan(0)
		end)
		t.it("miejsca startu leżą na wodzie i się nie nakładają", function()
			local problems = {}
			local small = { center = lake.center, radius = 30, spawn = Vector2.new(30, -20), heading = 0, obstacles = {} }
			for _, layout in { LakeLayout, small } do
				local water = Lake.new(layout)
				for slot = 1, Config.VILLAGE_KAYAK_SLOTS do
					local point = water:spawnPoint(slot)
					if (point - water.center).Magnitude + Config.HULL_REACH + Config.KAYAK_RADIUS >= water.radius then
						table.insert(problems, `miejsce {slot} przy brzegu`)
					end
				end
			end
			for slot = 1, Config.VILLAGE_KAYAK_SLOTS do
				for other = slot + 1, Config.VILLAGE_KAYAK_SLOTS do
					if (lake:spawnPoint(slot) - lake:spawnPoint(other)).Magnitude < Config.KAYAK_CONTACT then
						table.insert(problems, `miejsca {slot} i {other} się nakładają`)
					end
				end
			end
			t.expect(problems).toBeEmpty()
			t.expect(lake:spawnPoint(1 + Config.VILLAGE_KAYAK_SLOTS)).toBe(lake:spawnPoint(1))
		end)
		t.it("LakeLayout: start nie wypada w przeszkodzie", function()
			local water = Lake.new(LakeLayout)
			for _, rock in water.rocks do
				t.expect((water.spawn - rock.position).Magnitude).toBeGreaterThan(rock.radius + Config.KAYAK_RADIUS)
			end
		end)
	end)
end
