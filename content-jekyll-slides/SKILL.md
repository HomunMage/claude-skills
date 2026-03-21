---
name: content-jekyll-slides
description: Create Jekyll slide presentations. Use when building slides with h2 headings as separators.
---

# Jekyll Slides

Create slide presentations using Jekyll markdown format where `## h2` headings act as slide separators.

## Format

### Frontmatter

```yaml
---
title: "Topic - Subtitle"
layout: "page/note/slides"
---
```

### Slide Structure

- Each `## h2` heading creates a new slide and becomes the slide title
- Content under each `## h2` is the slide body
- Users navigate slides with left/right arrow keys

### Media Embedding

use `max-width:90%`

YouTube videos use iframe (never markdown links):
```html
<iframe style="max-width:90%; aspect-ratio:16/9;" src="https://www.youtube.com/embed/VIDEO_ID" title="Video Title" frameborder="0" ></iframe>
```

Images use HTML img tags (never markdown `![]()`):
```html
<img src="./image.webp" style="max-width:90%; height:auto;">
```

Default to `max-width:90%; height:auto` — fits container width and scales on zoom. Add `style="background-color: white;"` if image needs a white background.

**Image format: webp only.** Never use png/jpg in slides. If user provides a png/jpg, ask them to convert it first or run `_layouts/img2webp.sh` to batch-convert.

### Content Guidelines

- Keep each slide focused on one idea
- Use bullet points `*` or ordered lists `1.` for key points
- Embed YouTube iframes directly in slides for reference videos
- Link collections use markdown list format:
  ```markdown
  * [Link Text](https://url)
  ```
- First slide is typically a hook or introduction
- Last slide is typically homework or action items
- A references/resources slide collects source materials

## Example

```markdown
---
title: Topic - 01 Subtitle
layout: "page/note/slides"
---

## Opening Hook

Why is this topic important? A compelling question or statement to engage the audience.

## Self Introduction

Speaker Name

* relevant info
* background

## Core Concept

1. Key Point One
2. Key Point Two
3. Key Point Three

<iframe style="max-width:90%; aspect-ratio:16/9;" src="https://www.youtube.com/embed/VIDEO_ID" title="Reference Video" frameborder="0" ></iframe>

## Visual Example

<img src="./example.webp" style="max-width:90%; height:auto;">

## References

<iframe style="max-width:90%; aspect-ratio:16/9;" src="https://www.youtube.com/embed/VIDEO_ID" title="Source Video" frameborder="0" ></iframe>

* [Resource Name](https://url)
* [Another Resource](https://url)

## Homework

* Task for the audience
* (Optional) Additional exercise
```
