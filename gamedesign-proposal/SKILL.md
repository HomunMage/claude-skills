---
name: gamedesign-proposal
description: Generate one-page game proposal as proposal.yml — title, mechanics, selling points, concept art.
---

# Game Proposal

Generate one-page game proposal as `proposal.yml` files.

## Workflow

### Step 1: Discuss Game Concept

Before creating the proposal, confirm:

- **Game title and genre**
- **Core mechanic**: what makes this game unique
- **Target audience and platform**

### Step 2: Generate proposal.yml

The output filename should reflect the game title, e.g. `Siegel Battle.yml`.

**Do not change the YAML key format** — it will be post-processed to HTML.

## YAML Format

```yaml
Version: ""
Author: ""
Game_Title: ""
Game_Type: ""

Introduction: ""

Abstract: ""

System:
  - ""

TA_Platform:
  - ""

Selling_Points: ""

World: ""

Competitive:
  - ""

Concept_Art: ""
Game_Image1: ""
Game_Image2: ""

Play_Demo: ""
```

### Field Descriptions

| Field | Function |
|-------|----------|
| **Version** | Version number |
| **Author** | Author name |
| **Game_Title** | Game name |
| **Game_Type** | Genre and format (e.g. "2D 六角棋盤 SLG") |
| **Introduction** | Story hook / elevator pitch for the narrative |
| **Abstract** | One-line game description |
| **System** | Core game mechanics (list) |
| **TA_Platform** | Target audience and platforms (list) |
| **Selling_Points** | What makes the game stand out |
| **World** | World setting description |
| **Competitive** | Comparable/competitor games (list) |
| **Concept_Art** | Concept art image using `<img src="URL">` |
| **Game_Image1** | Game screenshot/mockup 1 using `<img src="URL">` |
| **Game_Image2** | Game screenshot/mockup 2 using `<img src="URL">` |
| **Play_Demo** | Gameplay flow description |

### Key Rules

- All string values are **quoted**
- List items use `- ""` format
- Images use raw HTML: `<img src="URL">` (not markdown `![]()`)
- **Do not change the key names or format** — downstream converter expects this exact structure

## Example

```yaml
Version: "1.0.1"
Author: "PosetMage"
Game_Title: "西格爾戰記"
Game_Type: "2D 六角棋盤 SLG"

Introduction: "一位被精靈扶養過之後被遺棄的人類少女,在幾經波折之後獲得魔神復活的消息，現在跟著矮人師傅一起修練，但似乎難以說服師傅一起對抗魔神......"

Abstract: "戰棋類遊戲,類似 DnD 版的魔喚精靈"

System:
  - "回合制戰棋"
  - "場地有狀態 Entropy"
  - "不同種族策略取捨"

TA_Platform:
  - "喜歡幻想世界的策略型玩家"
  - "PC, Console, Mobile"

Selling_Points: "遊戲的賣點在 Entropy 機制。 Entropy 區域內不同總族越多,行動懲罰越重"

World: "日系萌系 JRPG 風格的劍與魔法世界，有著戰士、法師、典型的精靈、矮人。世界最大的法則是 Entropy，影響著世界的運作，甚至平行世界之間也是由 Entropy 墻所阻隔。"

Competitive:
  - "魔喚精靈"
  - "皇家騎士團"
  - "天結"

Concept_Art: "<img src=https://shinra.posetmage.com/Grimoire/Siegel%20Battle/design/concept.webp>"
Game_Image1: "<img src=https://shinra.posetmage.com/Grimoire/Siegel%20Battle/design/first.webp>"
Game_Image2: "<img src=https://shinra.posetmage.com/Grimoire/Siegel%20Battle/design/second.webp>"

Play_Demo: "戰鬥前玩家需要配置隊伍成員中不同種族的比率。戰鬥開始後，雙方會派各自的兵力配置去戰鬥,在區域內有不同種族行動會觸發讓行動困難的 Entropy 值。"
```
