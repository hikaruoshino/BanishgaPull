_addon.name = 'BanishgaPull'
_addon.author = 'hikaruoshino'
_addon.version = '2.3'
_addon.commands = {'bp', 'banishgapull'}

require('chat')
local config = require('config')
local res = require('resources')

-- 設定 (data/settings.xml)
--   spell        : 唱える魔法 (日本語クライアントでは日本語名。例: バニシュガ / ディアガ)
--   max_distance : 自分からの射程 (m)
--   puller       : 釣り役の名前 (空なら全員自動検知)
local defaults = {
    spell = 'バニシュガ',
    max_distance = 20,
    puller = '',
}
local settings = config.load(defaults)

-- 旧版の英語名は日本語クライアントでは通らないため置き換える
if settings.spell == 'Banishga' then
    settings.spell = 'バニシュガ'
    config.save(settings)
end

local PULLER_NEAR_SQ = 225.0 -- 釣り役から 15m 以内 (2乗)

local function get_puller()
    local p = settings.puller
    if type(p) ~= 'string' or p == '' then return nil end
    return p
end

-- UTF-8からShift-JISへの変換ヘルパー
local function sjis(str)
    if not str then return '' end
    return windower.to_shift_jis and windower.to_shift_jis(str) or str
end

-- チャットから届く引数 (Shift-JIS) を UTF-8 に戻す
local function from_sjis(str)
    if not str then return nil end
    return windower.from_shift_jis and windower.from_shift_jis(str) or str
end

-- 敵 (モンスター) かどうか: spawn_type の 0x10 ビット。フェイス・ペット・羅盤・NPC は除外
local function is_enemy(mob)
    local st = tonumber(mob.spawn_type) or 0
    return math.floor(st / 0x10) % 2 == 1
end

-- 攻撃してよいクレーム状態か: 未クレーム (黄色ネーム) か自PT/アライアンスのクレームのみ。他PT (紫ネーム) は除外
local function is_claim_ok(mob, party_ids)
    local claim = tonumber(mob.claim_id) or 0
    return claim == 0 or party_ids[claim] ~= nil
end

-- 唱える魔法の ID を名前から探す (日本語名・英語名どちらでも)。見つからなければ nil
local function find_spell_id(name)
    if not name or name == '' then return nil end
    local lower = name:lower()
    for id, row in pairs(res.spells) do
        if type(row) == 'table' and (row.ja == name or (row.en and row.en:lower() == lower)) then
            return id
        end
    end
    return nil
end

windower.register_event('addon command', function(cmd, ...)
    local args = {...}
    cmd = cmd and cmd:lower() or 'pull'

    -- 1. 釣り役の設定・変更・解除処理
    if cmd == 'puller' or cmd == 'set' then
        local name = args[1]
        if not name or name == '' or name:lower() == 'reset' or name:lower() == 'clear' or name:lower() == 'off' then
            settings.puller = ''
            config.save(settings)
            windower.add_to_chat(158, '--------------------------------------------------')
            windower.add_to_chat(158, sjis('  [BanishgaPull] 釣り役指定を【解除】しました。'))
            windower.add_to_chat(158, sjis('  ※パーティメンバー全員を対象に自動検知します。'))
            windower.add_to_chat(158, '--------------------------------------------------')
        else
            settings.puller = name
            config.save(settings)
            windower.add_to_chat(209, '==================================================')
            windower.add_to_chat(209, sjis('  [BanishgaPull] 釣り役設定: 【 ') .. name .. sjis(' 】 さん'))
            windower.add_to_chat(209, sjis('  ※ ') .. name .. sjis(' さんの周囲の敵（黄色ネーム含む）を最優先で捕獲します！'))
            windower.add_to_chat(209, '==================================================')
        end
        return
    elseif cmd == 'spell' then
        -- //bp spell ディアガ : 唱える魔法を変更
        local name = from_sjis(table.concat(args, ' '))
        if not name or name == '' then
            windower.add_to_chat(207, sjis('[BanishgaPull] 現在の魔法: ' .. settings.spell .. ' (変更: //bp spell 魔法名)'))
            return
        end
        settings.spell = name
        config.save(settings)
        windower.add_to_chat(209, sjis('[BanishgaPull] 唱える魔法を【 ' .. name .. ' 】に変更しました。'))
        return
    elseif cmd == 'range' or cmd == 'distance' then
        -- //bp range 20 : 自分からの射程 (m) を変更
        local dist = tonumber(args[1])
        if not dist or dist <= 0 or dist > 50 then
            windower.add_to_chat(207, sjis(string.format('[BanishgaPull] 現在の射程: %sm (変更: //bp range 数値)', tostring(settings.max_distance))))
            return
        end
        settings.max_distance = dist
        config.save(settings)
        windower.add_to_chat(209, sjis(string.format('[BanishgaPull] 射程を %.1fm に変更しました。', dist)))
        return
    elseif cmd == 'status' or cmd == 'show' then
        local puller = get_puller()
        local status_str = puller and (sjis('【 ') .. puller .. sjis(' 】 さん')) or sjis('未指定（全員自動検知）')
        windower.add_to_chat(207, sjis('[BanishgaPull] 現在の釣り役: ') .. status_str)
        windower.add_to_chat(207, sjis(string.format('[BanishgaPull] 魔法: %s / 射程: %sm', settings.spell, tostring(settings.max_distance))))
        return
    elseif cmd == 'help' then
        windower.add_to_chat(207, sjis('[BanishgaPull] //bp              : 釣り役周辺の敵へ魔法を発動'))
        windower.add_to_chat(207, sjis('[BanishgaPull] //bp set 名前     : 釣り役を指定 (//bp set off で解除)'))
        windower.add_to_chat(207, sjis('[BanishgaPull] //bp spell 魔法名 : 唱える魔法を変更 (例: ディアガ)'))
        windower.add_to_chat(207, sjis('[BanishgaPull] //bp range 数値   : 自分からの射程 (m) を変更'))
        windower.add_to_chat(207, sjis('[BanishgaPull] //bp status       : 現在の設定を表示'))
        return
    end

    -- 2. 即時捕獲処理
    -- 魔法がリキャスト中なら、唱えずに残り時間を知らせる (ゲームの値が取れて、魔法名が分かるときだけ)
    local spell_id = find_spell_id(settings.spell)
    if spell_id then
        local frames = (windower.ffxi.get_spell_recasts() or {})[spell_id]
        if frames and frames > 0 then
            windower.add_to_chat(123, sjis(string.format('[BanishgaPull] [%s] はリキャスト中です (あと %.1f 秒)。', settings.spell, frames / 60)))
            return
        end
    end

    local designated_puller = get_puller()
    local party = windower.ffxi.get_party() or {}
    local mob_array = windower.ffxi.get_mob_array() or {}

    local party_ids = {}
    local puller_id = nil
    local puller_mob = nil

    for k, member in pairs(party) do
        if type(member) == 'table' and member.mob then
            party_ids[member.mob.id] = member.name
            if designated_puller and member.name and member.name:lower() == designated_puller:lower() then
                puller_id = member.mob.id
                puller_mob = member.mob
            end
        end
    end

    local max_dist = tonumber(settings.max_distance) or 20
    local max_dist_sq = max_dist * max_dist   -- mob.distance は2乗値
    local best_target = nil
    local min_dist_sq = max_dist_sq
    local min_puller_dist_sq = 999999.0  -- 釣り役からの距離の2乗
    local target_priority = 0
    local skipped_hidden = 0   -- 射程内にいるが、描画されていない (ターゲットできない) 敵
    local skipped_claim = 0    -- 射程内にいるが、他 PT にクレームされている敵

    for index, mob in pairs(mob_array) do
        -- 外した敵の数を数える (表示用)
        if mob.is_npc and is_enemy(mob) and (mob.hpp or 0) > 0 and mob.status ~= 2 and mob.status ~= 3
            and (mob.distance or math.huge) <= max_dist_sq then
            if not mob.valid_target then
                skipped_hidden = skipped_hidden + 1
            elseif not is_claim_ok(mob, party_ids) then
                skipped_claim = skipped_claim + 1
            end
        end
        -- 生きていてターゲット可能な敵 (フェイス・ペット・NPC・他PTクレームは除外)
        if mob.is_npc and mob.valid_target and is_enemy(mob) and is_claim_ok(mob, party_ids)
            and (mob.hpp or 0) > 0 and mob.status ~= 2 and mob.status ~= 3 then
            local dist_self_sq = mob.distance
            -- 自分からの距離が射程以内
            if dist_self_sq <= max_dist_sq then
                local current_priority = 1
                local dist_to_puller_sq = nil

                -- 釣り役の座標が取得できている場合、釣り役からの距離を計算
                if puller_mob then
                    local dx = mob.x - puller_mob.x
                    local dy = mob.y - puller_mob.y
                    local dz = mob.z - puller_mob.z
                    dist_to_puller_sq = dx*dx + dy*dy + dz*dz
                end

                -- 判定1: 敵がターゲットしている相手をチェック
                if mob.target_index and mob.target_index > 0 then
                    local target_entity = windower.ffxi.get_mob_by_index(mob.target_index)
                    if target_entity then
                        if puller_id and target_entity.id == puller_id then
                            current_priority = 4 -- 釣り役を直接攻撃・ターゲット中（最優先）
                        elseif party_ids[target_entity.id] then
                            current_priority = 2 -- その他PTメンバー攻撃中
                        end
                    end
                end

                -- 判定2: 赤ネームでない（ヘイト未発生・黄色ネーム）場合でも、釣り役の近く(15m以内)にいる敵を優先
                if current_priority < 4 and puller_mob and dist_to_puller_sq and dist_to_puller_sq <= PULLER_NEAR_SQ then
                    current_priority = 3 -- 釣り役の引連れ・周りの敵（黄色ネーム対応）
                end

                -- 優先度判定と最適なターゲットの選定
                if current_priority > target_priority then
                    target_priority = current_priority
                    best_target = mob
                    min_dist_sq = dist_self_sq
                    if dist_to_puller_sq then
                        min_puller_dist_sq = dist_to_puller_sq
                    end
                elseif current_priority == target_priority then
                    -- 同じ優先度同士の場合：
                    -- 釣り役関連（優先度3, 4）の場合は「釣り役から一番近い敵」を優先
                    if (current_priority == 3 or current_priority == 4) and dist_to_puller_sq then
                        if dist_to_puller_sq < min_puller_dist_sq then
                            min_puller_dist_sq = dist_to_puller_sq
                            min_dist_sq = dist_self_sq
                            best_target = mob
                        end
                    -- それ以外は「自分から一番近い敵」を優先
                    elseif dist_self_sq < min_dist_sq then
                        min_dist_sq = dist_self_sq
                        best_target = mob
                    end
                end
            end
        end
    end

    local skipped_msg = nil
    if skipped_hidden > 0 or skipped_claim > 0 then
        skipped_msg = sjis(string.format('[BanishgaPull] 対象外: 描画されていない敵 %d 体 / 他PTのクレーム %d 体', skipped_hidden, skipped_claim))
    end

    if best_target then
        local real_min_dist = math.sqrt(min_dist_sq)
        local p_msg = ''
        local color = 207

        if target_priority == 4 then
            local real_puller_dist = (min_puller_dist_sq < 990000.0) and math.sqrt(min_puller_dist_sq) or nil
            local p_dist_str = real_puller_dist and string.format(' [釣り役から%.1fm]', real_puller_dist) or ''
            p_msg = sjis('【★指定釣り役 (' .. (designated_puller or '') .. ') 被弾中' .. p_dist_str .. '】')
            color = 209
        elseif target_priority == 3 then
            local real_puller_dist = (min_puller_dist_sq < 990000.0) and math.sqrt(min_puller_dist_sq) or nil
            local p_dist_str = real_puller_dist and string.format(' [釣り役から%.1fm]', real_puller_dist) or ''
            p_msg = sjis('【★指定釣り役 (' .. (designated_puller or '') .. ') 追従・黄色ネーム' .. p_dist_str .. '】')
            color = 209
        elseif target_priority == 2 then
            p_msg = sjis('【PTメンバー被弾中】')
            color = 207
        else
            p_msg = sjis('【近隣敵】')
            color = 200
        end

        local spell = settings.spell
        windower.add_to_chat(color, sjis('[BanishgaPull] ') .. p_msg .. ' >> ' .. best_target.name .. ' (' .. string.format('%.1f', real_min_dist) .. 'm) ' .. sjis('へ [' .. spell .. '] 発動！'))
        -- ターゲットを切り替えずに、敵の ID を直接指定して唱える (切り替え待ちで別の敵に飛ぶのを防ぐ)
        windower.send_command(sjis('input /ma "' .. spell .. '" ' .. best_target.id))
        if skipped_msg then windower.add_to_chat(207, skipped_msg) end
    else
        windower.add_to_chat(123, sjis(string.format('[BanishgaPull Error] 射程%sm以内に有効な敵が見つかりません。', tostring(max_dist))))
        if skipped_msg then windower.add_to_chat(207, skipped_msg) end
    end
end)
