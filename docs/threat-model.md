# 威胁模型与原型边界

输入方可控制 ZIP、部件名、XML、关系、元数据和嵌入 bytes。PartSieve 不运行 VBA，不激活对象，不下载外部资源，不解析 DTD。支持范围内 VBA 为按 content type + 精确 relationship type 检出的 VBA 项目 payload；不判断其中代码是否恶意。

原型拒绝：超限、ZIP/CRC/XML 损坏、重复或 case-equivalent 名称、URI 编码歧义、missing target、duplicate local ID、源引用错误、未知部件类型/关系/命名空间/扩展、外部关系、公式、OLE、ActiveX、签名、非 XLSX/XLSM、孤儿/共享 VBA、VBA companion part。公式和 hyperlink 当前都不开放。重建仅输出 XLSX。

每个 XML 最大 8 MiB、深度 128、元素节点 200,000、属性 400,000；全包元素节点/属性各最多 1,000,000。单元素属性 256，markup（含注释/CDATA/PI）与 text token 65,536 code units。ZIP 默认 input 32 MiB、entry 32 MiB、全部解压 128 MiB、4096 entries；关系最多 32768；VBA 配置最多一个项目；output writer 64 MiB。支持配置还有严格 allowlist。这些值为 PROVISIONAL，尚未进行完整 1/10/30 MiB 内存校准。

SDK 接受宿主已取得的 bytes，并在 ZIP/parser 前检查限额。SDK 不承诺读取文件前的限额或硬时间截止；对外 Python CLI 负责有界文件读取和 60 秒 worker timeout。私有 worker 直接使用 x/fs，不能绕过脚本用于不可信文件摄入。

当前 XML 数值、样式、主题等没有完整 OOXML schema 校验，不能把包结构 Pass 描述为通用格式合法性或视觉保真。仅公开两个真实输入样本的独立 schema/client 证据。支持配置之外拒绝；生产发布前还需 TODO-2～TODO-13。

Receipt hash 绑定 bytes，不是签名/身份认证。URI、名称与错误经 JSON 转义；当前任何 external target 均在报告发布前拒绝，不回显含凭据地址。
