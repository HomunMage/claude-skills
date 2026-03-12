---
name: gamedesign-character
description: Generate character.yml for game characters — base profile, BigFive personality, multi-stage arcs for main characters.
---

# Character Design

Generate `character.yml` files for game characters.

## Workflow

### Step 1: Determine Role Importance

Before creating any character, first ask and confirm:

- **Main Character (主角圈)**: Multiple stages (Stage1, Stage2, Stage3...) showing character growth arc
- **NPC**: Only Stage1 — no additional stages, to highlight the distinction between main and supporting characters

The number of stages depends on narrative importance. More stages = more character development = more screen time justified.

### Step 2: Generate character.yml

## YAML Structure

### Base Profile (All Characters)

```yaml
Name: ""
Race_Gender: ""
Age: ""
Body_Shape: ""
Profession: ""
Speaking_Style: ""
Catchphrase: ""
Personality: ""
Faith: ""
Regret: ""
Goal: ""
Another_Perspective: ""
Brief_History: ""

References:
  - ""

Concept: "<img src=\"./first.png\">"
Importance: ""  # 重要人物 / 次要人物 / NPC
```

### Stage Profile (per stage)

Each stage represents a phase of the character's life that shapes their personality.

```yaml
Stage1_History: ""
Stage1_Personality: ""
Stage1_BigFive:
  - "openness: %"
  - "efficient: %"
  - "extraversion: %"
  - "rational: %"
  - "nervous: %"
Stage1_Faith: ""
Stage1_Regret: ""
Stage1_Goal: ""
```

- **NPC**: Stage1 only
- **Main Character**: Stage1, Stage2, Stage3... as needed for their arc

### BigFive Traits

Each trait is a percentage representing the character's tendency:
- `openness` — curiosity, creativity
- `efficient` — organization, discipline
- `extraversion` — sociability, energy
- `rational` — logic vs emotion driven
- `nervous` — anxiety, stress level

## Example: Main Character (3 Stages)

```yaml
Name: "Claire"
Race_Gender: "不死族 可能是女孩"
Age: "不詳 可能上千歲"
Body_Shape: "身高140 體重30kg"
Profession: "死靈魔法師"
Speaking_Style: "腹黑毒舌"
Catchphrase: "我忘了、就這樣吧"
Personality: "對於任何事情不在乎"
Faith: "沒有特別堅持，想到什麼就做什麼"
Regret: "因為都忘了，所以也無所謂了"
Goal: "召喚大量魔物進攻大陸"
Another_Perspective: "黑色系歌德羅利 使用操偶術 手上的玩偶也能是武器"
Brief_History: "不知從哪出現的謎之人物，也沒有之前的記憶，不在乎任何人的請求，召喚魔物攻打大陸單純是覺得太無聊了找一些事情做"

References:
  - "發想 - 鍊金系列 - (親女兒)帕梅拉"
  - "講話風格：果青 - 雪之下雪乃"
  - "外觀：天結 -ロズリーヌ・フラン"

Concept: "<img src=\"./first.png\">"
Importance: "重要人物"

Stage1_History: "父母離異之後被精靈族收養，但被排擠"
Stage1_Personality: "想要討好大家"
Stage1_BigFive:
  - "openness: 20%"
  - "efficient: 20%"
  - "extraversion: 90%"
  - "rational: 20%"
  - "nervous: 20%"
Stage1_Faith: "未來會更好"
Stage1_Regret: "父母離異，想要找到父母"
Stage1_Goal: "想找到父母"

Stage2_History: "離開精靈村莊之後，意外被捲入戰場，被矮人收留並且必須參與掠奪"
Stage2_Personality: "警戒心態"
Stage2_BigFive:
  - "openness: 20%"
  - "efficient: 80%"
  - "extraversion: 30%"
  - "rational: 60%"
  - "nervous: 80%"
Stage2_Faith: "不希望明天到來"
Stage2_Regret: "我不想這麼做，卻必須執行掠奪"
Stage2_Goal: "逃離矮人族"

Stage3_History: "收到魔神復活消息"
Stage3_Personality: "積極拯救這個世界"
Stage3_BigFive:
  - "openness: 20%"
  - "efficient: 80%"
  - "extraversion: 90%"
  - "rational: 50%"
  - "nervous: 20%"
Stage3_Faith: "不同種族可以友好相處"
Stage3_Regret: "太多戰爭，不想再看到戰爭"
Stage3_Goal: "封印魔神"
```

## Example: NPC (Stage1 Only)

```yaml
Name: "老鐵匠 Garth"
Race_Gender: "矮人 男性"
Age: "200歲"
Body_Shape: "身高130 體重80kg"
Profession: "鐵匠"
Speaking_Style: "粗獷直接"
Catchphrase: "少廢話，拿去用"
Personality: "務實，不喜歡囉嗦"
Faith: "好的武器能救人一命"
Regret: "年輕時沒能打出傳說級武器"
Goal: "打造一把能留名的武器"
Another_Perspective: "看似粗魯但會偷偷幫助年輕冒險者"
Brief_History: "礦山出身的老鐵匠，在邊境小鎮開店數十年"

References:
  - ""

Concept: ""
Importance: "NPC"

Stage1_History: "從小在礦山長大，跟著父親學打鐵"
Stage1_Personality: "踏實肯幹"
Stage1_BigFive:
  - "openness: 30%"
  - "efficient: 90%"
  - "extraversion: 40%"
  - "rational: 70%"
  - "nervous: 10%"
Stage1_Faith: "手藝就是一切"
Stage1_Regret: "沒有走出去看看世界"
Stage1_Goal: "守好這間店"
```
