-- =============================================================================
--  SISTEMA 1 — ANIMAÇÃO DE SKILL: CONFIGURAÇÃO E TABELA DE ANIMAÇÕES
--  Este é o arquivo que você edita no dia a dia. O motor fica em
--  data/lib/core/skill_animation.lua (não precisa mexer nele).
--  Depois de editar: /reload scripts (ou reinicie o servidor). Erros de
--  digitação na tabela aparecem no console como "[SkillAnimation] ...".
-- =============================================================================

SkillAnimationConfig = {
	-- Nome registrado em data/monster/monsters.xml para a "skin de animação".
	actorName = "Animation Actor",

	-- Condition de outfit vazio (invisibilidade do corpo real).
	-- Usa um conditionId de SLOT, que o servidor NUNCA grava no banco
	-- (Condition::isPersistent só persiste DEFAULT/COMBAT). Por isso um crash
	-- não consegue deixar ninguém invisível no próximo login.
	conditionId = CONDITIONID_AMMO,
	outfitSubId = 9101,   -- identifica a condition desta lib (não reutilize)
	invisibleSubId = 9102,

	-- Rede de segurança: a condition de outfit dura (duration + margem) e se
	-- apaga sozinha mesmo que todo o Lua falhe. O lock de ação dura exatamente
	-- "duration" e também expira sozinho (timestamp em memória no C++).
	safetyMarginMs = 400,

	-- Com que frequência o Actor confere se o jogador mudou de tile (teleport).
	syncIntervalMs = 250,

	-- Monstros: false = continuam atacando o corpo invisível (padrão pedido).
	--           true  = aplica também CONDITION_INVISIBLE, então monstros
	--                   perdem o alvo (e jogadores comuns veem o corpo vazio).
	monstersLoseTarget = false,

	-- Imunidade durante a animação (dano que não seja cura).
	-- Padrão: o corpo pode ser atingido por tudo (PvE e PvP).
	immuneToMonsters = false,
	immuneToPlayers = false,

	-- Mensagem quando alguém tenta usar spell/item/andar durante a animação é
	-- tratada no C++ (RETURNVALUE_YOUAREEXHAUSTED); aqui só o log de depuração.
	debug = false,
}

-- =============================================================================
--  TABELA DE ANIMAÇÕES
--
--  SkillAnimations["nome"] = {
--      duration = <ms>,         -- duração total = duração do stun
--      steps = {
--          {
--              delay   = <ms>,                 -- 0..duration, a partir do início
--              outfit  = "self" | { lookType=, lookHead=, lookBody=, lookLegs=,
--                                   lookFeet=, lookAddons=, lookTypeEx=, lookMount= },
--              direction = "self" | DIRECTION_*,  -- opcional
--              effect  = CONST_ME_*,           -- opcional, sai na posição do Actor
--              hit     = true,                 -- opcional: dispara o dano neste passo
--          },
--          ...
--      },
--  }
--
--  "self" no outfit = o outfit que o jogador tinha ao iniciar a skill.
--  O 1º passo com delay = 0 roda na hora; os demais, via agendador (mín. ~50ms).
--  Os outfits abaixo são PLACEHOLDERS (outfits padrão do client 10.98).
-- =============================================================================

SkillAnimations = {
	["teste_giro"] = {
		duration = 1500,
		steps = {
			{ delay = 0,    outfit = { lookType = 130, lookHead = 78, lookBody = 68, lookLegs = 58, lookFeet = 76 },
			                effect = CONST_ME_MAGIC_BLUE },
			{ delay = 400,  outfit = { lookType = 134, lookHead = 94, lookBody = 79, lookLegs = 114, lookFeet = 114 },
			                effect = CONST_ME_FIREAREA, hit = true },
			{ delay = 800,  outfit = { lookType = 131, lookHead = 77, lookBody = 94, lookLegs = 94, lookFeet = 77 },
			                effect = CONST_ME_HITAREA, hit = true },
			{ delay = 1200, outfit = "self", effect = CONST_ME_POFF },
		},
	},

	-- Exemplo mínimo: 1 passo só, dano no meio.
	["teste_curto"] = {
		duration = 600,
		steps = {
			{ delay = 0,   outfit = { lookType = 133, lookHead = 0, lookBody = 114, lookLegs = 114, lookFeet = 114 } },
			{ delay = 300, effect = CONST_ME_MORTAREA, hit = true },
		},
	},
}
