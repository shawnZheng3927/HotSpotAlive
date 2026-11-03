# 发布到 GitHub

推荐仓库名：`HotSpotAlive`，公开仓库。源码保存在仓库，安装文件保存在 Releases，后续换电脑只需下载 DMG。

## 发布前已经准备的内容

- `scripts/release.sh`：生成 Intel / Apple Silicon 通用安装包、ZIP、源码和校验文件。
- `.github/workflows/build.yml`：每次更新 `main` 或提交 Pull Request 时测试和构建。
- `.github/workflows/release.yml`：推送版本标签时自动创建 Release 并上传安装文件。
- `.gitignore`：排除本机构建目录、历史 app 备份、环境文件、证书及私钥文件。

安装文件不放进 Git 提交；发布时附在 Release 下。这样源码仓库不会积累每个版本的二进制包。

## 首次上传

可以通过已安装并授权的 GitHub 连接完成；也可以使用 [GitHub CLI](https://cli.github.com/)。首次使用 CLI 需要登录 GitHub 账号，并且本机 Git 已配置提交者姓名及邮箱。

在项目目录执行（项目已经初始化 Git 时跳过第一行）：

```sh
git init -b main
git add README.md .gitignore .gitattributes .github Sources Resources Tests scripts docs 'app logo.png'
git commit -m "Prepare HotSpotAlive for macOS distribution"
gh auth login
gh repo create HotSpotAlive --public --source=. --remote=origin --push
```

`gh repo create` 适用于账号下尚无同名仓库的情况；如果已经创建，请将当前项目关联到该仓库后推送，不要重复创建。

当前项目没有自动添加开源许可证，许可证可由仓库所有者选择后补充。

## 发布第一个安装包

上传源码后，在项目目录执行：

```sh
git tag v1.0
git push origin v1.0
```

版本号必须与 `Resources/Info.plist` 的 `CFBundleShortVersionString` 一致。GitHub Actions 会先测试、构建双架构程序和 DMG、验证签名与磁盘映像，再创建草稿 Release、上传全部文件并发布。若创建草稿后中断，可以在 GitHub 的 Releases 页面检查并完成该草稿，不必重复创建同名 Release。

也可以手动运行 `./scripts/release.sh`，在 GitHub 的 Releases 中创建版本，并上传 `build/release/` 下的四个文件。详细操作见 [GitHub 官方发布说明](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。

## 后续版本

1. 修改代码，同时递增 `Resources/Info.plist` 中的 `CFBundleShortVersionString` 和 `CFBundleVersion`。
2. 更新 `docs/RELEASE_NOTES.md`，提交并推送源码。
3. 创建并推送新的 `v版本号` 标签，工作流会生成新的 Release。

安装包目前为临时签名、未公证版本。若以后有 Apple Developer ID 证书，可以再加入正式签名和公证流程；GitHub 托管本身不会代替 Apple 公证。

## 验证下载文件

将同一版本的四个文件下载到同一目录，运行（版本号按实际修改）：

```sh
shasum -a 256 -c HotSpotAlive-1.0-SHA256SUMS.txt
```

源码 ZIP 自带构建脚本和图标，可在新 Mac 安装 Apple Command Line Tools 后运行 `./scripts/test.sh` 和 `./scripts/release.sh`。工作流和本地发布脚本都不上传偏好设置、账号信息或本机 app 备份。
