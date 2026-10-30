-- Mini-zestaw testowy w stylu Jest: describe / it / expect. Bez pakietów — ~80 linii, które w pełni rozumiemy.
-- Plik testów (*.spec) zwraca funkcję, która dostaje `t` (to API + foldery z kodem gry), np.:
--   return function(t)
--       local CombatMath = require(t.shared.CombatMath)
--       t.describe("CombatMath", function()
--           t.it("trafia okrąg na torze", function()
--               t.expect(CombatMath.segmentHitsCircle(a, b, c, 1)).toBe(true)
--           end)
--       end)
--   end
-- Błąd w `it` (nieudane expect albo wyjątek w kodzie gry) = test ✗, reszta testów leci dalej.
-- t.warn("...") = znany brak (np. biom bez muzyki): widać go w raporcie jako ⚠, ale test nie jest oblany.

local Spec = {}

export type Result = { name: string, ok: boolean, message: string?, warnings: { string }? }

-- Ładny zapis wartości w komunikacie błędu (tabele: pierwsze elementy, jak console.log).
local function show(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) == "table" then
		local parts = {}
		for key, item in value do
			if #parts >= 8 then
				table.insert(parts, "…")
				break
			end
			table.insert(parts, if type(key) == "number" then show(item) else tostring(key) .. " = " .. show(item))
		end
		return "{ " .. table.concat(parts, ", ") .. " }"
	end
	return tostring(value)
end

-- expect(x).toBe(y) — jak w Jest. Rzuca błąd z czytelnym opisem, gdy warunek nie jest spełniony.
function Spec.expect(actual: any)
	local function check(ok: boolean, message: string)
		if not ok then
			error(message, 3)
		end
	end
	return {
		toBe = function(expected: any)
			check(actual == expected, string.format("oczekiwano %s, jest %s", show(expected), show(actual)))
		end,
		toBeCloseTo = function(expected: number, tolerance: number?)
			local tol = tolerance or 1e-3
			check(math.abs(actual - expected) <= tol, string.format("oczekiwano ≈%s (±%s), jest %s", show(expected), tol, show(actual)))
		end,
		toBeGreaterThan = function(limit: number)
			check(actual > limit, string.format("oczekiwano > %s, jest %s", show(limit), show(actual)))
		end,
		toBeLessThan = function(limit: number)
			check(actual < limit, string.format("oczekiwano < %s, jest %s", show(limit), show(actual)))
		end,
		toBeTruthy = function()
			check(not not actual, string.format("oczekiwano prawdy, jest %s", show(actual)))
		end,
		-- Dla testów danych: lista znalezionych problemów ma być pusta (komunikat wypisuje je wszystkie).
		toBeEmpty = function()
			check(next(actual) == nil, string.format("%d problem(ów):\n      - %s", #actual, table.concat(actual, "\n      - ")))
		end,
	}
end

-- Tworzy `t` dla jednego pliku testów; wyniki trafiają do `results`.
function Spec.new(results: { Result }, fileName: string, extra: { [string]: any })
	local prefix = { fileName }
	local t = table.clone(extra)
	t.expect = Spec.expect
	t.describe = function(name: string, body: () -> ())
		table.insert(prefix, name)
		body()
		table.remove(prefix)
	end
	local warnings: { string } = {}
	t.warn = function(message: string)
		table.insert(warnings, message)
	end
	t.it = function(name: string, body: () -> ())
		local fullName = table.concat(prefix, " › ") .. " › " .. name
		warnings = {}
		local ok, err = pcall(body)
		table.insert(results, { name = fullName, ok = ok, message = if ok then nil else tostring(err), warnings = warnings })
	end
	return t
end

return Spec
