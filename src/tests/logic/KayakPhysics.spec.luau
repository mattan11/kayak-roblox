return function(t)
	local Config = require(t.shared.Config)
	local KayakPhysics = require(t.shared.KayakPhysics)
	local River = require(t.shared.River)
	local river = River.new(require(t.shared.content.rivers.Test))

	local function start(s: number?)
		local at = s or 100
		local q = river:query(river:pointAt(at))
		return KayakPhysics.new(river:pointAt(at), math.atan2(q.tangent.Y, q.tangent.X))
	end
	local function run(state, seconds: number, each: (() -> ())?)
		for _ = 1, math.floor(seconds * 60) do
			if each then
				each()
			end
			KayakPhysics.step(state, river, nil, 1 / 60)
		end
	end
	local function progress(state)
		return river:query(state.position).s
	end
	local function paddle(state)
		if state.queued == nil then
			KayakPhysics.requestStroke(state, if state.strokes % 2 == 0 then 1 else -1)
		end
	end

	t.describe("KayakPhysics", function()
		t.it("nurt sam niesie kajak", function()
			local state = start()
			run(state, 5)
			t.expect(progress(state)).toBeGreaterThan(35)
		end)
		t.it("wiosłowanie naprzemienne jest szybsze niż dryf", function()
			local drift, paddled = start(), start()
			run(drift, 8)
			run(paddled, 8, function()
				paddle(paddled)
			end)
			t.expect(progress(paddled)).toBeGreaterThan(progress(drift) + 30)
		end)
		t.it("lewe wiosło skręca w prawo", function()
			local state = start()
			local heading = state.heading
			run(state, 1.5, function()
				KayakPhysics.requestStroke(state, -1)
			end)
			t.expect(state.heading - heading).toBeGreaterThan(0.2)
		end)
		t.it("spam nie daje więcej machnięć niż pozwala czas", function()
			local state = start()
			run(state, 5, function()
				KayakPhysics.requestStroke(state, 1)
				KayakPhysics.requestStroke(state, -1)
			end)
			t.expect(state.strokes).toBeLessThan(5 / Config.STROKE_TIME + 2)
		end)
		t.it("wbicie wiosła zawraca", function()
			local state = start()
			run(state, 3, function()
				paddle(state)
			end)
			KayakPhysics.setBrace(state, 1)
			local turned, before = 0, state.heading
			run(state, 1.6, function()
				turned += (state.heading - before + math.pi) % (2 * math.pi) - math.pi
				before = state.heading
			end)
			t.expect(turned).toBeGreaterThan(math.pi * 0.7)
		end)
		t.it("wbicie hamuje względem wody", function()
			local braced, free = start(), start()
			braced.velocity = Vector2.new(0, -40)
			free.velocity = Vector2.new(0, -40)
			KayakPhysics.setBrace(braced, 1)
			run(braced, 0.5)
			run(free, 0.5)
			t.expect(braced.velocity.Magnitude).toBeLessThan(free.velocity.Magnitude)
		end)
		t.it("nie wypływa za brzeg, uderzenia są zgłaszane", function()
			local state = start()
			local hits, worst = 0, -math.huge
			run(state, 40, function()
				KayakPhysics.requestStroke(state, -1)
				local q = river:query(state.position, state.hint)
				worst = math.max(worst, math.abs(q.lateral) - q.halfWidth)
				if state.lastHit > 0 then
					hits += 1
					state.lastHit = 0
				end
			end)
			t.expect(worst).toBeLessThan(0)
			t.expect(hits).toBeGreaterThan(0)
		end)
		t.it("uderzenie rufą obraca kajak, a czołowe nie", function()
			local rock = river.rocks[1]
			local q = river:query(rock.position)
			local heading = math.atan2(q.tangent.Y, q.tangent.X)
			local forward = q.tangent
			local right = q.normal

			-- Rufa uderza w skałę bokiem: kajak obok skały, tył wchodzi w nią w poprzek rzeki
			local stern = KayakPhysics.new(rock.position + forward * Config.HULL_REACH - right * (rock.radius + Config.KAYAK_RADIUS + 0.05), heading)
			stern.velocity = right * 12
			KayakPhysics.step(stern, river, nil, 1 / 30)
			t.expect(math.abs(stern.spin)).toBeGreaterThan(0.3)

			-- Dziób prosto w skałę: siła idzie przez środek, obrót prawie żaden
			local bow = KayakPhysics.new(rock.position - forward * (Config.HULL_REACH + rock.radius + Config.KAYAK_RADIUS + 0.05), heading)
			bow.velocity = forward * 20
			KayakPhysics.step(bow, river, nil, 1 / 30)
			t.expect(math.abs(bow.spin)).toBeLessThan(0.2)
		end)
		t.it("na wodospadzie kajak spada i ląduje na niższej wodzie", function()
			local mountain = River.new(require(t.shared.content.rivers.Mountain))
			local fall = mountain.falls[1]
			local q = mountain:query(mountain:pointAt(fall.s - 15))
			local state = KayakPhysics.new(mountain:pointAt(fall.s - 15), math.atan2(q.tangent.Y, q.tangent.X))
			state.height = q.level
			local airborne, landed = false, false
			for _ = 1, 300 do
				KayakPhysics.step(state, mountain, nil, 1 / 60)
				airborne = airborne or state.fallSpeed > 0
				landed = landed or state.lastHit > 5
			end
			t.expect(airborne).toBe(true)
			t.expect(landed).toBe(true)
			t.expect(state.height).toBe(fall.level)
		end)
		t.it("bot płynie górską rzekę bez utknięcia", function()
			local mountain = River.new(require(t.shared.content.rivers.Mountain))
			local start0 = mountain:query(mountain:pointAt(Config.START_DISTANCE))
			local state = KayakPhysics.new(mountain:pointAt(Config.START_DISTANCE), math.atan2(start0.tangent.Y, start0.tangent.X))
			local elapsed = 0
			while elapsed < 300 do
				local q = mountain:query(state.position, state.hint)
				if q.s >= mountain.length - Config.FINISH_MARGIN then
					break
				end
				local target = mountain:pointAt(math.min(q.s + 25, mountain.length)) - state.position
				local want = math.atan2(target.Y, target.X)
				local err = (want - state.heading + math.pi) % (2 * math.pi) - math.pi
				KayakPhysics.setBrace(state, if math.abs(err) > 0.7 then (if err > 0 then 1 else -1) else nil)
				if state.queued == nil and state.brace == nil then
					if math.abs(err) > 0.15 then
						KayakPhysics.requestStroke(state, if err > 0 then -1 else 1)
					else
						paddle(state)
					end
				end
				KayakPhysics.step(state, mountain, nil, 1 / 30)
				elapsed += 1 / 30
			end
			print("[bot górski] czas", elapsed, "machnięć", state.strokes)
			t.expect(elapsed).toBeLessThan(240)
		end)
		t.it("ogłuszony kajak nie wiosłuje i płynie z prądem", function()
			local stunned, drift = start(), start()
			stunned.stunUntil = os.clock() + 60
			run(stunned, 4, function()
				paddle(stunned)
			end)
			run(drift, 4)
			t.expect(stunned.strokes).toBe(0)
			t.expect(stunned.strokeSide).toBe(nil)
			t.expect(math.abs(progress(stunned) - progress(drift))).toBeLessThan(0.5)
		end)
		t.it("ogłuszenie przerywa trwające machnięcie", function()
			local state = start()
			KayakPhysics.requestStroke(state, 1)
			run(state, 0.2)
			t.expect(state.strokeSide).toBe(1)
			state.stunUntil = os.clock() + 60
			run(state, 0.1)
			t.expect(state.strokeSide).toBe(nil)
		end)
		t.it("ogłuszony nie hamuje wbiciem, ale wbicie zostaje na czas po ogłuszeniu", function()
			local braced, free = start(), start()
			braced.velocity = Vector2.new(0, -40)
			free.velocity = Vector2.new(0, -40)
			braced.stunUntil = os.clock() + 60
			free.stunUntil = braced.stunUntil
			KayakPhysics.setBrace(braced, 1)
			run(braced, 0.5)
			run(free, 0.5)
			t.expect((braced.position - free.position).Magnitude).toBeLessThan(0.01)
			t.expect(braced.brace).toBe(1)
			braced.stunUntil = 0
			free.stunUntil = 0
			run(braced, 0.5)
			run(free, 0.5)
			t.expect(braced.velocity.Magnitude).toBeLessThan(free.velocity.Magnitude)
		end)
		t.it("po ogłuszeniu kajak znów wiosłuje", function()
			local state = start()
			state.stunUntil = os.clock() - 1
			KayakPhysics.requestStroke(state, 1)
			run(state, 0.1)
			t.expect(state.strokes).toBe(1)
		end)
		t.it("przyspieszenie mocniej ciągnie, tylko gdy trwa", function()
			local boosted, normal, expired = start(), start(), start()
			boosted.boostUntil = os.clock() + 60
			expired.boostUntil = os.clock() - 1
			for _, state in { boosted, normal, expired } do
				run(state, 4, function()
					paddle(state)
				end)
			end
			t.expect(progress(boosted)).toBeGreaterThan(progress(normal) + 2)
			t.expect(progress(expired)).toBe(progress(normal))
		end)
		t.it("wynik nie zależy od FPS", function()
			local a, b = start(), start()
			for _ = 1, 120 do
				KayakPhysics.step(a, river, nil, 1 / 60)
			end
			for _ = 1, 40 do
				KayakPhysics.step(b, river, nil, 1 / 20)
			end
			t.expect((a.position - b.position).Magnitude).toBeLessThan(1)
		end)
		t.it("dryf bez wiosłowania jest dużo wolniejszy od bota", function()
			local state = start(Config.START_DISTANCE)
			local elapsed = 0
			while elapsed < 400 and progress(state) < river.length - Config.FINISH_MARGIN do
				KayakPhysics.step(state, river, nil, 1 / 30)
				elapsed += 1 / 30
			end
			print("[dryf] czas", elapsed)
			t.expect(elapsed).toBeGreaterThan(170)
		end)
		t.it("bot płynący środkiem kończy rzekę w 90–170 s", function()
			local state = start(Config.START_DISTANCE)
			local elapsed = 0
			while elapsed < 300 and progress(state) < river.length - Config.FINISH_MARGIN do
				local q = river:query(state.position, state.hint)
				local target = river:pointAt(math.min(q.s + 35, river.length)) - state.position
				local want = math.atan2(target.Y, target.X)
				local err = (want - state.heading + math.pi) % (2 * math.pi) - math.pi
				if state.queued == nil then
					if math.abs(err) > 0.15 then
						KayakPhysics.requestStroke(state, if err > 0 then -1 else 1)
					else
						paddle(state)
					end
				end
				KayakPhysics.step(state, river, nil, 1 / 30)
				elapsed += 1 / 30
			end
			print("[bot] czas", elapsed, "machnięć", state.strokes)
			t.expect(elapsed).toBeGreaterThan(90)
			t.expect(elapsed).toBeLessThan(170)
		end)
	end)
end
