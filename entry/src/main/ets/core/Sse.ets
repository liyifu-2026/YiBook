// SSE 流解析 + UTF-8 分块喂入（流式回答的纯逻辑前置）。
// 契约：extractSseEvents 只切完整事件，残尾原样交还调用方续接。

function decodeUtf8(bytes: Uint8Array, start: number, end: number): string {
  let out = '';
  let i = start;
  while (i < end) {
    const b = bytes[i];
    if (b < 0x80) {
      out += String.fromCharCode(b);
      i += 1;
    } else if (b >= 0xC0 && b < 0xE0 && i + 1 < end) {
      out += String.fromCharCode(((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
      i += 2;
    } else if (b >= 0xE0 && b < 0xF0 && i + 2 < end) {
      out += String.fromCharCode(((b & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F));
      i += 3;
    } else if (b >= 0xF0 && b < 0xF8 && i + 3 < end) {
      const cp = ((b & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) | ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
      const v = cp - 0x10000;
      out += String.fromCharCode(0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF));
      i += 4;
    } else {
      i += 1;
    }
  }
  return out;
}

export interface SseExtract {
  events: Array<string>;
  rest: string;
}

export function extractSseEvents(buffer: string): SseExtract {
  const normalized = buffer.replace(/\r\n/g, '\n');
  const boundary = normalized.lastIndexOf('\n\n');
  if (boundary < 0) {
    const none: SseExtract = { events: [], rest: normalized };
    return none;
  }
  const complete = normalized.substring(0, boundary + 2);
  const rest = normalized.substring(boundary + 2);
  const blocks = complete.split('\n\n');
  const events: Array<string> = [];
  for (const block of blocks) {
    const dataLines: Array<string> = [];
    for (const line of block.split('\n')) {
      if (line.startsWith('data:')) {
        dataLines.push(line.substring(line.startsWith('data: ') ? 6 : 5));
      }
      // ': ' 开头的注释行（心跳）忽略
    }
    if (dataLines.length > 0) {
      events.push(dataLines.join('\n'));
    }
  }
  const out: SseExtract = { events: events, rest: rest };
  return out;
}

// UTF-8 跨块安全解码：不完整的尾部字节扣留到下次 feed
export class Utf8Feeder {
  private tail: Uint8Array = new Uint8Array(0);

  feed(chunk: Uint8Array): string {
    const all = new Uint8Array(this.tail.length + chunk.length);
    all.set(this.tail, 0);
    all.set(chunk, this.tail.length);
    let usable = all.length;
    // 从尾部回溯，找出不完整的多字节序列
    let i = all.length - 1;
    while (i >= 0 && i >= all.length - 4) {
      const b = all[i];
      if (b < 0x80) {
        break;
      }
      if (b >= 0xC0) {
        let expected = 2;
        if (b >= 0xF0) {
          expected = 4;
        } else if (b >= 0xE0) {
          expected = 3;
        }
        const have = all.length - i;
        if (have < expected) {
          usable = i;
        }
        break;
      }
      i--;
    }
    const text = decodeUtf8(all, 0, usable);
    this.tail = all.slice(usable);
    return text;
  }

  flush(): string {
    const text = decodeUtf8(this.tail, 0, this.tail.length);
    this.tail = new Uint8Array(0);
    return text;
  }
}
