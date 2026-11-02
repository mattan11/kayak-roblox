-- Katalog wyglądu: unikalne id, znane sloty i pola, jeden domyślny na slot, progi gwiazdek w zasięgu, skórki z decyzji Marka.

return function(t)
	local Cosmetics = require(t.shared.Cosmetics)
	local CosmeticCatalog = require(t.shared.content.CosmeticCatalog)

	local ALLOWED = { id = true, slot = true, label = true, render = true, unlock = true, hidden = true, order = true }
	local SLOTS = { kayak = true, paint = true }

	t.describe("CosmeticCatalog", function()
		t.it("id są unikalne, a sloty i pola znane", function()
			local seen = {}
			for _, item in CosmeticCatalog do
				t.expect(type(item.id)).toBe("string")
				t.expect(seen[item.id]).toBe(nil)
				seen[item.id] = true
				t.expect(SLOTS[item.slot]).toBe(true)
				t.expect(type(item.label)).toBe("string")
				for key in item do
					if not ALLOWED[key] then
						error(`{item.id}: niedozwolone pole '{key}'`)
					end
				end
			end
		end)

		t.it("każdy slot z Cosmetics.SLOTS ma dokładnie jedną pozycję domyślną", function()
			for _, slot in Cosmetics.SLOTS do
				local count = 0
				for _, item in CosmeticCatalog do
					if item.slot == slot and item.unlock.kind == "default" then
						count += 1
					end
				end
				t.expect(count).toBe(1)
			end
			t.expect(Cosmetics.default("kayak")).toBe("kayak_classic")
			t.expect(Cosmetics.default("paint")).toBe("paint_auto")
		end)

		t.it("warunki są znane, a progi gwiazdek mieszczą się w 0..max", function()
			local max = Cosmetics.maxStars()
			t.expect(max).toBe(21)
			for _, item in CosmeticCatalog do
				local kind = item.unlock.kind
				t.expect(kind == "default" or kind == "stars" or kind == "robux").toBe(true)
				if kind == "stars" then
					t.expect(type(item.unlock.min)).toBe("number")
					t.expect(item.unlock.min >= 0 and item.unlock.min <= max).toBe(true)
				end
				if kind == "robux" then
					t.expect(item.hidden).toBe(true) -- płatności nie ma w v1
				end
			end
		end)

		t.it("skórki kajaków: szablony i progi z decyzji Marka, kolor tylko na klasyku", function()
			local expected = {
				kayak_classic = { "KayakClassic", nil },
				kayak_round = { "KayakRound", 1 },
				kayak_duck = { "KayakDuck", 3 },
				kayak_racer = { "KayakRacer", 4 },
				kayak_shark = { "KayakShark", 6 },
				kayak_rocket = { "KayakRocket", 10 },
				kayak_icebreaker = { "KayakIcebreaker", 8 },
				kayak_neon = { "KayakNeon", 12 },
				kayak_phoenix = { "KayakPhoenix", 14 },
				kayak_gold = { "KayakGold", 16 },
				kayak_kraken = { "KayakKraken", 18 },
				kayak_ice_dragon = { "KayakIceDragon", 20 },
				kayak_dragon = { "KayakDragon", 21 },
			}
			local count = 0
			for _, item in CosmeticCatalog do
				if item.slot == "kayak" then
					count += 1
					local entry = expected[item.id]
					t.expect(entry ~= nil).toBe(true)
					t.expect(item.render.kind).toBe("model")
					t.expect(item.render.template).toBe(entry[1])
					t.expect(item.render.paintable).toBe(item.id == "kayak_classic")
					t.expect(typeof(item.render.swatch)).toBe("Color3")
					t.expect(if item.unlock.kind == "stars" then item.unlock.min else nil).toBe(entry[2])
				end
			end
			t.expect(count).toBe(13)
		end)

		t.it("kolory: auto domyślny i 6–8 kolorów z tanimi progami (0–5 gwiazdek)", function()
			local colors = 0
			for _, item in CosmeticCatalog do
				if item.slot == "paint" and item.id ~= "paint_auto" then
					colors += 1
					t.expect(item.render.kind).toBe("color")
					t.expect(typeof(item.render.color)).toBe("Color3")
					t.expect(item.unlock.kind).toBe("stars")
					t.expect(item.unlock.min <= 5).toBe(true)
				end
			end
			t.expect(colors >= 6 and colors <= 8).toBe(true)
		end)
	end)
end
