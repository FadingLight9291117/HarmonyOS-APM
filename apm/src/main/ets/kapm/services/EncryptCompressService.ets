import { Compression } from '../platform/Compression';
import { getFileSystem } from '../platform/FileSystem';
import { util } from '@kit.ArkTS';
import { Crypto } from '../platform/Crypto';
import { getLogger, safeFileOperation } from '../utils';

interface EncryptCompressOptions {
  keyHex: string;
  iv: string
}

export class EncryptCompressService {
  private readonly TAG = 'EncryptCompressService';
  private readonly log = getLogger(this.TAG);
  private fs = getFileSystem();
  private keyHex: string;
  private iv: string;
  static instance: EncryptCompressService | null;
  private context: Context;

  constructor(context: Context, options: EncryptCompressOptions) {
    this.context = context;
    const cfg = options;
    this.keyHex = cfg.keyHex;
    this.iv = cfg.iv;
  }

  createZipBuilder(): ZipBuilder {
    return new ZipBuilder(this.context, { keyHex: this.keyHex, iv: this.iv });
  }

  hasKeyMaterial(): boolean {
    return !!(this.keyHex && this.iv);
  }
}

class ZipBuilder {
  private TAG = 'ZipBuilder';
  private log = getLogger(this.TAG);
  private fs = getFileSystem();
  private keyHex: string;
  private iv: string;
  private cacheFiles: ZipItem[] = [];
  private inlineBuffers: Map<string, Uint8Array> = new Map();
  private context: Context;
  private tempDir: string;

  constructor(context: Context, opt: EncryptCompressOptions) {
    this.context = context;
    // this.tempDir = this.fs.join(this.context.getApplicationContext().tempDir, `apm_cache_${Date.now()}`)
    this.tempDir = this.fs.join("/data/storage/el2/base/temp", `apm_cache_${Date.now()}`)
    this.keyHex = opt.keyHex;
    this.iv = opt.iv;
  }

  addFile(filePath: string, filename?: string, isEncrypted = false): ZipBuilder {
    if (!filename) {
      filename = this.fs.basename(filePath);
    }
    this.cacheFiles.push({ filePath, filename, isEncrypted });
    return this;
  }

  addBuffer(buf: Uint8Array, filename: string, isEncrypted = false): ZipBuilder {
    this.inlineBuffers.set(filename, buf);
    this.cacheFiles.push({ filePath: `INLINE:${filename}`, filename, isEncrypted });
    return this;
  }

  addText(text: string, filename: string, isEncrypto = false): ZipBuilder {
    const encoder = new util.TextEncoder('utf-8');
    const buf = encoder.encodeInto(text);
    return this.addBuffer(buf, filename, isEncrypto);
  }

  private async writeIntoTempFile(filename: string, buf: Uint8Array): Promise<string> {
    await this.fs.ensureDir(this.tempDir)
    const finalPath = this.fs.join(this.tempDir, filename);
    await this.fs.writeFile(finalPath, buf.buffer);
    return finalPath
  }

  private async dealFile(item: ZipItem): Promise<ZipItem> {
    try {
      const buf = await this.fs.readFileAsBinary(item.filePath);
      let writeBuf = new Uint8Array(buf);
      if (item.isEncrypted) {
        writeBuf = await Crypto.encryptAes256CbcToBuffer(writeBuf, this.keyHex, this.iv);
      }
      const finalPath = await this.writeIntoTempFile(item.filename, writeBuf)
      return {
        filePath: finalPath,
        filename: item.filename,
        isEncrypted: item.isEncrypted
      }
    } catch (e) {
      this.log.error(`dealFile: error processing file ${item.filePath}: ${e}`);
      throw e as Error;
    }
  }

  private async dealBuffer(item: ZipItem): Promise<ZipItem> {
    try {
      if (!item.filePath.startsWith('INLINE:')) {
        this.log.error('dealBuffer: not an inline buffer');
        throw new Error('not an inline buffer');
      }
      // inline buffer
      let buf = this.inlineBuffers.get(item.filename);
      if (!buf) {
        this.log.error(`build: missing inline buffer for ${item.filename}`);
        throw new Error(`missing inline buffer for ${item.filename}`);
      }

      if (item.isEncrypted) {
        buf = await Crypto.encryptAes256CbcToBuffer(buf, this.keyHex, this.iv)
      }

      const finalPath = await this.writeIntoTempFile(item.filename, buf)
      this.inlineBuffers.delete(item.filename);
      return {
        filePath: finalPath,
        filename: item.filename,
        isEncrypted: item.isEncrypted
      }
    } catch (e) {
      this.log.error(`dealBuffer: error processing inline buffer ${item.filename}: ${e.stack}`);
      throw e as Error;
    }
  }

  /**
   * 1. 如果是buffer，判断是否加密，再写入文件，保存路径
   * 2. 如果是文件，先读取，判断是否加密，再写入临时文件后，保存路径
   * @returns 全部的路径
   */
  private async build(): Promise<ZipItem[]> {
    const preparedFiles: ZipItem[] = []
    for (const item of this.cacheFiles) {
      try {
        const newItem = (
          item.filePath.startsWith('INLINE:')
            ? await this.dealBuffer(item)
            : await this.dealFile(item)
        );
        preparedFiles.push(newItem);
      } catch (e) {
        this.log.error(`build: error preparing item ${item.filePath}: ${e}`);
        break;
      }
    }

    if (preparedFiles.length !== this.cacheFiles.length) {
      this.log.error('build: some files failed to prepare, aborting');
      // 清理已写入的临时文件
      for (const p of preparedFiles) {
        try {
          await this.fs.unlink(p.filePath);
        } catch (_e) {
        }
      }
      return [];
    }
    return preparedFiles
  }

  async buildToBuffer(): Promise<BuildToBufferResult | null> {
    const buildResult = await this.buildToFile();
    if (!buildResult) {
      this.log.error('buildToBuffer: failed to build zip file');
      return null;
    }
    const buf = await safeFileOperation(() => this.fs.readFileAsBinary(buildResult.zipPath))
    if (!buf) {
      this.log.error('buildToBuffer: failed to read zip file');
      return null;
    }
    const b = new Uint8Array(buf);
    const md5 = await Crypto.md5(b)
    return { buf: b, md5 }
  }

  // to temp file
  async buildToFile(outZipPath?: string): Promise<BuildToFileResult | null> {
    try {
      let zipPath: string
      if (outZipPath) {
        await this.fs.ensureDir(this.fs.parent(outZipPath || ''));
        zipPath = outZipPath
      } else {
        await this.fs.ensureDir(this.tempDir)
        zipPath = this.fs.join(this.tempDir, Date.now() + '.zip')
      }
      const preparedZipItems = await this.build();
      const preparedFilePaths = preparedZipItems.map(i => i.filePath);

      if (preparedFilePaths.length === 0) {
        this.log.error('buildToFile: no files to zip after preparation');
        return null;
      }
      const zipPathFinal = await Compression.packFilesToZip(preparedFilePaths, zipPath, false);
      if (!zipPathFinal) {
        this.log.error('buildToFile: failed to create zip file');
        return null;
      }

      const zipBuf = await safeFileOperation(() => this.fs.readFileAsBinary(zipPathFinal))
      if (!zipBuf) {
        this.log.error('buildToFile: failed to read zip file for md5 calculation');
        return null;
      }

      const md5 = await Crypto.md5(new Uint8Array(zipBuf))

      const stat = await safeFileOperation(() => this.fs.stat(zipPathFinal))

      return {
        zipPath: zipPathFinal,
        md5,
        filename: this.fs.basename(zipPathFinal),
        size: stat?.size ?? 0
      };
    } catch (e) {
      this.log.error(`buildToFile: error preparing zip file: ${e}`);
      return null;
    } finally {
      // delete temp files
      await this.fs.rmdir(this.tempDir)
    }
  }
}

interface ZipItem {
  filePath: string;
  filename: string;
  isEncrypted: boolean
}

export interface BuildToFileResult {
  zipPath: string;
  filename: string;
  md5: string;
  size: number;
}

interface BuildToBufferResult {
  buf: Uint8Array;
  md5: string;
}
