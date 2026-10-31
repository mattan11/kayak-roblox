-- Układ jeziora: przeszkody mieszczą się w wodzie i nie blokują startu ani strefy kolejki.

return function(t)
	local LakeLayout = require(t.shared.content.LakeLayout)

	t.describe("LakeLayout", function()
		t.it("start, strefa i przeszkody leżą w jeziorze", function()
			local edge = LakeLayout.radius
			t.expect((LakeLayout.spawn - LakeLayout.center).Magnitude < edge / 2).toBe(true)
			t.expect((LakeLayout.zone.position - LakeLayout.center).Magnitude + LakeLayout.zone.radius < edge).toBe(true)
			for _, obstacle in LakeLayout.obstacles do
				t.expect((obstacle.position - LakeLayout.center).Magnitude + obstacle.radius < edge).toBe(true)
			end
		end)

		t.it("przeszkody są z dala od startu i strefy, i nie nachodzą na siebie", function()
			for index, obstacle in LakeLayout.obstacles do
				t.expect((obstacle.position - LakeLayout.spawn).Magnitude > 15).toBe(true)
				t.expect((obstacle.position - LakeLayout.zone.position).Magnitude > LakeLayout.zone.radius + obstacle.radius).toBe(true)
				for other = index + 1, #LakeLayout.obstacles do
					t.expect((obstacle.position - LakeLayout.obstacles[other].position).Magnitude > 10).toBe(true)
				end
			end
		end)

		t.it("dziób na starcie patrzy na strefę", function()
			local forward = Vector2.new(math.cos(LakeLayout.heading), math.sin(LakeLayout.heading))
			local toZone = (LakeLayout.zone.position - LakeLayout.spawn).Unit
			t.expect(forward:Dot(toZone) > 0.999).toBe(true)
		end)
	end)
end
