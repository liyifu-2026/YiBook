import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { CacheData, VectorCache } from '../core/Ports';

// 索引缓存：向量以二进制落盘（index_{key}.bin），哈希清单存 JSON。
// 命中则跨会话零 embedding 费用；哈希序列不匹配即整体重建（v1 策略）。
//
// 本类是 core/Ports 中 VectorCache 端口的设备侧实现，也是本域唯一使用 @kit 文件 IO 的地方。
// BookIndexer 只依赖端口接口，因此建书编排层可以脱离 @kit 在本地单测中跑
// （实测本地单测运行时无法执行 @kit 文件 IO，写文件会返回 false）。

export class IndexCache implements VectorCache {
  private dir: string;
  private key: string;

  constructor(dir: string, key: string) {
    this.dir = dir;
    this.key = key;
  }

  load(): CacheData | null {
    try {
      const metaPath = `${this.dir}/index_${this.key}.json`;
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
      const binPath = `${this.dir}/index_${this.key}.bin`;
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

  save(hashes: Array<string>, dims: number, data: Float32Array): void {
    try {
      if (!fs.accessSync(this.dir)) {
        fs.mkdirSync(this.dir, true);
      }
      const metaObj: Record<string, Object> = {
        'hashes': hashes,
        'dims': dims
      };
      const metaJson = JSON.stringify(metaObj);
      // 决策 #31：全写点原子化——.bin 同样 tmp+rename，防中途被杀留下半截缓存
      const binTmp = `${this.dir}/index_${this.key}.bin.tmp`;
      const binFd = fs.openSync(binTmp,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(binFd.fd, data.buffer as ArrayBuffer);
      fs.closeSync(binFd);
      fs.renameSync(binTmp, `${this.dir}/index_${this.key}.bin`);
      const metaTmp = `${this.dir}/index_${this.key}.json.tmp`;
      const metaFd = fs.openSync(metaTmp,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(metaFd.fd, metaJson);
      fs.closeSync(metaFd);
      fs.renameSync(metaTmp, `${this.dir}/index_${this.key}.json`);
    } catch (err) {
      // 缓存失败不致命：索引仍在内存可用
    }
  }
}
