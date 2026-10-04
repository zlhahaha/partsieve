# Mooncakes 消费者验证

2026-10-04：在项目仓库外新建的 `E:/moonbit10/release-smoke` 执行，最初无 PartSieve 依赖，`moon add` 从注册表下载版本。没有本地源码覆盖或 workspace 替换。保留调用方三个源文件供复现；测试用 `fixture.xlsm` 是仓库 `tests/fixtures/upstream/macro01.xlsm` 的副本。

在仓库外新目录复制此处三个文件和上述 fixture（命名为 fixture.xlsm），运行：

```powershell
moon update
moon run . --target native
```

安装与运行均退出 0，输出 `Published SDK: audit/rebuild/verify Pass`。检查 XLSM、1 个 finding、重建 XLSX、保留 Pass 和准确输出 SHA-256；该消费者是作者自建验证，不作为独立下游采用证据。示例直接使用 x/fs，因此必须在调用方 moon.mod 显式声明 x 依赖，不能依赖 PartSieve 的传递依赖。
