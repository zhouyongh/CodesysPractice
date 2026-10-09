# AGENTS.md

CODESYS 系列教程仓库。每课 = 一篇文章 + 配套代码，成果提交到 GitHub。

## 通用技能库

跨仓库技能统一在 `D:\yohan\skills\`（目录见其 `INDEX.md`）。执行通用任务（配图、发布、写规范/规格/方案文档等）时，先查技能库有无对应技能：有则读其 `SKILL.md` 并遵循，技能库是这些规范的唯一事实源；没有才用本仓库自带做法。仓库特有的事实（文章放哪、本仓库主题）仍以本文件为准。

本仓库用到的技能：配图 `draw-image`、发布 `publish-blog`；本仓库不实现发布与配图工具。

## 结构

- `Lessons/LessonN/` — 一课一个目录
  - `Concept.md` — 概念主线稿（每环三段式：核心一句 → 最少展开 → 引出下一问）
  - `Content.md` — 正文
  - `images/` — 配图，文中用相对路径 `![描述](images/xxx.png)` 引用
  - `codesys/` `st/` `csharp/` — `.project` 工程、按 POU 导出的 `.st` 纯文本、上位机源码

## 流程

1. 写作：`Concept.md` 锁主线，定稿后扩写为 `Content.md`；需要示意图处插 `【生图】` 占位（格式见技能库 `draw-image`）
2. 生图：示意图经技能库 `draw-image` 生成（`--out` 到本课 `images/`），替换占位
3. 发布 GitHub：整课一次提交（`Add Lesson N: ...`）并 push，先于博客发布
4. 发布博客：按技能库 `publish-blog` 执行

## 约束

- 本仓库是文章的唯一事实源；发布副本的更新一律从本仓库发起
- `out/` 被 git 忽略，纳入版本管理的图一律放 `Lessons/LessonN/images/`
- 草稿归位于对应 `Lessons/LessonN/` 目录，不留仓库根目录
