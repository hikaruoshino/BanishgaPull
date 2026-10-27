# BanishgaPull (v2.5.2)

English follows the Japanese section. → [English](#english)

**FFXI (Windower 4) 用 釣り補助アドオン**

**マクロで `//bp` を押したときだけ、1 回だけ動きます。** そのとき敵を 1 体選び、魔法を 1 回送るだけです。自動で繰り返したり、連続で詠唱したりはしません（タイマーもループもありません）。押すたびに 1 回です。

`BanishgaPull` は、Windower 4 用のアドオンです。ダイバージェンス、オメン、オデシー（シェオル）、各種範囲狩りや多重リンクなどの集団戦において、指定した「釣り役」の周囲に集まった敵や、PTメンバーを攻撃している敵を優先順に探し、`バニシュガ` や `ディアガ` などの魔法を 1 回詠唱します。

最新の v2.5.2 では、まれな条件で止まる箇所と、魔法名の入力の確認を直しました。v2.5.1 では、表にないコマンドで詠唱が実行されないようにしました。v2.5.0 では、英語表示に対応しました。以前の版の変更は、末尾の更新履歴にあります。

---

## 主な機能

* **4段階の自動ターゲット優先度判定（黄色ネーム対応）**
  * **Priority 4（最高）**: 指定釣り役を直接ターゲット・攻撃している敵
  * **Priority 3**: 指定釣り役の周囲15m以内にいる敵（ヘイト未発生の黄色ネーム・引連れ群）
  * **Priority 2**: 他のパーティメンバーをターゲット・攻撃している敵
  * **Priority 1**: 自分から射程（初期値20m）以内にいるその他の敵
* **攻撃できる敵だけを選ぶフィルター（v2.2 新機能）**
  * 敵（モンスター）以外の **フェイス・ペット・羅盤・NPC は対象外**。
  * **他PTがクレームした敵（紫ネーム）は対象外**。未クレーム（黄色ネーム）と自PT・アライアンスのクレーム（赤ネーム）だけを狙います。
* **指定釣り役（Puller）追尾＆距離ソート**
  * `//bp set <キャラ名>` で指定した釣り役からの距離が近い敵を、優先して選びます。
* **敵ID直接指定の詠唱（v2.2 新機能）**
  * `/ma "バニシュガ" <敵ID>` の形で詠唱するため、ターゲット切り替えの待ち時間で別の敵に飛ぶことがありません。
* **使用魔法・射程の変更と自動保存**
  * `//bp spell <魔法名>` で `ディアガ` などに切り替え、`//bp range <m>` で射程を変更できます。
  * 釣り役・魔法・射程は `data/settings.xml` に保存され、再読み込み後も保持されます。
* **リキャスト中の知らせ・対象外の敵の数（v2.3 新機能）**
  * 魔法がリキャスト中なら、唱えずに「あと何秒」を知らせます。
  * 射程内にいるのに選べなかった敵の数（描画されていない敵／他PTにクレームされた敵）を表示します。敵が多すぎて画面に出ていないときに、飛ばせなかった理由が分かります。
* **受け付けられなかった敵を、しばらく選ばない（v2.4 新機能）**
  * 唱えた直後に「選択されたコマンドを実行できない」が届いたら、その敵を 15 秒間は選びません。同じ敵が選ばれ続けて、マクロを何度押しても唱えられなくなるのを防ぎます。
* **日本語クライアント対応**
  * チャット表示・詠唱コマンドは Shift-JIS へ自動変換します。魔法名は日本語（例: `バニシュガ`）で指定します。

---

## ファイル構成

```text
BanishgaPull/
├── BanishgaPull.lua    # アドオン本体スクリプト
├── LICENSE             # MIT License
├── README.md           # 本ドキュメント
└── data/
    └── settings.xml    # 自動生成される設定ファイル
```

---

## インストール方法

1. GitHub の Code → Download ZIP で、ファイル一式をダウンロードして解凍します。フォルダー名が `BanishgaPull-main` になるので、`BanishgaPull` に直します。
2. `Windower4/addons/` に、`BanishgaPull` フォルダーごと置きます（`Windower4/addons/BanishgaPull/BanishgaPull.lua` となるように）。
3. ゲーム内のコンソールまたはマクロで読み込みます：
   `//lua load BanishgaPull`

※ v2.1 以前から更新する場合は、`//lua reload BanishgaPull` で再読み込みしてください。設定ファイルの魔法名が英語（`Banishga`）のままでも、自動で `バニシュガ` に置き換わります。

---

## コマンド一覧 (`//bp` または `//banishgapull`)

| コマンド | 説明 | 実行例 |
| :--- | :--- | :--- |
| `//bp` または `//bp pull` | 最優先ターゲットを検索し、設定中の魔法を 1 回詠唱 | `//bp` |
| `//bp set <キャラ名>` | 最優先で横取り・保護する「指定釣り役」を設定（保存されます） | `//bp set Taro` |
| `//bp set off` | 釣り役指定を解除（PT全員の被弾自動検知モードへ。`reset` / `clear` も可） | `//bp set off` |
| `//bp spell <魔法名>` | 詠唱する魔法を変更（初期値: `バニシュガ`） | `//bp spell ディアガ` |
| `//bp range <メートル>` | 自分からの射程を変更（0 より大きく 50m まで、初期値 20m。`distance` も可） | `//bp range 18` |
| `//bp status` | 現在の釣り役・魔法・射程をチャット欄に表示 | `//bp status` |
| `//bp help` | コマンド一覧をチャット欄に表示 | `//bp help` |
| `//bp lang auto\|ja\|en` | 表示の言語（初期値 auto = クライアントの言語。読み込み直しで反映） | `//bp lang en` |

### マクロ例

```text
/console bp
```

---

## ターゲット優先度検索ロジック

`//bp` 実行時、自分から射程（初期値20m）以内にいる敵を以下の順序で判定します。

**対象になる敵の条件**
* 敵（モンスター）であること（フェイス・ペット・羅盤・NPC は除外）
* 未クレーム（黄色ネーム）または自PT・アライアンスのクレーム（赤ネーム）であること（紫ネームは除外）
* 生存していてターゲット可能であること

**優先度**
1. **Priority 4 (最高)**: 指定釣り役をターゲット・攻撃している敵
2. **Priority 3**: 指定釣り役の周囲15m以内にいる敵（黄色ネーム / リンク・引連れ中）
3. **Priority 2**: 他のPTメンバーをターゲット・攻撃している敵
4. **Priority 1**: 範囲内にいるその他の敵

※ Priority 3 および 4 の判定では、**「指定釣り役から最も近い位置にいる敵」** を最優先で選択します。それ以外は自分から最も近い敵を選びます。

---

## 注意事項

* Windower を含む外部ツールの利用は、FFXI の利用規約で禁止されています。アカウントの停止などの処分を受ける可能性があり、使用による不利益について、作者は責任を負えません。自己責任で使ってください。
* 旧版の説明にあった `//bp dist` は、現在のコードにありません。射程の変更は `//bp range` です（v2.5.1 から、表にないコマンドを打つと「不明なコマンドです」と出て、詠唱は実行されません。v2.5.0 以前は、詠唱が実行されました）。

---

## ライセンス・クレジット

* **作者**: hikaruoshino
* **動作環境**: Windower 4 (日本語クライアントで確認。英語クライアントは英語表示に対応していますが、未確認です)
* **使用ライブラリ**: `config`, `chat`, `resources`（すべて Windower 標準）
* **ライセンス**: MIT License

---

## 更新履歴（Changelog）

* **v2.5.2 (2026-10-28)**
  * **距離が取れない敵がいても止まらない**: 敵の一覧に距離の値が無い敵が混ざると、詠唱する敵を探す途中でエラーになって止まる箇所があった。距離が取れない敵は射程の外として扱う（数える側は以前からそうしていた）。実際に起きることはまれと思われる。
  * **魔法名に `"` と `;` を使えない**: 魔法名は `/ma "魔法名"` にそのまま入るので、`"` や `;`（コマンドの区切り）を含む名前は `//bp spell` で受け付けず、`data/settings.xml` に書かれていても詠唱しない。
* **v2.5.1 (2026-10-23)**
  * **表にないコマンドでは詠唱しない**: `//bp` の後に、コマンド一覧にない語（旧説明の `//bp dist`、綴り間違いなど）を打つと、これまでは詠唱が実行されていた。「不明なコマンドです」と表示して、何もしないようにした（`//bp` だけ、または `//bp pull` で詠唱する）。
* **v2.5.0 (2026-10-22)**
  * **英語表示に対応**: ゲームクライアントの言語に合わせて自動で切り替わる（`//bp lang auto|ja|en`、読み込み直しで反映）。魔法名は言語に合わせて自動で直る（英語クライアントでは `Banishga`）。英語クライアントでの動作は未確認。受け付けられなかった敵の検出に使う英語の文 `Unable to execute that command` は、記憶によるもので、ゲーム内未確認。`reject_message`（`data/settings.xml`）で検出する文を変えられる。
* **v2.4.0 (2026-10-18)**
  * **受け付けられなかった敵を 15 秒選ばない**: 唱えた直後に「選択されたコマンドを実行できない」が届いた敵を外し、同じ敵が選ばれ続けて唱えられなくなるのを解消。外した数は「対象外」の表示に「受け付けられなかった敵 N 体」として出ます。
* **v2.3.0 (2026-10-16)**
  * **リキャスト中の知らせ**: 魔法がリキャスト中のときは、詠唱を送らずに残り秒数を表示（魔法名が分からない場合は従来どおり唱える）。
  * **対象外の敵の数を表示**: 射程内で「描画されていない敵」「他PTのクレーム」を外した数を表示。
* **v2.2.0 (2026-10-06)**
  * **誤ターゲットの修正**: フェイス・ペット・羅盤・NPC を対象から除外（敵の `spawn_type` で判定）。釣り役が連れているフェイスにバニシュガが飛ぶ問題を解消。
  * **紫ネームの除外**: 他PTがクレームした敵を対象外にし、「既に他人が戦闘中」で詠唱が空振りする問題を解消。
  * **詠唱方式の変更**: `/target` で切り替えてから `<t>` へ詠唱する方式をやめ、敵IDを直接指定して詠唱するよう変更。切り替え待ちで別の敵に飛ぶ問題を解消。
  * **設定の反映**: `data/settings.xml` の魔法名・射程・釣り役を読み込み・保存するよう修正（v2.1 では保存されていませんでした）。
  * **コマンド追加**: `//bp spell`（魔法変更）、`//bp range`（射程変更）、`//bp help` を追加。`//bp status` に魔法と射程を表示。
  * **日本語クライアント対応**: 初期魔法を `バニシュガ` に変更し、旧設定の `Banishga` を自動で置き換え。
  * **ドキュメント整理**: 現行コードに無い HUD 表示（`//bp hud`）と `//bp dist` の記載を削除し、実際のコマンドに合わせました。
* **v2.1.0 (2026-10-05)**
  * **黄色ネーム（ヘイト未発生群）対応**: 指定釣り役の周囲15m以内にいる敵（Priority 3）を新設。赤ネーム化前の引連れ群に、すぐに詠唱できるようにした。
  * **距離ソートの最適化**: 自分基準ではなく「指定釣り役からの距離」でターゲットを最優先選別するよう判定ロジックを改良。
  * **チャット表示の機能拡張**: 追尾中（黄色ネーム）と被弾中（赤ネーム）の識別ログ表示を追加。
* **v2.0.0 (2026-10-01)**
  * 詠唱魔法を変更するコマンドと、最大検索範囲を変更するコマンドの記載を追加（当時は `//bp dist` と書いていましたが、現在のコードにあるのは `//bp range` です）。
* **v1.0.0 (2026-09-20)**
  * 初版リリース。釣り役の指定と、3段階の優先度による敵の検索。

---

<a id="english"></a>

## English

BanishgaPull is a Windower 4 addon for FINAL FANTASY XI, for fights with many mobs around (Divergence, Omen, Odyssey, mob packs). Put `/console bp` in a macro. **Each press picks one mob and casts one spell on it** (Banishga by default). It has no loop or timer, so nothing happens until you press.

**Not tested on the English client yet.** The display and the spell name switch to English when the client is English (`//bp lang ja|en|auto` to force it), but I have only played it on the Japanese client. Whether it detects a refused cast on the English client is not checked either (see below).

### How it picks a mob

Within your range (default 20 yalms), in this order:

1. A mob attacking the puller you set with `//bp set <name>`
2. A mob within 15 yalms of that puller
3. A mob attacking another party member (you included)
4. Any other mob in range

Priorities 1 and 2 only apply if you set a puller; they pick the mob closest to the puller. Otherwise it picks the mob closest to you.

Skipped: trusts, pets (automatons and luopans included), NPCs, mobs claimed by another party (purple name), dead mobs, and mobs that are not drawn on your screen. The cast goes out with the mob's ID (`/ma "Banishga" <id>`), so it does not depend on switching your target first.

### Other behavior

- If the spell is on recast, it prints the seconds left and does not cast.
- It prints how many mobs in range it had to skip (not drawn, claimed by another party, refused by the game).
- If the game refuses a mob right after the cast is sent, that mob is skipped for 15 seconds so the next press goes to another one. On the Japanese client it looks for 選択されたコマンドを実行できない ("unable to execute the selected command"). On the English client it looks for "Unable to execute that command" (from memory, **not checked on an English client yet**). If it never triggers, open a GitHub issue with the exact message, or set it yourself in `reject_message` in `data/settings.xml`.

### Install

1. Put the folder at `Windower4/addons/BanishgaPull/BanishgaPull.lua`.
2. In game: `//lua load BanishgaPull`. If you are updating from an older version, use `//lua reload BanishgaPull`.

### Commands (`//bp` or `//banishgapull`)

| Command | What it does |
| :--- | :--- |
| `//bp` or `//bp pull` | Pick one mob and cast the spell once |
| `//bp set <name>` | Set the puller (saved). `//bp set off` clears it (`reset` and `clear` also work) |
| `//bp spell <name>` | Change the spell (e.g. `//bp spell Diaga`) |
| `//bp range <yalms>` | Change the range from you (more than 0, up to 50, default 20) |
| `//bp status` | Show the puller, spell and range |
| `//bp lang auto` / `ja` / `en` | Display language (reload to apply) |
| `//bp help` | List the commands |

Macro example: `/con bp`

### Notes

- Settings (puller, spell, range, language) are saved in `data/settings.xml`.
- Using third-party tools such as Windower violates the FFXI Terms of Service. Your account may be penalized. Use this at your own risk; the author takes no responsibility.

Released under the MIT License. Author: hikaruoshino.

## 不具合・動作報告 / Feedback

「動きました」の一言だけでも歓迎です。GitHub のアカウントがあれば、[Issues](../../issues/new/choose) から書き込めます (日本語・英語どちらでも)。

A one-line "it works" is welcome too. With a GitHub account you can post from [Issues](../../issues/new/choose) (Japanese or English).
