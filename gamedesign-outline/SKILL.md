---
name: gamedesign-outline
description: Generate outline.yml following Save the Cat beat sheet in 3 acts. Use for story structure and narrative design.
---

# Story Outline

Generate `outline.yml` files following Blake Snyder's "Save the Cat!" Beat Sheet in 3 acts.

## Prompt

We are following Blake Snyder's "Save the Cat!" Beat Sheet in 3 act.

## Workflow

### Step 1: Discuss Story Scope

Before creating the outline, confirm:

- **Genre and setting**
- **Core concept**: what makes this story compelling
- **Main characters**: who drives the story

### Step 2: Generate outline.yml

The output filename should reflect the story title, e.g. `Shadow Over Drakewood.yml`.

**Do not change the YAML key format** — it will be post-processed to HTML.

## YAML Format

```yaml
Title:
  ""

Version:
  ""

Author:
  ""

Highlight:
  ""

# Act I
The_Setup:
  ""

Opening_Image:
  ""

Theme_Stated:
  ""

Set-Up:
  ""

Catalyst:
  ""

Debate:
  ""

# Act II part 1
The_Confrontation:
  ""

Break_into_Two:
  ""

B_Story:
  ""

Fun_and_Games:
  ""

# Act II part 2
The_Deepening:
  ""

Midpoint:
  ""

Bad_Guys_Close_In:
  ""

All_Is_Lost:
  ""

Dark_Night_of_the_Soul:
  ""

# Act III
The_Resolution:
  ""

Break_into_Three:
  ""

Finale:
  ""

Final_Image:
  ""
```

### Field Descriptions

| Field | Act | Function |
|-------|-----|----------|
| **Title** | — | Story title |
| **Version** | — | Version number |
| **Author** | — | Author name |
| **Highlight** | — | Logline / elevator pitch |
| **The_Setup** | Act I summary | Overview of the opening world and situation |
| **Opening_Image** | Act I | 世界狀態、主角現況 |
| **Theme_Stated** | Act I | 故事主題被提出 |
| **Set-Up** | Act I | 角色、世界、問題介紹 |
| **Catalyst** | Act I | 改變命運的事件 |
| **Debate** | Act I | 主角猶豫是否行動 |
| **The_Confrontation** | Act II-1 summary | Overview of the confrontation phase |
| **Break_into_Two** | Act II-1 | 主角踏入新世界 |
| **B_Story** | Act II-1 | 副線角色 / 愛情 / 友情 |
| **Fun_and_Games** | Act II-1 | 核心概念展開 |
| **The_Deepening** | Act II-2 summary | Overview of the deepening stakes |
| **Midpoint** | Act II-2 | 偽勝利或偽失敗 |
| **Bad_Guys_Close_In** | Act II-2 | 困難升級 |
| **All_Is_Lost** | Act II-2 | 最低谷 |
| **Dark_Night_of_the_Soul** | Act II-2 | 主角反思 |
| **The_Resolution** | Act III summary | Overview of the resolution |
| **Break_into_Three** | Act III | 找到真正解法 |
| **Finale** | Act III | 最終對決與解決 |
| **Final_Image** | Act III | 與開頭對比，展現成長 |

### Key Rules

- Each act has a **summary field** (`The_Setup`, `The_Confrontation`, `The_Deepening`, `The_Resolution`) that overviews the entire act
- All values are **quoted strings** on the line after the key
- YAML comments (`# Act I`, `# Act II part 1`, etc.) mark act boundaries
- **Do not change the key names or format** — downstream converter expects this exact structure

## Example

```yaml
Title:
  "The Shadow Over Drakewood"

Version:
  "1.0"

Author:
  "Navi, the Narrative Storyteller"

Highlight:
  "A band of unlikely heroes discovers an ancient evil threatening to engulf the world in darkness. They must embark on a perilous journey to unite the fractured kingdoms and thwart the dark forces before it's too late."

# Act I
The_Setup:
  "A tranquil village on the outskirts of Drakewood, untouched by the outside world's chaos, suddenly faces a dark, creeping shadow, foreboding a change. The villagers, unaware of the dangers lurking, continue their daily lives. Among them, four distinct individuals, each bearing secrets and dreams, find their fates intertwined by a series of mysterious events leading them to a path of adventure."

Opening_Image:
  "A serene village on the edge of the Drakewood forest, life is peaceful until a sinister shadow creeps over the land."

Theme_Stated:
  "In a local tavern, an old bard whispers a tale: \"Only when the lost are found, can the looming darkness be bound.\" This hints at the theme of unity and finding one's purpose in the face of adversity."

Set-Up:
  "Introduce our heroes: A rogue with a mysterious past, a wizard seeking knowledge, a warrior with a noble heart, and a cleric guided by divine visions. They each have their reasons for journeying, but fate has intertwined their paths."

Catalyst:
  "The discovery of an ancient ruin deep in Drakewood, where they find a prophecy warning of a rising darkness, an army of the undead led by a forgotten deity seeking to return and conquer the world."

Debate:
  "The group debates their next steps. Should they seek out the fragmented artifacts mentioned in the prophecy that can seal away the deity once more, or is the task too daunting for them?"

# Act II part 1
The_Confrontation:
  "As the group embarks on their quest, they face challenges that test their resolve and push them to their limits. Encounters with dark creatures, treacherous landscapes, and the remnants of a long-forgotten battle lead them to the heart of Drakewood. Here, the true extent of the threat is revealed: an ancient evil, bound for centuries, is stirring, seeking to break its chains and plunge the world into darkness."

Break_into_Two:
  "Choosing to confront the threat, they embark on their quest, understanding the stakes and the need for unity against the darkness."

B_Story:
  "The B Story focuses on the personal growth of the characters and their relationships with one another, fostering trust and friendship."

Fun_and_Games:
  "Adventures in seeking the artifacts: deciphering ancient puzzles, battling mythical creatures, and navigating treacherous terrains. These trials showcase their strengths and weaknesses, both as individuals and as a team."

# Act II part 2
The_Deepening:
  "As they collect the artifacts, the reality of their mission sinks in. They encounter survivors and remnants of the deity's past wrath, deepening their resolve but also highlighting the cost of failure."

Midpoint:
  "The heroes successfully retrieve all the artifacts but at a great personal loss, revealing the depth of the villain's power and influence. The midpoint is a mix of victory and vulnerability."

Bad_Guys_Close_In:
  "The deity's forces attack, aiming to retrieve the artifacts. The heroes face betrayal from an unexpected quarter, and the unity within the group is tested."

All_Is_Lost:
  "The artifacts are stolen, and the cleric is captured, leaving the group fractured and hopeless. The shadow over Drakewood grows darker."

Dark_Night_of_the_Soul:
  "The heroes reflect on their failures, confronting their inner demons. It's their lowest point, filled with doubt and despair."

# Act III
The_Resolution:
  "United by their journey and strengthened by the trials they have overcome, the group confronts the ancient evil in a climactic battle. Drawing on their newfound friendship, skills, and the artifacts they've gathered, they seal the darkness away, restoring peace to Drakewood. As they leave the forest, the once sinister shadow over the land is lifted, leaving the village—and the world—bathed in a new light. Their journey has changed them, and though they part ways, the bonds formed during their adventure remain, a testament to their courage and unity."

Break_into_Three:
  "A renewed sense of purpose unites them. They realize the bard's tale not only referred to the physical journey but their personal growth and unity as the true key to defeating the darkness."

Finale:
  "A climactic battle where the heroes, now fully united and embracing their destinies, confront the deity. They manage to restore the artifacts, using their newfound strength and unity to seal the deity away once more."

Final_Image:
  "The shadow over Drakewood recedes, and peace is restored. Our heroes, changed by their journey, look out over the village, now in sunlight. The final image mirrors the opening but transformed by the journey's events, showing growth and hope."
```
