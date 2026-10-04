-- =============================================================================
-- BanishgaPull.lua : FFXI タグ取り・最速バニシュガ捕獲アドオン (v2.0.0 完全適応版)
-- =============================================================================
-- 【概要】
-- Windower 4 Addon Development Rules & API 仕様書（config, texts, res, packets）に完全準拠。
-- パーティ内の指定釣り役 (Designated Puller) または PTメンバーが交戦・被弾している敵を
-- 最優先で自動検知し、バニシュガ (Banishga) 等の範囲/単体魔法で即座にタグ横取り・捕獲します。
--
-- 【仕様書準拠・機能強化】
-- 1. 設定永続化 (libs/config.lua): 指定釣り役名、使用魔法、HUD位置等を data/settings.xml へ永続化。
-- 2. リアルタイムHUD (libs/texts.lua): 指定釣り役、使用魔法、最優先ターゲット名・距離をUTF-8描画。
-- 3. チャット出力 (windower.add_to_chat): FFXI本体用 Shift-JIS 変換 (windower.to_shift_jis) 適用。
-- 4. 使用魔法カスタマイズ: バニシュガ / バニシュガII / ディアガ / ポイゾガ / ディア 等の自由切替対応。
-- 5. イベントライフサイクル: unload / zone change 時の安全クリーンアップを徹底。
-- =============================================================================

_addon.name     = "BanishgaPull"
_addon.author   = "Gemini Notebook"
_addon.version  = "2.0.0"
_addon.commands = {"bp", "banishgapull"}

require("luau")
local config  = require("config")
local texts   = require("texts")
local res     = require("resources")
local packets = require("packets")

-- -----------------------------------------------------------------------------
-- デフォルト設定 (data/settings.xml 永続化)
-- -----------------------------------------------------------------------------
local defaults = {}
defaults.puller = ""           -- 指定釣り役名 (空文字でPT全員自動検知)
defaults.spell = "Banishga"    -- 使用魔法 (Banishga, Banishga II, Diaga, Dia, Poisonga 等)
defaults.max_distance = 20.0   -- 索敵最大距離 (メートル)
defaults.show_hud = true       -- HUD表示 ON/OFF
defaults.pos = {x = 500, y = 400}
defaults.text = {font = "Meiryo", size = 11, alpha = 255}
defaults.bg = {alpha = 180, red = 10, green = 10, blue = 15}
defaults.padding = 6

local settings = config.load(defaults)

-- -----------------------------------------------------------------------------
-- チャット出力用 Shift-JIS 変換ヘルパー関数
-- -----------------------------------------------------------------------------
local function chat_msg(msg, color)
    color = color or 207
    if windower and windower.to_shift_jis then
        local ok, converted = pcall(windower.to_shift_jis, tostring(msg))
        if ok and converted then
            windower.add_to_chat(color, converted)
            return
        end
    end
    windower.add_to_chat(color, tostring(msg))
end

-- カラーコード装飾 (HUD用 UTF-8)
local function color_text(str, r, g, b)
    return string.format("\cs(%d,%d,%d)%s\cr", r, g, b, tostring(str or ""))
end

-- -----------------------------------------------------------------------------
-- 状態管理変数
-- -----------------------------------------------------------------------------
local state = {
    target_mob = nil,
    target_priority = 0,
    target_dist = 0,
    puller_dist = 0,
}

-- HUDテキストボックス初期化 (texts.lua 準拠)
local hud = texts.new("${text}", settings)

-- -----------------------------------------------------------------------------
-- ターゲット検知コアロジック
-- -----------------------------------------------------------------------------
local function scan_best_target()
    local party = windower.ffxi.get_party()
    local mob_array = windower.ffxi.get_mob_array()
    if not party or not mob_array then return nil end

    local party_ids = {}
    local puller_id = nil
    local puller_mob = nil
    local designated = (settings.puller and settings.puller ~= "") and settings.puller:lower() or nil

    for _, member in pairs(party) do
        if type(member) == "table" and member.mob then
            party_ids[member.mob.id] = member.name
            if designated and member.name:lower() == designated then
                puller_id = member.mob.id
                puller_mob = member.mob
            end
        end
    end

    local max_dist_sq = settings.max_distance * settings.max_distance
    local best_mob = nil
    local best_priority = 0
    local min_dist_self_sq = max_dist_sq
    local min_dist_puller_sq = 999999.0

    for _, mob in pairs(mob_array) do
        if mob.is_npc and mob.valid_target and mob.hpp > 0 and mob.status ~= 2 and mob.status ~= 3 then
            local dist_self_sq = mob.distance
            if dist_self_sq <= max_dist_sq then
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

                if current_priority > best_priority then
                    best_priority = current_priority
                    best_mob = mob
                    min_dist_self_sq = dist_self_sq
                    if current_priority == 3 and dist_to_puller_sq then
                        min_dist_puller_sq = dist_to_puller_sq
                    end
                elseif current_priority == best_priority then
                    if current_priority == 3 and dist_to_puller_sq then
                        if dist_to_puller_sq < min_dist_puller_sq then
                            min_dist_puller_sq = dist_to_puller_sq
                            min_dist_self_sq = dist_self_sq
                            best_mob = mob
                        end
                    elseif dist_self_sq < min_dist_self_sq then
                        min_dist_self_sq = dist_self_sq
                        best_mob = mob
                    end
                end
            end
        end
    end

    if best_mob then
        return {
            mob = best_mob,
            priority = best_priority,
            dist_self = math.sqrt(min_dist_self_sq),
            dist_puller = (min_dist_puller_sq < 990000.0) and math.sqrt(min_dist_puller_sq) or nil,
        }
    end
    return nil
end

-- -----------------------------------------------------------------------------
-- HUD 描画ループ (毎フレーム呼び出し)
-- -----------------------------------------------------------------------------
windower.register_event("prerender", function()
    if not settings.show_hud then
        hud:hide()
        return
    end

    local lines = {}
    table.insert(lines, color_text("=== [ BanishgaPull v2.0 ] ===", 200, 220, 255))
    
    local puller_display = (settings.puller and settings.puller ~= "") and string.format("【 %s 】", settings.puller) or "未指定 (PT全員自動検知)"
    table.insert(lines, string.format("指定釣り役: %s", color_text(puller_display, 255, 220, 100)))
    table.insert(lines, string.format("使用魔法: %s (範囲%.1fm)", color_text(settings.spell, 0, 210, 255), settings.max_distance))

    local res_target = scan_best_target()
    if res_target then
        state.target_mob = res_target.mob
        local prio_tag = "【近隣敵】"
        local prio_color = {200, 200, 200}
        
        if res_target.priority == 3 then
            prio_tag = string.format("【★釣り役(%s)被弾中】", settings.puller)
            prio_color = {255, 100, 100}
        elseif res_target.priority == 2 then
            prio_tag = "【PTメンバー被弾中】"
            prio_color = {255, 200, 100}
        end

        local p_dist_str = res_target.dist_puller and string.format(" / 釣り役から%.1fm", res_target.dist_puller) or ""
        table.insert(lines, string.format("捕獲標的: %s %s", color_text(prio_tag, unpack(prio_color)), color_text(res_target.mob.name, 100, 255, 150)))
        table.insert(lines, string.format("標的距離: %.1fm%s", res_target.dist_self, p_dist_str))
    else
        state.target_mob = nil
        table.insert(lines, string.format("捕獲標的: %s", color_text("範囲内に対象なし", 180, 180, 180)))
    end

    hud.text = table.concat(lines, string.char(10))
    hud:show()
end)

-- -----------------------------------------------------------------------------
-- イベントクリーンアップ (unload / zone change)
-- -----------------------------------------------------------------------------
windower.register_event("unload", function()
    if hud then hud:hide() end
end)

windower.register_event("zone change", function()
    state.target_mob = nil
end)

-- -----------------------------------------------------------------------------
-- セルフコマンド処理 (//bp または //banishgapull)
-- -----------------------------------------------------------------------------
windower.register_event("addon command", function(cmd, ...)
    local args = {...}
    cmd = cmd and cmd:lower() or "pull"

    -- 1. 釣り役の設定・解除
    if cmd == "puller" or cmd == "set" then
        local name = args[1]
        if not name or name == "" or name:lower() == "reset" or name:lower() == "clear" or name:lower() == "off" then
            settings.puller = ""
            config.save(settings)
            chat_msg("[BanishgaPull] 釣り役指定を【解除】しました。(PT全員自動検知)")
        else
            settings.puller = name
            config.save(settings)
            chat_msg(string.format("[BanishgaPull] 釣り役設定: 【 %s 】さんを最優先追跡します！", name), 209)
        end
        return

    -- 2. 使用魔法の変更
    elseif cmd == "spell" or cmd == "ma" then
        local spell_name = args[1]
        if spell_name and spell_name ~= "" then
            settings.spell = spell_name
            config.save(settings)
            chat_msg(string.format("[BanishgaPull] 使用魔法を 【 %s 】 に変更しました。", spell_name))
        else
            chat_msg("[BanishgaPull] 使用例: //bp spell Banishga II")
        end
        return

    -- 3. 索敵距離の設定
    elseif cmd == "dist" or cmd == "distance" then
        local dist_val = tonumber(args[1])
        if dist_val and dist_val >= 5.0 and dist_val <= 30.0 then
            settings.max_distance = dist_val
            config.save(settings)
            chat_msg(string.format("[BanishgaPull] 索敵最大距離を %.1fm に設定しました。", dist_val))
        end
        return

    -- 4. HUD表示ON/OFF
    elseif cmd == "hud" then
        settings.show_hud = not settings.show_hud
        config.save(settings)
        chat_msg(string.format("[BanishgaPull] HUD表示: %s", settings.show_hud and "ON" or "OFF"))
        return

    -- 5. ステータス確認
    elseif cmd == "status" or cmd == "show" then
        local p_str = (settings.puller and settings.puller ~= "") and string.format("【 %s 】さん", settings.puller) or "未指定 (PT全員自動検知)"
        chat_msg("=== BanishgaPull 設定ステータス ===")
        chat_msg(string.format("指定釣り役: %s / 使用魔法: %s / 索敵距離: %.1fm", p_str, settings.spell, settings.max_distance))
        return
    end

    -- 6. 即時バニシュガ捕獲実行 (引数なし //bp または //bp pull)
    local res_target = scan_best_target()
    if res_target then
        local p_msg = "【近隣敵】"
        local color = 200

        if res_target.priority == 3 then
            local p_dist_str = res_target.dist_puller and string.format(" [釣り役から%.1fm]", res_target.dist_puller) or ""
            p_msg = string.format("【★指定釣り役(%s)被弾中%s】", settings.puller, p_dist_str)
            color = 209
        elseif res_target.priority == 2 then
            p_msg = "【PTメンバー被弾中】"
            color = 207
        end

        chat_msg(string.format("[BanishgaPull] %s >> %s (%.1fm) へ [%s] 発動！", p_msg, res_target.mob.name, res_target.dist_self, settings.spell), color)
        
        -- タゲ切り替え ➔ 魔法キャスト実行
        windower.send_command(string.format('input /target %s; wait 0.05; input /ma "%s" <t>', res_target.mob.name, settings.spell))
    else
        chat_msg(string.format("[BanishgaPull Error] 射程%.1fm以内に有効な敵が見つかりません。", settings.max_distance), 123)
    end
end)
