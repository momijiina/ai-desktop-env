# ai-desktop-env
AIにWSL2を使ってUbuntuのデスクトップ環境を与える為のテスト環境構築の自動化テストです<br/>
Ubuntu 24 LTSを使っています
<img width="1873" height="944" alt="image" src="https://github.com/user-attachments/assets/9f295664-24f8-4080-8a50-93e036132649" />


## 使い方

### 1. Windows側

PowerShellで実行:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\00_windows_prepare_wsl.ps1
```

管理者権限で実行すると、6080/TCPのFirewall許可も自動で試みます。

### 2. WSL Ubuntu側

Ubuntuを起動して、このスクリプトファイルを配置したディレクトリで実行:

```sh
bash 01_wsl_build_ai_desktop_env.sh
```

初回は `lxd` グループ反映のために止まることがあります。  
その場合はWindows側PowerShellで以下を実行してから、Ubuntuを開き直して再実行してください。

```powershell
wsl --shutdown
```

### 3. アクセス

```text
http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale
```

### 4. 削除と再構築
削除スクリプトはまだ未検証です。

### 5. 再起動後など
WSLを閉じた時などに起動しなおす必要があります
####  WSL側で起動する

```sh
cd ~/ai-desktop-env
bash 03_start_ai_desktop_env.sh
```

成功したら:

```text
http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale
```

### 永続化
起動スクリプト名は以下とする。
```text
~/ai-desktop-env/03_start_ai_desktop_env.sh
```
#### WSL側
```sh
cd ~/ai-desktop-env
bash 04_persist_ai_desktop_env.sh
```
確認:
```sh
systemctl --user status ai-desktop-env-start.service --no-pager -l
sudo journalctl --user -u ai-desktop-env-start.service -n 100 --no-pager
```

## 内容

- WSL mirrored networking 用 `.wslconfig`
- LXD / Workshop 導入
- Workshop project 生成
- Xfce Desktop
- TigerVNC
- noVNC / websockify
- Chromium
- 日本語フォント
- 日本語ロケール
- tunnel接続

## 注意

現在のVNCは検証優先で `-SecurityTypes None`
つまりパスワードなしです。  
LAN公開や別PC利用では、VPNやVNC認証などを追加してください。
