# 我的小账本 (My Wallet)

个人记账 **安卓 App**，极简风格，数据全部保存在手机本地，不联网、不申请权限。

> ⚠️ **仅支持安卓（Android 5.0+）**，暂不支持苹果 iOS / iPadOS。

## 功能

- **记一笔**：收入 / 支出，支持今天、昨天、任意日期（可提前记录未来的计划账）
- **概览**：本月收入、支出、结余一目了然；设置月预算后自动计算"已花 / 还剩 / 每天还能花多少"，超支自动标红
- **明细**：按月分组流水，点击任意记录可编辑或删除；未来的账目标记为"计划"
- **规划**：设置每月预算、发薪日；支持数据导出 / 导入（剪贴板备份，方便换机）

## 截图

<img width="1200" height="2532" alt="ce6e3daf7642f145360e26db6be80ffb" src="https://github.com/user-attachments/assets/fd573a60-27a1-4520-a9a0-8aec53307c8b" />
<img width="1200" height="2523" alt="1dfec8f976fad914d05265df2f187e98" src="https://github.com/user-attachments/assets/e9df5b44-1ae4-43e7-8559-53f1e891722e" />


## 下载安装

到 [Releases](../../releases) 页面下载 `我的小账本.apk`，传到安卓手机后点击安装即可
（安装时系统提示"未知来源应用"，选择"仍要安装"）。

## 构建

1. 安装 Flutter 3.24+ 与 Android SDK
2. `flutter pub get`
3. 复制 `android/key.properties.example` 为 `android/key.properties`，填入你自己的签名信息
4. `flutter build apk --release`

产物：`build/app/outputs/flutter-apk/app-release.apk`

## 说明

- 无后端、无账号、无网络请求，数据存储于应用私有目录（卸载即清除，记得用"导出"功能备份）
- 仅供个人学习使用
