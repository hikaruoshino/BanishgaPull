# BanishgaPull v2.0.0 (完全適応版)

FFXI（ファイナルファンタジー11）のダイバージェンス・ソーティ・オデシー・アンバスケード等において、指定した釣り役やパーティメンバーがヘイトを取った敵（タグ）を最速で横取り・捕獲（タグ取り）する Windower 4 用アドオンです。

---

## 🌟 v2.0.0 の主な特徴と改善点

1. **Windower 4 公式開発規約 (windower_mdc) 完全適応**:
   - `config` (設定永続化), `texts` (DirectWrite UTF-8 GUI), `resources`, `packets` をフル活用。
2. **リアルタイムHUDオーバーレイ表示**:
   - 画面上に指定釣り役、使用魔法、最優先ターゲット名・距離を常時表示。
3. **設定の自動永続化 (`data/settings.xml`)**:
   - 指定釣り役名や使用魔法、画面表示位置などの設定がゾーン切り替え・アドオン再読み込み後も保持されます。
4. **使用魔法のカスタマイズ**:
   - バニシュガ (`Banishga`) のほか、`Banishga II`、`Diaga` (ディアガ)、`Dia` (ディア)、`Poisonga` (ポイゾガ) 等の魔法へ自由変更可能。
5. **文字化け・POLクラッシュ 0%**:
   - UTF-8 と Shift-JIS の二重エンコーディング構造により文字化け（□）とクラッシュを完全防御。

---

## 💻 コマンド一覧 (`//bp` または `//banishgapull`)

| コマンド | 説明・使用例 |
| :--- | :--- |
| **`//bp`** または **`//bp pull`** | 最優先ターゲットへ即座にバニシュガ（指定魔法）をキャスト発動 |
| **`//bp set <プレイヤー名>`** | 指定釣り役を設定 (例: `//bp set Taro`) |
| **`//bp set reset`** | 指定釣り役を解除 (PT全員を自動検知対象にする) |
| **`//bp spell <魔法名>`** | 使用する魔法を変更 (例: `//bp spell Banishga II`, `//bp spell Diaga`) |
| **`//bp dist <メートル>`** | 索敵最大距離を変更 (例: `//bp dist 18`) |
| **`//bp hud`** | HUD表示の ON / OFF 切替 |
| **`//bp status`** | 現在の設定ステータスを表示 |

---

## 📦 インストール方法

1. ダウンロードした `BanishgaPull.zip` を解凍します。
2. `BanishgaPull` フォルダを Windower 4 の `addons` フォルダへ配置します。
   - 配置パス: `Windower4/addons/BanishgaPull/`
3. ゲーム内で `//lua load BanishgaPull` を実行します。
