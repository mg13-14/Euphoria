# 巨魔R / Relaxin 机制档案（T36 检索交付 · B 线）

> 触发：v24 清单 T36（用户点名参考物"巨魔R，Relaxin 越狱的那个"）
> 检索路径：web-search 8 轮 → web-reader 防爬受阻 → **agent-browser 破壁**（多米诺骨牌源
> roothide 分区 + trollstore.xin 文章页 428.html 全文抓取）——三方独立结论互证
> （B 情报包 §四 + C 20:58 判断 + 本档案），链路已闭环。

## 一、工具谱系（实证）

```
Relaxin 越狱（82Flex / OwnGoal Studio，roothide 架构）
  域：iOS 16.5.1 ~ 17.3.1（正式版）；GitHub 开源仓库；Relaxin Lite=网页版一键越狱
        │
        └──> 巨魔R【红巨魔】（作者 Fluoxetine，为 Relaxin 越狱特别制作）
              形态：Sileo 越狱商店 deb 插件（非独立 TrollStore fork！）
              域：iOS 17.0 ~ 17.3.1（与 Relaxin 域重合）
              设备：iPhone 11 ~ 15 Pro Max 全系
              依赖：AppSync Unified_116.0（免签安装的经典依赖）
              版本：巨魔R_1.0.3（35 天前发布，社区反馈源时有失效）
              分发：多米诺骨牌源（apt.wxhbts.com，roothide 分区）等中文源
```

**能力口径（原话级）**：越狱状态下支持免签安装 IPA、Tipa 应用，支持注入任意
dylib 和 deb 插件；**只能在越狱环境中使用**；"白巨魔无法使用，大家可以尝试
红巨魔"——即白巨魔（常规 TrollStore）与红巨魔（越狱态）是互补关系。

## 二、机制拆解（AE86 频道技术描述 + 源条目交叉验证）

1. **免签安装**：走 AppSync Unified 路线（越狱态篡改 installd/amfid 签名校验），
   **不是 CT 漏洞路线**——这是它能覆盖 17.0.1+（原版 NEVER 域）的唯一秘诀
2. **注入机制本质**：把 dylib 改成"插件形式"放入目标 app（AE86 原话）——
   即 deb 解包→dylib 抽取→植入目标 .app→加载表追加，与 TrollFools 的
   insert_dylib+ChOma in-place 方案同构（TrollFools 开源可学，巨魔R 闭源不可搬运）
3. **iOS 15.0~18.7.1 宽域标注的真相**：多米诺源页面的宽域是**整个 roothide 源**
   的域，巨魔R 本体=17.0~17.3.1（trollstore.xin 428.html 官方条目）——防以讹传讹

## 三、"底部小横板"UI 形态（如实口径）

- 公开渠道**无巨魔R 界面截图细节**（deb 应用+闭源，教程均以文字步骤为主）；
  用户口中的"底下的小横板"=巨魔R 应用内底部常驻横板区（安装/注入双入口形态），
  **以用户描述为交互基准**，我们自行设计落地
- 可参考形态：巨魔增强版（lin.mrlin.vip）「x 件管理」——插件池导入+装 IPA 时
  一并注入+deb 长按解压提取 dylib（bilibili 视频描述实证）——横板交互的活样本

## 四、对巨魔E 本体的直接输入（结论三连）

| 参考维度 | 巨魔R 的做法 | 巨魔E 的更强落位 |
|---|---|---|
| 形态 | Sileo deb（依赖越狱商店+AppSync） | **独立 .tipa 应用**（不依赖 sileo/越狱商店） |
| 域 | 17.0~17.3.1 越狱态 | **双域**：14.0~17.0 免越狱 CT 域 + 引擎A 越狱态 15.0~18.7.1（R35 契约） |
| 注入 | dylib/deb 越狱态植入 | TrollFools 同构（ChOma vendor 在位）集成进底部横板 |
| 许可证 | Fluoxetine 私有 deb，**代码不可搬运** | TrollFools 开源思路+自研实现；ChOma 沿用既有 LGPL 合规处理 |

**形态决策输入（供汇总员零节裁定）**：用户语义=原版界面骨架+仙境皮肤+底部横板
（巨魔R 式注入入口）。巨魔E 无需复刻巨魔R 的 deb 形态（那是受限于"只为 Relaxin
服务"的生态位），按我们三引擎架构直接超集覆盖即可——**底部横板=注入功能落位，
交互参考巨魔R 用户语义+增强版 x 件管理，引擎用 ChOma 同源自研**。

## 五、信息来源清单

1. trollstore.xin/428.html《巨魔 R【红巨魔】》（agent-browser 全文，权威条目）
2. 多米诺骨牌源 roothide 分区（apt.wxhbts.com / apt.cydiaa.com，agent-browser 破壁）
3. AE86 频道（telemetr.io 镜像）：Relaxin 注入插件形式技术描述
4. Relaxin GitHub（OwnGoalStudio）+ owngoal.dev 官网（web-reader）
5. Lessica/TrollFools GitHub（raw README，注入机制开源参照）
6. bilibili《巨魔"新版"来了》视频页（增强版 x 件管理形态，web-search 快照）

— 并行搜索员B，2026-09-07 21:15 交付（T36 闭环，T37 骨架已附情报包 §2）
