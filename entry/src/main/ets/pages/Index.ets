import { LibraryView } from '../view/LibraryView';
import { StudyRoomView } from '../view/StudyRoomView';
import { ReaderView } from '../view/ReaderView';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct Index {
  @State openedPath: string = '';
  @State openedTitle: string = '';
  @State openedPage: number = -1;
  @State showStudy: boolean = false;
  @StorageLink('nightMode') nightMode: boolean = true;

  // 系统侧滑/返回键：阅读→书房，管家→书房，书房→退出；与产品铁律「阅读视图常驻」一致
  onBackPress(): boolean {
    if (this.openedPath !== '') {
      this.openedPath = '';
      return true;
    }
    if (this.showStudy) {
      this.showStudy = false;
      return true;
    }
    return false;
  }

  aboutToAppear(): void {
    // 首帧前载入主题（缺省夜间）——两个视图同读 AppStorage
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const p = `${ctx.filesDir}/theme.json`;
      if (fs.accessSync(p)) {
        const stat = fs.statSync(p);
        const buf = new ArrayBuffer(stat.size);
        const fd = fs.openSync(p, fs.OpenMode.READ_ONLY);
        fs.readSync(fd.fd, buf);
        fs.closeSync(fd);
        const obj = JSON.parse(util.TextDecoder.create('utf-8')
          .decodeToString(new Uint8Array(buf))) as Record<string, Object>;
        this.nightMode = obj['night'] as boolean;
        AppStorage.setOrCreate('nightMode', this.nightMode);
      }
    } catch (err) {
      // 缺省夜间
    }
  }

  private bg(): string {
    return this.nightMode ? '#101E33' : '#F3EEE2';
  }

  build() {
    Stack() {
      if (this.showStudy) {
        StudyRoomView({
          onBack: (): void => {
            this.showStudy = false;
          },
          onOpenBook: (p: string, t: string, pg: number): void => {
            this.openedPage = pg;
            this.openedPath = p;
            this.openedTitle = t;
            this.showStudy = false;
          }
        })
      } else if (this.openedPath === '') {
        LibraryView({
          onOpen: (p: string, t: string, pg: number): void => {
            this.openedPage = pg;
            this.openedPath = p;
            this.openedTitle = t;
          },
          onOpenStudy: (): void => {
            this.showStudy = true;
          }
        })
      } else {
        Column() {
          Row() {
            Button('← 书房')
              .fontSize(13)
              .height(28)
              .backgroundColor(this.nightMode ? '#182A47' : '#FFFFFF')
              .fontColor(this.nightMode ? '#F7F0E4' : '#101E33')
              .onClick(() => {
                this.openedPath = '';
              })
            Blank()
          }
          .width('100%')
          .height(36)
          .padding({ left: 12 })

          ReaderView({
            pdfPath: this.openedPath,
            bookTitle: this.openedTitle,
            initialPage: this.openedPage
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.bg())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bg())
  }
}
