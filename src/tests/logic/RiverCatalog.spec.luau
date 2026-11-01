-- Katalog rzek: 7 pozycji o różnych id, podział trudności, każda rzeka ma plik z danymi.

return function(t)
	local RiverCatalog = require(t.shared.content.RiverCatalog)

	t.describe("RiverCatalog", function()
		t.it("ma 7 pozycji o różnych id: 3 łatwe, 2 średnie, 2 trudne", function()
			t.expect(#RiverCatalog).toBe(7)
			local seen, counts = {}, {}
			for _, entry in RiverCatalog do
				t.expect(seen[entry.id]).toBe(nil)
				seen[entry.id] = true
				counts[entry.difficulty] = (counts[entry.difficulty] or 0) + 1
			end
			t.expect(counts["Łatwa"]).toBe(3)
			t.expect(counts["Średnia"]).toBe(2)
			t.expect(counts["Trudna"]).toBe(2)
		end)

		t.it("wszystkie są dostępne, pod swoimi nazwami i z plikami tras", function()
			local labels = {}
			for _, entry in RiverCatalog do
				t.expect(entry.available).toBe(true)
				t.expect(entry.river).toBe(entry.id)
				local module = t.shared.content.rivers:FindFirstChild(entry.river)
				t.expect(module ~= nil).toBe(true)
				t.expect(require(module).id).toBe(entry.id) -- `id` trasy to też nazwa rankingu Times_<id>
				labels[entry.id] = entry.label
			end
			t.expect(labels.Test).toBe("Leśna Struga")
			t.expect(labels.Mountain).toBe("Górski Potok")
		end)
	end)
end
