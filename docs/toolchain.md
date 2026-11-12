# Native 工具链复现

0.9.1 支持 Windows x86-64/MSVC 和 Linux x86-64 的 Native 构建。
两个 CI 作业使用 `moonc v0.10.20+65efd5b93` 与 `moon 0.1.20261104 (940aa18)`。
从 0.9.1 开始停止支持旧的 0.10.14 工具链。0.8.0-spike 的历史构建固定为 0.10.14。
安装后运行 `moon version --all` 核对版本，完整检查还会核对安装依赖的文件数和内容哈希。

Windows PowerShell 7，在 VS Developer PowerShell 中运行：

```powershell
$env:MOONBIT_INSTALL_VERSION = '0.10.20+65efd5b93'
$installer = Join-Path $env:TEMP 'install-moonbit.ps1'
Invoke-WebRequest https://cli.moonbitlang.com/install/powershell.ps1 -OutFile $installer
& $installer
$env:Path = "$env:USERPROFILE/.moon/bin;$env:Path"
./tools/check.ps1
```

Linux，在安装了 C 编译器和 PowerShell 7 的环境运行：

```sh
curl -fsSL https://cli.moonbitlang.com/install/unix.sh -o /tmp/install-moonbit.sh
MOONBIT_INSTALL_VERSION='0.10.20+65efd5b93' bash /tmp/install-moonbit.sh
export PATH="$HOME/.moon/bin:$PATH"
pwsh -File ./tools/check.ps1
```

## Issue #1

Windows 11 x64 上从公开仓库干净克隆复现，提交为
`705f2fe96618ee5296f67b56b73dd2ce4b67f472`。使用 `moon 0.1.20261104`、
`moonc v0.10.20+65efd5b93`、`rr_moon_mod,rr_moon_pkg`。
安装依赖为 `moonbit-community/flate@0.8.4`、`Milky2018/xml@0.5.0`、
`moonbitlang/x@0.5.5`，哈希见[依赖锁](dependency-lock.json)。

```sh
git clone https://github.com/zlhahaha/partsieve.git
cd partsieve
git checkout 705f2fe96618ee5296f67b56b73dd2ce4b67f472
moon version --all
moon check --target native --deny-warn
```

首条错误为 `authorization.mbt:30:16 [4015] Type String has no method to_json`。
同轮退出码为 1，共 60 个错误，包括其他字符串及 Map 的 JSON 方法解析错误，
以及严格检查下的 `[0027] deprecated_syntax`。新版 core 将该 trait 放在 JSON 包中，
对应调用改用明确的 JSON 构造或 trait 调用。工具链格式化器迁移为 `#derive`，
生成接口中的 `Int32` 和 `@json.Json` 是新版类型拼写。原有回执和计划保留工具标识，
使已有校验调用继续使用同一协议。新版工作流还移除了用于同步依赖的 `moon install`，
由 `moon check` 自动同步。

[原始兼容问题](https://github.com/zlhahaha/partsieve/issues/1)
