// 临时探针（用完删除）：挂载新的 PdfReaderView，用样张真机验证。
import { PdfReaderView } from '../view/PdfReaderView';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct PdfReaderProbe {
  @State path: string = '';

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    // 用扫描教材样张：24 页、有文字与图，最能看出清晰度与跨页
    this.path = `${ctx.filesDir}/books/sample_textbook.pdf`;
  }

  build() {
    Column() {
      if (this.path !== '') {
        PdfReaderView({
          pdfPath: this.path,
          bookTitle: '样张',
          initialPage: -1,
          debugCrossPage: true
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
