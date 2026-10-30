-- Odwrotność River:query: efekty losują punkty we współrzędnych rzecznych.

return function(t)
	local River = require(t.shared.River)
	local RiverSampler = require(t.client.logic.RiverSampler)
	local river = River.new(require(t.shared.content.rivers.Test))

	t.describe("RiverSampler", function()
		t.it("at trafia w zadane s i lateral", function()
			for _, s in { 50, 700, 1500, 2600 } do
				local _, q = RiverSampler.at(river, s, 5)
				t.expect(q.s).toBeCloseTo(s, 1)
				t.expect(q.lateral).toBeCloseTo(5, 1)
			end
		end)
		t.it("atFraction: ±1 to brzegi", function()
			local _, q = RiverSampler.atFraction(river, 1000, 1)
			t.expect(q.lateral).toBeCloseTo(q.halfWidth, 1)
		end)
		t.it("nie wychodzi poza rzekę", function()
			local _, before = RiverSampler.at(river, -50, 0)
			local _, after = RiverSampler.at(river, river.length + 50, 0)
			t.expect(before.s).toBeCloseTo(0, 0.5)
			t.expect(after.s).toBeCloseTo(river.length, 0.5)
		end)
	end)
end
