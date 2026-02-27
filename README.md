# Vivo设备查找 - Flutter应用

这是一个使用Flutter开发的Android应用，用于访问vivo设备查找网站（https://find.vivo.com.cn/h5/home/devices），并实现登录凭证的长期保存。

## 功能特点

- 🌐 通过WebView访问vivo设备查找网站
- 💾 自动保存登录凭证（Cookies）
- 🔄 下次打开应用自动恢复登录状态
- 🗑️ 可手动清除登录凭证
- 📱 完整的Android应用体验

## 技术栈

- Flutter SDK (>=3.0.0)
- WebView加载网页内容
- SharedPreferences持久化存储登录凭证
- Cookie管理实现长期登录

## 构建步骤

### 1. 确保已安装Flutter

```bash
flutter doctor
```

如果没有安装Flutter，请访问 [Flutter官网](https://flutter.dev/docs/get-started/install) 下载安装。

### 2. 安装依赖

在项目根目录运行：

```bash
flutter pub get
```

### 3. 连接Android设备或启动模拟器

```bash
flutter devices
```

### 4. 运行应用

```bash
# 调试版本
flutter run

# 或指定设备
flutter run -d <device-id>
```

### 5. 构建APK

```bash
# 构建调试版本APK
flutter build apk --debug

# 构建发布版本APK
flutter build apk --release
```

APK文件位置：
- 调试版本：`build/app/outputs/flutter-apk/app-debug.apk`
- 发布版本：`build/app/outputs/flutter-apk/app-release.apk`

### 6. 安装到设备

```bash
# 通过USB安装
flutter install

# 或手动安装APK
adb install build/app/outputs/flutter-apk/app-release.apk
```

## 使用说明

1. **首次使用**：打开应用后，会加载vivo设备查找网站
2. **登录**：在WebView中完成登录操作
3. **自动保存**：登录成功后，应用会自动保存登录凭证
4. **下次使用**：重新打开应用时，会自动恢复登录状态
5. **清除凭证**：点击右上角菜单 → "清除登录凭证"可以清除保存的登录信息

## 项目结构

```
├── lib/
│   └── main.dart              # 主应用代码
├── android/                   # Android平台配置
│   ├── app/
│   │   ├── build.gradle       # 应用级构建配置
│   │   └── src/main/
│   │       ├── AndroidManifest.xml
│   │       └── kotlin/        # MainActivity
│   ├── build.gradle           # 项目级构建配置
│   └── settings.gradle
├── pubspec.yaml               # Flutter依赖配置
└── README.md                  # 项目说明
```

## 权限说明

应用需要以下权限：
- `INTERNET`：访问网络
- `ACCESS_NETWORK_STATE`：检查网络状态

## 注意事项

- 本应用仅用于个人学习和研究
- 请遵守vivo设备查找网站的使用条款
- 登录凭证存储在本地，请确保设备安全
- 如遇到加载问题，请检查网络连接

## 自定义配置

### 修改应用名称

编辑 [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)：
```xml
android:label="你的应用名称"
```

### 修改应用包名

1. 重命名包目录：`com/example/vivo_device_finder` → `your/package/name`
2. 更新 [android/app/build.gradle](android/app/build.gradle)：
```gradle
applicationId "your.package.name"
namespace "your.package.name"
```
3. 更新 [MainActivity.kt](android/app/src/main/kotlin/com/example/vivo_device_finder/MainActivity.kt)：
```kotlin
package your.package.name
```

### 修改目标网址

编辑 [lib/main.dart](lib/main.dart)，修改URL：
```dart
.loadRequest(Uri.parse('https://your-url.com'));
```

## 故障排除

### WebView显示空白
- 检查网络连接
- 确认目标网站可访问
- 尝试清除应用缓存

### 登录状态未保存
- 检查应用存储权限
- 确认网站使用了可持久化的Cookie
- 尝试手动刷新页面

### APK安装失败
- 确保允许安装未知来源应用
- 检查Android版本兼容性（最低Android 5.0）

## 开发者信息

本应用使用Flutter框架开发，支持Android 5.0（API 21）及以上版本。

## 许可证

MIT License
