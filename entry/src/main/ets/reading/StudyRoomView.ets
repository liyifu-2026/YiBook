import { common } from '@kit.AbilityKit';
import { ReviewQueue, QuizCard } from './ReviewQueue';
import { QaRecord } from './Qa';
import { Palette, paletteOf } from './Theme';
import { readJsonFile, writeJsonFile } from './JsonFile';

// 书房管家（纯被动，决策 #3）：只住在书房，绝不进入阅读界面。
// 今日一页 = 到期测验卡（SM-2 排期），翻卡自评，材料全部来自你自己的圈选提问。

@Component
export struct StudyRoomView {
  onBack: () => void = () => {
  };
  onOpenBook: (path: string, title: string, page: number) => void =
    (_p: string, _t: string, _pg: number) => {
    };
  @State dueCards: Array<QuizCard> = [];
  @State revealed: boolean = false;
  @State total: number = 0;
  @State qaAll: Array<QaRecord> = [];
  @State catBreathe: boolean = false;
  @StorageLink('nightMode') nightMode: boolean = true;
  private queue: ReviewQueue = new ReviewQueue();

  aboutToAppear(): void {
    this.load();
    // 管家打盹呼吸（极低调的往复缩放）
    this.getUIContext().animateTo({
      duration: 2600,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, () => {
      this.catBreathe = true;
    });
  }

  private ctx(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private P(): Palette {
    return paletteOf(this.nightMode);
  }

  private load(): void {
    const reviewArr = readJsonFile<Array<QuizCard>>(this.ctx().filesDir + '/review.json');
    if (reviewArr !== null) {
      this.queue.load(reviewArr);
    }
    const qaArr = readJsonFile<Array<QaRecord>>(this.ctx().filesDir + '/qa.json');
    if (qaArr !== null) {
      this.qaAll = qaArr;
    }
    this.qaAll.sort((a, b) => {
      if (a.bookTitle !== b.bookTitle) {
        return a.bookTitle < b.bookTitle ? -1 : 1;
      }
      if (a.chapterTitle !== b.chapterTitle) {
        return a.chapterTitle < b.chapterTitle ? -1 : 1;
      }
      return a.pageIndex - b.pageIndex;
    });
    this.refresh();
  }

  private persist(): void {
    writeJsonFile(this.ctx().filesDir + '/review.json', JSON.stringify(this.queue.all()));
  }

  private refresh(): void {
    this.dueCards = this.queue.due(Date.now());
    this.total = this.queue.count();
    this.revealed = false;
  }

  private grade(quality: number): void {
    const cur = this.dueCards[0];
    if (cur === undefined) {
      return;
    }
    this.queue.grade(cur.id, quality, Date.now());
    this.persist();
    this.refresh();
  }

  build() {
    Column() {
      Row() {
        Button('← 书房')
          .fontSize(13)
          .height(28)
          .backgroundColor(this.P().panel)
          .fontColor(this.P().text)
          .onClick(() => {
            this.onBack();
          })
        Blank()
        Text('管家')
          .fontColor(this.P().text)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text(`共 ${this.total} 卡`)
          .fontColor(this.P().dim)
          .fontSize(12)
          .visibility(this.total > 0 ? Visibility.Visible : Visibility.None)
        Text(`问答 ${this.qaAll.length}`)
          .fontColor(this.P().dim)
          .fontSize(12)
          .margin({ left: 8 })
          .visibility(this.qaAll.length > 0 ? Visibility.Visible : Visibility.None)
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 12 })

      if (this.qaAll.length > 0) {
        Row() {
          Text('问答归档')
            .fontColor(this.P().dim)
            .fontSize(12)
          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }

      if (this.qaAll.length > 0) {
        List({ space: 6 }) {
          ForEach(this.qaAll, (rec: QaRecord) => {
            ListItem() {
              Column() {
                Text(`${rec.bookTitle} · ${rec.chapterTitle} · P${rec.pageIndex + 1}`)
                  .fontColor(this.P().accent)
                  .fontSize(11)
                Text(rec.question)
                  .fontColor('#DCE6F5')
                  .fontSize(12)
                  .maxLines(2)
                  .margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding(10)
              .borderRadius(8)
              .backgroundColor(this.P().panel)
              .onClick(() => {
                this.onOpenBook(rec.bookPath, rec.bookTitle, rec.pageIndex);
              })
            }
          }, (rec: QaRecord) => `qa_${rec.bookKey}_${rec.createdAt}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 4 })
      }

      if (this.dueCards.length === 0) {
        Column() {
          Image($r('app.media.cat'))
            .width(190)
            .height(190)
            .scale({
              x: this.catBreathe ? 1.04 : 0.97,
              y: this.catBreathe ? 1.04 : 0.97
            })
            .animation({
              duration: 2600,
              curve: Curve.EaseInOut,
              iterations: -1,
              playMode: PlayMode.Alternate
            })
          Text('今日一页已清空')
            .fontColor(this.P().text)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20 })
          Text('继续读书圈选提问，管家会把它们变成复习卡')
            .fontColor(this.P().dim)
            .fontSize(13)
            .margin({ top: 10 })
        }
        .width('100%')
        .layoutWeight(this.qaAll.length > 0 ? 0 : 1)
        .justifyContent(FlexAlign.Center)
      } else {
        Row() {
          Column() {
            Text(`待复习 ${this.dueCards.length}`)
              .fontColor(this.P().accent)
              .fontSize(12)
            Text(`${this.dueCards[0].bookTitle} · P${this.dueCards[0].page}`)
              .fontColor(this.P().dim)
              .fontSize(11)
              .margin({ top: 6 })
            Text(this.dueCards[0].question)
              .fontColor(this.P().text)
              .fontSize(16)
              .margin({ top: 14 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Image($r('app.media.cat'))
            .width(56)
            .height(56)
        }
        .width('100%')
        Column() {
          if (this.revealed) {
            Text(this.dueCards[0].answer)
              .fontColor(this.P().dim)
              .fontSize(13)
              .margin({ top: 12 })
            Row({ space: 8 }) {
              Button('忘了')
                .fontSize(12)
                .height(32)
                .backgroundColor(this.P().panel)
                .onClick(() => {
                  this.grade(1);
                })
              Button('想起')
                .fontSize(12)
                .height(32)
                .backgroundColor(this.P().panel)
                .onClick(() => {
                  this.grade(3);
                })
              Button('记得')
                .fontSize(12)
                .height(32)
                .backgroundColor(this.P().accent).opacity(0.7)
                .onClick(() => {
                  this.grade(4);
                })
              Button('秒答')
                .fontSize(12)
                .height(32)
                .backgroundColor(this.P().accent)
                .onClick(() => {
                  this.grade(5);
                })
            }
            .margin({ top: 16 })
          } else {
            Button('显示答案')
              .fontSize(13)
              .height(34)
              .margin({ top: 16 })
              .backgroundColor(this.P().panel)
              .onClick(() => {
                this.revealed = true;
              })
          }
        }
        .width('90%')
        .padding(16)
        .borderRadius(12)
        .backgroundColor(this.P().panel)
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 16 })
      }
      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.P().bg)
  }
}
