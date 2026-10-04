import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { Utf8Feeder, extractSseEvents } from './Sse';
import { common } from '@kit.AbilityKit';

// BYOK：OpenAI 兼容接口（DeepSeek/Qwen/GLM 通用），chat 为一次性、chatStream 为 SSE 流式；
// key 存本地 preferences，云端只收到作答所需片段。
export interface ByokConfig {
  baseUrl: string;
  apiKey: string;
  model: string;
  // embedding 可选：留空则向量路关闭，检索退化为词法（BM25）单路
  embedBaseUrl: string;
  embedModel: string;
  // 视觉可选：扫描书圈选即 OCR（T1）；留空则扫描书无圈选转录
  visionBaseUrl: string;
  visionModel: string;
  // 统一知识库跨书引用开关（决策 #14：默认开 + 首次告知）
  crossBook: boolean;
  crossNoticeShown: boolean;
}

export const DEFAULT_BASE_URL = 'https://api.deepseek.com';
export const DEFAULT_MODEL = 'deepseek-chat';

const PREF_NAME = 'byok';
const KEY_BASE = 'baseUrl';
const KEY_API = 'apiKey';
const KEY_MODEL = 'model';
const KEY_EMBED_BASE = 'embedBaseUrl';
const KEY_EMBED_MODEL = 'embedModel';
const KEY_VISION_BASE = 'visionBaseUrl';
const KEY_VISION_MODEL = 'visionModel';
const KEY_CROSS_BOOK = 'crossBook';
const KEY_CROSS_NOTICE = 'crossNoticeShown';

export class ByokStore {
  async load(ctx: common.UIAbilityContext): Promise<ByokConfig> {
    const pref = await preferences.getPreferences(ctx, PREF_NAME);
    const cfg: ByokConfig = {
      baseUrl: (await pref.get(KEY_BASE, DEFAULT_BASE_URL)) as string,
      apiKey: (await pref.get(KEY_API, '')) as string,
      model: (await pref.get(KEY_MODEL, DEFAULT_MODEL)) as string,
      embedBaseUrl: (await pref.get(KEY_EMBED_BASE, '')) as string,
      embedModel: (await pref.get(KEY_EMBED_MODEL, '')) as string,
      visionBaseUrl: (await pref.get(KEY_VISION_BASE, '')) as string,
      visionModel: (await pref.get(KEY_VISION_MODEL, '')) as string,
      crossBook: (await pref.get(KEY_CROSS_BOOK, true)) as boolean,
      crossNoticeShown: (await pref.get(KEY_CROSS_NOTICE, false)) as boolean
    };
    return cfg;
  }

  async save(ctx: common.UIAbilityContext, cfg: ByokConfig): Promise<void> {
    const pref = await preferences.getPreferences(ctx, PREF_NAME);
    await pref.put(KEY_BASE, cfg.baseUrl);
    await pref.put(KEY_API, cfg.apiKey);
    await pref.put(KEY_MODEL, cfg.model);
    await pref.put(KEY_EMBED_BASE, cfg.embedBaseUrl);
    await pref.put(KEY_EMBED_MODEL, cfg.embedModel);
    await pref.put(KEY_VISION_BASE, cfg.visionBaseUrl);
    await pref.put(KEY_VISION_MODEL, cfg.visionModel);
    await pref.put(KEY_CROSS_BOOK, cfg.crossBook);
    await pref.put(KEY_CROSS_NOTICE, cfg.crossNoticeShown);
    await pref.flush();
  }
}

export interface ChatMessage {
  role: string;
  content: string;
}

// 单次流式调用的结果：failed 区分「回答为空」与「请求失败」——失败文本绝不能当回答入库
export interface LlmStreamResult {
  text: string;
  failed: boolean;
}

export class LlmClient {
  // 流式问答：dataReceive 事件 → UTF-8 分块解码 → SSE 解析 → 增量回调。
  // 返回完整文本与失败标志；onDelta 收到的是累积全文。
  async chatStream(cfg: ByokConfig, system: string, user: string,
    onDelta: (full: string) => void): Promise<LlmStreamResult> {
    const req = http.createHttp();
    return new Promise<LlmStreamResult>((resolve: (v: LlmStreamResult) => void) => {
      const finish = (result: string, failed: boolean): void => {
        if (settled) {
          return;
        }
        settled = true;
        try {
          req.off('dataReceive');
          req.off('dataEnd');
          req.destroy();
        } catch (err) {
          // 已销毁
        }
        const out: LlmStreamResult = { text: result, failed: failed };
        resolve(out);
      };
      const finishOk = (): void => {
        if (!settled) {
          finish(full, false);
        }
      };
      const feeder = new Utf8Feeder();
      let sseBuf = '';
      let full = '';
      let settled = false;
      req.on('dataReceive', (chunk: ArrayBuffer) => {
        sseBuf += feeder.feed(new Uint8Array(chunk));
        const ex = extractSseEvents(sseBuf);
        sseBuf = ex.rest;
        for (const ev of ex.events) {
          if (ev === '[DONE]') {
            finishOk();
            return;
          }
          try {
            const obj = JSON.parse(ev) as Record<string, Object>;
            const choices = obj['choices'] as Array<Record<string, Object>>;
            const delta = choices[0]['delta'] as Record<string, Object>;
            const piece = delta['content'];
            if (piece !== undefined && piece !== null) {
              full += String(piece);
              onDelta(full);
            }
          } catch (err) {
            // 忽略无法解析的事件（心跳等）
          }
        }
      });
      req.on('dataEnd', () => {
        finishOk();
      });
      const sysMsg: ChatMessage = { role: 'system', content: system };
      const usrMsg: ChatMessage = { role: 'user', content: user };
      const bodyObj: Record<string, Object> = {
        'model': cfg.model,
        'messages': [sysMsg, usrMsg],
        'temperature': 0.2,
        'stream': true
      };
      const url = cfg.baseUrl.replace(/\/$/, '') + '/chat/completions';
      // 流式必须走 requestInStream：dataReceive/dataEnd 事件只对流式请求触发，
      // 用 request() 会拿到整体缓冲且事件永不回调（P0 教训）
      req.requestInStream(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + cfg.apiKey
        },
        extraData: JSON.stringify(bodyObj),
        expectDataType: http.HttpDataType.STRING,
        readTimeout: 90000,
        connectTimeout: 15000
      }).then((code: number) => {
        if (code !== 200) {
          finish(`请求失败(${code})`, true);
        }
      }).catch((err: BusinessError) => {
        finish('网络错误：' + String(err), true);
      });
    });
  }
}
