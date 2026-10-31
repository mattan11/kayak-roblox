-- Miniaturka rzeki: mieści się w prostokącie, dłuższa oś w poziomie, start po lewej, odcinki stykają się końcami.

return function(t)
	local River = require(t.shared.River)
	local RiverThumbnail = require(t.shared.RiverThumbnail)
	local Mountain = require(t.shared.content.rivers.Mountain)

	local BOX = { width = 160, height = 96, padding = 8, maxStretch = 3 }

	-- Końce odcinka policzone tak, jak zobaczy je obrócony Frame.
	local function ends(segment: any): (Vector2, Vector2)
		local radians = math.rad(segment.rotation)
		local half = Vector2.new(math.cos(radians), math.sin(radians)) * (segment.length / 2)
		local center = Vector2.new(segment.x, segment.y)
		return center - half, center + half
	end

	local function expectInside(point: Vector2)
		local slack = 1e-6
		t.expect(point.X >= BOX.padding - slack and point.X <= BOX.width - BOX.padding + slack).toBe(true)
		t.expect(point.Y >= BOX.padding - slack and point.Y <= BOX.height - BOX.padding + slack).toBe(true)
	end

	t.describe("RiverThumbnail.layout", function()
		t.it("poziomy odcinek wypełnia szerokość i leży na środku wysokości", function()
			local layout = RiverThumbnail.layout({ Vector2.new(0, 5), Vector2.new(100, 5) }, {}, BOX)
			t.expect(#layout.segments).toBe(1)
			local segment = layout.segments[1]
			t.expect(segment.length).toBeCloseTo(144)
			t.expect(segment.x).toBeCloseTo(80)
			t.expect(segment.y).toBeCloseTo(48)
			t.expect(segment.rotation).toBeCloseTo(0)
		end)

		t.it("rzeka płynąca wzdłuż Z też leży poziomo, start po lewej", function()
			local layout = RiverThumbnail.layout({ Vector2.new(0, 0), Vector2.new(0, -500) }, {}, BOX)
			local first, last = ends(layout.segments[1])
			t.expect(first.X).toBeCloseTo(8)
			t.expect(last.X).toBeCloseTo(152)
			t.expect(first.Y).toBeCloseTo(48)
		end)

		t.it("odcinki stykają się końcami", function()
			local points = { Vector2.new(0, 0), Vector2.new(30, 40), Vector2.new(90, 10), Vector2.new(120, 70) }
			local layout = RiverThumbnail.layout(points, {}, BOX)
			t.expect(#layout.segments).toBe(3)
			for i = 2, #layout.segments do
				local _, previousEnd = ends(layout.segments[i - 1])
				local nextStart = ends(layout.segments[i])
				t.expect((previousEnd - nextStart).Magnitude).toBeCloseTo(0)
			end
		end)

		t.it("maxStretch ogranicza rozciąganie osi poprzecznej", function()
			local points = { Vector2.new(0, 0), Vector2.new(1000, 0), Vector2.new(1000, 10) }
			local faithful = RiverThumbnail.layout(points, {}, { width = 160, height = 96, padding = 8, maxStretch = 1 })
			local stretched = RiverThumbnail.layout(points, {}, BOX)
			t.expect(faithful.segments[2].length).toBeCloseTo(1.44)
			t.expect(stretched.segments[2].length).toBeCloseTo(4.32)
		end)

		t.it("kropka trafia w to samo miejsce co punkt przebiegu", function()
			local points = { Vector2.new(0, 0), Vector2.new(50, 20), Vector2.new(100, 0) }
			local layout = RiverThumbnail.layout(points, { points[2] }, BOX)
			local _, joint = ends(layout.segments[1])
			t.expect(layout.dots[1].x).toBeCloseTo(joint.X)
			t.expect(layout.dots[1].y).toBeCloseTo(joint.Y)
		end)

		t.it("mniej niż 2 punkty i punkty w jednym miejscu nie wybuchają", function()
			t.expect(#RiverThumbnail.layout({}, {}, BOX).segments).toBe(0)
			t.expect(#RiverThumbnail.layout({ Vector2.new(1, 1) }, {}, BOX).segments).toBe(0)
			t.expect(#RiverThumbnail.layout({ Vector2.new(1, 1), Vector2.new(1, 1) }, {}, BOX).segments).toBe(0)
		end)
	end)

	t.describe("RiverThumbnail.sample", function()
		t.it("prawdziwa rzeka: tyle odcinków, ile próbek, wodospady jako kropki, wszystko w ramce", function()
			local river = River.new(Mountain)
			local points, marks = RiverThumbnail.sample(river, 28)
			t.expect(#points).toBe(29)
			t.expect(#marks).toBe(#river.falls)

			local layout = RiverThumbnail.layout(points, marks, BOX)
			t.expect(#layout.segments).toBe(28)
			t.expect(#layout.dots).toBe(#river.falls)
			for _, segment in layout.segments do
				local first, last = ends(segment)
				expectInside(first)
				expectInside(last)
			end
			for _, dot in layout.dots do
				expectInside(Vector2.new(dot.x, dot.y))
			end
			local start = ends(layout.segments[1])
			local _, finish = ends(layout.segments[#layout.segments])
			t.expect(start.X).toBeLessThan(finish.X)
		end)
	end)
end
