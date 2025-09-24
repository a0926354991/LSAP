# Smart Trash Can 系統安裝與設定報告

## 一、系統概述
**Smart Trash Can System** 是一個「像丟進垃圾桶但可安全回收」的檔案管理工具。它包含三個指令：

- **`srm`**：安全刪除檔案/資料夾──先打包壓縮，再移到 `~/.trash`，同時建立中繼資料以便日後還原。  
- **`srm-restore`**：顯示垃圾桶清單，讓你用索引號選擇要復原的項目。  
- **`srm-empty`**：清除超過設定保存天數的垃圾；天數可用環境變數 `TRASH_MAX_AGE_DAYS` 設定，亦可搭配 `systemd` 計時器自動執行。

---

## 二、原始碼與檔案
- `~/bin/srm`：把指定的檔案或資料夾打包成 **tar.gz**，搬到 `~/.trash/files/`，並在 `~/.trash/meta/` 建立 **.meta.csv**，記錄原始路徑、刪除時間與檔案大小。  
- `~/bin/srm-restore`：讀取 **.meta.csv**，列出清單，讓你用索引選擇要還原的檔案或資料夾。  
- `~/bin/srm-empty`：移除超過 `TRASH_MAX_AGE_DAYS`（預設 **7 天**）的壓縮檔與其中繼資料。  
- `~/.config/systemd/user/srm-empty.service` / `srm-empty.timer`：設定使用者層級的 `systemd` 服務與計時器，每日自動執行清理。

建議的目錄結構：
```
~
├── bin/
│   ├── srm
│   ├── srm-restore
│   └── srm-empty
└── .trash/
    ├── files/        # 存 .tar.gz 的實體垃圾
    └── meta/         # 存對應的 .meta.csv
```

---

## 三、系統設定步驟

### 1) 建立目錄
```bash
mkdir -p ~/bin ~/.config/systemd/user ~/.trash/files ~/.trash/meta
```

### 2) 建立三支指令檔並賦予可執行權限
> 將你的腳本內容各自存為 `~/bin/srm`、`~/bin/srm-restore`、`~/bin/srm-empty` 後：
```bash
chmod +x ~/bin/srm ~/bin/srm-restore ~/bin/srm-empty
```

### 3) 確保 `~/bin` 在 PATH 裡
```bash
grep -q 'export PATH="$HOME/bin:$PATH"' ~/.bashrc || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 4) 建立 `systemd` 服務與排程（使用者層級）

#### 建立 `~/.config/systemd/user/srm-empty.service`
```ini
[Unit]
Description=Run srm-empty once to purge expired trashed items

[Service]
Type=oneshot
ExecStart=%h/bin/srm-empty
```

#### 建立 `~/.config/systemd/user/srm-empty.timer`
```ini
[Unit]
Description=Daily run of srm-empty

[Timer]
OnCalendar=daily
Persistent=true
Unit=srm-empty.service

[Install]
WantedBy=timers.target
```

#### 啟用與立即啟動
```bash
systemctl --user daemon-reload
systemctl --user enable --now srm-empty.timer
systemctl --user list-timers srm-empty.timer
```

> 小提醒：若你的系統需要透過 `loginctl enable-linger <使用者>` 才能在未登入時啟動使用者計時器，請依環境調整。

---

## 四、功能示範

### 1) 刪除檔案 / 資料夾
刪除單一檔案：
```bash
srm ~/lab/a.txt
```
成功後，垃圾桶內會生成對應的 `files/*.tar.gz` 與 `meta/*.meta.csv`。

刪除資料夾：
```bash
srm ~/lab            # 系統會提示要加上 -r
srm -r ~/lab         # 使用 -r 進行遞迴打包刪除
```

### 2) 還原檔案
```bash
srm-restore
```
執行後會列出清單並顯示索引號，依照指示輸入索引與還原目的地即可。

### 3) 自動清空（依保存天數）
手動測試（將最大片保存天數設為 0 天，以便立即清除）：
```bash
TRASH_MAX_AGE_DAYS=0 srm-empty
```
查看計時器狀態：
```bash
systemctl --user list-timers srm-empty.timer
```

---

## 五、環境變數
- `TRASH_MAX_AGE_DAYS`：控制垃圾保留天數（整數；預設 `7`）。  
  可在單次執行前臨時設定：
  ```bash
  TRASH_MAX_AGE_DAYS=3 srm-empty
  ```
  或寫入 `~/.bashrc` 長期生效：
  ```bash
  echo 'export TRASH_MAX_AGE_DAYS=7' >> ~/.bashrc
  source ~/.bashrc
  ```

---

## 六、常見問題
- **找不到 `srm` 指令**：確認 `~/bin` 已加入 `PATH`，或重新登入 Shell。  
- **`systemctl --user` 無法使用**：確認目前使用者 session 支援 user services，或改用系統層級的 `systemd`。  
- **還原時路徑權限失敗**：確認目標路徑存在且具有寫入權限。

---

## 七、版本與授權（可選）
- 版本：v1.0  
- 授權：MIT / Apache-2.0（請依實際專案選擇）
