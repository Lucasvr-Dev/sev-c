-- =============================================================================
--  SISTEMA 1 — MOTOR DA ANIMAÇÃO DE SKILL
--  Configuração e tabela de animações: data/lib/core/skill_animation_config.lua
--
--  Ciclo:  playSkillAnimation() -> cria o Actor na tile do jogador, deixa o
--  corpo real invisível (Condition de outfit vazio) e trava as ações
--  (Player:setActionLock, no C++) -> roda os passos por addEvent -> finish().
--
--  Garantias de segurança (nada deixa o jogador preso/invisível):
--    1. Lock de ação = timestamp em memória no C++: expira sozinho e nunca é
--       gravado no banco.
--    2. A condition de outfit usa um conditionId de slot (não persistente) e
--       tem ticks = duration + margem: some sozinha mesmo se o Lua morrer.
--    3. Todo addEvent confere um TOKEN por animação (sem eventos órfãos).
--    4. finish() é idempotente e roda dentro de pcall nos passos.
--    5. Um globalevent (sweep) encerra animações vencidas / de jogador que
--       sumiu, e logout/morte chamam SkillAnimation.cancel().
--  O estado fica em SkillAnimation.active, preservado em /reload scripts.
-- =============================================================================

SkillAnimation = SkillAnimation or {}
SkillAnimation.active = SkillAnimation.active or {}      -- [playerId] = state
SkillAnimation.nextToken = SkillAnimation.nextToken or 0

local function cfg()
	return SkillAnimationConfig
end

local function log(message)
	print("[SkillAnimation] " .. tostring(message))
end

local function debugLog(message)
	if cfg().debug then
		log(message)
	end
end

local function getState(playerId, token)
	local state = SkillAnimation.active[playerId]
	if state and state.token == token then
		return state
	end
	return nil
end

local function copyOutfit(outfit)
	return {
		lookType = outfit.lookType or 0,
		lookTypeEx = outfit.lookTypeEx or 0,
		lookHead = outfit.lookHead or 0,
		lookBody = outfit.lookBody or 0,
		lookLegs = outfit.lookLegs or 0,
		lookFeet = outfit.lookFeet or 0,
		lookAddons = outfit.lookAddons or 0,
		lookMount = outfit.lookMount or 0,
	}
end

local function resolveOutfit(state, outfit)
	if outfit == "self" then
		return state.originalOutfit
	end
	return outfit
end

-- ---------------------------------------------------------------------------
--  Validação da tabela (roda ao carregar; também chamável à mão)
-- ---------------------------------------------------------------------------
function SkillAnimation.validate()
	local errors = 0
	local function bad(name, message)
		errors = errors + 1
		log(string.format("animação '%s': %s", tostring(name), message))
	end

	for name, anim in pairs(SkillAnimations or {}) do
		if type(anim) ~= "table" then
			bad(name, "deve ser uma tabela")
		else
			if type(anim.duration) ~= "number" or anim.duration < 100 then
				bad(name, "duration deve ser um número >= 100 (ms)")
			end
			if type(anim.steps) ~= "table" or #anim.steps == 0 then
				bad(name, "steps deve ser uma lista com ao menos 1 passo")
			else
				for index, step in ipairs(anim.steps) do
					local where = "passo " .. index
					if type(step.delay) ~= "number" or step.delay < 0 then
						bad(name, where .. ": delay deve ser um número >= 0")
					elseif type(anim.duration) == "number" and step.delay > anim.duration then
						bad(name, where .. ": delay maior que a duration (o passo nunca rodaria)")
					end
					if step.outfit ~= nil and step.outfit ~= "self"
							and (type(step.outfit) ~= "table" or (not step.outfit.lookType and not step.outfit.lookTypeEx)) then
						bad(name, where .. ": outfit deve ser \"self\" ou tabela com lookType/lookTypeEx")
					end
					if step.effect ~= nil and type(step.effect) ~= "number" then
						bad(name, where .. ": effect deve ser um CONST_ME_*")
					end
				end
			end
		end
	end
	return errors
end

-- ---------------------------------------------------------------------------
--  Actor (a "skin de animação")
-- ---------------------------------------------------------------------------
local function spawnActor(state, player)
	-- force = true: nasce mesmo em tile ocupada pelo jogador e em PZ.
	-- (teleportTo NÃO serve: o servidor recusa mover monstro para tile ocupada.)
	local actor = Game.createMonster(cfg().actorName, player:getPosition(), false, true)
	if not actor then
		return nil
	end
	state.actorId = actor:getId()
	actor:setDirection(state.direction)
	if state.actorOutfit then
		actor:setOutfit(state.actorOutfit)
	end
	return actor
end

-- Garante que o Actor está na mesma tile do jogador (teleport/empurrão).
local function syncActor(state, player)
	local actor = Creature(state.actorId)
	if actor then
		local playerPos, actorPos = player:getPosition(), actor:getPosition()
		if playerPos.x == actorPos.x and playerPos.y == actorPos.y and playerPos.z == actorPos.z then
			return actor
		end
		actor:remove()
	end
	return spawnActor(state, player)
end

-- ---------------------------------------------------------------------------
--  Limpeza
-- ---------------------------------------------------------------------------
local function removeAnimationConditions(player)
	local c = cfg()
	for _, conditionId in ipairs({ c.conditionId, CONDITIONID_COMBAT, CONDITIONID_DEFAULT }) do
		for _ = 1, 3 do
			if not player:removeCondition(CONDITION_OUTFIT, conditionId, c.outfitSubId, true) then
				break
			end
		end
		for _ = 1, 3 do
			if not player:removeCondition(CONDITION_INVISIBLE, conditionId, c.invisibleSubId, true) then
				break
			end
		end
	end
end

-- Idempotente. Usar token = nil para encerrar a animação atual seja qual for.
function SkillAnimation.finish(playerId, token, reason)
	local state = SkillAnimation.active[playerId]
	if not state or (token ~= nil and state.token ~= token) then
		return false
	end

	-- 1º: tira do registro (à prova de reentrada e de erro no resto da função)
	SkillAnimation.active[playerId] = nil

	for _, eventId in ipairs(state.events) do
		stopEvent(eventId)
	end
	if state.syncEvent then
		stopEvent(state.syncEvent)
	end

	local actor = Creature(state.actorId)
	if actor then
		actor:remove()
	end

	local player = Player(playerId)
	if player then
		removeAnimationConditions(player)
		player:clearActionLock()
	end

	debugLog(string.format("fim '%s' (%s)", state.anim, tostring(reason)))
	return true
end

function SkillAnimation.cancel(player, reason)
	if not player then
		return false
	end
	return SkillAnimation.finish(player:getId(), nil, reason or "cancel")
end

function SkillAnimation.isActive(player)
	return player ~= nil and SkillAnimation.active[player:getId()] ~= nil
end

-- Chamado pelo globalevent: encerra o que venceu ou perdeu o dono.
function SkillAnimation.sweep()
	local now = os.mtime()
	local margin = cfg().safetyMarginMs
	for playerId, state in pairs(SkillAnimation.active) do
		local player = Player(playerId)
		if not player or player:getHealth() <= 0 or now > state.deadline + margin then
			SkillAnimation.finish(playerId, state.token, "sweep")
		end
	end
end

-- Remove sobras de uma sessão anterior (defesa extra; roda no login).
function removeLeftoverInvisibility(player)
	removeAnimationConditions(player)
	player:clearActionLock()
end

-- ---------------------------------------------------------------------------
--  Execução dos passos
-- ---------------------------------------------------------------------------
local function runStep(playerId, token, index)
	local state = getState(playerId, token)
	if not state then
		return
	end

	local player = Player(playerId)
	if not player or player:getHealth() <= 0 then
		SkillAnimation.finish(playerId, token, "player_gone")
		return
	end

	local anim = SkillAnimations[state.anim]
	local step = anim and anim.steps[index]
	if not step then
		return -- tabela editada com /reload no meio da animação: ignora
	end

	local actor = syncActor(state, player)
	if not actor then
		SkillAnimation.finish(playerId, token, "actor_missing")
		return
	end

	local ok, err = pcall(function()
		if step.outfit ~= nil then
			state.actorOutfit = resolveOutfit(state, step.outfit)
			actor:setOutfit(state.actorOutfit)
		end
		if step.direction ~= nil then
			state.direction = (step.direction == "self") and state.baseDirection or step.direction
			actor:setDirection(state.direction)
		end
		if step.effect then
			actor:getPosition():sendMagicEffect(step.effect)
		end
	end)
	if not ok then
		log(string.format("erro visual no passo %d de '%s': %s", index, state.anim, tostring(err)))
	end

	if step.hit and state.onHit then
		local hitOk, hitErr = pcall(state.onHit, player, state.variant, index, step)
		if not hitOk then
			log(string.format("erro no dano do passo %d de '%s': %s", index, state.anim, tostring(hitErr)))
		end
	end
end

local function tickSync(playerId, token)
	local state = getState(playerId, token)
	if not state then
		return
	end

	local player = Player(playerId)
	if not player or player:getHealth() <= 0 then
		SkillAnimation.finish(playerId, token, "player_gone")
		return
	end

	if os.mtime() >= state.deadline then
		return -- o evento de finish cuida do encerramento
	end

	if not syncActor(state, player) then
		SkillAnimation.finish(playerId, token, "actor_missing")
		return
	end

	state.syncEvent = addEvent(tickSync, cfg().syncIntervalMs, playerId, token)
end

local function onFinishEvent(playerId, token)
	SkillAnimation.finish(playerId, token, "done")
end

-- ---------------------------------------------------------------------------
--  API principal
--    playSkillAnimation(player, animName, variant, onHit) -> boolean
--    onHit(player, variant, stepIndex, step) roda nos passos com hit = true.
--  Retorna false (sem efeitos colaterais) se a animação não puder iniciar;
--  devolva esse false no onCastSpell para não gastar mana/cooldown.
-- ---------------------------------------------------------------------------
function SkillAnimation.play(player, animName, variant, onHit)
	local c = cfg()

	if not player or not player:isPlayer() then
		return false
	end

	local anim = SkillAnimations[animName]
	if not anim then
		log("animação inexistente: " .. tostring(animName))
		return false
	end

	local playerId = player:getId()
	if SkillAnimation.active[playerId] or player:isActionLocked() then
		return false
	end

	local originalOutfit = copyOutfit(player:getOutfit())
	if originalOutfit.lookType == 0 and originalOutfit.lookTypeEx == 0 then
		-- jogador já estava invisível por outro meio: usa um outfit-base
		originalOutfit.lookType = (player:getSex() == PLAYERSEX_FEMALE) and 136 or 128
	end

	SkillAnimation.nextToken = SkillAnimation.nextToken + 1
	local token = SkillAnimation.nextToken
	local now = os.mtime()

	local state = {
		token = token,
		anim = animName,
		playerId = playerId,
		variant = variant,
		onHit = onHit,
		originalOutfit = originalOutfit,
		actorOutfit = originalOutfit,
		baseDirection = player:getDirection(),
		direction = player:getDirection(),
		deadline = now + anim.duration,
		events = {},
	}

	-- Registrar ANTES de mexer em qualquer coisa: se algo falhar daqui pra
	-- frente, finish() sabe desfazer tudo.
	SkillAnimation.active[playerId] = state

	local ok, err = pcall(function()
		local actor = spawnActor(state, player)
		assert(actor, "não foi possível criar o Actor '" .. tostring(c.actorName) .. "'")

		-- corpo real invisível (outfit vazio) durante duration + margem
		local ticks = anim.duration + c.safetyMarginMs

		local outfitCondition = Condition(CONDITION_OUTFIT, c.conditionId)
		assert(outfitCondition, "Condition(CONDITION_OUTFIT) retornou nil")
		outfitCondition:setParameter(CONDITION_PARAM_SUBID, c.outfitSubId)
		outfitCondition:setTicks(ticks)
		outfitCondition:setOutfit({ lookType = 0, lookTypeEx = 0 })
		assert(player:addCondition(outfitCondition), "addCondition(outfit) falhou")

		if c.monstersLoseTarget then
			local invisibleCondition = Condition(CONDITION_INVISIBLE, c.conditionId)
			assert(invisibleCondition, "Condition(CONDITION_INVISIBLE) retornou nil")
			invisibleCondition:setParameter(CONDITION_PARAM_SUBID, c.invisibleSubId)
			invisibleCondition:setTicks(ticks)
			player:addCondition(invisibleCondition)
		end

		-- stun: andar, auto-walk, usar/mover item, outras spells e runas (C++)
		player:setActionLock(anim.duration)

		-- agenda: passos futuros, sincronização e encerramento
		for index, step in ipairs(anim.steps) do
			if step.delay > 0 then
				state.events[#state.events + 1] = addEvent(runStep, step.delay, playerId, token, index)
			end
		end
		state.syncEvent = addEvent(tickSync, c.syncIntervalMs, playerId, token)
		state.events[#state.events + 1] = addEvent(onFinishEvent, anim.duration, playerId, token)
	end)

	if not ok then
		log(string.format("falha ao iniciar '%s': %s", animName, tostring(err)))
		SkillAnimation.finish(playerId, token, "start_failed")
		return false
	end

	-- passos com delay 0 rodam agora (o Actor já nasce com o 1º outfit)
	for index, step in ipairs(anim.steps) do
		if step.delay <= 0 then
			runStep(playerId, token, index)
		end
	end

	debugLog(string.format("início '%s' (%dms)", animName, anim.duration))
	return true
end

function playSkillAnimation(player, animName, variant, onHit)
	return SkillAnimation.play(player, animName, variant, onHit)
end

function cancelSkillAnimation(player, reason)
	return SkillAnimation.cancel(player, reason)
end

if SkillAnimation.validate() == 0 then
	-- silencioso quando tudo certo
end
