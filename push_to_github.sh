#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  Push OCP Antenna firmware + docs lên GitHub
#  Repo  : https://github.com/TuanPT176/OCP_Antenna_Control.git
#  Branch: main
# ─────────────────────────────────────────────────────────────

REPO_URL="https://github.com/TuanPT176/OCP_Antenna_Control.git"
LOCAL_DIR="D:/Phan_Thanh_Tuan/UIT-Online/TTLab/Hold_Project/OCP Antenna/OCP_Firmware"

# ── 1. Di chuyển vào thư mục project ─────────────────────────
cd "$LOCAL_DIR" || { echo "❌ Không tìm thấy thư mục: $LOCAL_DIR"; exit 1; }
echo "📁 Đang ở: $(pwd)"

# ── 2. Khởi tạo git nếu chưa có ──────────────────────────────
if [ ! -d ".git" ]; then
    echo "🔧 Khởi tạo git repo..."
    git init
    git remote add origin "$REPO_URL"
else
    # Nếu đã init rồi, kiểm tra remote
    if ! git remote get-url origin &>/dev/null; then
        git remote add origin "$REPO_URL"
    else
        git remote set-url origin "$REPO_URL"
    fi
    echo "✅ Git repo đã tồn tại"
fi

# ── 3. Tạo .gitignore (bỏ qua file rác) ─────────────────────
cat > .gitignore << 'EOF'
# Arduino build output
build/
*.bin
*.elf
*.map

# OS junk
.DS_Store
Thumbs.db
desktop.ini

# Editor
.vscode/
*.swp
EOF

# ── 4. Stage các file cần push ────────────────────────────────
echo ""
echo "📦 Staging files..."

# File .ino (tất cả trong thư mục)
git add *.ino 2>/dev/null && echo "  ✔ .ino files" || echo "  ⚠ Không tìm thấy .ino"

# File markdown
git add *.md   2>/dev/null && echo "  ✔ .md files"  || echo "  ⚠ Không tìm thấy .md"

# File slide PowerPoint
git add *.pptx 2>/dev/null && echo "  ✔ .pptx files" || echo "  ⚠ Không tìm thấy .pptx"

# .gitignore
git add .gitignore

# ── 5. Kiểm tra có gì để commit không ────────────────────────
if git diff --cached --quiet; then
    echo ""
    echo "ℹ️  Không có thay đổi mới để commit. Repo đã up-to-date."
    exit 0
fi

# ── 6. Commit ─────────────────────────────────────────────────
COMMIT_MSG="Add ESP32-C3 PE64906 DTC firmware, guide and slide"
git commit -m "$COMMIT_MSG"
echo ""
echo "✅ Committed: $COMMIT_MSG"

# ── 7. Set branch main và push ───────────────────────────────
git branch -M main
echo ""
echo "🚀 Pushing lên $REPO_URL ..."
git push -u origin main

# ── 8. Kết quả ───────────────────────────────────────────────
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Push thành công!"
    echo "🔗 https://github.com/TuanPT176/OCP_Antenna_Control"
else
    echo ""
    echo "❌ Push thất bại. Xem lỗi ở trên."
    echo ""
    echo "💡 Gợi ý:"
    echo "   - Kiểm tra đã đăng nhập GitHub chưa:"
    echo "     git config --global user.name  'TuanPT176'"
    echo "     git config --global user.email 'your@email.com'"
    echo "   - Nếu bị lỗi authentication, dùng Personal Access Token:"
    echo "     git remote set-url origin https://<TOKEN>@github.com/TuanPT176/OCP_Antenna_Control.git"
    exit 1
fi
