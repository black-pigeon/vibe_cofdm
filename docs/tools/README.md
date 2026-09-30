# 架构文档生成

`../整体链路架构.md` 是内容源；`../assets/architecture_*.dot` 是三幅图的源文件。PNG用于Word及Markdown，SVG便于进一步编辑。

在工程根目录运行：

```bash
python3 matlab/docs/tools/build_architecture_doc.py
```

依赖：Python3/Pillow、Graphviz、.NET8、DocumentFormat.OpenXml 3.5.1。优先使用PATH中的dotnet，否则查找用户目录 `.dotnet/dotnet`。脚本通过OpenXML SDK创建Word，不改动PHY算法；构建完成自动运行完整OpenXML验证，验证失败则报错退出。

排版参照docx-toolkit的ModernCorporate方案：A4、1英寸页边距、11pt正文、20/16/13pt标题、1.15倍行距；中西文字体分别设置。表格重复表头、图保持宽高比、页脚包含页码。模块和参数更新时请同步维护内容源和图，再重新生成Word。
