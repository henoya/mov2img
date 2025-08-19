#!/usr/bin/env bash
set -euo pipefail

# ========================================
# 画面録画から静止画を自動抽出するスクリプト
# ========================================
# 用途：iPhone/iPad/macOSの画面録画動画から、
#       画面が静止した瞬間の画像を自動で抽出して
#       操作手順書用の静止画ファイルを作成する
# ========================================

# デフォルト設定値
DEFAULT_THRESHOLD="0.03"    # 3%の差分閾値（デフォルト）
DEFAULT_FPS="30"            # 処理フレームレート（デフォルト）
DEFAULT_STATIC_DURATION="1.0"  # 静止判定の最小時間（秒）

# グローバル変数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="${SCRIPT_DIR}/temp"
VERBOSE=false
SKIP_EXTRACTION=false

# ========================================
# 終了時の後始末処理
# ========================================
# cleanup() {
#     if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
#         rm -rf "$TEMP_DIR"
#     fi
# }
# trap cleanup EXIT INT TERM

# ========================================
# 使用方法の表示
# ========================================
usage() {
    cat << EOF
使用方法: $0 [オプション] -i 入力ファイル

画面録画動画から、静止した瞬間の画像を自動抽出します。

必須パラメータ:
  -i, --input ファイル      入力動画ファイル (.mov/.mp4)

オプション:
  -o, --output フォルダ     出力フォルダ (省略時: 入力ファイル名)
  -n, --name プレフィックス 画像ファイル名のベース (省略時: 出力フォルダ名)
  -t, --threshold パーセント 差分閾値パーセント (省略時: 3%)
  -f, --fps レート          処理フレームレート (省略時: 30)
  -d, --duration 秒         静止判定の最小時間 (省略時: 1.0秒)
  -s, --skip-extraction    フレーム抽出をスキップ (temp/の既存フレームを使用)
  -v, --verbose            詳細出力を有効にする
  -h, --help              この説明を表示

使用例:
  $0 -i recording.mov
  $0 -i recording.mp4 -o frames -n screenshot -t 5 -f 15
  $0 -i tutorial.mov -t 2 -d 0.5 -v
  $0 -i recording.mov -s  # 既存フレームを使用して解析のみ実行
EOF
}

# ========================================
# コマンドライン引数の解析
# ========================================
parse_args() {
    local input_file=""
    local output_dir=""
    local base_name=""
    local threshold="$DEFAULT_THRESHOLD"
    local fps="$DEFAULT_FPS"
    local min_duration="$DEFAULT_STATIC_DURATION"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--input)
                input_file="$2"
                shift 2
                ;;
            -o|--output)
                output_dir="$2"
                shift 2
                ;;
            -n|--name)
                base_name="$2"
                shift 2
                ;;
            -t|--threshold)
                threshold="$2"
                shift 2
                ;;
            -f|--fps)
                fps="$2"
                shift 2
                ;;
            -d|--duration)
                min_duration="$2"
                shift 2
                ;;
            -s|--skip-extraction)
                SKIP_EXTRACTION=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "エラー: 不明なパラメータ $1" >&2
                usage
                exit 1
                ;;
        esac
    done
    
    # 必須パラメータの確認
    if [[ -z "$input_file" ]]; then
        echo "エラー: 入力ファイルが指定されていません" >&2
        usage
        exit 1
    fi
    
    # デフォルト値の設定
    if [[ -z "$output_dir" ]]; then
        output_dir="$(basename "$input_file" | sed 's/\.[^.]*$//')_frames"
    fi
    
    if [[ -z "$base_name" ]]; then
        base_name="$(basename "$output_dir")"
    fi
    
    # 他の関数で使用するため変数をエクスポート
    export INPUT_FILE="$input_file"
    export OUTPUT_DIR="$output_dir"
    export BASE_NAME="$base_name"
    export THRESHOLD="$threshold"
    export FPS="$fps"
    export MIN_DURATION="$min_duration"
}

# ========================================
# 環境確認と入力ファイルの検証
# ========================================
validate_environment() {
    # 入力ファイルの存在確認
    if [[ ! -f "$INPUT_FILE" ]]; then
        echo "エラー: 入力ファイル '$INPUT_FILE' が見つかりません" >&2
        exit 1
    fi
    
    # 入力ファイルが動画ファイルかどうか確認
    local mime_type
    mime_type=$(file -b --mime-type "$INPUT_FILE" 2>/dev/null || echo "unknown")
    if [[ ! "$mime_type" =~ ^video/ ]]; then
        echo "エラー: '$INPUT_FILE' は動画ファイルではありません (検出タイプ: $mime_type)" >&2
        exit 1
    fi
    
    # ffmpegが利用可能か確認
    if ! command -v ffmpeg &> /dev/null; then
        echo "エラー: ffmpegが見つかりません。次のコマンドでインストールしてください: brew install ffmpeg" >&2
        exit 1
    fi
    
    # ffprobeが利用可能か確認
    if ! command -v ffprobe &> /dev/null; then
        echo "エラー: ffprobeが見つかりません。次のコマンドでインストールしてください: brew install ffmpeg" >&2
        exit 1
    fi
}

# ========================================
# 動画情報の取得と解析
# ========================================
analyze_video() {
    local input_file="$1"
    
    # 動画の基本情報を取得
    local duration
    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null | cut -d. -f1)
    
    local fps
    fps=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null | bc -l 2>/dev/null | cut -d. -f1)
    
    local width
    width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null)
    
    local height
    height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null)
    
    local codec
    codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null)
    
    # 動画情報をエクスポート
    export VIDEO_DURATION="${duration:-0}"
    export VIDEO_FPS="${fps:-30}"
    export VIDEO_WIDTH="${width:-0}"
    export VIDEO_HEIGHT="${height:-0}"
    export VIDEO_CODEC="${codec:-unknown}"
}

# ========================================
# 推奨設定の表示
# ========================================
show_recommendations() {
    echo ""
    echo "========================================" >&2
    echo "📹 動画情報の解析結果" >&2
    echo "========================================" >&2
    echo "ファイル名: $(basename "$INPUT_FILE")" >&2
    echo "動画時間: ${VIDEO_DURATION}秒" >&2
    echo "解像度: ${VIDEO_WIDTH}x${VIDEO_HEIGHT}" >&2
    echo "フレームレート: ${VIDEO_FPS} fps" >&2
    echo "コーデック: ${VIDEO_CODEC}" >&2
    echo "" >&2
    
    echo "========================================" >&2
    echo "⚙️  推奨設定" >&2
    echo "========================================" >&2
    
    # 動画の長さに基づく推奨設定
    local recommended_fps="$FPS"
    local recommended_threshold="$THRESHOLD"
    local recommended_duration="$MIN_DURATION"
    
    if [[ $VIDEO_DURATION -gt 600 ]]; then
        # 10分以上の長い動画
        recommended_fps="15"
        echo "📌 長時間動画（10分以上）の推奨設定:" >&2
        echo "   - 処理FPS: 15 (処理時間短縮のため)" >&2
        echo "   - 閾値: 3-5% (重要な変化のみ検出)" >&2
        echo "   - 静止時間: 1.5秒以上" >&2
    elif [[ $VIDEO_DURATION -gt 180 ]]; then
        # 3-10分の中程度の動画
        recommended_fps="20"
        echo "📌 中程度の動画（3-10分）の推奨設定:" >&2
        echo "   - 処理FPS: 20" >&2
        echo "   - 閾値: 3% (標準的な設定)" >&2
        echo "   - 静止時間: 1.0秒" >&2
    else
        # 3分未満の短い動画
        recommended_fps="30"
        echo "📌 短い動画（3分未満）の推奨設定:" >&2
        echo "   - 処理FPS: 30 (詳細な検出)" >&2
        echo "   - 閾値: 2% (細かい変化も検出)" >&2
        echo "   - 静止時間: 0.5-1.0秒" >&2
    fi
    
    # 解像度に基づく推奨
    if [[ $VIDEO_WIDTH -gt 1920 ]]; then
        echo "" >&2
        echo "⚠️  高解像度動画の注意点:" >&2
        echo "   - 処理に時間がかかる可能性があります" >&2
        echo "   - 必要に応じてFPSを下げることを検討してください" >&2
    fi
    
    echo "" >&2
    echo "========================================" >&2
    echo "📊 現在の設定" >&2
    echo "========================================" >&2
    echo "出力フォルダ: $OUTPUT_DIR" >&2
    echo "ファイル名プレフィックス: $BASE_NAME" >&2
    echo "処理FPS: $FPS" >&2
    echo "差分閾値: $THRESHOLD%" >&2
    echo "最小静止時間: $MIN_DURATION秒" >&2
    echo "" >&2
    
    # 処理時間の目安を計算
    local estimated_frames=$((VIDEO_DURATION * FPS))
    local estimated_time=$((estimated_frames / 30))  # 概算：30フレーム/秒で処理
    
    echo "⏱️  処理時間の目安: 約${estimated_time}秒" >&2
    echo "" >&2
}

# ========================================
# 処理実行の確認
# ========================================
confirm_execution() {
    echo "上記の設定で処理を開始しますか？ [Y/n]: " >&2
    read -r response
    
    # デフォルトはYes
    if [[ -z "$response" ]] || [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        echo "処理をキャンセルしました。" >&2
        exit 0
    fi
}

# ========================================
# 出力フォルダの準備
# ========================================
setup_output_directory() {
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        mkdir -p "$OUTPUT_DIR" || {
            echo "エラー: 出力フォルダ '$OUTPUT_DIR' を作成できません" >&2
            exit 1
        }
    fi
    
    if [[ ! -w "$OUTPUT_DIR" ]]; then
        echo "エラー: 出力フォルダ '$OUTPUT_DIR' に書き込み権限がありません" >&2
        exit 1
    fi
}

# ========================================
# ログ出力関数（詳細モード時のみ）
# ========================================
log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$(date '+%H:%M:%S')] $*" >&2
    fi
}

# ========================================
# 静止画像の抽出メイン処理
# ========================================
extract_static_frames() {
    local input="$1"
    local output_dir="$2" 
    local base_name="$3"
    local threshold="$4"
    local fps="$5"
    local min_duration="$6"
    
    log "フレーム抽出を開始: $input"
    log "パラメータ: 閾値=$threshold, FPS=$fps, 最小静止時間=$min_duration"
    
    # 一時フォルダの作成
    mkdir -p "$TEMP_DIR" || {
        echo "エラー: 一時フォルダ '$TEMP_DIR' を作成できません" >&2
        return 1
    }
    
    # 環境変数を一時フォルダに export
    # TEMP_DIR=$(mktemp -d -t "frame_extractor_$$_XXXXXX")
    # chmod 700 "$TEMP_DIR"
    
    # 静止判定に必要な最小フレーム数を計算
    local min_frames
    min_frames=$(echo "$fps * $min_duration" | bc -l | cut -d. -f1)
    
    # 動画情報から抽出予定のフレーム数を計算
    local video_duration
    video_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input" 2>/dev/null || echo "0")
    
    local estimated_frames
    estimated_frames=$(echo "$video_duration * $fps" | bc -l | cut -d. -f1)
    
    echo "========================================" >&2
    echo "📊 フレーム抽出情報" >&2
    echo "========================================" >&2
    echo "動画の長さ: ${video_duration}秒" >&2
    echo "処理FPS: ${fps} fps" >&2
    echo "抽出予定フレーム数: 約${estimated_frames}枚" >&2
    echo "一時保存先: ${TEMP_DIR}/" >&2
    echo "========================================" >&2
    echo "" >&2
    
    # ステップ1: フレーム抽出またはスキップ
    if [[ "$SKIP_EXTRACTION" == "true" ]]; then
        # 既存フレームの確認
        echo "フレーム抽出をスキップします..." >&2
        echo "既存フレームを確認中..." >&2
        
        local existing_frames=($(ls "$TEMP_DIR"/frame_*.png 2>/dev/null | sort -V))
        local existing_count=${#existing_frames[@]}
        
        if [[ $existing_count -eq 0 ]]; then
            echo "エラー: $TEMP_DIR/ にフレームファイルが見つかりません" >&2
            echo "先に -s オプションなしで実行してフレームを抽出してください" >&2
            return 1
        fi
        
        echo "既存フレーム数: $existing_count 枚" >&2
        echo "" >&2
    else
        # 既存フレームファイルの削除
        if [[ -d "$TEMP_DIR" ]]; then
            echo "既存フレームファイルを削除中..." >&2
            rm -f "$TEMP_DIR"/frame_*.png 2>/dev/null || true
            log "TEMP_DIR内のフレームファイルを削除しました"
        fi
        
        log "指定されたFPSでフレームを抽出中..."
        
        # フレーム抽出（進捗表示付き）
        echo "フレーム抽出を開始しています..." >&2
        
        # ffmpegをバックグラウンドで実行し、進捗を監視
        ffmpeg -i "$input" \
            -vf "fps=$fps" \
            -q:v 2 \
            -pix_fmt yuv420p \
            -progress pipe:1 \
            "$TEMP_DIR/frame_%08d.png" 2>/dev/null | \
        while IFS='=' read -r key value; do
            if [[ "$key" == "frame" ]]; then
                # 現在のフレーム番号を取得
                local current_frame="$value"
                local progress_percent=$(echo "scale=1; $current_frame * 100 / $estimated_frames" | bc -l 2>/dev/null || echo "0")
                
                # 10フレームごとに進捗を更新
                if [[ $((current_frame % 10)) -eq 0 ]]; then
                    echo -ne "\r抽出中: $current_frame / $estimated_frames フレーム (${progress_percent}%)" >&2
                fi
            fi
        done
        
        echo -ne "\r" >&2
        echo "フレーム抽出完了" >&2
    fi
    
    # ステップ2: 抽出されたフレームの解析
    local frame_files=("$TEMP_DIR"/frame_*.png)
    local total_frames=${#frame_files[@]}
    
    if [[ $total_frames -eq 0 ]]; then
        echo "エラー: 動画からフレームを抽出できませんでした" >&2
        return 1
    fi
    
    log "静止期間の解析中: $total_frames フレーム"
    
    # ステップ3: 連続フレーム比較と静止期間の特定
    local static_start=""        # 静止期間の開始フレーム番号
    local static_count=0         # 連続静止フレーム数
    local extracted_count=0      # 抽出した画像の数
    
    echo "フレーム解析中..." >&2
    
    for ((i=0; i<total_frames-1; i++)); do
        local current_frame="${frame_files[i]}"
        local next_frame="${frame_files[i+1]}"
        
        # フレームファイルの存在確認
        if [[ ! -f "$current_frame" || ! -f "$next_frame" ]]; then
            log "警告: フレームファイルが見つかりません: $current_frame または $next_frame"
            continue
        fi
        
        # エラー時の自動終了を一時的に無効化
        set +e
        
        # ffmpegを使ってフレーム間の差分を計算（SSIM使用）
        local ssim_output
        ssim_output=$(ffmpeg -i "$current_frame" -i "$next_frame" \
            -lavfi "ssim=stats_file=/dev/stdout" \
            -f null - 2>&1 | grep "SSIM" | tail -1)
        local ffmpeg_status=$?
        
        # エラー時の自動終了を再有効化
        set -e
        
        # SSIM計算が失敗した場合のハンドリング
        if [[ $ffmpeg_status -ne 0 || -z "$ssim_output" ]]; then
            log "警告: SSIM計算に失敗しました。フレーム $((i+1)) → $((i+2)) (終了コード: $ffmpeg_status)"
            continue
        fi
        
        # SSIM値を抽出（1.0が完全一致、0.0が完全不一致）
        local ssim_value
        ssim_value=$(echo "$ssim_output" | grep -o "All:[0-9.]*" | cut -d: -f2 2>/dev/null)
        
        # 無効なSSIM値のチェック
        if [[ -z "$ssim_value" ]]; then
            log "警告: SSIM値の抽出に失敗しました: $ssim_output"
            continue
        fi
        
        # SSIM値を差分パーセンテージに変換（0%が完全一致、100%が完全不一致）
        local diff_score
        set +e
        diff_score=$(echo "scale=2; (1 - $ssim_value) * 100" | bc -l 2>/dev/null)
        local bc_status=$?
        set -e
        
        # bc計算が失敗した場合のハンドリング
        if [[ $bc_status -ne 0 || -z "$diff_score" ]]; then
            log "警告: 差分スコア計算に失敗しました (SSIM値: $ssim_value)"
            continue
        fi
        
        # Verboseモードでは差分スコアを表示
        if [[ "$VERBOSE" == "true" ]]; then
            local frame_num=$(printf "%04d" $((i+1)))
            local next_num=$(printf "%04d" $((i+2)))
            log "フレーム $frame_num → $next_num: 差分スコア=$diff_score% (閾値=$threshold%)"
        fi
        
        # 差分が閾値以下なら静止フレームと判定
        set +e
        local comparison_result
        comparison_result=$(echo "$diff_score < $threshold" | bc -l 2>/dev/null)
        local comparison_status=$?
        set -e
        
        if [[ $comparison_status -ne 0 ]]; then
            log "警告: 閾値比較に失敗しました (差分: $diff_score, 閾値: $threshold)"
            continue
        fi
        
        if (( comparison_result )); then
            if [[ -z "$static_start" ]]; then
                static_start="$i"
                static_count=1
                log "静止期間開始: フレーム $(printf "%04d" $((i+1)))"
            else
                ((static_count++))
            fi
        else
            # 静止期間の終了
            log "静止期間終了を検出: static_start=$static_start, static_count=$static_count, min_frames=$min_frames"
            if [[ -n "$static_start" && $static_count -ge $min_frames ]]; then
                log "静止期間抽出条件を満たしています。処理開始..."
                # 静止期間の中央フレームを抽出
                local middle_frame_idx=$((static_start + static_count / 2))
                local source_frame="${frame_files[middle_frame_idx]}"
                log "中央フレーム計算: middle_frame_idx=$middle_frame_idx, source_frame=$source_frame"
                
                # ソースフレームの存在確認
                if [[ ! -f "$source_frame" ]]; then
                    log "エラー: ソースフレームが見つかりません: $source_frame"
                    static_start=""
                    static_count=0
                    continue
                fi
                log "ソースフレーム確認完了: $source_frame"
                
                log "extracted_count更新前: $extracted_count"
                extracted_count=$((extracted_count + 1))
                log "extracted_count更新後: $extracted_count"
                local output_frame="$output_dir/${base_name}_$(printf '%04d' $extracted_count).png"
                log "出力ファイル名決定: $output_frame"
                
                # ファイルコピーをエラーハンドリング付きで実行
                log "ファイルコピー開始..."
                set +e
                cp "$source_frame" "$output_frame"
                local cp_status=$?
                set -e
                log "ファイルコピー完了: 終了コード=$cp_status"
                
                if [[ $cp_status -eq 0 ]]; then
                    log "静止画像を抽出: $output_frame (静止期間: $static_count フレーム)"
                    
                    if [[ "$VERBOSE" == "true" ]]; then
                        echo "  → 静止期間: フレーム $(printf "%04d" $((static_start+1))) から $(printf "%04d" $((i+1))) まで ($static_count フレーム)" >&2
                        echo "  → 中央フレーム $(printf "%04d" $((middle_frame_idx+1))) を抽出" >&2
                    fi
                else
                    log "エラー: ファイルコピーに失敗しました: $source_frame → $output_frame (終了コード: $cp_status)"
                    extracted_count=$((extracted_count - 1))  # カウントを戻す
                fi
                log "静止期間抽出処理完了"
            elif [[ -n "$static_start" ]]; then
                log "静止期間終了: フレーム $(printf "%04d" $((i+1))) (期間: $static_count フレーム < 最小: $min_frames フレーム)"
            fi
            
            # 静止期間のリセット
            static_start=""
            static_count=0
        fi
        
        # 進行状況表示
        if [[ $((i % 30)) -eq 0 ]]; then
            local progress=$((i * 100 / total_frames))
            echo -ne "\r進行状況: $progress% ($i/$total_frames フレーム解析済み)" >&2
        fi
    done
    
    # 最後の静止期間の処理
    if [[ -n "$static_start" && $static_count -ge $min_frames ]]; then
        local middle_frame_idx=$((static_start + static_count / 2))
        local source_frame="${frame_files[middle_frame_idx]}"
        extracted_count=$((extracted_count + 1))
        local output_frame="$output_dir/${base_name}_$(printf '%04d' $extracted_count).png"
        
        cp "$source_frame" "$output_frame"
        log "最終静止画像を抽出: $output_frame"
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo "  → 最終静止期間: フレーム $(printf "%04d" $((static_start+1))) から $(printf "%04d" $total_frames) まで ($static_count フレーム)" >&2
            echo "  → 中央フレーム $(printf "%04d" $((middle_frame_idx+1))) を抽出" >&2
        fi
    fi
    
    echo -ne "\r" >&2
    echo "抽出完了。$extracted_count 個の静止画像を見つけました。" >&2
    
    return 0
}

# ========================================
# メイン実行関数
# ========================================
main() {
    parse_args "$@"
    validate_environment
    setup_output_directory
    
    log "設定確認:"
    log "  入力ファイル: $INPUT_FILE"
    log "  出力フォルダ: $OUTPUT_DIR"
    log "  ベース名: $BASE_NAME"
    log "  差分閾値: $THRESHOLD%"
    log "  処理FPS: $FPS"
    log "  最小静止時間: $MIN_DURATION 秒"
    
    extract_static_frames "$INPUT_FILE" "$OUTPUT_DIR" "$BASE_NAME" "$THRESHOLD" "$FPS" "$MIN_DURATION"
}

# ========================================
# スクリプト実行開始
# ========================================
main "$@"
