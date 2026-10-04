import { http } from '@kit.NetworkKit';
import { PageVision } from '../core/Ports';

// T1 圈选即 OCR：视觉 LLM（OpenAI 兼容多模态 /chat/completions，
// Qwen-VL / GLM-4V / SiliconFlow VL 系列）。构造器为纯函数可测。

export interface ChatPart {
  type: string;
  text: string;
  imageUrl: string;
}

export interface VisionMessage {
  role: string;
  content: Array<ChatPart>;
}

const OCR_SYSTEM = '你是OCR引擎。逐字转录图片中的所有文字，保持原有段落与顺序，' +
  '不要添加解释、翻译或Markdown符号。';

export function buildVisionMessages(system: string, userText: string, imageBase64: string,
  mime: string): Array<VisionMessage> {
  const sysPart: ChatPart = { type: 'text', text: system, imageUrl: '' };
  const sysMsg: VisionMessage = { role: 'system', content: [sysPart] };
  const tPart: ChatPart = { type: 'text', text: userText, imageUrl: '' };
  const iPart: ChatPart = {
    type: 'image_url',
    text: '',
    imageUrl: `data:${mime};base64,${imageBase64}`
  };
  const userMsg: VisionMessage = { role: 'user', content: [tPart, iPart] };
  const msgs: Array<VisionMessage> = [sysMsg, userMsg];
  return msgs;
}

export class VisionClient implements PageVision {
  private baseUrl: string;
  private apiKey: string;
  private model: string;

  constructor(baseUrl: string, apiKey: string, model: string) {
    this.baseUrl = baseUrl;
    this.apiKey = apiKey;
    this.model = model;
  }

  available(): boolean {
    return this.baseUrl !== '' && this.model !== '' && this.apiKey !== '';
  }

  async extractText(imageBase64: string, mime: string): Promise<string> {
    const messages = buildVisionMessages(OCR_SYSTEM, '转录这段内容。', imageBase64, mime);
    return this.chat(messages);
  }

  async chat(messages: Array<VisionMessage>): Promise<string> {
    const req = http.createHttp();
    try {
      const outMsgs: Array<Record<string, Object>> = [];
      for (const m of messages) {
        if (m.role === 'system') {
          const o: Record<string, Object> = { 'role': 'system', 'content': m.content[0].text };
          outMsgs.push(o);
        } else {
          const parts: Array<Object> = [];
          for (const p of m.content) {
            if (p.type === 'image_url') {
              const u: Record<string, string> = { 'url': p.imageUrl };
              const ip: Record<string, Object> = { 'type': 'image_url', 'image_url': u };
              parts.push(ip);
            } else {
              const tp: Record<string, string> = { 'type': 'text', 'text': p.text };
              parts.push(tp);
            }
          }
          const o2: Record<string, Object> = { 'role': m.role, 'content': parts };
          outMsgs.push(o2);
        }
      }
      const bodyObj: Record<string, Object> = {
        'model': this.model,
        'messages': outMsgs,
        'temperature': 0.1,
        'stream': false
      };
      const url = this.baseUrl.replace(/\/$/, '') + '/chat/completions';
      const resp = await req.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + this.apiKey
        },
        extraData: JSON.stringify(bodyObj),
        expectDataType: http.HttpDataType.STRING,
        readTimeout: 90000,
        connectTimeout: 15000
      });
      if (resp.responseCode !== 200) {
        return '';
      }
      const obj = JSON.parse(String(resp.result)) as Record<string, Object>;
      const choices = obj['choices'] as Array<Record<string, Object>>;
      const message = choices[0]['message'] as Record<string, Object>;
      return String(message['content']);
    } catch (err) {
      return '';
    } finally {
      req.destroy();
    }
  }
}
