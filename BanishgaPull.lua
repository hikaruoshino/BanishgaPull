_addon.name = 'BanishgaPull'
_addon.author = 'Hikaru Oshino'
_addon.version = '1.8'
_addon.commands = {'bp', 'banishgapull'}

require('luau')
require('chat')

local designated_puller = nil

-- UTF-8からShift-JISへの変換ヘルパー（FF11チャットログの文字化け防止）
local function sjis(str)
    if not str then return '' end
    return windower.to_shift_jis and windower.to_shift_jis(str) or str
end

-- 味方専用特殊オブジェクト（羅盤等）除外用リスト
local ignore_names = S{
    'luopan', '羅盤'
}

-- 有効な敵モンスター判定関数（NPC, 競売カウンター, 味方ペット除外）
local function is_valid_enemy(mob)
    if not mob or not mob.is_npc or not mob.valid_target or mob.hpp <= 0 then return false end
    if mob.status == 2 or mob.status == 3 then return false end
    if mob.in_party or mob.in_alliance then return false end
    if mob.spawn_type and mob.spawn_type ~= 16 then return false end

    local name_lower = mob.name:lower()
    if ignore_names:contains(name_lower) or ignore_names:contains(mob.name) then return false end

    return true
end

-- ヘルプ表示関数
local function show_help()
    windower.add_to_chat(207, '==================================================')
    windower.add_to_chat(207, sjis('  [BanishgaPull v1.8] コマンド・使い方ヘルプ'))
    windower.add_to_chat(207, '--------------------------------------------------')
    windower.add_to_chat(207, sjis('  //bp                    : 最優先の敵を自動選択し即時バニシュガ'))
    windower.add_to_chat(207, sjis('  //bp puller <キャラ名>   : 指定キャラを「釣り役」に設定'))
    windower.add_to_chat(207, sjis('  //bp puller <t>         : ターゲット中の味方を「釣り役」に設定'))
    windower.add_to_chat(207, sjis('  //bp puller reset       : 釣り役設定を解除（全員自動検知）'))
    windower.add_to_chat(207, sjis('  //bp status             : 現在の釣り役設定を確認'))
    windower.add_to_chat(207, sjis('  //bp ?                  : このヘルプを表示'))
    windower.add_to_chat(207, '==================================================')
end

windower.register_event('addon command', function(cmd, ...)
    local args = {...}
    cmd = cmd and cmd:lower() or 'pull'

    -- ★ ヘルプ表示（//bp ? / //bp help / //bp h）
    if cmd == '?' or cmd == 'help' or cmd == 'h' then
        show_help()
        return
    end

    -- 1. 釣り役の設定・変更・解除処理
    if cmd == 'puller' or cmd == 'set' then
        local raw_name = args and table.concat(args, ' ') or ''
        local name = raw_name:match('^%s*(.-)%s*$')

        if not name or name == '' or name:lower() == 'reset' or name:lower() == 'clear' or name:lower() == 'off' then
            designated_puller = nil
            windower.add_to_chat(158, '--------------------------------------------------')
            windower.add_to_chat(158, sjis('  [BanishgaPull] 釣り役指定を【解除】しました。'))
            windower.add_to_chat(158, sjis('  ※パーティメンバー全員を対象に自動検知します。'))
            windower.add_to_chat(158, '--------------------------------------------------')
        else
            local party = windower.ffxi.get_party()
            local is_in_party = false
            local matched_name = name

            if party then
                for k, member in pairs(party) do
                    if type(member) == 'table' and member.name and member.name:lower() == name:lower() then
                        is_in_party = true
                        matched_name = member.name
                        break
                    end
                end
            end

            if is_in_party then
                designated_puller = matched_name
                windower.add_to_chat(209, '==================================================')
                windower.add_to_chat(209, sjis('  [BanishgaPull] 釣り役設定: 【 ') .. designated_puller .. sjis(' 】 さん'))
                windower.add_to_chat(209, sjis('  ※ ') .. designated_puller .. sjis(' さんに最も近い攻撃中の敵を最優先で捕獲します！'))
                windower.add_to_chat(209, '==================================================')
            else
                windower.add_to_chat(123, sjis('[BanishgaPull Error] 【 ') .. name .. sjis(' 】 はパーティメンバーではありません。'))
            end
        end
        return
    elseif cmd == 'status' or cmd == 'show' then
        local status_str = designated_puller and (sjis('【 ') .. designated_puller .. sjis(' 】 さん')) or sjis('未指定（全員自動検知）')
        windower.add_to_chat(207, sjis('[BanishgaPull] 現在の釣り役: ') .. status_str)
        return
    end

    -- 2. 即時バニシュガ捕獲処理
    local player = windower.ffxi.get_player()
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
    local min_dist = 999          -- 自分からの距離
    local min_puller_dist = 999   -- 釣り役からの距離
    local target_priority = 0

    for index, mob in pairs(mob_array) do
        if is_valid_enemy(mob) then
            local dist_self = math.sqrt(mob.distance)
            if dist_self <= 20.0 then -- 自分から射程20m以内
                local current_priority = 1
                local dist_to_puller = nil

                if mob.target_index and mob.target_index > 0 then
                    local target_entity = windower.ffxi.get_mob_by_index(mob.target_index)
                    if target_entity then
                        if puller_id and target_entity.id == puller_id then
                            current_priority = 3
                            if puller_mob then
                                local dx = mob.x - puller_mob.x
                                local dy = mob.y - puller_mob.y
                                local dz = mob.z - puller_mob.z
                                dist_to_puller = math.sqrt(dx*dx + dy*dy + dz*dz)
                            end
                        elseif party_ids[target_entity.id] then
                            current_priority = 2
                        end
                    end
                end

                if current_priority > target_priority then
                    target_priority = current_priority
                    best_target = mob
                    min_dist = dist_self
                    if current_priority == 3 and dist_to_puller then
                        min_puller_dist = dist_to_puller
                    end
                elseif current_priority == target_priority then
                    if current_priority == 3 and dist_to_puller then
                        if dist_to_puller < min_puller_dist then
                            min_puller_dist = dist_to_puller
                            min_dist = dist_self
                            best_target = mob
                        end
                    elseif dist_self < min_dist then
                        min_dist = dist_self
                        best_target = mob
                    end
                end
            end
        end
    end

    if best_target then
        local p_msg = ''
        local color = 207
        if target_priority == 3 then
            local p_dist_str = (min_puller_dist and min_puller_dist < 990) and string.format(' [釣り役から%.1fm]', min_puller_dist) or ''
            p_msg = sjis('【★指定釣り役 (' .. (designated_puller or '') .. ') 被弾中' .. p_dist_str .. '】')
            color = 209
        elseif target_priority == 2 then
            p_msg = sjis('【PTメンバー被弾中】')
            color = 207
        else
            p_msg = sjis('【近隣の敵】')
            color = 200
        end

        windower.add_to_chat(color, sjis('[BanishgaPull] ') .. p_msg .. ' >> ' .. best_target.name .. ' (' .. string.format('%.1f', min_dist) .. 'm) ' .. sjis('へ [バニシュガ] 発動！'))
        windower.send_command('input /target ' .. best_target.id .. '; wait 0.05; input /ma "' .. sjis('バニシュガ') .. '" <t>')
    else
        windower.add_to_chat(123, sjis('[BanishgaPull Error] 周囲に敵はいません。'))
    end
end)
