#!/bin/bash

# 无限灌溉系统发布脚本
# 自动备份当前发布版本并更新为最新开发版本

set -e  # 遇到错误立即退出

# 获取当前时间戳
TIMESTAMP=$(date +"%Y%m%d%H%M%S")

echo "开始发布流程，时间戳: $TIMESTAMP"

# 定义路径
SOURCE_DIR="/Users/matrix/Zomboid/Workshop/Infinite Irrigation System/Contents/mods/WaterPipes-IrrigationSystems"
SOURCE_WORKSHOP_FILE="/Users/matrix/Zomboid/Workshop/Infinite Irrigation System/workshop.txt"
SOURCE_SCHINESE_DESCRIPTION_FILE="/Users/matrix/Zomboid/Workshop/Infinite Irrigation System/workshop-schinese-description.txt"
SOURCE_RUSSIAN_DESCRIPTION_FILE="/Users/matrix/Zomboid/Workshop/Infinite Irrigation System/workshop-russian-description.txt"
SOURCE_PREVIEW_FILE="/Users/matrix/Zomboid/Workshop/Infinite Irrigation System/preview.png"
RELEASE_ROOT="/Users/matrix/Zomboid/Workshop/Infinite Irrigation System Release/Contents/mods"
RELEASE_DIR="$RELEASE_ROOT/WaterPipes-IrrigationSystems"
RELEASE_WORKSHOP_FILE="/Users/matrix/Zomboid/Workshop/Infinite Irrigation System Release/workshop.txt"
RELEASE_SCHINESE_DESCRIPTION_FILE="/Users/matrix/Zomboid/Workshop/Infinite Irrigation System Release/workshop-schinese-description.txt"
RELEASE_RUSSIAN_DESCRIPTION_FILE="/Users/matrix/Zomboid/Workshop/Infinite Irrigation System Release/workshop-russian-description.txt"
RELEASE_PREVIEW_FILE="/Users/matrix/Zomboid/Workshop/Infinite Irrigation System Release/preview.png"
COMPANY_DIR="/Users/matrix/Zomboid/Workshop/Infinite Irrigation System Company"
BACKUP_NAME="WaterPipes-IrrigationSystems_$TIMESTAMP"
BACKUP_DIR="$COMPANY_DIR/$BACKUP_NAME"
CLEANUP_SCRIPT="/Users/matrix/Zomboid/Workshop/remove_ds_store.sh"
RELEASE_MOD_INFO="$RELEASE_DIR/42/mod.info"
RENDER_ASSET_SCRIPT="/Users/matrix/Zomboid/Workshop/Infinite Irrigation System/tools/build_floor_render_assets.py"


echo "源目录: $SOURCE_DIR"
echo "发布目录: $RELEASE_DIR"
echo "备份目录: $BACKUP_DIR"

# 检查源目录是否存在
if [ ! -d "$SOURCE_DIR" ]; then
    echo "错误: 源目录不存在: $SOURCE_DIR"
    exit 1
fi

# 检查发布根目录是否存在
if [ ! -d "$RELEASE_ROOT" ]; then
    echo "错误: 发布根目录不存在: $RELEASE_ROOT"
    exit 1
fi

# 创建备份目录父目录（如果不存在）
mkdir -p "$COMPANY_DIR"

# 每次发布都从当前 11 张世界贴图重新生成地面渲染层资源，避免美术
# 更新后游戏仍读取旧的纹理包。
echo "步骤0: 生成水管地面渲染资源"
python3 "$RENDER_ASSET_SCRIPT"
echo "✅ 地面渲染资源已更新"
echo ""

# 步骤1: 统计当前发布版本信息（备份前）
echo "步骤1: 统计当前发布版本信息"
if [ -d "$RELEASE_DIR" ]; then
    cd "$RELEASE_DIR"

    OLD_MOD_SIZE=$(du -sh . | cut -f1)
    OLD_TOTAL_FILES=$(find . -type f | wc -l | xargs)
    OLD_LUA_FILES=$(find . -name "*.lua" | wc -l | xargs)
    OLD_LUA_LINES=$(find . -name "*.lua" -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")

    echo "📊 当前版本统计："
    echo "📦 模组大小: $OLD_MOD_SIZE"
    echo "📁 总文件数: $OLD_TOTAL_FILES 个文件"
    echo "🔧 Lua脚本: $OLD_LUA_FILES 个文件"
    echo "📝 代码行数: $OLD_LUA_LINES 行"
else
    echo "⚠️ 当前没有发布版本，这是首次发布"
    OLD_MOD_SIZE="0B"
    OLD_TOTAL_FILES=0
    OLD_LUA_FILES=0
    OLD_LUA_LINES=0
fi
echo ""

# 后续会删除并重建 RELEASE_DIR，不能继续停留在该目录中。
# 切回稳定存在的源目录，避免子进程出现 getcwd 失败。
cd "$SOURCE_DIR"

# 步骤2: 备份当前发布版本
echo "步骤2: 备份当前发布版本到 $BACKUP_DIR"
if [ -d "$RELEASE_DIR" ]; then
    cp -R "$RELEASE_DIR" "$BACKUP_DIR"
    echo "✅ 备份完成"
else
    echo "✅ 无需备份（首次发布）"
fi

# 步骤3: 清理发布目录
echo "步骤3: 清理发布目录"
if [ -d "$RELEASE_DIR" ]; then
    rm -rf "$RELEASE_DIR"
    echo "✅ 发布目录已清理"
else
    echo "✅ 发布目录原本为空"
fi

# 步骤4: 复制最新开发版本到发布目录（排除 .git）
echo "步骤4: 复制最新开发版本到发布目录（排除 .git）"
mkdir -p "$RELEASE_DIR"
rsync -a --delete --exclude ".git" "$SOURCE_DIR/" "$RELEASE_DIR/"
echo "✅ 最新版本已复制到发布目录（已排除 .git）"

# 步骤5: 更新发布版本的 mod.info
# 将开发版 ID 改为正式发布版 ID

echo "步骤5: 更新发布版本的 mod.info"
if [ -f "$RELEASE_MOD_INFO" ]; then
    sed -i '' 's/id=InfiniteIrrigationPipes-dev/id=InfiniteIrrigationPipes/' "$RELEASE_MOD_INFO"
    echo "✅ mod.info ID 已更新为发布版本"
else
    echo "⚠️ mod.info 文件不存在: $RELEASE_MOD_INFO"
fi

# 步骤6: 同步工坊描述与预览图，并保留正式发布 ID
echo "步骤6: 同步工坊描述与预览图"
cp "$SOURCE_WORKSHOP_FILE" "$RELEASE_WORKSHOP_FILE"
sed -i '' 's/^id=.*/id=3548529064/' "$RELEASE_WORKSHOP_FILE"
sed -i '' 's/^title=.*/title=[B42] Infinite Irrigation Pipes/' "$RELEASE_WORKSHOP_FILE"
cp "$SOURCE_SCHINESE_DESCRIPTION_FILE" "$RELEASE_SCHINESE_DESCRIPTION_FILE"
cp "$SOURCE_RUSSIAN_DESCRIPTION_FILE" "$RELEASE_RUSSIAN_DESCRIPTION_FILE"
cp "$SOURCE_PREVIEW_FILE" "$RELEASE_PREVIEW_FILE"
echo "✅ 英文描述、简体中文粘贴稿与俄语粘贴稿已同步到正式发布目录"

# 步骤7: 运行清理脚本并移除 macOS 元数据文件
echo "步骤7: 运行清理脚本并移除 macOS 元数据文件"
if [ -f "$CLEANUP_SCRIPT" ]; then
    bash "$CLEANUP_SCRIPT"
    echo "✅ DS_Store 文件已清理"
else
    echo "⚠️ 清理脚本不存在: $CLEANUP_SCRIPT"
fi

find "$RELEASE_DIR" -name ".DS_Store" -type f -delete
find "$RELEASE_DIR" -name "._*" -type f -delete

echo "✅ 已移除 macOS 元数据文件（.DS_Store / ._*）"

# 步骤8: 统计新发布版本信息并对比差异
echo "步骤8: 统计新发布版本信息并对比差异"
cd "$RELEASE_DIR"

NEW_MOD_SIZE=$(du -sh . | cut -f1)
NEW_TOTAL_FILES=$(find . -type f | wc -l | xargs)
NEW_LUA_FILES=$(find . -name "*.lua" | wc -l | xargs)
NEW_LUA_LINES=$(find . -name "*.lua" -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")

if [ "$OLD_TOTAL_FILES" -ne 0 ]; then
    FILES_DIFF=$((NEW_TOTAL_FILES - OLD_TOTAL_FILES))
    LUA_FILES_DIFF=$((NEW_LUA_FILES - OLD_LUA_FILES))
    LUA_LINES_DIFF=$((NEW_LUA_LINES - OLD_LUA_LINES))

    if [ "$FILES_DIFF" -gt 0 ]; then
        FILES_CHANGE="(+$FILES_DIFF)"
    elif [ "$FILES_DIFF" -lt 0 ]; then
        FILES_CHANGE="($FILES_DIFF)"
    else
        FILES_CHANGE="(无变化)"
    fi

    if [ "$LUA_FILES_DIFF" -gt 0 ]; then
        LUA_FILES_CHANGE="(+$LUA_FILES_DIFF)"
    elif [ "$LUA_FILES_DIFF" -lt 0 ]; then
        LUA_FILES_CHANGE="($LUA_FILES_DIFF)"
    else
        LUA_FILES_CHANGE="(无变化)"
    fi

    if [ "$LUA_LINES_DIFF" -gt 0 ]; then
        LUA_LINES_CHANGE="(+$LUA_LINES_DIFF)"
    elif [ "$LUA_LINES_DIFF" -lt 0 ]; then
        LUA_LINES_CHANGE="($LUA_LINES_DIFF)"
    else
        LUA_LINES_CHANGE="(无变化)"
    fi
else
    FILES_CHANGE="(新增)"
    LUA_FILES_CHANGE="(新增)"
    LUA_LINES_CHANGE="(新增)"
fi

echo ""
echo "📊 版本对比统计："
echo "┌─────────────────┬─────────────────┬─────────────────┬─────────────────┐"
echo "│     项目        │   上一版本      │   新版本        │     变化        │"
echo "├─────────────────┼─────────────────┼─────────────────┼─────────────────┤"
echo "│ 📦 模组大小     │ $OLD_MOD_SIZE$(printf '%*s' $((16-${#OLD_MOD_SIZE})) '')│ $NEW_MOD_SIZE$(printf '%*s' $((16-${#NEW_MOD_SIZE})) '')│ $OLD_MOD_SIZE→$NEW_MOD_SIZE$(printf '%*s' $((16-${#OLD_MOD_SIZE}-${#NEW_MOD_SIZE}-1)) '')│"
echo "│ 📁 总文件数     │ $OLD_TOTAL_FILES$(printf '%*s' $((16-${#OLD_TOTAL_FILES})) '')│ $NEW_TOTAL_FILES$(printf '%*s' $((16-${#NEW_TOTAL_FILES})) '')│ $FILES_CHANGE$(printf '%*s' $((16-${#FILES_CHANGE})) '')│"
echo "│ 🔧 Lua脚本      │ $OLD_LUA_FILES$(printf '%*s' $((16-${#OLD_LUA_FILES})) '')│ $NEW_LUA_FILES$(printf '%*s' $((16-${#NEW_LUA_FILES})) '')│ $LUA_FILES_CHANGE$(printf '%*s' $((16-${#LUA_FILES_CHANGE})) '')│"
echo "│ 📝 代码行数     │ $OLD_LUA_LINES$(printf '%*s' $((16-${#OLD_LUA_LINES})) '')│ $NEW_LUA_LINES$(printf '%*s' $((16-${#NEW_LUA_LINES})) '')│ $LUA_LINES_CHANGE$(printf '%*s' $((16-${#LUA_LINES_CHANGE})) '')│"
echo "└─────────────────┴─────────────────┴─────────────────┴─────────────────┘"

echo ""
echo "🎉 发布流程完成！"
echo "📦 备份版本: $BACKUP_DIR"
echo "🚀 发布版本: $RELEASE_DIR"
echo "🧹 DS_Store 文件已清理"
echo ""
echo "现在可以发布新版本了！🌱"
