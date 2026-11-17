-- Spell de teste do Sistema 1: dano 3x3 nos passos "hit" da animação "teste_giro".
local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_PHYSICALDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, CONST_ME_HITAREA)
combat:setArea(createCombatArea(AREA_SQUARE1X1))

function onGetFormulaValues(player, level, maglevel)
	local min = (level / 5) + (maglevel * 1.2) + 10
	local max = (level / 5) + (maglevel * 2.0) + 20
	return -min, -max
end

combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")

function onCastSpell(creature, variant)
	-- false = animação não iniciou: o servidor não cobra mana nem cooldown
	return playSkillAnimation(creature, "teste_giro", variant, function(player, var)
		combat:execute(player, var)
	end)
end
