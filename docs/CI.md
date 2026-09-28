# Android 自動檢查與編譯

工作流程：`.github/workflows/android-ci.yml`。

## 何時執行

- 推送至 `master`。
- 對 `master` 開啟或更新 Pull Request。
- 在 Actions 的 **Android checks and build** 按 **Run workflow**。

同一分支有更新時取消舊工作，避免重複編譯。工作流程只需要 `contents: read`，不需要設定私人 Token 或手機憑證。

## 檢查內容

1. **Ubuntu 24.04**：UTF-8／LF、必要檔案、JSON／Cargo.lock、Gradle wrapper JAR、Bash 與 mksh 語法、所有已提交工具與 `tools.sh` SHA 表的一致性。
2. **Windows 2022**：安裝 JDK 17、Android SDK 34、Build Tools 34.0.0、NDK r30 `30.0.16248370`、Rust `1.96.0`，從來源編譯 Dex 與 Android arm64 `speednative`。
3. Dex 沿用建置腳本的單一 Dex／必要 capability 檢查；Rust 沿用 ELF 架構、PIE、16 KiB segment、Android API 28／NDK r30 note 檢查。
4. 在獨立目錄組裝 CI 執行包，替換新 Dex／Rust，更新包內工具 SHA，重新核對 ZIP 實際位元組。

`ci/toolchain.json` 集中記錄 Rust／NDK／SDK 版本。Java major 與 Python minor 固定於工作流程；官方 Actions 固定到 commit SHA。

`versions.properties` 集中維護各組件版本；檢查器會核對腳本、Dex、Cargo 與自檢腳本，建置前亦執行 `sync_version.ps1 -Check`。更新來源時，應一起提交根目錄的 `build.ps1`、`VERSION`、`versions.properties`、`read_versions.ps1`、`sync_version.ps1`、`sync_artifacts.ps1`，以及完整 `dex/`、`rust/` 來源與相符的 `tools/` 產物。Rust 的 `src/` 與 `build.rs` 都是必要來源。同步腳本同時支援 GitHub 的 `tools/` 與 FULL_SOURCE 根目錄佈局；自行建置後仍需將產物複製至 `tools/`，CI 會在獨立打包目錄完成這一步。

## 下載產物

成功後，在該次 Actions 的 **Artifacts** 下載 `speedbackup-android-<commit>`，保留14天，包含：

- `SpeedBackup_<commit>_CI_RUNTIME.zip`：`start.sh`、完整 `tools/`、說明與授權；Dex／Rust 是本次新編譯，其他工具沿用該 commit 已提交且 SHA 驗證成功的版本。
- `SpeedBackup_<commit>_SOURCE_SNAPSHOT.zip`：由 `git archive` 生成的同一 commit 原始快照。
- `SHA256SUMS.txt`、`BUILD_INFO.json`：外層校驗碼、來源 commit、工具鏈與包內工具雜湊。

另有獨立的 `android-build-log-<commit>`，失敗時也盡量保存建置日誌。

這是 CI 產物，尚未設定自動發布 GitHub Release。`SOURCE_SNAPSHOT` 如實保存倉庫內容；目前倉庫沒有 tar／zstd／smbclient 的完整建置來源，因此不將它標為涵蓋所有工具的 `FULL_SOURCE`。原有完整源碼交付包仍獨立提供。

## 驗證範圍

- 語法檢查不執行備份／恢復腳本；Rust 建置會編譯既有 Android 測試，但不在 Windows 執行 Android ELF。
- 工作流程不連接手機或家中 SMB／WebDAV，不含私人資料或裝置設定。
- AppState、SSAID、Root、SELinux、凍結守護與不同 ROM 的實際行為仍需備用機驗收。CI 通過表示上述來源、語法、編譯與產物校驗通過。

## 本次初始化修正

最初的 `7ead439` 有 tar／zstd SHA 不一致；使用者的後續 `bc6c4c6` 更新已同步這兩筆記錄及全部 11 個工具。本 PR 以該更新為基底，保留新版二進位檔。

`bc6c4c6` 的腳本已使用 v780，版本設定與自檢脚本仍標記 v778；本次將兩者同步至 v780。Dex 及八個 Rust 子程序仍保留各自的功能版本。

實際 CI 也發現舊自製 Gradle wrapper 會優先使用主機的 `GRADLE_HOME`，令宣告的 8.2 被 runner 的 9.7.1 取代，導致 AGP 8.2.2 編譯失敗。本次改用 Gradle 8.2 官方 wrapper，並固定發行 ZIP 的 SHA256；建置步驟完整保存子程序輸出與錯誤碼。
