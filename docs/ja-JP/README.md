<div align="center">

<img src="../../docs/assets/icon.png" width="160" alt="mac-aec-relay" />

# mac-aec-relay

**有料サービスなしで macOS の通話エコーを消す中継プログラム**

[![Platform](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-5.9%2B-orange?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![speexdsp](https://img.shields.io/badge/speexdsp-BSD--3-green?style=flat-square)](https://gitlab.xiph.org/xiph/speexdsp)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](../../LICENSE)

**言語** · [English](../../README.md) · [한국어](../ko-KR/README.md) · 日本語

</div>

---

## これは何か

外部スピーカーを使う Mac で通話すると、相手は自分の声が返ってくるのを聞くことに
なります。相手の声がスピーカーから出て部屋で反射し、こちらのマイクに再び入るから
です。

macOS にもエコーキャンセラー(`AUVoiceProcessingIO`)はありますが、アプリ側が明示的に
使う必要があります。FaceTime と電話アプリはその選択肢を出さず、ユニットを直接
動かそうとしても三通りの経路すべてで塞がれます。詳細は
[構造と背景](../../구조와-배경.md)に記録しました。

そこでこの中継プログラムはデバイスの間に入ります。マイクを読み、通話アプリが再生
している音を読み、speexdsp でエコーを差し引き、仮想デバイス経由で通話アプリに返し
ます。

> **正直な現状:** エコーは減りますが、消えるわけではありません。実通話での抑圧量は
> 8-14 dB です。相手の評価が「エコーがある」から「問題ない」に変わった時点で作業を
> 止めました。何が検証済みで何がそうでないかは[測定結果](#測定結果)にあります。

## 仕組み

```
  マイク ─────────────────┐
                          ├──► [ speexrelay ] ──► BlackHole 2ch ──► 通話アプリのマイク
  BlackHole 16ch ─────────┘         │
       ▲                            └────────────► スピーカー
       │
  通話アプリの出力
```

仮想デバイスが二組必要なのは、信号がアプリの境界を二度またぐからです。一度は通話
アプリが再生する音を取り込むため(キャンセルの参照信号)、もう一度は処理済みの
マイク信号を返すためです。

参照信号がマイク内のエコーと時間的に揃っていないとキャンセルできません。中継
プログラムは通話開始から数秒の間に相互相関でそのずれを測り、動作中に反映します。

## インストール

```bash
brew install speexdsp
brew install --cask blackhole-2ch blackhole-16ch
sudo killall coreaudiod          # 新しいドライバを認識させる
```

```bash
git clone https://github.com/neocode24/mac-aec-relay.git
cd mac-aec-relay
./build_speex.sh
./install.sh                     # launchd エージェントを登録して起動
```

`./install.sh -u` で削除します。ログは `~/Library/Logs/mac-aec-relay/` に出ます。

### 通話アプリの設定

FaceTime の設定で**マイク**を `BlackHole 2ch`、**出力**を `BlackHole 16ch` に
指定します。電話アプリは FaceTime の設定に従うので、一度だけで済みます。

> **注意:** 通話アプリが BlackHole を指している間は中継プログラムが動いている必要が
> あります。設定を戻さずに中継だけ止めると、相手の声が聞こえなくなります。

## 使い方

launchd が起動し続けるので、普段は何もすることがありません。測定やデバッグのとき
は直接実行します。

```bash
./speexrelay --mode aec --autocal          # 通常動作
./speexrelay --mode bypass                 # キャンセルなしで通過、比較測定用
./speexrelay --devices                     # デバイスと UID の一覧
```

デバイスは既定でシステムの入出力を使います。名前の一部か UID で変更できます。

```bash
./speexrelay --mode aec --autocal --mic Maono --spk DELL
AEC_MIC_UID=... AEC_SPK_UID=... ./speexrelay --mode aec --autocal
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `--mode aec\|bypass` | `aec` | bypass はキャンセルせず通過 |
| `--autocal` | オフ | 通話中に参照遅延を自動補正。実通話では事実上必須 |
| `--refdelay <ms>` | 0 | 遅延を手動指定 |
| `--tail <ms>` | 400 | フィルタ長。どれだけ長いエコーを扱えるか |
| `--frame <サンプル>` | 480 | 処理単位 |
| `--esup <dB>` | -40 | 誰も話していないときの残留エコー抑圧 |
| `--esup-active <dB>` | -15 | 相手が話している間の残留エコー抑圧 |
| `--mic`, `--spk` | システム既定 | UID または名前の一部 |
| `--duration <秒>` | Ctrl-C まで | N 秒後に終了 |
| `--record <パス>` | オフ | 出力を f32le mono 48k で記録 |
| `--farfile <パス>` | オフ | ファイルを参照信号として再生。通話なしの測定用 |
| `--devices` | — | デバイス一覧を出力して終了 |

### 自動起動の管理

```bash
launchctl print    gui/$(id -u)/com.neocode24.aecrelay   # 状態
launchctl kickstart -k gui/$(id -u)/com.neocode24.aecrelay   # 再ビルド後に反映
launchctl bootout  gui/$(id -u)/com.neocode24.aecrelay   # 停止
tail -f ~/Library/Logs/mac-aec-relay/relay.log
```

## ログの読み方

```
[ 54s] mic -51.6/-70.0  ref -15.2/-32.9  out -64.7/-83.8  aecFrames=5348 refZero=3762
       ring mic=0 ref=4288(89ms drop=8992) refSpk=512(11ms drop=22336) out=832
```

- `mic` マイク原信号、`ref` 参照信号、`out` 処理後 (peak/rms)
- **相手だけが話している区間の `mic` 引く `out` が抑圧量です。** 自分が話している
  区間は 0 に近いのが正常です。自分の声を消してはいけません
- `ref=N(Xms)` 参照遅延。100 ms 付近で安定すべきです
- `refSpk=N(Xms)` スピーカー出力遅延。増えると相手の声が遅れます
- `micCb`/`spkCb`/`bh16Cb`/`bh2Cb` 四つのコールバックカウンタ。すべて増え続ける
  必要があります
- `underrun` が 0 でなければ音が途切れています

起動すると `정합 캘리브레이션: 신호 대기 중` が出て、相手が話し始めると
`lag=... corr=...` と `refdelay 적용:` の二行が出ます。**この二行がなければ補正
なしで動いており、エコーはほとんど消えません。**

## 測定結果

2026-09-12、このプログラムを作った機体での測定値です。

| 条件 | 抑圧量 (mic → out) |
|---|---|
| 実通話 | 8-14 dB |
| ベンチ、相手のみ発話 | 5.6-9.4 dB |
| ベンチ、双方発話 | -0.6 ~ 10.8 dB |

実通話で相手だけが話している区間の詳細:

| ref | mic | out | 抑圧量 |
|---|---|---|---|
| −1.0 | −39.5 | −49.0 | 9.5 |
| −15.2 | −51.6 | −64.7 | 13.1 |
| −22.0 | −56.5 | −71.2 | 14.7 |

三つが近いことが重要です。ダブルトークがボトルネックだという初期の診断は、基準を
揃えて測り直すと**成り立ちませんでした。** 何が抑圧量を抑えているのかは、まだ特定
できていません。

### 悪化すると確認されたもの

いずれも元に戻して確認しました。

| 変更 | 抑圧量 |
|---|---|
| 現在の設定 | 8-14 dB |
| 参照とスピーカーのバッファ 100 ms → 50/40 ms | 1-3 dB |
| スピーカーのバッファのみ 100 → 40 ms | 3-7 dB |
| 参照が途切れた際の遅延線整合とフィルタリセット | 3.4-5.6 dB |
| 無音の尾を待ってから出力をゲート | 0.8-4.8 dB |

それらのバッファが保持するサンプルこそ、**フィルタが必要とするエコーの元信号**
です。捨てると学習した経路が合わなくなります。体感遅延はキャンセル経路の外にある
`bh2MaxBacklog` で調整します。

## 自己復旧

オーディオデバイスは消えることがあります。HDMI モニタがスリープしたり
`coreaudiod` が再起動したりすると IOProc コールバックが止まりますが、プロセスは
生きたままログだけ出し続けます。これで 4 時間 45 分間、通話不能なまま放置された
ことがあります。

現在は 30 秒ごとに四つのコールバックカウンタを検査し、一つでも増えていなければ
`exit(1)` で自ら終了します。launchd が新しいプロセスを起動し、その時点で存在する
デバイスに対して UID を解決し直します。判定はカウンタだけを見て dB は見ません。
**無音とキャンセル成功は測定値が同じだからです。** 起動後 30 秒以内と、検査間隔が
35 秒を超えた場合は判定しないので、スリープ復帰で誤作動しません。

`sudo killall -9 coreaudiod` で検証しました。30 秒以内にプロセスが終了し、launchd
が復帰させ、カウンタが再び増え始めます。

## さらに読む

| 文書 | 内容 |
|---|---|
| [構造と背景](../../구조와-배경.md) | エコーが生じる原理、VPIO が塞がれている理由、信号の流れ、コード構造、踏んだ罠 |
| [実通話試験手順](../../실통화-시험-절차.md) | 実通話試験の手順とログの読み方 |

## 測定ツール

測定環境を作ることが作業の大半でした。その最初の版が間違っていたために三度も無駄に
修正しています。だから一緒に置いておきます。

| スクリプト | 用途 |
|---|---|
| `pm_verify_autocal.sh` | bypass との比較 |
| `pm_doubletalk.sh` | 双方が同時に話す状況の再現 |
| `pm_delay_probe.py` | 相互相関による遅延測定 |
| `pm_delay_sweep.sh` | `--refdelay` の値ごとの抑圧量 |
| `pm_split_measure.py` | 区間ごとのレベル。長い発話での崩れを見る |

## 制限

- 一台の機体で作り、検証しました。数値は出発点として扱ってください。
- エコーは減りますが、なくなりはしません。
- 通話開始の検知は試みて断念しました。`avconferenced` がオーディオデバイスを掴む
  方式がポーリングでは捉えられません。中継を常時動かす方式に代えています。
- FaceTime と電話アプリのみを経由します。Teams や Slack は自前のキャンセル機能が
  あるので触れていません。

## ライセンス

[MIT](../../LICENSE) © 2026 neocode24

[speexdsp](https://gitlab.xiph.org/xiph/speexdsp)(BSD 3-Clause)を使用しています。
ヘッダは Homebrew でインストールしたものを読み、このリポジトリには含めていません。
