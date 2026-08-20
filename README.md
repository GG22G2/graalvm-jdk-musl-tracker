# 自动跟踪 GraalVM 官方 muslib-ol10 镜像

本仓库自动跟踪官方 [graalvm/container](https://github.com/graalvm/container) 发布的
`ghcr.io/graalvm/native-image-community` 的 **`*-muslib-ol10-YYYYMMDD`** 系列镜像：

- 官方每发布一个新日期 tag → `check-upstream`（每天定时）自动触发 `build` 构建
- 构建产物：官方镜像 + Maven 3.9.16（阿里云源）+ git + pigz + 瘦身
- 推送位置：`ghcr.io/gg22g2/graalvm-jdk-musl-maven`，tag 与官方同款：
  - `25i2-25.0.4-muslib-ol10-20260728`（同官方日期 tag）
  - `25i2-25.0.4-muslib-ol10`（去日期短 tag）
  - `latest`

## 使用

```bash
docker pull ghcr.io/gg22g2/graalvm-jdk-musl-maven:latest
docker run --rm -v "$PWD":/workspace ghcr.io/gg22g2/graalvm-jdk-musl-maven:latest mvn -B package
```

## 工作原理

- `check-upstream.yml`：每天北京时间 02:37 拉取 ghcr.io 官方 tag 列表，与
  `built-tag.txt`（最近一次成功构建的官方 tag）对比，发现新的就触发 `build`。
- `build.yml`：用官方新 tag 作基础镜像构建，验证 5 个工具版本，推送 3 个 tag，
  成功后把新 tag 写回 `built-tag.txt`。
- 构建失败不会写 `built-tag.txt`，下一次 check 会自动重试。
