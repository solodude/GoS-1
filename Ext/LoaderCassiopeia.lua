if myHero.charName ~= "Cassiopeia" then return end
--print("hello")



local Q = {Range = 850,Delay = 0.6, Radius = 60, Speed = math.huge,Type = "Circle"}
local W = {Range = 800,Delay = 0.5, Radius = 90, Speed = 3000,Type = "Circle"}
local E = {Range = 700}
local R = {Range = 825,Delay = 0.6, Radius = 80, Speed = math.huge, Angle = 40}

local LastQ = 0

local function isReady(slot)
	return Game.CanUseSpell(slot) == READY
end

local function CalcMagicalDamage(source, target, amount)
  local mr = target.magicResist
  local value = 100 / (100 + (mr * source.magicPenPercent) - source.magicPen)

  if mr < 0 then
    value = 2 - 100 / (100 - mr)
  elseif (mr * source.magicPenPercent) - source.magicPen < 0 then
    value = 1
  end
  return value * amount
end
local function GetDistanceSqr(p1, p2)
    assert(p1, "GetDistance: invalid argument: cannot calculate distance to "..type(p1))
    p2 = p2 or myHero.pos
    return (p1.x - p2.x) ^ 2 + ((p1.z or p1.y) - (p2.z or p2.y)) ^ 2
end

local function GetDistance(p1, p2)
    return math.sqrt(GetDistanceSqr(p1, p2))
end

local function ValidTarget(unit,range,from)
	from = from or myHero.pos
	range = range or math.huge
	return unit and unit.valid and not unit.dead and unit.visible and unit.isTargetable and GetDistanceSqr(unit.pos,from) <= range*range
end



class "Cassiopeia"

function Cassiopeia:__init()
	self.Ts = ExtLib.TargetSelector
	self.Pred = ExtLib.Prediction
	if not self.Pred then print("ExtLib is outdated. Please update script") end
	self.Ts:PresetMode("LESS_CAST")
	
	self.Allies = {}
	self.Enemies = {}
	for i = 1,Game.HeroCount() do
		local hero = Game.Hero(i)
		if hero.isAlly then
			table.insert(self.Allies,hero)
		else
			table.insert(self.Enemies,hero)
		end	
	end	
	self:LoadMenu()
	
	OnActiveMode(function(...) self:OnActiveMode(...) end)
	Callback.Add("Tick",function() self:Tick() end)
	Callback.Add("Draw",function() self:Draw() end)
end

function Cassiopeia:LoadMenu()
	self.Menu = MenuElement({type = MENU,id = "ExtLib: "..myHero.charName,name = myHero.charName, leftIcon = "http://ddragon.leagueoflegends.com/cdn/7.1.1/img/champion/Cassiopeia.png"})
	
	self.Menu:MenuElement({type = MENU,id = "Combo",name = "Combo Settings"})
	self.Menu.Combo:MenuElement({id = "UseQ",name = "Use Q",value = true})
	self.Menu.Combo:MenuElement({id = "UseW",name = "Use W",value = true})
	self.Menu.Combo:MenuElement({id = "UseE",name = "Use E",value = true})
	self.Menu.Combo:MenuElement({id = "UseR",name = "Use R",value = true})
	self.Menu.Combo:MenuElement({id = "AutoR",name = "Use R if hit x enemies",value = 2, min = 1, max = 5, step = 1})
	
	self.Menu:MenuElement({type = MENU,id = "Harass",name = "Harass Settings"})
	self.Menu.Harass:MenuElement({id = "UseQ",name = "Use Q",value = true})
	self.Menu.Harass:MenuElement({id = "UseW",name = "Use W",value = false})
	self.Menu.Harass:MenuElement({id = "UseE",name = "Use E",value = true})
	self.Menu.Harass:MenuElement({id = "ELastHit",name = "Use E LastHit",value = true})
	self.Menu.Harass:MenuElement({id = "MinMana",name = "Don't use spells if mana is lower than",value = 70,min = 0,max = 100, step = 1})
	
	self.Menu:MenuElement({type = MENU,id = "LastHit",name = "LastHit Settings"})
	self.Menu.LastHit:MenuElement({id = "UseQ",name = "Use Q",value = false})
	self.Menu.LastHit:MenuElement({id = "UseE",name = "Use E",value = true})
	
	self.Menu:MenuElement({type = MENU,id = "LaneClear",name = "LaneClear Settings"})
	self.Menu.LaneClear:MenuElement({id = "Enable",name = "Enable",value = true,key = string.byte("T"), toggle = true})
	self.Menu.LaneClear:MenuElement({id = "UseQ",name = "Use Q",value = true})
	self.Menu.LaneClear:MenuElement({id = "UseW",name = "Use W",value = false})
	self.Menu.LaneClear:MenuElement({id = "UseE",name = "Use E",value = true})
	self.Menu.LaneClear:MenuElement({id = "MinMana",name = "Don't use spells if mana is lower than",value = 30,min = 0,max = 100, step = 1})
	
	self.Menu:MenuElement({type = MENU,id = "Drawing",name = "Drawing Settings"})
	self.Menu.Drawing:MenuElement({id = "DrawQ",name = "Draw Q Range",value = true})
	self.Menu.Drawing:MenuElement({id = "DrawW",name = "Draw W Range",value = false})
	self.Menu.Drawing:MenuElement({id = "DrawE",name = "Draw E Range",value = true})
	self.Menu.Drawing:MenuElement({id = "DrawR",name = "Draw R Range",value = true})
end

function Cassiopeia:IsPoisonedTarget(unit)
	for i = 0, unit.buffCount do
		local buff = unit:GetBuff(i)
		if buff.count > 0 and (buff.name == "cassiopeiaqdebuff" or buff.name == "cassiopeiawpoison")  then 
			return true
		end
	end
	return false
end

function Cassiopeia:GetETarget()
	local target = nil
	local N = 1000
	for i, enemy in pairs(self.Enemies) do
		if ValidTarget(enemy,E.Range) and not self:IsInvulnerableTarget(enemy) and self:IsPoisonedTarget(enemy) then
			local tokill = enemy.health/CalcMagicalDamage(myHero,enemy,100)
			if tokill < N then
				N = tokill
				target = enemy
			end
		end
	end
	return target
end

function Cassiopeia:GetDamage(spell,unit,poison)
	if spell == "E" then
		local base = 48 + myHero.levelData.lvl*4 + myHero.ap*0.1 
		if poison or self:IsPoisonedTarget(unit)  then	
			local bonus = ({10, 40, 70, 100, 130})[myHero:GetSpellData(_E).level] + myHero.ap*0.35
			return CalcMagicalDamage(myHero,unit, base + bonus)	
		else
			return CalcMagicalDamage(myHero,unit, base)	
		end
	elseif spell == "Q"	 then
		local dmg = ({75, 120, 165, 210, 255})[myHero:GetSpellData(_Q).level] + 0.7 * myHero.ap
		return CalcMagicalDamage(myHero,unit, dmg)	
	elseif spell == "R"	 then
		local dmg = ({150, 250, 350})[myHero:GetSpellData(_R).level] + 0.5 * myHero.ap
		return CalcMagicalDamage(myHero,unit, dmg)	
	end	
end

function Cassiopeia:CastQ(target)
	local CastPosition, Hitchance = self.Pred:GetPrediction(target,Q)
	if Hitchance == "High" then
		--LastPos = CastPosition
		SpellCast:CastSpell(HK_Q,CastPosition,0.7)
	end
end

function Cassiopeia:CastW(target)
	local CastPosition, Hitchance = self.Pred:GetPrediction(target,W)
	if Hitchance == "High" and GetDistanceSqr(CastPosition,myHero.pos) > 400*400 then
		SpellCast:CastSpell(HK_W,CastPosition)
	end
end

function Cassiopeia:CastE(target)
	--Control.CastSpell(HK_E,target)
	SpellCast:CastSpell(HK_E,target.pos)
end

function Cassiopeia:CastR(target)
	local CastPosition, Hitchance = self.Pred:GetPrediction(target,R)
	if Hitchance == "High" then
		SpellCast:CastSpell(HK_R,CastPosition)
	end
end

function Cassiopeia:CanR(target)
	local p1 = (target.pos - myHero.pos):Normalized()
	p1 = Point2(p1.x,p1.z)
	local p2 = target.dir
	p2 = Point2(p2.x,p2.z)
	if p1:angleBetween(p2) > 100 then
		return true
	end
	return false
end

function Cassiopeia:IsKillable(target)
	local totalDmg = 0
	local qDmg = self:GetDamage("Q",target)
	local eDmg = self:GetDamage("E",target,true)
	local rDmg  = self:GetDamage("R",target)
	if isReady(0) then
		totalDmg  = totalDmg + qDmg
	end
	--if isReady(2) then
		totalDmg = totalDmg + eDmg*3
	--end
	if totalDmg < target.health and totalDmg + rDmg + 1.5*eDmg > target.health then 
		return true
	end
	return false
end

function Cassiopeia:OnActiveMode(OW,Minions)
	if OW.Mode == "Combo" then
		self:Combo(OW,Minions)
		OW.enableAttack = true
	elseif 	OW.Mode == "LastHit" then
		OW.enableAttack = true
		self:LastHit(OW,Minions)
	elseif 	OW.Mode == "LaneClear" then	
		OW.enableAttack = true
		self:LaneClear(OW,Minions)
		self:JungleClear(OW,Minions)
	elseif OW.Mode == "Harass" then		
		OW.enableAttack = true
		self:Harass(OW,Minions)
	end
	OW.enableAttack = true
end

function Cassiopeia:Combo(OW,Minions)
	local useq = self.Menu.Combo.UseQ:Value()
	local usew = self.Menu.Combo.UseW:Value()
	local usee = self.Menu.Combo.UseE:Value()
	local user = self.Menu.Combo.UseR:Value()
	for i,enemy in pairs(self.Enemies) do
		if ValidTarget(enemy,Q.Range) and self:GetDamage("Q",enemy) > enemy.health and isReady(0) then
			self:CastQ(enemy)
			return
		end
		if ValidTarget(enemy,E.Range) and isReady(2) and self:GetDamage("E",enemy) > enemy.health and not isReady(0) then
			self:CastE(enemy)
			return
		end
	end
	if user and isReady(3) then
		local rTarget = self.Ts:GetTarget(650)
		if rTarget and not self:IsKillable(rTarget) and self:CanR(rTarget) then
			
			self:CastR(rTarget)
	
		end
	end
	
	local etarget = self:GetETarget()
	if etarget then
		if myHero.totalDamage < etarget.health then
			OW.enableAttack = false
		else
			OW.enableAttack = true
		end
		if isReady(2) then
			self:CastE(etarget)
			return
		end	
	end	
	local qTarget = self.Ts:GetTarget(Q.Range)
	if qTarget then
		if isReady(0) and useq then
			LastQ = os.clock()
			self:CastQ(qTarget)
			return
		end
		if not isReady(0) and isReady(1) and usew and not self:IsPoisonedTarget(qTarget) and os.clock() - LastQ > 1 then
			self:CastW(qTarget)
			return
		end
	end

end

function Cassiopeia:Harass(OW,Minions)
	
	local elasthit = self.Menu.Harass.ELastHit:Value()
	local useq = self.Menu.Harass.UseQ:Value()
	local usee = self.Menu.Harass.UseE:Value()
	if isReady(2) and elasthit then
	for i,minion in pairs(Minions[1]) do
		if ValidTarget(minion,E.Range) then
			if self:IsPoisonedTarget(minion) then
				local distance =  GetDistance(myHero.pos,minion.pos)
				local time = 0.025 + distance/2500
				if distance < E.Range and OW:GetHealthPrediction(minion,time,Minions[3]) < self:GetDamage("E",minion,true) then
					self:CastE(minion)	
					return
				end
			end
		end
	end
	end
	if myHero.mana/myHero.maxMana < self.Menu.Harass.MinMana:Value()/100 then return end
	local etarget = self:GetETarget()
	if isReady(2) and usee and etarget then
		self:CastE(etarget)	
		return
	end
	local qTarget = self.Ts:GetTarget(Q.Range)
	if qTarget and isReady(0) and useq and not self:IsPoisonedTarget(qTarget) then
		self:CastQ(qTarget)
	end
end


function Cassiopeia:LaneClear(OW,Minions)
	
	local minions = {}
	local minions2 = {}
	local q = true
	for i,minion in pairs(Minions[1]) do
		local distance =  GetDistance(myHero.pos,minion.pos)
		if isReady(2) and ValidTarget(minion,E.Range) and self:GetDamage("E",minion) > OW:GetHealthPrediction(minion,0.025 + distance/2500,Minions[3]) then
			q = false
			self:CastE(minion)
		end
		if ValidTarget(minion,Q.Range + Q.Radius) then
			minions[#minions+1] = minion
		end
	end
	if #minions > 0 then
		if myHero.mana/myHero.maxMana < self.Menu.LaneClear.MinMana:Value()/100 then return end
		if not isReady(0) then return end
		if #minions == 1 and minions[1].health < myHero.totalDamage then
			q = false
			return
		end
		local bestPos, bestHit = self:GetBestCircularFarmPosition(Q.Range,Q.Radius + 40, minions)
		if bestHit > 0 and q then
			SpellCast:CastSpell(HK_Q,bestPos,0.6)
		end
	end	
	
end

function Cassiopeia:JungleClear(OW,Minions)
	local mobs = {}
	for i, minion in pairs(Minions[2]) do
		if ValidTarget(minion,Q.Range) then
			table.insert(mobs,minion)
		end	
	end
	table.sort(mobs,function(a,b) return a.maxHealth > b.maxHealth end)
	local mob = mobs[1]
	if mob then
		if isReady(2) and self:IsPoisonedTarget(mob)and GetDistanceSqr(mob.pos) < E.Range*E.Range then	
			self:CastE(mob)
			return
		end
		if isReady(0) then
			SpellCast:CastSpell(HK_Q, mob.pos,0.6)
		end
	end
end

function Cassiopeia:LastHit(OW,Minions)
	local elasthit = self.Menu.LastHit.UseE:Value()
	local qlasthit = self.Menu.LastHit.UseQ:Value()
	
	if isReady(2) and elasthit then
	for i,minion in pairs(Minions[1]) do
		if ValidTarget(minion,E.Range) then
			if self:IsPoisonedTarget(minion) then
				local distance =  GetDistance(myHero.pos,minion.pos)
				local time = 0.025 + distance/2500
				if distance < E.Range and OW:GetHealthPrediction(minion,time,Minions[3]) < self:GetDamage("E",minion,true) then
					Control.CastSpell(HK_E,minion)
					return
				end
			end
		end
	end
	end
	
	if isReady(0) and qlasthit and not isReady(2) then
		for i,minion in pairs(Minions[1]) do
			if ValidTarget(minion,Q.Range) and self:GetDamage("Q",minion) > minion.health and minion.health > myHero.totalDamage then
				SpellCast:CastSpell(HK_Q, minion.pos,0.6)
			end
		end		
	end
end


function Cassiopeia:Tick()
	
	if isReady(3) then
		local enemies = {}
		for i,enemy in pairs(self.Enemies) do
			if ValidTarget(enemy,R.Range) and self:CanR(enemy) then
				if enemy.range < 350 and GetDistanceSqr(enemy.pos,myHero.pos) < 200*200 and myHero.health/myHero.maxHealth < 0.5 then
					self:CastR(enemy)
					return
				end
				table.insert(enemies,enemy)
			end
		end
		if #enemies >= 2 then
			local rTarget = self.Ts:GetTarget(650)--need better logic
			if rTarget then
				self:CastR(rTarget)
			end
		end
	end
end

function Cassiopeia:IsInvulnerableTarget(unit)
	
	local Buffs = {
	["UndyingRage"] = true,
    ["JudicatorIntervention"] = true,
    ["VladimirSanguinePool"] = true,--isTargetable
    ["ChronoRevive"] = true,
    ["ChronoShift"] = true,
    ["zhonyasringshield"] = true,
    ["lissandrarself"] = true,
}
	for i = 0, unit.buffCount do
		local buff = unit:GetBuff(i)
		if buff and buff.name and buff.count > 0 and buff.expireTime > Game.Timer() and (Buffs[buff.name] or (buff.name == "kindredrnodeathbuff" and GetPercentHP(unit) < 10) or (buff.name == "UndyingRage" and unit.health < 10) ) then
			return true
		end
	end
	return false
end

function Cassiopeia:GetBestCircularFarmPosition(range, radius, objects)

    local BestPos 
    local BestHit = 0
    for i, object in pairs(objects) do
        local hit = self:CountObjectsNearPos(object.pos, range, radius, objects)
        if hit > BestHit then
            BestHit = hit
            BestPos = object.pos
            if BestHit == #objects then
               break
            end
         end
    end

    return BestPos, BestHit

end

function Cassiopeia:CountObjectsNearPos(pos, range, radius, objects)

    local n = 0
    for i, object in pairs(objects) do
        if GetDistanceSqr(pos, object.pos) <= radius * radius then
            n = n + 1
        end
    end

    return n

end

function Cassiopeia:Draw()
	if myHero.dead then return end
	if self.Menu.Drawing.DrawQ:Value() and myHero:GetSpellData(0).level > 0 then
		local qcolor = isReady(0) and  Draw.Color(189, 183, 107, 255) or Draw.Color(150,255,0,0)
		Draw.Circle(Vector(myHero.pos),Q.Range,1,qcolor)
	end
	if self.Menu.Drawing.DrawR:Value() and myHero:GetSpellData(3).level > 0  then
		local rcolor = isReady(3) and  Draw.Color(240,30,144,255) or Draw.Color(150,255,0,0)
		Draw.Circle(Vector(myHero.pos),R.Range,1,rcolor)
	end
	if self.Menu.Drawing.DrawE:Value() and myHero:GetSpellData(2).level > 0 then
		local ecolor = isReady(2) and  Draw.Color(233, 150, 122, 255) or Draw.Color(150,255,0,0)
		Draw.Circle(Vector(myHero.pos),E.Range,1,ecolor)
	end
	if LastPos then 
		--Draw.Circle(LastPos,80,2,Draw.Color(255, 228, 196, 255))
	end
end

Callback.Add("Load",function() Cassiopeia() end)


