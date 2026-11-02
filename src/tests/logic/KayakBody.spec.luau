-- Skóra kajaka: bez szablonów (Lune nie ma ReplicatedStorage.LookAssets) zawsze powstaje stary kajak z części,
-- a każda część jest bez kolizji i bez masy, czyli wygląd nie może zmienić fizyki. Fizyka nie zna modułów wyglądu.

return function(t)
	local Cosmetics = require(t.shared.Cosmetics)
	local KayakBody = require(t.shared.KayakBody)

	t.describe("KayakBody", function()
		t.it("brak szablonu dowolnej skórki = klasyk z części w kolorze na powrót", function()
			for _, item in Cosmetics.list("kayak") do
				local look = Cosmetics.look({ kayak = item.id, paint = "paint_night" }, 1)
				local model = KayakBody.build(look)
				t.expect(model.Name).toBe(KayakBody.NAME)
				local paint = model:FindFirstChild("Paint")
				t.expect(paint ~= nil).toBe(true)
				t.expect(paint.Color).toBe(Cosmetics.item("paint_night").render.color)
			end
		end)

		t.it("części bez kolizji, dotyku, raycastów i masy, w limicie i w obudowie ok. 8 studs", function()
			local model = KayakBody.build(Cosmetics.look(nil, 3))
			local parts = KayakBody.parts(model)
			t.expect(#parts > 0 and #parts <= 14).toBe(true)
			local minZ, maxZ = math.huge, -math.huge
			for _, part in parts do
				t.expect(part.CanCollide).toBe(false)
				t.expect(part.CanTouch).toBe(false)
				t.expect(part.CanQuery).toBe(false)
				t.expect(part.Massless).toBe(true)
				local half = part.Size.Z / 2
				minZ = math.min(minZ, part.CFrame.Position.Z - half)
				maxZ = math.max(maxZ, part.CFrame.Position.Z + half)
			end
			local length = maxZ - minZ
			t.expect(length >= 7.5 and length <= 8.5).toBe(true)
		end)

		t.it("fizyka i sterowanie nie wymagają modułów wyglądu", function()
			local sources = { t.shared.KayakPhysics.Source, t.client.Controllers.KayakController.Source }
			for _, source in sources do
				t.expect(string.find(source, "KayakBody", 1, true)).toBe(nil)
				t.expect(string.find(source, "Cosmetics", 1, true)).toBe(nil)
			end
		end)
	end)
end
