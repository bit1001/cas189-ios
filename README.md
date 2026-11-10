# 189秒传 iOS 复刻 (CAS189)

把 Android 版「189云盘秒传 v1.51」的能力用 Swift 重写成一个可侧载的 iOS App：天翼云盘 PC 接口 + 签名上传 + 秒传 + 后台下载。
逆向依据见 `189秒传-逆向报告与iOS复刻方案.md` 与 `189秒传-v1.51-反编译源码.zip`。

- **Core 是跨平台 SwiftPM 包**，Linux 上可编译、可跑单测、可用 CLI 打真实接口。
- **App 是 SwiftUI 外壳**（iOS 16+），出包走 GitHub Actions，无需 Mac。

## 目录

```
Package.swift              # CAS189Core 跨平台包（Linux 可编译可测）+ cas189 CLI
Sources/CAS189Core/
  C.swift                  # 常量（appId / 版本 / 分片 10MB / 域名 / 家庭云 appKey）
  Crypto.swift             # MD5、SHA1、HMAC-SHA1、分片指纹、RSA(PKCS1 v1.5)
  AES.swift                # 纯 Swift AES-128/ECB/PKCS7（CryptoKit 不提供 ECB）
  Signer.swift             # 与 uploadRequestWithKey 一致的请求签名
  Transport.swift          # URLSession + 自管 Cookie + 302 拦截
  Cloud189Client.swift     # 登录 / 会话 / 目录 / 列表(含缩略图) / 签名接口
  Rapid.swift              # 秒传三段式：init → checkTransSecond → commit
  Upload.swift             # 真实分片上传（S3 预签名直传 + 上传回调）
  Download.swift           # 下载直链（家庭云签名通道 / 个人云 web 通道 + https 规范化）
  Family.swift             # 家庭云：列表 / 建夹 / 上传 / 秒传 / COPY 转存 / 改名 / 删除
  Share.swift              # 创建分享链接
  ShareImport.swift        # 分享信息 / 目录 / 转存（SHARE_SAVE + 任务轮询）
  CasFile.swift            # .cas 凭证解析（裸 JSON / Base64(JSON) / 多层嵌套 / zip 批量）
  Torrent.swift + Bencode.swift  # .torrent 解析与单文件种子秒传
  WebListParser.swift      # web 通道 XML 解析（含 <smallUrl> 缩略图）
  Models.swift
Sources/cas189/main.swift  # 命令行（28 个子命令，见下）
Tests/CAS189CoreTests/     # 28 个用例（MD5/SHA1/HMAC/AES 向量、cas/torrent 解析、XML）
App/                       # SwiftUI 外壳（xcodegen 生成 Xcode 工程）
.github/workflows/ios.yml  # CI：Linux 单测 + macOS 编译 + 未签名 IPA + 直链发布
```

## 本地跑（Linux，无 Xcode）

```bash
export PATH=/opt/swift/usr/bin:$PATH     # Swift 6.0.3 已装在 /opt/swift
swift build && swift test
```

实测结果（Ubuntu 24.04 / Swift 6.0.3）：

- `swift build` 零错误
- `swift test` **28/28 通过**（含 FIPS-197 AES 向量、RFC 2202 HMAC-SHA1）
- CLI 指纹与 `md5sum`、独立 Python 实现逐字符一致

## App 功能

底部 5 个 Tab：

### 登录
- 内嵌 `WKWebView` 走官方网页登录（拼图验证码做了 touch→mouse 事件桥 + UA 切换）
- 也支持粘贴 Cookie 直接换 sessionKey
- 会话持久化到本地，重启自动恢复

### 文件
- 个人云 / 家庭云双空间切换（家庭云用另一套 `AccessToken` + MD5 签名体系）
- 目录浏览、进入/返回、缩略图（`iconOption=5` 的 `<smallUrl>`，免 Cookie）
- 新建文件夹、改名、删除
- 搜索（服务端无接口，客户端递归遍历 depth ≤ 3）
- 长按菜单：下载 / 创建分享链接 / 转存到个人云（家庭云）
- 下载走后台任务，进「下载」Tab 看进度

### 导入
- **选择文件上传**：先试秒传，未命中自动转真实分片上传
- **导入秒传凭证**：`.cas` / `.torrent` / `.zip` 批量，zip 自动落到同名文件夹
  - `.cas` 兼容裸 JSON、Base64(JSON)、多层嵌套、五字段精简格式
  - zip 里的条目按内容判断，不依赖后缀名
- **分享链接转存**：支持提取码，转到指定空间与目录
- **剪贴板导入**：在「文件」App 里拷贝后一键取用（绕开选择器限制）
- **URL 导入**：直接下载远程文件再导入
- App 文件夹管理：查看 / 删除 / 清空凭证文件
- 上传成功后自动清理 App 文件夹里的本地副本（只删沙盒内，失败保留）

### 下载
- 后台 `URLSession` 会话，切走页面、锁屏、App 退到后台都继续下
- 任务列表带进度条、已下载/总大小/百分比，状态区分 排队 / 下载中 / 已暂停 / 完成 / 失败 / 中断
- 暂停 / 继续 / 取消 / 重试 / 删除
- 保存目录可选：App 文件夹 / Inbox / 已有子文件夹 / 新建文件夹（在「文件」App 里也能看到）
- 同名文件自动加序号，不覆盖
- 任务元数据持久化，重启后列表不丢；中断任务标「可重试」
- 完成/失败都写日志

### 日志
- 全链路请求日志（含 HTTP 状态与字节数）、诊断环境自检、清空

## 命令行（不用 iPhone 也能验证真实接口）

共 28 个子命令，直接运行 `swift run cas189` 会打印完整帮助。主要几个：

```bash
# 登录与列表
swift run cas189 login --cookie "COOKIE_LOGIN_USER=…"   # 会话存 ~/.cas189/session.json (600)
swift run cas189 ls --folder -11                        # 列个人云目录
swift run cas189 fingerprint --file ~/a.mp4             # 离线，只算 md5 + 10MB 分片 sliceMd5

# 上传与秒传
swift run cas189 rapid --file ~/a.mp4 --folder -11
swift run cas189 upload --file ~/a.mp4 --folder -11
swift run cas189 make-cas --file ~/a.mp4 --out a.cas
swift run cas189 cas-info --file a.cas
swift run cas189 rapid-cas --file a.cas --folder -11
swift run cas189 rapid-zip --file pack.zip --folder -11
swift run cas189 make-torrent --file ~/a.mp4 --out a.torrent
swift run cas189 torrent-info --file a.torrent
swift run cas189 rapid-torrent --file a.torrent --folder -11

# 文件管理
swift run cas189 mkdir --name 新建 --folder -11
swift run cas189 rename --id <fileId> --name 新名
swift run cas189 rm --id <fileId>
swift run cas189 search --keyword 关键词 --folder -11
swift run cas189 get --id <fileId> --out ./a.mp4        # 下载（同名已存在时用 Range 续传）
swift run cas189 url --id <fileId>                      # 只取下载直链
swift run cas189 get --id <fileId> --family-id <fid>    # 家庭云下载

# 分享
swift run cas189 share --id <fileId> --days 7
swift run cas189 parse-share --text "https://cloud.189.cn/t/…"
swift run cas189 share-info --code <shareCode>          # 有提取码加 --pwd
swift run cas189 share-save --code <shareCode> --pwd <pwd> --to -11

# 家庭云
swift run cas189 family-ls
swift run cas189 family-mkdir --name 目录
swift run cas189 family-upload --file ~/a.mp4           # 真实文件上传（秒传未命中时）
swift run cas189 family-rapid --file a.cas              # 凭 .cas / .cas.torrent 秒传
swift run cas189 family-copy --id <fileId> --to -11     # 家庭云 → 个人云

# 兜底
swift run cas189 raw --uri /api/open/… --params "k=v&k2=v2"   # 发任意签名请求，便于继续挖接口
```

## 出 app

本地（有 Mac）：

```bash
brew install xcodegen
cd App && xcodegen generate
open CAS189.xcodeproj
```

CI（`bit1001/cas189-ios`）：

- `core-tests`：Linux 容器跑 `swift test`
- `build-app`：macOS 编模拟器 app
- `build-ipa`：macOS 出**未签名** IPA，并把下载直链写到 `ci-artifacts` 分支

侧载：LiveContainer 直接装，或用 AltStore / Sideloadly 自签。未签名 IPA 需要重签名才能装到非越狱设备。

## 已实现

**协议层**

- [x] Cookie 登录（`COOKIE_LOGIN_USER` → `getUserBriefInfo.action` 换 sessionKey）
- [x] 账号密码登录（RSA/PKCS1 + 图形验证码 + `getSessionForPC.action`）
- [x] 签名接口（AES-128-ECB + HMAC-SHA1 + RSA(EncryptionText) + `decodefields`）
- [x] 目录浏览 / 新建 / 改名 / 删除 / 搜索（客户端遍历）
- [x] 本地文件指纹（10MB 分片 MD5，并发）+ 秒传命中判定
- [x] 秒传三段式（`initMultiUpload` → `checkTransSecond` → `commitMultiUploadFile`）
- [x] 真实分片上传（S3 预签名直传，`partInfo` 用 Base64(raw MD5)）
- [x] 下载直链双通道（家庭云签名接口 / 个人云 web 通道）+ `http`→`https` 规范化
- [x] 缩略图（`iconOption=5` 的 `<smallUrl>`）
- [x] 创建分享链接、解析分享、带提取码转存、任务轮询
- [x] `.cas` 凭证生成与解析（含 Base64 / 多层 / zip 批量 / 五字段精简格式）
- [x] `.torrent` 解析与单文件种子秒传
- [x] 家庭云完整链路：列表 / 建夹 / 上传 / 秒传 / COPY 转存到个人云 / 改名 / 删除
- [x] 会话过期检测与重新登录
- [x] 28 个子命令的 CLI，可脱离 App 验证真实接口

**App 层**

- [x] 5 Tab 界面：登录 / 文件 / 导入 / 下载 / 日志
- [x] WKWebView 网页登录（验证码事件桥）
- [x] 双空间（个人云 / 家庭云）浏览与文件管理
- [x] 上传（秒传优先 / 真实上传兜底）与进度
- [x] 凭证包批量秒传（zip 自动落地同名文件夹）
- [x] 分享转存、家庭云跨空间转存
- [x] 原生文件选择器（独立 UIWindow 呈现，绕开 SwiftUI 层级问题）
- [x] 分享进来文件（Open in…）的处理界面，可选处理方式与目标目录
- [x] 剪贴板导入、URL 导入
- [x] 上传成功自动清理本地副本（仅沙盒内）
- [x] 后台下载管理（进度 / 暂停 / 续 / 取消 / 重试 / 目标目录）
- [x] 后台任务（`BGTaskScheduler`）与诊断自检
- [x] 未签名 IPA 的 CI 自动出包与直链发布

## 未实现 / 已知限制

- [ ] 压缩包解包（rar/7z，需要第三方 C 库）
- [ ] 移动文件（`moveFile.action` 的 `destFolderId` / `targetFolderId` 均返回 `InvalidArgument`，接口参数未打通）
- [ ] 分享转存到家庭云（`SHARE_SAVE` 在家庭云固定报 `ShareSaveTaskIsAlreadyExist`，只能走 COPY）
- [ ] 服务端搜索接口（`searchFile.action` / `search.action` 均 404，目前客户端递归）
- [ ] App 端下载断点续传（后台会话中断后需重下，标「可重试」；CLI 的 `get` 已支持 Range 续传）
- [ ] Keychain 持久化会话（目前存沙盒文件）

## 关键算法（与服务端对齐）

```
sliceSize = 10MB
每个分片 MD5（大写） → 拼接后 MD5（大写）= sliceMd5；单分片时 sliceMd5 = 该分片 MD5
initMultiUpload 返回 fileDataExists==1 → 云端已有内容
commitMultiUploadFile = 落库，0 字节流量完成

签名（个人云）：
  rnd        = 随机 16~31 位
  paramsHex  = hex(AES-128-ECB-PKCS7(paramsString, key=rnd[0:16]))
  Signature  = HMAC-SHA1(key=rnd,
                 "SessionKey=..&Operate=..&RequestURI=..&Date=<ms>&params=<paramsHex>")
  EncryptionText = Base64(RSA-PKCS1(rnd))

家庭云鉴权（两段）：
  1. GET /api/open/oauth2/getAccessTokenBySsKey.action
       头 Signature = md5("AppKey=..&SessionKey=..&Timestamp=..")
     → accessToken
  2. 调 api.cloud.189.cn/open/family/*
       头 Signature = md5("AccessToken=..&Timestamp=.." + 参数按 key 升序 "&k=v")
     表单 body 的键与值要分别 URL 编码

上传：POST {prefix}/getMultiUploadUrls，partInfo = "<n>-<Base64(raw MD5)>"（1-based）
commit：uploadFileId, fileMd5, sliceMd5, lazyCheck=1, opertype=(overwrite ? 3 : 1)

下载直链规范化（与官方 App 的 normalizeDownloadUrl 一致）：
  去空白 → &amp; 还原为 & → "//" 前缀补 "https:" → "http://" 改写 "https://"
```

## 许可

MIT，见 `LICENSE`。
