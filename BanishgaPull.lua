_addon.name = 'BanishgaPull'
_addon.author = 'Gemini Notebook'
_addon.version = '3.5'
_addon.commands = {'bp', 'banishgapull'}

require('chat')

local designated_puller = nil

-- UTF-8からShift-JISへの変換ヘルパー
local function sjis(str)
    if not str then return '' end
    return windower.to_shift_jis and windower.to_shift_jis(str) or str
end

windower.register_event('addon command', function(cmd, ...)
    local args = {...}
    cmd = cmd and cmd:lower() or 'pull'

    -- 1. 釣り役の設定・変更・解除処理
    if cmd == 'puller' or cmd == 'set' then
        local name = args[1]
        if not name or name == '' or name:lower() == 'reset' or name:lower() == 'clear' or name:lower() == 'off' then
            designated_puller = nil
            windower.add_to_chat(158, '--------------------------------------------------')
            windower.add_to_chat(158, sjis('  [BanishgaPull] 釣り役指定を【解除】しました。'))
            windower.add_to_chat(158, sjis('  ※パーティメンバー全員を対象に自動検知します。'))
            windower.add_to_chat(158, '--------------------------------------------------')
        else
            designated_puller = name
            windower.add_to_chat(209, '==================================================')
            windower.add_to_chat(209, sjis('  [BanishgaPull] 釣り役設定: 【 ') .. designated_puller .. sjis(' 】 さん'))
            windower.add_to_chat(209, sjis('  ※ ') .. designated_puller .. sjis(' さんに最も近い攻撃中の敵を最優先で捕獲します！'))
            windower.add_to_chat(209, '==================================================')
        end
        return
    elseif cmd == 'status' or cmd == 'show' then
        local status_str = designated_puller and (sjis('【 ') .. designated_puller .. sjis(' 】 さん')) or sjis('未指定（全員自動検知）')
        windower.add_to_chat(207, sjis('[BanishgaPull] 現在の釣り役: ') .. status_str)
        return
    end

    -- 2. 即時バニシュガ捕獲処理
    local party = windower.ffxi.get_party()
    local mob_array = windower.ffxi.get_mob_array()

    local party_ids = {}
    local puller_id = nil
    local puller_mob = nil

    for k, member in pairs(party) do
        if type(member) == 'table' and member.mob then
            party_ids[member.mob.id] = member.name
            if designated_puller and member.name:lower() == designated_puller:lower() then
                puller_id = member.mob.id
                puller_mob = member.mob
            end
        end
    end

    local best_target = nil
    local min_dist_sq = 400.0            -- 射程20mの2乗 (20^2 = 400)
    local min_puller_dist_sq = 999999.0  -- 釣り役からの距離の2乗
    local target_priority = 0

    for index, mob in pairs(mob_array) do
        if mob.is_npc and mob.valid_target and mob.hpp > 0 and mob.status ~= 2 and mob.status ~= 3 then
            local dist_self_sq = mob.distance
            if dist_self_sq <= 400.0 then
                local current_priority = 1
                local dist_to_puller_sq = nil

                if mob.target_index and mob.target_index > 0 then
                    local target_entity = windower.ffxi.get_mob_by_index(mob.target_index)
                    if target_entity then
                        if puller_id and target_entity.id == puller_id then
                            current_priority = 3
                            if puller_mob then
                                local dx = mob.x - puller_mob.x
                                local dy = mob.y - puller_mob.y
                                local dz = mob.z - puller_mob.z
                                dist_to_puller_sq = dx*dx + dy*dy + dz*dz
                            end
                        elseif party_ids[target_entity.id] then
                            current_priority = 2
                        end
                    end
                end

                if current_priority > target_priority then
                    target_priority = current_priority
                    best_target = mob
                    min_dist_sq = dist_self_sq
                    if current_priority == 3 and dist_to_puller_sq then
                        min_puller_dist_sq = dist_to_puller_sq
                    end
                elseif current_priority == target_priority then
                    if current_priority == 3 and dist_to_puller_sq then
                        if dist_to_puller_sq < min_puller_dist_sq then
                            min_puller_dist_sq = dist_to_puller_sq
                            min_dist_sq = dist_self_sq
                            best_target = mob
                        end
                    elseif dist_self_sq < min_dist_sq then
                        min_dist_sq = dist_self_sq
                        best_target = mob
                    end
                end
            end
        end
    end

    if best_target then
        local real_min_dist = math.sqrt(min_dist_sq)
        local p_msg = ''
        local color = 207

        if target_priority == 3 then
            local real_puller_dist = (min_puller_dist_sq < 990000.0) and math.sqrt(min_puller_dist_sq) or nil
            local p_dist_str = real_puller_dist and string.format(' [釣り役から%.1fm]', real_puller_dist) or ''
            p_msg = sjis('【★指定釣り役 (' .. (designated_puller or '') .. ') 被弾中' .. p_dist_str .. '】')
            color = 209
        elseif target_priority == 2 then
            p_msg = sjis('【PTメンバー被弾中】')
            color = 207
        else
            p_msg = sjis('【近隣敵】')
            color = 200
        end

        windower.add_to_chat(color, sjis('[BanishgaPull] ') .. p_msg .. ' >> ' .. best_target.name .. ' (' .. string.format('%.1f', real_min_dist) .. 'm) ' .. sjis('へ [バニシュガ] 発動！'))
        windower.send_command('input /target ' .. best_target.id .. '; wait 0.05; input /ma "Banishga" <t>')
    else
        windower.add_to_chat(123, sjis('[BanishgaPull Error] 射程20m以内に有効な敵が見つかりません。'))
    end
end)
