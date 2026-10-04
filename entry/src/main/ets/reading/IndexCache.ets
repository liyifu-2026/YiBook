import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

// 索引缓存：向量以二进制落盘（index_{key}.bin），哈希清单存 JSON。
// 命中则跨会话零 embedding 费用；哈希序列不匹配即整体重建（v1 策略）。

export interface CacheData {
  hashes: Array<string>;
  dims: number;
  data: Float32Array;
}

export class IndexCache {
  static load(dir: string, key: string): CacheData | null {
    try {
      const metaPath = `${dir}/index_${key}.json`;
      if (!fs.accessSync(metaPath)) {
        return null;
      }
      const metaStat = fs.statSync(metaPath);
      const metaBuf = new ArrayBuffer(metaStat.size);
      const metaFd = fs.openSync(metaPath, fs.OpenMode.READ_ONLY);
      fs.readSync(metaFd.fd, metaBuf);
      fs.closeSync(metaFd);
      const decoder = util.TextDecoder.create('utf-8');
      const meta = JSON.parse(decoder.decodeToString(new Uint8Array(metaBuf))) as Record<string, Object>;
      const hashes = meta['hashes'] as Array<string>;
      const dims = meta['dims'] as number;
      const binPath = `${dir}/index_${key}.bin`;
      const binStat = fs.statSync(binPath);
      const rawBuf = new ArrayBuffer(binStat.size);
      const binFd = fs.openSync(binPath, fs.OpenMode.READ_ONLY);
      fs.readSync(binFd.fd, rawBuf);
      fs.closeSync(binFd);
      const data = new Float32Array(rawBuf);
      const cd: CacheData = { hashes: hashes, dims: dims, data: data };
      return cd;
    } catch (err) {
      return null;
    }
  }

  static save(dir: string, key: string, hashes: Array<string>, dims: number, data: Float32Array): void {
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const metaObj: Record<string, Object> = {
        'hashes': hashes,
        'dims': dims
      };
      const metaJson = JSON.stringify(metaObj);
      // 决策 #31：全写点原子化——.bin 同样 tmp+rename，防中途被杀留下半截缓存
      const binTmp = `${dir}/index_${key}.bin.tmp`;
      const binFd = fs.openSync(binTmp,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(binFd.fd, data.buffer as ArrayBuffer);
      fs.closeSync(binFd);
      fs.renameSync(binTmp, `${dir}/index_${key}.bin`);
      const metaTmp = `${dir}/index_${key}.json.tmp`;
      const metaFd = fs.openSync(metaTmp,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(metaFd.fd, metaJson);
      fs.closeSync(metaFd);
      fs.renameSync(metaTmp, `${dir}/index_${key}.json`);
    } catch (err) {
      // 缓存失败不致命：索引仍在内存可用
    }
  }
}
