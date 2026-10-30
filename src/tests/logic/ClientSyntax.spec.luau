-- Kontrolery potrzebują silnika, więc w Lune ich nie uruchamiamy, ale każdy skrypt klienta musi się chociaż kompilować.

return function(t)
	t.describe("skrypty klienta", function()
		t.it("wszystkie się kompilują", function()
			local problems = {}
			local items = t.client:GetDescendants()
			table.insert(items, t.client)
			for _, item in items do
				if item:IsA("LuaSourceContainer") then
					local chunk, err = loadstring(item.Source, item.Name)
					if chunk == nil then
						table.insert(problems, `{item.Name}: {err}`)
					end
				end
			end
			t.expect(problems).toBeEmpty()
		end)
	end)
end
