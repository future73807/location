# vivo设备查找 - Flutter应用

基于 Flutter WebView 的 Android 应用，封装 [vivo查找设备](https://find.vivo.com.cn/h5/home/devices) 网页，支持登录凭证持久化和密码管理。

## 功能

- **WebView 封装** — 内嵌 vivo 设备查找网页，原生应用体验
- **登录持久化** — Cookie + DOM Storage + SharedPreferences 多重保存，长时间保持登录
- **密码自动保存** — 检测登录表单，提示保存/更新密码
- **密码自动填充** — 页面加载后自动填充已保存的凭证（支持点击"密码登录"标签页）
- **多账号管理** — 支持保存多个账号，通过单选框选择用于自动填充的账号
- **加密存储** — 密码使用 `flutter_secure_storage`（Android EncryptedSharedPreferences）加密保存
- **生物认证** — 查看密码前需通过指纹/面容/PIN/图案验证
- **返回手势** — 返回键优先 WebView 后退，无历史时双击退出
- **工具栏** — 主页、刷新、密码管理、清除凭证

## 技术栈

| 组件 | 说明 |
|------|------|
| Flutter >=3.0.0 | 跨平台框架 |
| webview_flutter ^4.4.2 | WebView 组件 |
| shared_preferences ^2.2.2 | Cookie/配置持久化 |
| flutter_secure_storage ^9.2.4 | 加密存储密码 |
| local_auth ^2.3.0 | 设备生物认证 |
| hugeicons ^1.1.5 | 图标库 |

## 构建

```bash
# 安装依赖
flutter pub get

# 构建 Release APK
flutter build apk --release

# 安装到设备
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## 项目结构

```
lib/
  main.dart              # 应用入口、WebView、密码管理、UI
assets/
  icon.png               # 应用图标（导航箭头）
android/
  app/src/main/
    AndroidManifest.xml   # 权限配置（网络、生物认证）
    kotlin/.../
      MainActivity.kt     # FlutterFragmentActivity（生物认证需要）
```

## 许可证

MIT License
