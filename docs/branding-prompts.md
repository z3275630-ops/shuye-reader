# 书叶 0.3.2 封面与图标处理记录

使用 Codex 内置 image_gen 的编辑模式，输入为用户选定的黑底、白绿叠页图片。去掉外部圆角框，保留叠页主体，分别适配方形图标与 2.6:1 横向封面。保存后仅缩放与格式压缩；Android 自适应图标通过 drawable inset 增加 14dp 安全边距，不拉伸主体。原图保存在本目录，应用只打入压缩资源。

## 最终图标编辑提示词

```text
Use case: precise-object-edit. Image 1 is the exact edit target supplied by the user, not merely inspiration. Prepare this existing black, white and mint-green folded-book-page app artwork as a production Android launcher image. Preserve the recognizable overlapping folded-page silhouette, exact white / translucent mint / charcoal arrangement, translucent material, highlight direction and dark aesthetic. Remove only the redundant outer black framing and the pre-rounded enclosing tile boundary; reframe the page motif cleanly on a continuous edge-to-edge near-black square background. The complete folded-page motif must fit inside the central 58 percent of both width and height, centered, so Android circular and rounded-square adaptive masks cannot clip it. No enclosing badge, no nested rounded rectangle, no borders, no additional objects, no book/ginkgo/mountains, no letters, no text, no watermark. Output one square full-bleed image, not a phone mockup. Keep the user's artwork identity and internal shape intact.
```

## 最终横向封面编辑提示词

```text
Use case: precise-object-edit. Image 1 is the user-supplied edit target for the reading app's cover. Produce a wide panoramic 2.6:1 adaptation of this same existing black, white and mint translucent folded-book-page artwork. Preserve the exact recognizable layered-page shape and its internal white, mint, charcoal material arrangement, curved leaflike paper edges and mint glow. Reframe it centrally, smaller enough that the whole motif is visible vertically with comfortable margin, on a continuous near-black horizontal background extending to both edges. Remove the pre-rounded enclosing square tile boundary and redundant outer frame. Use subtle restrained dark ambient mint light adjacent to the same motif, nothing else. No additional subjects, no open book, no ginkgo, no mountains, no typography, no watermark, no phone mockup. Do not stretch, crop, cut off, or duplicate the folded-page motif. One production panoramic reading-app cover artwork.
```
