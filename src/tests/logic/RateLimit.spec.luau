-- Limit zapytań (token bucket): przepuszcza do `burst` naraz, potem w tempie `rate`/s, osobno dla każdego gracza.

return function(t)
	local RateLimit = require(t.shared.RateLimit)

	t.describe("RateLimit", function()
		t.it("przepuszcza burst, potem odrzuca", function()
			local limiter = RateLimit.new()
			local passed = 0
			for _ = 1, 10 do
				if limiter:allow("p1", "Build", 2, 5, 0) then passed += 1 end
			end
			t.expect(passed).toBe(5)
		end)
		t.it("dolewa żetony z czasem", function()
			local limiter = RateLimit.new()
			for _ = 1, 5 do limiter:allow("p1", "Build", 2, 5, 0) end
			t.expect(limiter:allow("p1", "Build", 2, 5, 0)).toBe(false)
			t.expect(limiter:allow("p1", "Build", 2, 5, 0.6)).toBe(true) -- 0,6 s × 2/s = 1,2 żetonu
		end)
		t.it("gracze i zdarzenia mają osobne wiadra", function()
			local limiter = RateLimit.new()
			for _ = 1, 5 do limiter:allow("p1", "Build", 2, 5, 0) end
			t.expect(limiter:allow("p2", "Build", 2, 5, 0)).toBe(true)
			t.expect(limiter:allow("p1", "Sell", 2, 5, 0)).toBe(true)
		end)
		t.it("forget czyści gracza", function()
			local limiter = RateLimit.new()
			for _ = 1, 5 do limiter:allow("p1", "Build", 2, 5, 0) end
			limiter:forget("p1")
			t.expect(limiter:allow("p1", "Build", 2, 5, 0)).toBe(true)
		end)
	end)
end
