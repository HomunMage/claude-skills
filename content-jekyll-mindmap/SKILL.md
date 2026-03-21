---
name: content-jekyll-mindmap
description: Create Jekyll mindmap visualizations using markmap layout. Use when building mind maps with nested bullet points.
---

# Jekyll Mindmap (Markmap)

Create mind map visualizations using Jekyll markdown format with markmap layout.

## Format

### Frontmatter

```yaml
---
title: "Topic - mindmap"
layout: page/note/markmap
---
```

### Structure

- `# h1` is the root node (central topic)
- Nested bullet points `*` create branches and sub-branches
- Indentation depth determines hierarchy level
- Each bullet point becomes a node in the mind map

### Media Embedding

YouTube videos use iframe inline within bullet points:
```html
* topic
  * <iframe width="450" height="255" src="https://www.youtube.com/embed/VIDEO_ID" title="Video Title" frameborder="0" ></iframe>
```

Images use HTML img tags inline within bullet points (never markdown `![]()`):
```html
* topic <img src="./image.webp" width="450">
* <img src="https://example.com/image.png" width="450" style="background-color: white;">
```

### Content Guidelines

- Keep node text concise — mind maps are for overview, not paragraphs
- Group related concepts under common parent nodes
- Use 2-4 top-level branches from the root
- Embed media (iframes, images) as leaf nodes or inline with text
- Deeper nesting (4-5 levels) is fine for detailed sub-topics
- Use inline `<img>` with `width` to control size

## Example

```markdown
---
title: Topic - mindmap
layout: page/note/markmap
---

# Main Topic

* Branch One
  * Sub-topic A
    * detail
    * <iframe width="450" height="255" src="https://www.youtube.com/embed/VIDEO_ID" title="Reference" frameborder="0" ></iframe>
  * Sub-topic B
    * point 1
    * point 2

* Branch Two
  * Concept X vs Concept Y
    * comparison detail
    * <img src="https://example.com/diagram.svg" height="300" style="background-color: white;">
  * Concept Z
    * <img src="./local-image.webp" width="450">

* Branch Three
  * Key idea
    * supporting point
    * supporting point
  * Another idea
    * detail with image <img src="./photo.webp" width="450">
```
