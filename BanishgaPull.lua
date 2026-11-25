_addon.name = 'BanishgaPull'
_addon.author = 'hikaruoshino'
_addon.version = '2.5.3'
_addon.commands = {'bp', 'banishgapull'}

require('chat')
local config = require('config')
local res = require('resources')

-- 設定 (data/settings.xml)
--   spell        : 唱える魔法 (日本語クライアントでは日本語名。例: バニシュガ / ディアガ)
--   max_distance : 自分からの射程 (m)
--   puller       : 釣り役の名前 (空なら全員自動検知)
local DEFAULT_SPELL = 'バニシュガ'
local DEFAULT_RANGE = 20
local MAX_RANGE = 50    -- //bp range と settings.xml の射程の上限 (m)
local defaults = {
    spell = DEFAULT_SPELL,
    max_distance = DEFAULT_RANGE,
    puller = '',
    lang = 'auto',          -- 表示の言語: auto (クライアントの言語に合わせる) / ja / en
    reject_message = '',    -- 「唱えられなかった」と判断するチャットの文 (空なら言語ごとの既定)
}
local settings = config.load(defaults)

-- 前後の空白を除く。文字列でなければ nil
local function trim(s)
    if type(s) ~= 'string' then return nil end
    return s:match('^%s*(.-)%s*$')
end

-- settings.spell を文字列にそろえる。config は settings.xml の <spell>123</spell> や <spell>true</spell> を
-- 数値・真偽値のまま入れるので文字列に直す。nil・表・空・空白だけは既定の魔法に戻す
local function normalize_spell(v)
    local t = type(v)
    if t == 'number' or t == 'boolean' then
        v = tostring(v)
    elseif t ~= 'string' then
        return DEFAULT_SPELL
    end
    v = trim(v)
    if v == '' then return DEFAULT_SPELL end
    return v
end

-- settings.max_distance を //bp range と同じ範囲 (0 超〜MAX_RANGE 以下) にそろえる。
-- 数にできない値・NaN・無限大・0 以下は既定の射程、MAX_RANGE を超える値は MAX_RANGE にする
local function normalize_range(v)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge or n <= 0 then return DEFAULT_RANGE end
    if n > MAX_RANGE then return MAX_RANGE end
    return n
end

-- 読み込んだ値を直す (保存はしない。読み込みのたびに直る)
settings.spell = normalize_spell(settings.spell)
settings.max_distance = normalize_range(settings.max_distance)

-- ゲームクライアントの言語 (windower.ffxi.get_info().language)。
-- 送る魔法名・拒否文・チャットの文字コードはこちらで決める (表示の言語 LANG とは別)
local function client_is_ja()
    local ok, info = pcall(windower.ffxi.get_info)
    local l = ok and info and info.language and tostring(info.language):lower() or 'japanese'
    return l == 'japanese'
end
local CLIENT_JA = client_is_ja()

-- 表示の言語。auto のときはクライアントの言語に合わせる。
-- 英語クライアントは日本語の文字を出せないので、lang = ja でも英語にする (2 つ目の戻り値 true で知らせる)
local function resolve_lang()
    local s = tostring(settings.lang or 'auto'):lower()
    if s == 'ja' and not CLIENT_JA then return 'en', true end
    if s == 'ja' or s == 'en' then return s end
    return CLIENT_JA and 'ja' or 'en'
end
local LANG, LANG_FALLBACK = resolve_lang()

-- 日本語と英語の文を対で書く。言語に合わせたほうを返す
local function L(ja, en)
    if LANG == 'ja' then return ja end
    return en
end

local PULLER_NEAR_SQ = 225.0 -- 釣り役から 15m 以内 (2乗)

local function get_puller()
    local p = settings.puller
    if type(p) ~= 'string' or p == '' then return nil end
    return p
end

-- UTF-8からShift-JISへの変換ヘルパー (チャットとゲームへのコマンドに通す。日本語クライアントのときだけ)
local function sjis(str)
    if not str then return '' end
    if not CLIENT_JA then return str end
    return windower.to_shift_jis and windower.to_shift_jis(str) or str
end

-- チャットから届く引数 (Shift-JIS) を UTF-8 に戻す (日本語クライアントのときだけ)
local function from_sjis(str)
    if not str then return nil end
    if not CLIENT_JA then return str end
    return windower.from_shift_jis and windower.from_shift_jis(str) or str
end

-- 設定を保存する。保存先を開けないと libs/files.lua が例外を出すので pcall で包む。保存できたら true
local function save_settings()
    local ok = pcall(config.save, settings)
    return ok
end

-- 保存できなかったときに知らせる (変更は今回の読み込みのあいだだけ有効)
local function warn_save_failed()
    windower.add_to_chat(123, sjis(L('[BanishgaPull] 設定を保存できませんでした。変更は今回だけ有効です。',
        '[BanishgaPull] Could not save the settings. The change lasts until the addon is reloaded.')))
end

local function save_or_warn()
    if not save_settings() then warn_save_failed() end
end

-- 有限の数か (nil・NaN・無限大を外す)
local function finite(v)
    return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge
end

-- 2 つの座標の距離の 2 乗。どちらかの x・y・z が有限の数でなければ nil
local function dist_sq_between(a, b)
    local ax, ay, az, bx, by, bz = a.x, a.y, a.z, b.x, b.y, b.z
    if not (finite(ax) and finite(ay) and finite(az) and finite(bx) and finite(by) and finite(bz)) then return nil end
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return dx*dx + dy*dy + dz*dz
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

-- ゲームが受け付けなかった敵 (「選択されたコマンドを実行できない」) は、しばらく選ばない。
-- 同じ敵が選ばれ続けて、マクロを何度押しても唱えられなくなるのを防ぐ
-- 英語クライアントの文は 'Unable to execute that command' (ユーザーの記憶による。ゲーム内未確認)。届かないときは settings.xml の reject_message に実際の文を書く
-- 拒否文はクライアントの言語で届くので、表示の言語ではなくクライアントの言語で既定を選ぶ
-- settings.xml の値が文字列のときだけ使う。config は <reject_message>123</reject_message> を数値、空タグを表で入れるので、
-- 文字列でない・空・空白だけのときは言語ごとの既定の文に戻す (spell と同じ扱い。例外を出さない)
local function normalize_reject_message(v)
    v = trim(v)
    if v and v ~= '' then return v end
    return CLIENT_JA and '選択されたコマンドを実行できない' or 'Unable to execute that command'
end
local REJECT_MESSAGE = normalize_reject_message(settings.reject_message)
local REJECT_MESSAGE_RAW = sjis(REJECT_MESSAGE)   -- incoming text の original と比べる形 (読み込み時に 1 回だけ変換)
local REJECT_WINDOW_SEC = 3     -- 唱えると送ってから、この秒数以内に届いたこのメッセージを、その敵のものとみなす
local SEND_GUARD_SEC = 1        -- 送ってからこの秒数のうちに押されたら、もう一度は送らない (押し直しの重複を防ぐ)
local BAD_TARGET_SEC = 15       -- 受け付けなかった敵を選ばない秒数
local CAST_BEGIN, CAST_INTERRUPT = 24931, 28787   -- action の category 8 (詠唱) の param: 開始 / 中断

-- 直近の要求 (送った詠唱)。nil なら結び付ける要求は無い
--   id: 敵の ID / spell_id: 魔法の ID (名前が res に無ければ nil) / at: 送った時刻 (os.clock)
--   ambiguous: 前の要求が未確定のうちに送った (拒否文がどちらのものか分からない)
local pending = nil
local bad_targets = {}          -- [敵の ID] = 選ばない期限 (os.clock)

local function is_bad_target(id, now)
    local until_time = bad_targets[id]
    return until_time ~= nil and now <= until_time
end

-- 期限の過ぎた除外を消す (その敵が候補に戻るかどうかに関係なく、コマンドのたびに)
local function prune_bad_targets(now)
    for id, until_time in pairs(bad_targets) do
        if now > until_time then bad_targets[id] = nil end
    end
end

-- 除外表と直近の要求を消す (ゾーン移動・ログアウト)
local function reset_state()
    pending = nil
    for id in pairs(bad_targets) do bad_targets[id] = nil end
end

-- 送ってから REJECT_WINDOW_SEC 秒を過ぎた要求を消す (詠唱開始も拒否文も届かなかった要求を残さない)。
-- 時刻が逆に進んだとき (now < at) も、結び付けられないので消す
local function expire_pending(now)
    local p = pending
    if p and (type(p.at) ~= 'number' or now - p.at > REJECT_WINDOW_SEC or now < p.at) then
        pending = nil
    end
end

-- 唱える魔法の ID を名前から探す (日本語名・英語名どちらでも)。見つからなければ nil
local function find_spell_id(name)
    if type(name) ~= 'string' or name == '' then return nil end
    local lower = name:lower()
    for id, row in pairs(res.spells) do
        if type(row) == 'table' and (row.ja == name or (row.en and row.en:lower() == lower)) then
            return id
        end
    end
    return nil
end

-- 唱える魔法の ID と、ゲームへ送る名前 (クライアントの言語の名前)。
-- 旧版の英語名 'Banishga' を日本語クライアントで日本語名にし、英語クライアントで日本語名を英語名にする。
-- 保存の成否に関係なく、毎回 settings.spell から決める (同じ名前なら前の結果を使い、res.spells を引き直さない)
-- 3 つ目の戻り値は表示用の名前 (表示の言語の名前。res に無い名前は設定のまま)
-- settings.spell が文字列でない・空になっていても、normalize_spell で直した名前から決める (例外を出さない)
local spell_cache_set = false
local spell_cache_key, spell_cache_id, spell_cache_name, spell_cache_label = nil, nil, nil, nil
local function current_spell()
    local raw = settings.spell
    if not spell_cache_set or raw ~= spell_cache_key then
        local s = normalize_spell(raw)
        local id = find_spell_id(s)
        local row = id and res.spells[id]
        spell_cache_set, spell_cache_key, spell_cache_id = true, raw, id
        spell_cache_name = row and (CLIENT_JA and (row.ja or row.en) or (row.en or row.ja)) or s
        spell_cache_label = row and ((LANG == 'ja') and (row.ja or row.en) or (row.en or row.ja)) or s
    end
    return spell_cache_id, spell_cache_name, spell_cache_label
end

-- 設定の名前がクライアントの言語の名前と違えば直して保存する (保存できなくても、送る名前は current_spell で直る)
do
    local _, name = current_spell()
    if name and name ~= settings.spell then
        settings.spell = name
        save_settings()
    end
end

if LANG_FALLBACK then
    windower.add_to_chat(167, '[BanishgaPull] lang = ja needs the Japanese client. Using English.')
end

windower.register_event('addon command', function(cmd, ...)
    local args = {...}
    cmd = cmd and cmd:lower() or 'pull'
    expire_pending(os.clock())

    -- 1. 釣り役の設定・変更・解除処理
    if cmd == 'puller' or cmd == 'set' then
        local name = args[1]
        if not name or name == '' or name:lower() == 'reset' or name:lower() == 'clear' or name:lower() == 'off' then
            settings.puller = ''
            windower.add_to_chat(158, '--------------------------------------------------')
            windower.add_to_chat(158, sjis(L('  [BanishgaPull] 釣り役指定を【解除】しました。', '  [BanishgaPull] Puller cleared.')))
            windower.add_to_chat(158, sjis(L('  ※パーティメンバー全員を対象に自動検知します。', '  Mobs attacking any party member are now picked.')))
            windower.add_to_chat(158, '--------------------------------------------------')
        else
            settings.puller = name
            windower.add_to_chat(209, '==================================================')
            windower.add_to_chat(209, sjis(L('  [BanishgaPull] 釣り役設定: 【 ', '  [BanishgaPull] Puller set: ')) .. name .. sjis(L(' 】 さん', '')))
            windower.add_to_chat(209, sjis(L('  ※ ', '  Mobs attacking or near ')) .. name .. sjis(L(' さんの周囲の敵（黄色ネーム含む）を最優先で捕獲します！', ' (including unclaimed ones) are picked first.')))
            windower.add_to_chat(209, '==================================================')
        end
        save_or_warn()
        return
    elseif cmd == 'spell' then
        -- //bp spell ディアガ : 唱える魔法を変更
        -- 前後の空白を除く。空・空白だけは、従来どおり現在の魔法を表示する (設定の読み込みと同じ扱い)
        local name = trim(from_sjis(table.concat(args, ' ')))
        if not name or name == '' then
            windower.add_to_chat(207, sjis(L('[BanishgaPull] 現在の魔法: ' .. settings.spell .. ' (変更: //bp spell 魔法名)', '[BanishgaPull] Current spell: ' .. settings.spell .. ' (change: //bp spell <name>)')))
            return
        end
        -- 魔法名は /ma "魔法名" にそのまま入るので、引用符と ; (コマンドの区切り) を含む名前は受け付けない
        if name:find('[";]') then
            windower.add_to_chat(123, sjis(L('[BanishgaPull] 魔法名に " と ; は使えません: ' .. name, '[BanishgaPull] A spell name cannot contain " or ;: ' .. name)))
            return
        end
        settings.spell = name
        windower.add_to_chat(209, sjis(L('[BanishgaPull] 唱える魔法を【 ' .. name .. ' 】に変更しました。', '[BanishgaPull] Spell set to [' .. name .. '].')))
        save_or_warn()
        return
    elseif cmd == 'range' or cmd == 'distance' then
        -- //bp range 20 : 自分からの射程 (m) を変更
        -- NaN・無限大は拒否する (tonumber('nan') や tonumber('inf') の結果は C ランタイムによって違うので、どちらでも拒否する)
        local dist = tonumber(args[1])
        if not dist or dist ~= dist or dist == math.huge or dist <= 0 or dist > MAX_RANGE then
            windower.add_to_chat(207, sjis(string.format(L('[BanishgaPull] 現在の射程: %sm (変更: //bp range 数値)', '[BanishgaPull] Current range: %sm (change: //bp range <yalms>)'), tostring(settings.max_distance))))
            return
        end
        settings.max_distance = dist
        windower.add_to_chat(209, sjis(string.format(L('[BanishgaPull] 射程を %.1fm に変更しました。', '[BanishgaPull] Range set to %.1f.'), dist)))
        save_or_warn()
        return
    elseif cmd == 'status' or cmd == 'show' then
        local puller = get_puller()
        local status_str = puller and (sjis(L('【 ', '')) .. puller .. sjis(L(' 】 さん', ''))) or sjis(L('未指定（全員自動検知）', 'none (any party member)'))
        windower.add_to_chat(207, sjis(L('[BanishgaPull] 現在の釣り役: ', '[BanishgaPull] Puller: ')) .. status_str)
        windower.add_to_chat(207, sjis(string.format(L('[BanishgaPull] 魔法: %s / 射程: %sm', '[BanishgaPull] Spell: %s / range: %s'), settings.spell, tostring(settings.max_distance))))
        return
    elseif cmd == 'lang' then
        local v = args[1] and args[1]:lower()
        if v == 'auto' or v == 'ja' or v == 'en' then
            settings.lang = v
            windower.add_to_chat(207, '[BanishgaPull] Language: ' .. v .. ' (reload with //lua r BanishgaPull to apply)')
            save_or_warn()
        else
            windower.add_to_chat(207, '[BanishgaPull] Language: ' .. tostring(settings.lang) .. ' (now ' .. LANG .. '). Use //bp lang auto|ja|en')
        end
        return
    elseif cmd == 'help' then
        windower.add_to_chat(207, sjis(L('[BanishgaPull] //bp              : 釣り役周辺の敵へ魔法を発動', '[BanishgaPull] //bp              : pick one mob and cast the spell on it')))
        windower.add_to_chat(207, sjis(L('[BanishgaPull] //bp set 名前     : 釣り役を指定 (//bp set off で解除)', '[BanishgaPull] //bp set <name>  : set the puller (//bp set off to clear)')))
        windower.add_to_chat(207, sjis(L('[BanishgaPull] //bp spell 魔法名 : 唱える魔法を変更 (例: ディアガ)', '[BanishgaPull] //bp spell <name>: change the spell (e.g. Diaga)')))
        windower.add_to_chat(207, sjis(L('[BanishgaPull] //bp range 数値   : 自分からの射程 (m) を変更', '[BanishgaPull] //bp range <n>   : change the range from you (yalms)')))
        windower.add_to_chat(207, sjis(L('[BanishgaPull] //bp status       : 現在の設定を表示', '[BanishgaPull] //bp status       : show the current settings')))
        windower.add_to_chat(207, sjis('[BanishgaPull] //bp lang auto|ja|en : ' .. L('表示の言語', 'display language')))
        return
    elseif cmd ~= 'pull' then
        -- 表にないコマンド (旧説明の //bp dist や綴り間違いなど) で、詠唱が実行されないようにする
        windower.add_to_chat(123, sjis(L('[BanishgaPull] 不明なコマンドです: ' .. cmd .. ' (一覧: //bp help)', '[BanishgaPull] Unknown command: ' .. cmd .. ' (list: //bp help)')))
        return
    end

    -- 2. 即時捕獲処理
    -- 魔法がリキャスト中なら、唱えずに残り時間を知らせる (ゲームの値が取れて、魔法名が分かるときだけ)
    local now = os.clock()
    prune_bad_targets(now)
    -- 送った直後の押し直しでは送らない (同じ要求を重ねて送らない。結果は詠唱開始か拒否文で分かる)
    if pending and now - pending.at < SEND_GUARD_SEC then
        windower.add_to_chat(207, sjis(L('[BanishgaPull] 送信済みです。結果を待っています。', '[BanishgaPull] Already sent. Waiting for the result.')))
        return
    end
    local spell_id, spell, spell_label = current_spell()   -- spell: ゲームへ送る名前 / spell_label: 表示する名前
    if spell_id then
        local frames = (windower.ffxi.get_spell_recasts() or {})[spell_id]
        if frames and frames > 0 then
            windower.add_to_chat(123, sjis(string.format(L('[BanishgaPull] [%s] はリキャスト中です (あと %.1f 秒)。', '[BanishgaPull] [%s] is on recast (%.1f s left).'), spell_label, frames / 60)))
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

    local max_dist = normalize_range(settings.max_distance)   -- 読み込み時に直した値。数にできなければ既定の射程
    local max_dist_sq = max_dist * max_dist   -- mob.distance は2乗値
    local best_target = nil
    local min_dist_sq = max_dist_sq
    local min_puller_dist_sq = 999999.0  -- 釣り役からの距離の2乗
    local target_priority = 0
    local skipped_hidden = 0   -- 射程内にいるが、描画されていない (ターゲットできない) 敵
    local skipped_claim = 0    -- 射程内にいるが、他 PT にクレームされている敵
    local skipped_bad = 0      -- 射程内にいるが、ゲームが受け付けなかった敵 (しばらく選ばない)

    for index, mob in pairs(mob_array) do
        -- 外した敵の数を数える (表示用)
        if mob.is_npc and is_enemy(mob) and (mob.hpp or 0) > 0 and mob.status ~= 2 and mob.status ~= 3
            and (mob.distance or math.huge) <= max_dist_sq then
            if not mob.valid_target then
                skipped_hidden = skipped_hidden + 1
            elseif not is_claim_ok(mob, party_ids) then
                skipped_claim = skipped_claim + 1
            elseif is_bad_target(mob.id, now) then
                skipped_bad = skipped_bad + 1
            end
        end
        -- 生きていてターゲット可能な敵 (フェイス・ペット・NPC・他PTクレームは除外)
        if mob.is_npc and mob.valid_target and is_enemy(mob) and is_claim_ok(mob, party_ids) and not is_bad_target(mob.id, now)
            and (mob.hpp or 0) > 0 and mob.status ~= 2 and mob.status ~= 3 then
            local dist_self_sq = mob.distance or math.huge   -- 距離が取れない敵は射程外として扱う (上の数える側と同じ)
            -- 自分からの距離が射程以内
            if dist_self_sq <= max_dist_sq then
                local current_priority = 1
                local dist_to_puller_sq = nil

                -- 釣り役と敵の両方で有限の座標が取れる場合だけ、釣り役からの距離を計算 (取れなければ nil のまま、ほかの判定を続ける)
                if puller_mob then
                    dist_to_puller_sq = dist_sq_between(mob, puller_mob)
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
                    -- 優先度が上がったら、前の優先度の敵の距離を引き継がない (取れなければ「距離なし」に戻す)
                    min_puller_dist_sq = dist_to_puller_sq or 999999.0
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
    if skipped_hidden > 0 or skipped_claim > 0 or skipped_bad > 0 then
        skipped_msg = sjis(string.format(L('[BanishgaPull] 対象外: 描画されていない敵 %d 体 / 他PTのクレーム %d 体', '[BanishgaPull] Skipped: %d not drawn / %d claimed by another party'), skipped_hidden, skipped_claim))
        if skipped_bad > 0 then
            skipped_msg = skipped_msg .. sjis(string.format(L(' / 受け付けられなかった敵 %d 体', ' / %d refused by the game'), skipped_bad))
        end
    end

    if best_target then
        local real_min_dist = math.sqrt(min_dist_sq)
        local p_msg, color   -- 下の分岐のどれかで必ず決まる

        if target_priority == 4 then
            local real_puller_dist = (min_puller_dist_sq < 990000.0) and math.sqrt(min_puller_dist_sq) or nil
            local p_dist_str = real_puller_dist and string.format(L(' [釣り役から%.1fm]', ' [%.1f from puller]'), real_puller_dist) or ''
            p_msg = sjis(L('【★指定釣り役 (' .. (designated_puller or '') .. ') 被弾中' .. p_dist_str .. '】', '[Puller (' .. (designated_puller or '') .. ') is being attacked' .. p_dist_str .. ']'))
            color = 209
        elseif target_priority == 3 then
            local real_puller_dist = (min_puller_dist_sq < 990000.0) and math.sqrt(min_puller_dist_sq) or nil
            local p_dist_str = real_puller_dist and string.format(L(' [釣り役から%.1fm]', ' [%.1f from puller]'), real_puller_dist) or ''
            p_msg = sjis(L('【★指定釣り役 (' .. (designated_puller or '') .. ') 追従・黄色ネーム' .. p_dist_str .. '】', '[Near puller (' .. (designated_puller or '') .. ')' .. p_dist_str .. ']'))
            color = 209
        elseif target_priority == 2 then
            p_msg = sjis(L('【PTメンバー被弾中】', '[Party member is being attacked]'))
            color = 207
        else
            p_msg = sjis(L('【近隣敵】', '[Nearby mob]'))
            color = 200
        end

        -- settings.xml を手で書いたときも、引用符と ; を含む名前は送らない (/ma のコマンドが崩れるため)
        if spell:find('[";]') then
            windower.add_to_chat(123, sjis(L('[BanishgaPull] 魔法名に " と ; は使えません: ' .. spell, '[BanishgaPull] A spell name cannot contain " or ;: ' .. spell)))
            return
        end
        -- ここでは「送った」だけを出す。受理 (詠唱の開始) は action イベントで確かめてから出す
        windower.add_to_chat(color, sjis('[BanishgaPull] ') .. p_msg .. ' >> ' .. best_target.name .. ' (' .. string.format('%.1f', real_min_dist) .. 'm) ' .. sjis(L('へ [' .. spell_label .. '] を送信', '-> [' .. spell_label .. '] sent')))
        -- ターゲットを切り替えずに、敵の ID を直接指定して唱える (切り替え待ちで別の敵に飛ぶのを防ぐ)
        windower.send_command(sjis('input /ma "' .. spell .. '" ' .. best_target.id))
        -- 前の要求が未確定のうちに送ったら、このあとの拒否文がどちらのものか分からない
        local ambiguous = pending ~= nil and now - pending.at <= REJECT_WINDOW_SEC
        pending = {id = best_target.id, name = best_target.name, spell_id = spell_id, spell = spell_label, at = now, ambiguous = ambiguous}
        if skipped_msg then windower.add_to_chat(207, skipped_msg) end
    else
        windower.add_to_chat(123, sjis(string.format(L('[BanishgaPull Error] 射程%sm以内に有効な敵が見つかりません。', '[BanishgaPull Error] No valid mob within %s yalms.'), tostring(max_dist))))
        if skipped_msg then windower.add_to_chat(207, skipped_msg) end
    end
end)

-- 唱えると送った直後に「選択されたコマンドを実行できない」が届いたら、その敵は受け付けられなかったので、しばらく選ばない。
-- 拒否文には敵も魔法も書かれていないので、次のときだけ直近の要求に結び付ける:
--   送ってから REJECT_WINDOW_SEC 秒以内・まだ詠唱の開始も中断も届いていない・前の要求が未確定のうちに送った要求ではない
windower.register_event('incoming text', function(original)
    local p = pending
    if not p then return end
    if type(original) ~= 'string' or not original:find(REJECT_MESSAGE_RAW, 1, true) then return end
    local now = os.clock()
    pending = nil
    if now - p.at > REJECT_WINDOW_SEC or p.ambiguous then return end
    bad_targets[p.id] = now + BAD_TARGET_SEC
    windower.add_to_chat(123, sjis(string.format(L('[BanishgaPull] その敵には唱えられなかったので、%d 秒間は選びません。もう一度押すと別の敵を選びます。', '[BanishgaPull] The game refused that mob, so it is skipped for %d s. Press again to pick another.'), BAD_TARGET_SEC)))
end)

-- 自分の詠唱の開始・中断 (action パケット category 8) で、直近の要求の結果を確かめる。
-- 開始は「自分・同じ敵 (targets[1].id)・同じ魔法 (魔法 ID が分かるとき)」が揃ったときだけ受理とみなす
windower.register_event('action', function(act)
    if not pending then return end
    expire_pending(os.clock())   -- 時間切れの要求には結び付けない
    local p = pending
    if not p or type(act) ~= 'table' or act.category ~= 8 then return end
    local player = windower.ffxi.get_player()
    if not player or act.actor_id ~= player.id then return end
    if act.param == CAST_INTERRUPT then
        pending = nil   -- 詠唱は始まっていた。このあとの拒否文は、この要求のものではない
        return
    end
    if act.param ~= CAST_BEGIN then return end
    local target = act.targets and act.targets[1]
    local action = target and target.actions and target.actions[1]
    if not target or target.id ~= p.id then return end
    if p.spell_id and (not action or action.param ~= p.spell_id) then return end
    pending = nil
    -- 敵の名前はゲームから届いたままの文字列なので、変換 (sjis) の外でつなぐ (送信時の表示と同じ)
    if LANG == 'ja' then
        windower.add_to_chat(207, sjis('[BanishgaPull] ') .. tostring(p.name) .. sjis(' へ [' .. p.spell .. '] の詠唱開始を確認'))
    else
        windower.add_to_chat(207, sjis('[BanishgaPull] Casting [' .. p.spell .. '] on ') .. tostring(p.name) .. ' started')
    end
end)

-- ゾーン移動・ログアウトで、除外表と直近の要求を消す (敵の ID は移動先で別の敵になる)
windower.register_event('zone change', reset_state)
windower.register_event('logout', reset_state)

