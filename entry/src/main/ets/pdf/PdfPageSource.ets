import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BBox } from './CropMath';
import { SampleGrid, downsampleGrid, regionForBBox } from './CropPipeline';
import { OutlineMarker } from '../core/DocModel';
import { PageImageSource } from '../core/Ports';
import { PARSE_SUCCESS, PARSE_THREW } from './OpenDiagnosis';

export interface PageSize {
  width: number;
  height: number;
}

export interface PageSample {
  gray: Uint8Array;
  grid: SampleGrid;
}

export class PdfPageSource implements PageImageSource {
  private doc: pdfService.PdfDocument | null = null;
  // 最近一次 open() 的 pdfService.ParseResult：失败成因判定（pdf/OpenDiagnosis）需要它。
  // 原先只把码写进日志、对外只回 boolean，于是「文件没了」和「格式不对」无法区分。
  private lastCode: number = PARSE_SUCCESS;

  open(path: string): boolean {
    const doc = new pdfService.PdfDocument();
    let result = -1;
    try {
      const r: pdfService.ParseResult = doc.loadDocument(path);
      result = Number(r);
    } catch (err) {
      hilog.error(0x0000, 'PdfPageSource', `loadDocument threw: ${err} path=${path}`);
      this.lastCode = PARSE_THREW;
      return false;
    }
    // PARSE_SUCCESS=0（SDK d.ts 字面量）；不用枚举常量比较，防运行时常量解析差异
    if (result !== 0) {
      hilog.error(0x0000, 'PdfPageSource', `loadDocument code=${result} path=${path}`);
      this.lastCode = result;
      return false;
    }
    this.lastCode = PARSE_SUCCESS;
    this.doc = doc;
    return true;
  }

  lastParseCode(): number {
    return this.lastCode;
  }

  close(): void {
    if (this.doc !== null) {
      this.doc.releaseDocument();
      this.doc = null;
    }
  }

  pageCount(): number {
    if (this.doc === null) {
      return 0;
    }
    return this.doc.getPageCount();
  }

  // 读出像素并生成独立白底不透明副本（RGBA/BGRA 的 alpha 都在第 4 字节）。
  // 不回写原 PixelMap：writeBufferToPixels 会损坏显示通道。
  private async opaqueCopy(pm: image.PixelMap): Promise<image.PixelMap> {
    const info = await pm.getImageInfo();
    const w = info.size.width;
    const h = info.size.height;
    // 源格式未知（0）时按 RGBA 处理：createPixelMap 拿到 srcPixelFormat=0 会产出黑图
    const srcFmt = (info.pixelFormat === image.PixelMapFormat.UNKNOWN)
      ? image.PixelMapFormat.RGBA_8888 : info.pixelFormat;
    const buf = new ArrayBuffer(w * h * 4);
    await pm.readPixelsToBuffer(buf);
    const b = new Uint8Array(buf);
    for (let p = 0; p < b.length; p += 4) {
      if (b[p + 3] !== 255) {
        if (b[p + 3] === 0) {
          b[p] = 255;
          b[p + 1] = 255;
          b[p + 2] = 255;
        }
        b[p + 3] = 255;
      }
    }
    const opts: image.InitializationOptions = {
      size: { width: w, height: h },
      srcPixelFormat: srcFmt,
      pixelFormat: image.PixelMapFormat.RGBA_8888
    };
    return image.createPixelMap(buf, opts);
  }

  private async opaqueCopyBase64(pm: image.PixelMap, quality: number): Promise<string> {
    const flat = await this.opaqueCopy(pm);
    const packer = image.createImagePacker();
    const data = await packer.packToData(flat, { format: 'image/jpeg', quality: quality });
    const helper = new util.Base64Helper();
    return helper.encodeToStringSync(new Uint8Array(data));
  }

  // T1：渲染整页并裁出手势区域（含外扩），打包 JPEG 转 base64 供视觉模型转录
  async regionJpegBase64(index: number, bbox: BBox | null, grid: SampleGrid,
    padRatio: number): Promise<string> {
    if (this.doc === null) {
      return '';
    }
    const pm = this.doc.getPage(index).getPagePixelMap();
    const info = await pm.getImageInfo();
    if (bbox !== null) {
      const r = regionForBBox(bbox, grid, info.size.width, info.size.height, padRatio);
      const size: image.Size = { width: r.width, height: r.height };
      const region: image.Region = { size: size, x: r.x, y: r.y };
      await pm.crop(region);
    }
    return this.opaqueCopyBase64(pm, 80);
  }

  // core/Ports.PageImageSource 的适配：OCR 只要整页图，不需要裁框。
  // 等价于 regionJpegBase64(index, null, 任意栅格, 任意 padRatio)——bbox 为 null 时后两者不被使用。
  async pageJpegBase64(index: number): Promise<string> {
    return this.regionJpegBase64(index, null, downsampleGrid(1, 1, 1), 0);
  }

  // 渲染整页（含簇裁剪）→ 独立像素副本（白底不透明）。
  // pdfService 的 getPagePixelMap 疑似共享原生缓冲：后渲染的页会顶掉先渲染的页，
  // 且文本页常为透明底。因此立即拷贝为独立 PixelMap 并压平，再交给 Image 显示。
  async pagePixelCopy(index: number, crop: BBox | null, grid: SampleGrid): Promise<image.PixelMap | null> {
    if (this.doc === null) {
      return null;
    }
    const pm = await this.cropPage(index, crop, grid);
    if (pm === null) {
      return null;
    }
    return this.opaqueCopy(pm);
  }

  // T0 文字层直提：原生书返回页面文字，扫描书返回空串（走 T1 圈选即 OCR）
  pageText(index: number): string {
    if (this.doc === null) {
      return '';
    }
    try {
      return this.doc.getPage(index).getTextContent();
    } catch (err) {
      return '';
    }
  }

  // 平铺 PDF 书签树为OutlineMarker列表（供 chaptersFromOutline 自动分章）
  outlineMarkers(): Array<OutlineMarker> {
    const markers: Array<OutlineMarker> = [];
    if (this.doc === null) {
      return markers;
    }
    this.walkBookmarks(this.doc.getRootBookmarks(), markers);
    return markers;
  }

  private walkBookmarks(bookmarks: Array<pdfService.Bookmark>, out: Array<OutlineMarker>): void {
    for (const bm of bookmarks) {
      const info = bm.getBookmarkInfo();
      const dest = bm.getDestInfo();
      const marker: OutlineMarker = { title: info.title, page: dest.pageIndex };
      out.push(marker);
      if (bm.hasChild()) {
        this.walkBookmarks(bm.getChildren(), out);
      }
    }
  }

  // 渲染整页并降采样为灰度栅格，供白边检测使用
  async sampleGray(index: number, maxSamples: number): Promise<PageSample | null> {
    if (this.doc === null) {
      return null;
    }
    const pm = this.doc.getPage(index).getPagePixelMap();
    const info = await pm.getImageInfo();
    const w = info.size.width;
    const h = info.size.height;
    if (w <= 0 || h <= 0) {
      return null;
    }
    const grid = downsampleGrid(w, h, maxSamples);
    const buf = new ArrayBuffer(w * h * 4);
    await pm.readPixelsToBuffer(buf);
    const bytes = new Uint8Array(buf);
    const gray = new Uint8Array(grid.cols * grid.rows);
    for (let gy = 0; gy < grid.rows; gy++) {
      const rowOffset = Math.min(gy * grid.stepY, h - 1) * w;
      for (let gx = 0; gx < grid.cols; gx++) {
        const px = Math.min(gx * grid.stepX, w - 1);
        gray[gy * grid.cols + gx] = bytes[(rowOffset + px) * 4];
      }
    }
    const sample: PageSample = { gray: gray, grid: grid };
    return sample;
  }

  // 渲染整页并按奇偶簇裁剪框（采样栅格坐标）裁掉白边
  async cropPage(index: number, crop: BBox | null, grid: SampleGrid): Promise<image.PixelMap | null> {
    if (this.doc === null) {
      return null;
    }
    const pm = this.doc.getPage(index).getPagePixelMap();
    if (crop !== null) {
      // 裁剪框×栅格步长可能因取整越界，钳制到像素边界内（crop 越界会抛 62980109）
      const info = await pm.getImageInfo();
      let x = crop.left * grid.stepX;
      let y = crop.top * grid.stepY;
      let w = (crop.right - crop.left + 1) * grid.stepX;
      let h = (crop.bottom - crop.top + 1) * grid.stepY;
      x = Math.max(0, Math.min(x, info.size.width - 1));
      y = Math.max(0, Math.min(y, info.size.height - 1));
      w = Math.max(1, Math.min(w, info.size.width - x));
      h = Math.max(1, Math.min(h, info.size.height - y));
      const size: image.Size = { width: w, height: h };
      const region: image.Region = { size: size, x: x, y: y };
      await pm.crop(region);
    }
    return pm;
  }
}
