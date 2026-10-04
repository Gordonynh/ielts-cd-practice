# IELTS CD Practice

在 iPad 上模拟雅思机考（computer-delivered IELTS）的练习 App，SwiftUI 原生开发。

- **机考界面**：自己编写的考试引擎，版式对照官方机考：
  - 页眉、Part 横条、左右分栏与拖动柄、底部题号导航；
  - Review 标记、右键 Highlight / Notes / Clear；
  - Options 菜单里的对比度与字号；
  - 说明页与结束页。
- **其余界面**：遵循 Apple Human Interface Guidelines，支持深色模式，横屏、竖屏都能用。
- **数据只在本机**：练习记录、生词本、备考计划都存在 iPad 上，可以导出 / 恢复 JSON 备份。

## 一句话安装

把下面这句话复制给你的 AI（Claude Code、Codex 等能操作电脑的 AI 助手）：

```text
阅读 https://github.com/Gordonynh/ielts-cd-practice 的 README，按「安装」一节帮我把这个 App 安装到我的 iPad 上。
```

需要一台装了 Xcode 的 Mac 和一根能连接 iPad 的数据线。用免费 Apple ID 就能安装，不需要付费开发者账号。

## 功能

题库按「套题」组织：剑桥雅思 5–21 与红皮密卷（学术类），每套包含听力 Part 1–4、阅读 Passage 1–3、写作 Task 1–2。题库在[单独的仓库](https://github.com/Gordonynh/ielts-cd-practice-content)，安装脚本会自动下载。

| 侧边栏 | 内容 |
| --- | --- |
| 首页 | 一屏内的仪表盘：今日计划、学习概况、继续作答、按科目随机练习、近期机经、学习趋势 |
| 备考计划 | 自适应计划，见下方说明 |
| 剑桥真题 | 按书分组的整套试题，可以做完整模考，也可以单独练整套听力、阅读、写作或单个 Part；听力音频可按套下载离线使用 |
| 机经预测 | 听力、阅读、写作、口语的近期考题、重考次数、最近考到日期，以及考试回忆 |
| 专项练习 | 阅读按 Passage / 题型，听力按 Part / 题型，写作按 Task、图表类型和话题；错题与收藏 |
| 练习记录 | 按科目筛选；模考成绩（听力、阅读自动换算 Band，写作、口语自评后估算总分）、正确率趋势、热力图、题型正确率 |
| 生词本 | 机考中选词加入（附原文语境和 ECDICT 释义）、雅思核心词表、间隔重复复习 |
| 设置 | 练习计时、对比度与字号、备份导出 / 恢复 |

**备考计划怎么安排**
- **目标**：设总分目标和四科分项目标，例如总分 7.5 = 听力 8、阅读 8、写作 6.5、口语 6.5。
- **起点**：可以填以往的正式成绩；没有成绩时，第一天先做诊断模考。
- **模考**：之后定期模考，最后一次在考前两天，考前一天只做轻量复习。
- **每天的任务**：每天第一次打开时，按最新成绩安排：
  - 离目标差得多的科目多练；
  - 优先选含薄弱题型的题目；
  - 做到一半的练习接着做，昨天的错题先复盘；
  - 没做完的练习自动顺延；
  - 超出每天可用时间时，先去掉可选任务。
- **任务说明**：写作、口语的练法参考 2023 版官方评分标准，例如 Task 1 先写总览、Part 3 按观点 → 理由 → 例子展开。

| 机考 | 内容 |
| --- | --- |
| 完整模考 | 按听力 → 阅读 → 写作依次进行：<br>• 每部分前有说明页；<br>• 录音只播放一次、不能暂停，听完后有 2 分钟检查时间；<br>• 阅读、写作各 60 分钟，不能暂停；<br>• 中途退出可从当前部分继续 |
| 练习 | 单个 Part / Passage / Task 或整套；听力可暂停、回放、调速；计时可暂停；自动保存草稿 |
| 写作 | 左侧题目与图表，右侧作答，实时统计字数；提交后可对照参考范文 |
| 作答 | • 题型：填空、单选、多选（按集合判分）、表格匹配、下拉选择、拖拽题；<br>• 和官方一致：右键（触控板双指点按）或长按选中文字 → Highlight / Notes / Clear，左下角 Review 标记题目；<br>• 外接键盘：Tab / Shift+Tab 切换题目，方向键选选项；<br>• 只能输入英文，没有拼写检查、自动纠错和输入预测 |
| 复盘 | 逐题对错、正确答案、中文解析、段落翻译、听力原文随音频高亮 |
| 背题模式 | 直接显示答案与解析 |

## 安装

### 需要准备

- **Mac 与 Xcode**：macOS 上安装 Xcode 26 或更新版本（App Store 免费下载），装好后打开一次，完成组件安装。
- **Apple ID**：在 Xcode 的「设置 → 账户」中点左下角 + 登录 Apple ID。免费账号即可。
- **iPad**：iPadOS 17 或更新版本，用数据线连接 Mac，解锁后点「信任此电脑」。
- **开发者模式**：iPad 连接过装有 Xcode 的 Mac 后，「设置 → 隐私与安全性」里会出现「开发者模式」。打开后按提示重启，再确认一次。

### 一键安装

```bash
git clone https://github.com/Gordonynh/ielts-cd-practice.git
```

```bash
cd ielts-cd-practice && ./scripts/install-ipad.sh
```

脚本会依次完成六步，每一步失败都会说明原因和解决办法：
1. 检查 Xcode；
2. 下载题库（约 120 MB）；
3. 读取 Xcode 里登录的 Apple ID 对应的团队 ID；
4. 找到连接的 iPad；
5. 生成工程并编译；
6. 安装并打开 App。

第一次打开时，如果提示「不受信任的开发者」：在 iPad「设置 → 通用 → VPN 与设备管理」中选择你的 Apple ID，点「信任」。

可选参数：

| 参数 | 用途 |
| --- | --- |
| `--team <Team ID>` | 指定签名团队（有多个 Apple ID 时） |
| `--bundle-id <ID>` | 指定 Bundle ID，默认是 `com.ieltscdpractice.<团队 ID>`；提示 ID 被占用时换一个，例如 `com.yourname.ieltscdpractice` |
| `--device <设备 ID>` | 连接了多台 iPad 时指定其中一台（`xcrun devicectl list devices` 查看） |
| `--skip-content` | 不下载题库，使用你自己的题库（见下方「题库」） |

### 续期与更新

- **续期**：免费 Apple ID 签名的 App 有效期 7 天，到期后打不开。重新运行 `./scripts/install-ipad.sh` 即可，练习记录和生词本都会保留。
- **更新**：先运行 `git pull` 拉取新版本，再运行 `./scripts/install-ipad.sh`，题库也会一起更新。

### 给 AI 助手的说明

请按以下步骤操作，并把每一步的结果告诉用户：

1. **检查 Xcode**：确认这台 Mac 已安装 Xcode（`xcodebuild -version`）。没有的话请用户从 App Store 安装，不要尝试其他安装方式。
2. **运行脚本**：克隆仓库后，在仓库根目录运行 `./scripts/install-ipad.sh`。
3. **用户操作**：脚本提示的以下事项需要用户亲手完成，请把提示原样转告用户，等用户完成后重新运行脚本：
   - 在 Xcode 中登录 Apple ID；
   - 在 iPad 上点「信任此电脑」；
   - 打开开发者模式；
   - 信任开发者证书。
4. **不要代办账号密码**：不要替用户输入 Apple ID 密码，也不要修改系统安全设置。
5. **编译失败**：看脚本输出的错误：
   - 签名相关：确认用户已在 Xcode 登录 Apple ID；
   - Bundle ID 被占用：加 `--bundle-id com.<用户名>.ieltscdpractice` 重试。
6. **完成后提醒用户**：免费账号 7 天后需要重新运行脚本续期。

## 题库

- **题库仓库**：[ielts-cd-practice-content](https://github.com/Gordonynh/ielts-cd-practice-content)。安装脚本把它克隆到 `content/`，再复制到 `IELTSCDPractice/Content/bank/`。题库的版权与授权说明见该仓库。
- **用自己的题库**：
  1. 按 [docs/题库数据格式.md](docs/题库数据格式.md) 整理题目（示例：[docs/题库格式示例-sample-test1.json](docs/题库格式示例-sample-test1.json)），放进 `bank-source/`；
  2. 用 Node.js 18 或更新版本生成题库：

```bash
node scripts/build-bank.mjs && node scripts/build-extras.mjs
```

  3. 再运行 `./scripts/install-ipad.sh --skip-content`。

- **段落翻译（可选）**：可以用 Apple 翻译为没有译文的文章生成段落翻译。需要 macOS 26 或更新版本，并在系统设置中下载英语和简体中文翻译语言：

```bash
xcrun swiftc scripts/translate-bank.swift -o /tmp/translate-bank && /tmp/translate-bank bank-source
```

- **离线词典和雅思核心词表**：由 [ECDICT](https://github.com/skywind3000/ECDICT)（MIT）生成，已包含在本仓库中。重新生成：

```bash
node scripts/build-dictionary.mjs
```

## 开发

生成 Xcode 工程（新增或删除 Swift 文件后重新运行；签名设置保存在 `signing.local.json`，不提交）：

```bash
python3 scripts/generate-xcodeproj.py --team <你的团队 ID>
```

然后用 Xcode 打开 `IELTSCDPractice.xcodeproj`，在模拟器或 iPad 上运行。

> 项目放在 iCloud 同步的文件夹（如「桌面」「文稿」）中时，构建产物不要放在项目目录内，否则 iCloud 写入的扩展属性会导致签名失败。安装脚本已把 DerivedData 放在 `~/Library/Developer/Xcode/DerivedData/IELTSCDPractice`。

```text
IELTSCDPractice/
  App/            入口、侧边栏与页面路由
  Data/           题库模型与目录、SwiftData 模型、判分、统计、备考计划、词典、备份
  Exam/           机考界面的原生宿主（WKWebView、草稿、提交判分、模考流程）
  ExamEngine/     机考引擎（exam.html / exam.css / exam.js）
  Features/       首页、备考计划、剑桥真题、机经预测、专项练习、练习记录、生词本、设置
  Components/     设计规范与通用组件
  Content/        词典、词表；bank/ 为题库（不在本仓库）
scripts/
  install-ipad.sh          一键安装到 iPad
  generate-xcodeproj.py    生成 Xcode 工程
  build-bank.mjs           题库源文件 → Content/bank
  build-extras.mjs         机经、考试回忆、口语 → Content/bank/extras.json
  build-dictionary.mjs     ECDICT → 离线词典与核心词表
  translate-bank.swift     用 Apple 翻译补充段落译文
  export-content.sh        把生成的题库导出到题库仓库（维护者使用）
docs/                      题库数据格式与示例
```

## 判分规则

- **宽松匹配**：忽略大小写、首尾标点、多余空格、连字符与空格的差异、数字千分位。
- **可选写法**：答案中 `/` 分隔可选写法，括号内为可省略部分。
- **多选题**：「选出 N 个字母」按集合判分，与选择顺序无关。
- **换算 Band**：完整模考按 40 题评分表估算听力、阅读的 Band，总分按官方规则取整（平均分 .25 进到 .5，.75 进到整数）。

## 许可与声明

- **代码**：以 [GPL-3.0](LICENSE) 协议开源。
- **题库**：在单独的仓库发布，版权归原权利人所有，使用前请阅读该仓库的说明。
- **离线词典**：来自 [ECDICT](https://github.com/skywind3000/ECDICT)，MIT 协议。
- **商标**：IELTS 是其所有者的注册商标，本项目与 IELTS 官方（British Council、IDP、Cambridge University Press & Assessment）无关。
