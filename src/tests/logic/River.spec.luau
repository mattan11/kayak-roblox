return function(t)
	local River = require(t.shared.River)
	local data = require(t.shared.content.rivers.Test)
	local river = River.new(data)

	t.describe("River", function()
		t.it("górska rzeka: skały w korycie i daleko od wodospadów, poziomy schodzą w dół", function()
			local mountain = River.new(require(t.shared.content.rivers.Mountain))
			local problems = {}
			for i, rock in mountain.rocks do
				local q = mountain:query(rock.position)
				if math.abs(q.lateral) + rock.radius > q.halfWidth then
					table.insert(problems, "skała poza korytem " .. i)
				end
				for _, fall in mountain.falls do
					if math.abs(fall.s - rock.s) < 30 then
						table.insert(problems, "skała przy wodospadzie " .. i)
					end
				end
			end
			t.expect(problems).toBeEmpty()
			t.expect(mountain:levelAt(0)).toBe(0)
			t.expect(mountain:levelAt(mountain.length)).toBe(-24)
		end)
		t.it("ma rozsądną długość", function()
			t.expect(river.length).toBeGreaterThan(2500)
			t.expect(river.length).toBeLessThan(4000)
		end)
		t.it("środek rzeki ma przesunięcie 0", function()
			local q = river:query(river:pointAt(1000))
			t.expect(q.lateral).toBeCloseTo(0, 0.01)
			t.expect(q.s).toBeCloseTo(1000, 0.5)
		end)
		t.it("skały leżą w korycie i zostawiają przejście", function()
			local problems = {}
			for i, rock in river.rocks do
				local q = river:query(rock.position)
				if math.abs(q.lateral) + rock.radius > q.halfWidth or q.halfWidth + math.abs(q.lateral) - rock.radius < 6 then
					table.insert(problems, "skała " .. i)
				end
			end
			t.expect(problems).toBeEmpty()
		end)
		t.it("nurt płynie w dół rzeki na środku", function()
			local q = river:query(river:pointAt(100))
			t.expect(river:currentAt(q):Dot(q.tangent)).toBeGreaterThan(8)
		end)
		t.it("przy brzegu nurt jest wolniejszy", function()
			local q = river:query(river:pointAt(100))
			local edge = river:query(river:pointAt(100) + q.normal * (q.halfWidth - 1))
			t.expect(river:currentAt(edge):Dot(q.tangent)).toBeLessThan(river:currentAt(q):Dot(q.tangent))
		end)
		t.it("na zakręcie znosi na zewnątrz", function()
			local checked = 0
			for s = 50, river.length - 50, 20 do
				local q = river:query(river:pointAt(s))
				local nearRock = false
				for _, rock in river.rocks do
					nearRock = nearRock or math.abs(rock.s - s) < 30
				end
				if math.abs(q.curvature) > 0.004 and not nearRock then
					checked += 1
					t.expect(river:currentAt(q):Dot(q.normal) * q.curvature).toBeLessThan(0)
				end
			end
			t.expect(checked).toBeGreaterThan(0)
		end)
		t.it("za skałą jest wir: woda płynie pod prąd", function()
			local rock = river.rocks[1]
			local radius = rock.radius * 2.2
			local q = river:query(rock.position)
			local eddy = river:query(rock.position + q.tangent * radius)
			t.expect(river:currentAt(eddy):Dot(q.tangent)).toBeLessThan(0)
		end)
	end)
end
