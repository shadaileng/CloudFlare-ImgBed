# CloudFlare-ImgBed 部署到 Hugging Face Docker Spaces

## 前置条件

- HF 账号 + Access Token（https://huggingface.co/settings/tokens，需要 write 权限）
- 项目代码：`MarSeventh/CloudFlare-ImgBed`

## 修改清单

### 1. `Dockerfile` — HF Space 适配

```dockerfile
FROM node:22-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl python3 make g++ && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm install --omit=dev && \
    apt-get purge -y --auto-remove python3 make g++ && \
    rm -rf /root/.npm /tmp/*

COPY . .

RUN mkdir -p /data && chown -R node:node /app /data

USER node

ENV PORT=7860
ENV DATA_DIR=/data
EXPOSE 7860

CMD ["node", "--import", "./deploy/server/register.mjs", "deploy/server/index.js"]
```

**关键点：**
- 用镜像自带的 `node` 用户（UID=1000），不要 `useradd`——`node:22-slim` 已有 `node` 用户
- `ENV PORT=7860` — HF Spaces 默认检测 7860
- `ENV DATA_DIR=/data` — 配合 HF Persistent Storage 挂载点
- `COPY package.json package-lock.json` — 不用通配符 `*`，避免 Docker glob 匹配失败

### 2. `deploy/server/index.js:75` — 数据目录可配置

```js
// 改前
const DATA_DIR = resolve(ROOT_DIR, 'data');

// 改后
const DATA_DIR = process.env.DATA_DIR || resolve(ROOT_DIR, 'data');
```

使应用优先读 `DATA_DIR` 环境变量，默认回退到项目 `data/` 目录。

### 3. `README.md` — HF Space 元数据

在文件最顶部添加 YAML front matter：

```yaml
---
title: Img Bed
emoji: 🌖
colorFrom: green
colorTo: yellow
sdk: docker
pinned: false
license: mit
short_description: img_bed
---
```

### 4. 仓库瘦身（可选，减小推送体积）

```bash
# 删除 readme 截图（44MB，不影响运行，.dockerignore 已排除）
git rm -r --cached readme/
echo "readme/" >> .gitignore

# 删除前端 source map（11MB，生产不需要）
rm frontend-dist/js/*.map frontend-dist/js/*.map.gz
```

## 部署步骤

### 创建 HF Space

在 HF 网站创建 Docker Space，或通过 API 创建。

### 推送代码

```bash
cd /path/to/CloudFlare-ImgBed

# 添加远程仓库
git remote add hf https://user:YOUR_TOKEN@huggingface.co/spaces/YOUR_USER/YOUR_SPACE

# 推送
GIT_PROTOCOL_FROM_USER=0 git -c http.proxy=socks5://127.0.0.1:1080 \
  push https://user:YOUR_TOKEN@huggingface.co/spaces/YOUR_USER/YOUR_SPACE main:main --force
```

**注意：** HF Spaces 拒绝二进制文件直接进 git。可以用 `huggingface-hub` Python 库绕开此限制：

```bash
pip install "huggingface-hub" "httpx[socks]"

# 设置代理
export HTTPS_PROXY=socks5://127.0.0.1:1080
export HTTP_PROXY=socks5://127.0.0.1:1080

# 上传目录（自动处理二进制文件）
python3 -c "
from huggingface_hub import HfApi
api = HfApi(token='YOUR_TOKEN')
api.upload_folder(
    folder_path='.',
    repo_id='YOUR_USER/YOUR_SPACE',
    repo_type='space',
    ignore_patterns=['.git/*', 'node_modules/*'],
    commit_message='deploy CloudFlare-ImgBed',
)
"
```

单文件更新可以用：

```python
api.upload_file(
    path_or_fileobj='Dockerfile',
    path_in_repo='Dockerfile',
    repo_id='YOUR_USER/YOUR_SPACE',
    repo_type='space',
)
```

### HF Space 设置

| 设置项 | 值 |
|--------|-----|
| Persistent Storage 挂载路径 | `/data` |
| Hardware | 免费计划可用 `cpu-basic` |

应用配置（Bot Token 等）首次打开管理面板后在线设置，数据自动写入 `/data/database.sqlite` 持久化。

## 常见问题

| 问题 | 原因 | 解决 |
|------|------|------|
| Space 卡在 `starting` | 端口不匹配 | `ENV PORT=7860`，HF 默认检测此端口 |
| 构建失败 `useradd: not found` | `node:22-slim` 已有 UID 1000 用户 | 用 `node` 用户，不创建新用户 |
| 构建失败 `COPY package-lock.json*` | Docker glob 不匹配 | 去掉通配符，写完整文件名 |
| 构建成功但 `BUILD_ERROR` | 容器启动失败 | 查看 `runtime.errorMessage` 定位 |
| 数据重启丢失 | 未挂载 Persistent Storage | Space Settings → 挂载 `/data` |
| 大文件无法访问 | Cloudflare Worker CPU 限制 | HF Space 无此限制，改用此部署 |
