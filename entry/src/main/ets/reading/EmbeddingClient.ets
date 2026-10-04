import { http } from '@kit.NetworkKit';
import { batchTexts } from './IndexerMath';

// BYOK embeddings：OpenAI 兼容 /embeddings（Qwen text-embedding-v3、
// SiliconFlow bge-m3 等）。DeepSeek 无 embeddings 接口，留空即关闭向量路。

const EMBED_BATCH = 16;

export class EmbeddingClient {
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

  async embed(texts: Array<string>): Promise<Array<Array<number>>> {
    const out: Array<Array<number>> = [];
    if (!this.available()) {
      return out;
    }
    const batches = batchTexts(texts, EMBED_BATCH);
    for (const batch of batches) {
      const vecs = await this.embedBatch(batch);
      for (const v of vecs) {
        out.push(v);
      }
    }
    return out;
  }

  private async embedBatch(texts: Array<string>): Promise<Array<Array<number>>> {
    const req = http.createHttp();
    try {
      const bodyObj: Record<string, Object> = {
        'model': this.model,
        'input': texts
      };
      const url = this.baseUrl.replace(/\/$/, '') + '/embeddings';
      const resp = await req.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + this.apiKey
        },
        extraData: JSON.stringify(bodyObj),
        expectDataType: http.HttpDataType.STRING,
        readTimeout: 60000,
        connectTimeout: 15000
      });
      if (resp.responseCode !== 200) {
        return [];
      }
      const obj = JSON.parse(String(resp.result)) as Record<string, Object>;
      const data = obj['data'] as Array<Record<string, Object>>;
      const sorted = data.sort((a, b) => (a['index'] as number) - (b['index'] as number));
      const out: Array<Array<number>> = [];
      for (const item of sorted) {
        out.push(item['embedding'] as Array<number>);
      }
      return out;
    } catch (err) {
      return [];
    } finally {
      req.destroy();
    }
  }
}
