# BanishgaPull v2.0.3 - FFXI タグ取り・最速ヘイト捕獲 Windower 4 アドオン

Windower 4 公式開発規格 (`config`, `texts`, `resources`, `packets`) に完全適応した、ダイバーシティ・オーメン・範囲狩り用ヘイト捕獲・タグ横取りアドオンです。

---

## 🌟 主な特徴

- **指定釣り役 (Designated Puller) 最優先追跡**:
  指定した釣り役メンバーが被弾・交戦中の敵を最優先で検知し、バニシュガ等で瞬時にヘイトを横取り・キャッチ。
- **設定の完全永続化 (`data/settings.xml`)**:
  指定釣り役名、使用魔法、索敵距離、HUD位置などが自動保存され、エリアチェンジや再読み込みでリセットされません。
- **リアルタイム HUD オーバーレイ表示**:
  指定釣り役、使用魔法、標的モンスター名、自分/釣り役からの高精度3D距離 (メートル) を画面上にリアルタイム表示。
- **使用魔法の自由変更**:
  バニシュガ (`Banishga`) のほか、`Banishga II`、`Diaga` (ディアガ)、`Dia` (ディア)、`Poisonga` (ポイゾガ) など自由に変更可能。

---

## 💻 コマンド一覧 (`//bp` または `//banishgapull`)

| コマンド | 実行例・機能説明 |
| :--- | :--- |
| `//bp` または `//bp pull` | 最優先標的（釣り役被弾中 ➔ PT被弾中 ➔ 近隣敵）へ指定魔法を発動 |
| `//bp set <名前>` | 指定釣り役を設定 (例: `//bp set Taro`) / 解除は `//bp set reset` |
| `//bp spell <魔法名>` | 使用魔法を変更 (例: `//bp spell Banishga II`, `//bp spell Diaga`) |
| `//bp dist <メートル>` | 索敵最大距離を設定 (例: `//bp dist 18`) |
| `//bp pos <x> <y>` | HUD表示位置を変更 (例: `//bp pos 500 400`) |
| `//bp hud` | 画面HUD表示の ON / OFF 切り替え |
| `//bp status` | 現在の設定ステータスを表示 |

---

## 📦 導入・使用手順

1. `BanishgaPull_v2.0.4.zip` を解凍します。
2. Windower 4 の `addons/BanishgaPull/` フォルダへ配置します。
3. FFXIゲーム内で `//lua load BanishgaPull` を実行します。
