_addon.name = 'BanishgaPull'
_addon.author = 'Gemini Notebook'
_addon.version = '2.1.0'
_addon.commands = {'bp', 'banishgapull'}

require('chat')

local designated_puller = nil
local target_spell = 'Banishga'
local max_search_dist = 20.0

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
            windower.add_to_chat(209, sjis('  ※ ') .. designated_puller .. sjis(' さん周囲の敵（黄色ネーム含む）を最優先で捕獲します！'))
            windower.add_to_chat(209, '==================================================')
        end
        return
    elseif cmd == 'spell' then
        if args[1] and args[1] ~= '' then
            target_spell = table.concat(args, ' ')
            windower.add_to_chat(207, sjis('[BanishgaPull] 詠唱魔法を変更しました: ') .. target_spell)
        end
        return
    elseif cmd == 'dist' or cmd == 'distance' then
        local val = tonumber(args[1])
        if val and val >= 5.0 and val <= 30.0 then
            max_search_dist = val
            windower.add_to_chat(207, sjis('[BanishgaPull] 最大検索距離を変更しました: ') .. max_search_dist .. 'm')
        end
        return
    elseif cmd == 'status' or cmd == 'show' then
        local status_str = designated_puller and (sjis('【 ') .. designated_puller .. sjis(' 】 さん')) or sjis('未指定（全員自動検知）')
        windower.add_to_chat(207, sjis('[BanishgaPull] 現在の釣り役: ') .. status_str .. sjis(' / 魔法: ') .. target_spell .. sjis(' / 範囲: ') .. max_search_dist .. 'm')
        return
    end

    -- 2. 即時バニシュガ/タゲ捕獲処理
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
    local max_dist_sq = max_search_dist * max_search_dist
    local min_dist_sq = max_dist_sq
    local min_puller_dist_sq = 999999.0
    local target_priority = 0

    for index, mob in pairs(mob_array) do
        if mob.is_npc and mob.valid_target and mob.hpp > 0 and mob.status ~= 2 and mob.status ~= 3 then
            local dist_self_sq = mob.distance
            if dist_self_sq <= max_dist_sq then
                local current_priority = 1
                local dist_to_puller_sq = nil

                if puller_mob then
                    local dx = mob.x - puller_mob.x
                    local dy = mob.y - puller_mob.y
                    local dz = mob.z - puller_mob.z
                    dist_to_puller_sq = dx*dx + dy*dy + dz*dz
                end

                if mob.target_index and mob.target_index > 0 then
                    local target_entity = windower.ffxi.get_mob_by_index(mob.target_index)
                    if target_entity then
                        if puller_id and target_entity.id == puller_id then
                            current_priority = 4 -- 釣り役被弾中（赤ネーム）
                        elseif party_ids[target_entity.id] then
                            current_priority = 2 -- 他PTメンバー被弾中
                        end
                    end
                end

                -- 釣り役の周囲15m以内にいる敵（黄色ネーム/リンク追尾中）
                if current_priority == 1 and puller_mob and dist_to_puller_sq and dist_to_puller_sq <= 225.0 then
                    current_priority = 3 -- 釣り役追従（黄色ネーム）
                end

                if current_priority > target_priority then
                    target_priority = current_priority
                    best_target = mob
                    min_dist_sq = dist_self_sq
                    if (current_priority == 4 or current_priority == 3) and dist_to_puller_sq then
                        min_puller_dist_sq = dist_to_puller_sq
                    end
                elseif current_priority == target_priority then
                    if (current_priority == 4 or current_priority == 3) and dist_to_puller_sq then
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

        windower.add_to_chat(color, sjis('[BanishgaPull] ') .. p_msg .. ' >> ' .. best_target.name .. ' (' .. string.format('%.1f', real_min_dist) .. 'm) ' .. sjis('へ [' .. target_spell .. '] 発動！'))
        windower.send_command('input /target ' .. best_target.id .. '; wait 0.05; input /ma "' .. target_spell .. '" <t>')
    else
        windower.add_to_chat(123, sjis('[BanishgaPull Error] 射程' .. max_search_dist .. 'm以内に有効な敵が見つかりません。'))
    end
end)
