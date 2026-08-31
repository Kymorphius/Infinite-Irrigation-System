#!/bin/bash

# 在 macOS 上绕过 Project Zomboid 游戏内上传器，使用 Valve SteamCMD
# 更新现有的 Steam Workshop 物品。

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RELEASE_ROOT="${SCRIPT_DIR} Release"
WORKSHOP_FILE="$RELEASE_ROOT/workshop.txt"
SCHINESE_DESCRIPTION_FILE="$RELEASE_ROOT/workshop-schinese-description.txt"
RUSSIAN_DESCRIPTION_FILE="$RELEASE_ROOT/workshop-russian-description.txt"
CONTENT_DIR="$RELEASE_ROOT/Contents"
PREVIEW_FILE="$RELEASE_ROOT/preview.png"
EXPECTED_APP_ID="108600"
EXPECTED_WORKSHOP_ID="3548529064"
MAX_DESCRIPTION_BYTES=8000
# Valve 自带的 steamcmd.sh 没有完整处理带空格的安装路径。
# 使用无空格的缓存目录，避免启动脚本把路径拆成多个参数。
STEAMCMD_ROOT="${STEAMCMD_ROOT:-$HOME/Library/Caches/InfiniteIrrigationSteamCMD}"
STEAMCMD="$STEAMCMD_ROOT/steamcmd.sh"
STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz"
PREFERENCES_DOMAIN="com.matrix.InfiniteIrrigationPublisher"
PREFERENCES_ACCOUNT_KEY="SteamUsername"

DRY_RUN=0
PREPARE_ONLY=0
STEAM_USERNAME="${STEAM_USERNAME:-}"
CHANGE_NOTE="${CHANGE_NOTE:-}"

usage() {
    echo "用法:"
    echo "  ./publish-macos.sh [--user Steam登录名] [--change-note 更新说明]"
    echo "  ./publish-macos.sh --prepare"
    echo "  ./publish-macos.sh --dry-run"
    echo ""
    echo "说明:"
    echo "  实际发布前会自动运行 release.sh。"
    echo "  成功上传后会记住登录名，下次直接回车即可复用。"
    echo "  密码和 Steam Guard 登录状态由 SteamCMD 安全管理，不会写入项目文件。"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --user)
            [ "$#" -ge 2 ] || { echo "错误: --user 缺少参数"; exit 2; }
            STEAM_USERNAME="$2"
            shift 2
            ;;
        --change-note)
            [ "$#" -ge 2 ] || { echo "错误: --change-note 缺少参数"; exit 2; }
            CHANGE_NOTE="$2"
            shift 2
            ;;
        --prepare)
            PREPARE_ONLY=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "错误: 未知参数 $1"
            usage
            exit 2
            ;;
    esac
done

install_steamcmd() {
    if [ -x "$STEAMCMD" ]; then
        return
    fi

    echo "正在从 Valve 官方服务器安装 SteamCMD……"
    mkdir -p "$STEAMCMD_ROOT"
    local archive
    archive=$(mktemp "${TMPDIR:-/tmp}/steamcmd_osx.XXXXXX.tar.gz")
    curl -fL --retry 3 -o "$archive" "$STEAMCMD_URL"
    tar -xzf "$archive" -C "$STEAMCMD_ROOT"
    unlink "$archive"

    if [ ! -x "$STEAMCMD" ]; then
        echo "错误: SteamCMD 安装后仍不可执行: $STEAMCMD"
        exit 1
    fi
}

validate_release() {
    [ -f "$WORKSHOP_FILE" ] || { echo "错误: 缺少 $WORKSHOP_FILE"; exit 1; }
    [ -f "$SCHINESE_DESCRIPTION_FILE" ] || { echo "错误: 缺少 $SCHINESE_DESCRIPTION_FILE"; exit 1; }
    [ -f "$RUSSIAN_DESCRIPTION_FILE" ] || { echo "错误: 缺少 $RUSSIAN_DESCRIPTION_FILE"; exit 1; }
    [ -d "$CONTENT_DIR" ] || { echo "错误: 缺少 $CONTENT_DIR"; exit 1; }
    [ -f "$PREVIEW_FILE" ] || { echo "错误: 缺少 $PREVIEW_FILE"; exit 1; }

    local workshop_id
    workshop_id=$(sed -n 's/^id=//p' "$WORKSHOP_FILE" | head -n 1)
    if [ "$workshop_id" != "$EXPECTED_WORKSHOP_ID" ]; then
        echo "错误: Release 的 Workshop ID 是 $workshop_id，预期为 $EXPECTED_WORKSHOP_ID"
        exit 1
    fi

    local release_mod_info="$CONTENT_DIR/mods/WaterPipes-IrrigationSystems/42/mod.info"
    [ -f "$release_mod_info" ] || { echo "错误: 缺少正式版 mod.info"; exit 1; }
    if ! grep -q '^id=InfiniteIrrigationPipes$' "$release_mod_info"; then
        echo "错误: Release 仍不是正式 Mod ID InfiniteIrrigationPipes"
        exit 1
    fi

	local description_bytes
	description_bytes=$(sed -n 's/^description=//p' "$WORKSHOP_FILE" | LC_ALL=C wc -c | xargs)
	if [ "$description_bytes" -gt "$MAX_DESCRIPTION_BYTES" ]; then
		echo "错误: 工坊描述为 $description_bytes 字节，超过 Steam 的 $MAX_DESCRIPTION_BYTES 字节限制"
		exit 1
	fi
	echo "工坊描述: $description_bytes/$MAX_DESCRIPTION_BYTES 字节"

	local schinese_description_bytes
	schinese_description_bytes=$(LC_ALL=C wc -c < "$SCHINESE_DESCRIPTION_FILE" | xargs)
	if [ "$schinese_description_bytes" -gt "$MAX_DESCRIPTION_BYTES" ]; then
		echo "错误: 简体中文描述为 $schinese_description_bytes 字节，超过 Steam 的 $MAX_DESCRIPTION_BYTES 字节限制"
		exit 1
	fi
	echo "简体中文描述: $schinese_description_bytes/$MAX_DESCRIPTION_BYTES 字节"

	local russian_description_bytes
	russian_description_bytes=$(LC_ALL=C wc -c < "$RUSSIAN_DESCRIPTION_FILE" | xargs)
	if [ "$russian_description_bytes" -gt "$MAX_DESCRIPTION_BYTES" ]; then
		echo "错误: 俄语描述为 $russian_description_bytes 字节，超过 Steam 的 $MAX_DESCRIPTION_BYTES 字节限制"
		exit 1
	fi
	echo "俄语描述: $russian_description_bytes/$MAX_DESCRIPTION_BYTES 字节"

    local release_title
    release_title=$(sed -n 's/^title=//p' "$WORKSHOP_FILE" | head -n 1)
    if [ "$release_title" != "[B42] Infinite Irrigation Pipes" ]; then
        echo "错误: Release 的英文标题是 $release_title"
        exit 1
    fi
}

vdf_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '%s' "$value"
}

install_steamcmd

if [ "$PREPARE_ONLY" -eq 1 ]; then
    echo "正在初始化 SteamCMD……"
    "$STEAMCMD" +quit
    echo "SteamCMD 已准备完成: $STEAMCMD"
    exit 0
fi

if [ "$DRY_RUN" -eq 0 ] && pgrep -f 'Project Zomboid.app/Contents/(MacOS/JavaAppLauncher|PlugIns/.*/bin/java)' >/dev/null 2>&1; then
    echo "提示: 检测到 Project Zomboid 正在运行，将继续上传。"
    echo "如果 SteamCMD 拒绝同账号登录，请退出游戏后重试。"
fi

if [ "$DRY_RUN" -eq 0 ]; then
    echo "步骤1: 重新生成 Release"
    "$SCRIPT_DIR/release.sh"
fi

validate_release

if [ -z "$CHANGE_NOTE" ]; then
    CHANGE_NOTE=$(git -C "$SCRIPT_DIR" log -1 --pretty=%s 2>/dev/null || true)
fi
if [ -z "$CHANGE_NOTE" ]; then
    CHANGE_NOTE="Project Zomboid Build 42 compatibility update"
fi

VDF_FILE=$(mktemp "${TMPDIR:-/tmp}/infinite-irrigation-workshop.XXXXXX.vdf")
trap 'unlink "$VDF_FILE" 2>/dev/null || true' EXIT

escaped_content=$(vdf_escape "$CONTENT_DIR")
escaped_preview=$(vdf_escape "$PREVIEW_FILE")
escaped_note=$(vdf_escape "$CHANGE_NOTE")
workshop_title=$(sed -n 's/^title=//p' "$WORKSHOP_FILE" | head -n 1)
escaped_title=$(vdf_escape "$workshop_title")
workshop_description=$(sed -n 's/^description=//p' "$WORKSHOP_FILE")
escaped_description=$(vdf_escape "$workshop_description")

printf '%s\n' \
    '"workshopitem"' \
    '{' \
    "    \"appid\" \"$EXPECTED_APP_ID\"" \
    "    \"publishedfileid\" \"$EXPECTED_WORKSHOP_ID\"" \
    "    \"contentfolder\" \"$escaped_content\"" \
    "    \"previewfile\" \"$escaped_preview\"" \
    "    \"title\" \"$escaped_title\"" \
    "    \"description\" \"$escaped_description\"" \
    "    \"changenote\" \"$escaped_note\"" \
    '}' > "$VDF_FILE"

echo "步骤2: 校验完成"
echo "Workshop ID: $EXPECTED_WORKSHOP_ID"
echo "发布内容: $CONTENT_DIR"
echo "更新说明: $CHANGE_NOTE"
echo "英文标题与描述: 将从 Release/workshop.txt 更新"
echo "简体中文描述: 请手动粘贴 $SCHINESE_DESCRIPTION_FILE"
echo "俄语描述: 请手动粘贴 $RUSSIAN_DESCRIPTION_FILE"
echo "标签和可见性不会被修改。"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run 完成，未登录 Steam，也未上传。"
    exit 0
fi

saved_steam_username=$(defaults read "$PREFERENCES_DOMAIN" "$PREFERENCES_ACCOUNT_KEY" 2>/dev/null || true)
if [ -z "$STEAM_USERNAME" ]; then
    if [ -n "$saved_steam_username" ]; then
        read -r -p "Steam 登录名 [$saved_steam_username]: " STEAM_USERNAME
        STEAM_USERNAME="${STEAM_USERNAME:-$saved_steam_username}"
    else
        read -r -p "请输入 Steam 登录名: " STEAM_USERNAME
    fi
fi
if [ -z "$STEAM_USERNAME" ]; then
    echo "错误: Steam 登录名不能为空"
    exit 1
fi

echo "步骤3: 登录 Steam 并上传"
echo "接下来如有提示，请直接在 SteamCMD 中输入密码和 Steam Guard 验证码。"
"$STEAMCMD" +login "$STEAM_USERNAME" +workshop_build_item "$VDF_FILE" +quit
defaults write "$PREFERENCES_DOMAIN" "$PREFERENCES_ACCOUNT_KEY" "$STEAM_USERNAME"

echo "发布命令已完成，已记住账号 ${STEAM_USERNAME}。"
echo "请继续更新本地化页面："
echo "  简体中文: https://steamcommunity.com/sharedfiles/filedetails/?id=${EXPECTED_WORKSHOP_ID}&l=schinese"
echo "  俄语: https://steamcommunity.com/sharedfiles/filedetails/?id=${EXPECTED_WORKSHOP_ID}&l=russian"
