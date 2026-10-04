import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

// 设备层 JSON 文件读写：统一「整读 + UTF-8 解码」与「tmp + rename 原子写」。
// 纯逻辑域禁止 import @ohos，本文件只被页面/壳层引用。

export function fileExists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (err) {
    return false;
  }
}

// 文件不存在/空文件/解析失败返回 null（首次启动/坏文件统一走缺省路径）
export function readJsonFile<T>(path: string): T | null {
  try {
    if (!fs.accessSync(path)) {
      return null;
    }
    const stat = fs.statSync(path);
    const buf = new ArrayBuffer(stat.size);
    const fd = fs.openSync(path, fs.OpenMode.READ_ONLY);
    fs.readSync(fd.fd, buf);
    fs.closeSync(fd);
    const decoder = util.TextDecoder.create('utf-8');
    const text = decoder.decodeToString(new Uint8Array(buf));
    // 空文件（历史版本可能写入 0 字节）按不存在处理：JSON.parse('') 会抛异常
    if (text.trim() === '') {
      return null;
    }
    return JSON.parse(text) as T;
  } catch (err) {
    return null;
  }
}

// 读取原始文本（不解析 JSON）：墨迹等自管序列化格式的文件用
export function readTextFile(path: string): string | null {
  try {
    if (!fs.accessSync(path)) {
      return null;
    }
    const stat = fs.statSync(path);
    const buf = new ArrayBuffer(stat.size);
    const fd = fs.openSync(path, fs.OpenMode.READ_ONLY);
    fs.readSync(fd.fd, buf);
    fs.closeSync(fd);
    const decoder = util.TextDecoder.create('utf-8');
    const text = decoder.decodeToString(new Uint8Array(buf));
    return text.trim() === '' ? null : text;
  } catch (err) {
    return null;
  }
}

// tmp + rename 原子写，失败返回 false（调用方按「不阻塞主流程」处理）
export function writeJsonFile(path: string, json: string): boolean {
  try {
    const tmp = path + '.tmp';
    const fd = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(fd.fd, json);
    fs.closeSync(fd);
    fs.renameSync(tmp, path);
    return true;
  } catch (err) {
    return false;
  }
}
