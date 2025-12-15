import { fileIo } from "@kit.CoreFileKit";
import { getLogger } from "../utils";

export interface FileSystem {
  ensureDir(dir: string): Promise<void>;
  writeFile(fullPath: string, data: string | ArrayBuffer): Promise<string>;
  readFile(fullPath: string, encoding?: string): Promise<string>;
  readFileAsBinary(fullPath: string): Promise<ArrayBuffer>;
  readdir(dir: string): Promise<string[]>;
  stat(fullPath: string): Promise<fileIo.Stat>;
  unlink(fullPath: string): Promise<void>;
  rmdir(fullPath: string): Promise<void>;
  isDirectory(fullPath: string): Promise<boolean>;
  join(...segments: string[]): string;
  parent(filePath: string): string;
  basename(filePath: string): string;
  exists(fullPath: string): Promise<boolean>;
  clearDir(fullPath: string): Promise<void>;
}

class OSFileSystem implements FileSystem {
  private TAG = 'OSFileSystem';
  private log = getLogger(this.TAG);
  private readonly root?: string;

  constructor(root?: string) {
    this.root = root;
  }

  async clearDir(fullPath: string): Promise<void> {
    const files = await this.readdir(fullPath);
    for (const file of files) {
      await this.unlink(this.join(fullPath, file));
    }
  }

  async isDirectory(fullPath: string): Promise<boolean> {
    const stat = await this.stat(fullPath);
    return stat.isDirectory();
  }

  rmdir(fullPath: string): Promise<void> {
    return fileIo.rmdir(fullPath);
  }

  private resolve(path: string): string {
    if (!this.root) return this.normalize(path);
    if (path.startsWith(this.root)) return this.normalize(path);
    return this.normalize(this.root + '/' + path);
  }

  private normalize(p: string): string {
    // 去重连续斜杠并移除末尾多余斜杠（根除外）
    let np = p.replace(/\\/g, '/').replace(/\/+/g, '/');
    if (np.length > 1 && np.endsWith('/')) np = np.slice(0, -1);
    return np;
  }

  join(...segments: string[]): string {
    const filtered: string[] = [];
    for (let i = 0; i < segments.length; i++) {
      const seg = segments[i];
      if (!seg) continue;
      filtered.push(seg.replace(/^[\\/]+|[\\/]+$/g, ''));
    }
    if (filtered.length === 0) return '';
    return this.normalize(filtered.join('/'));
  }

  async ensureDir(dir: string): Promise<void> {
    const target = this.resolve(dir);
    const parts = target.split('/');
    let acc = '';
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      if (!part) continue;
      acc = acc ? acc + '/' + part : part;
      try {
        // 尝试 stat 判断是否存在
        await this.tryStat(acc);
      } catch (_e) {
        try { await this.mkdir(acc); } catch (e2) { /* 可能并发创建，忽略 EEXIST */ }
      }
    }
  }

  private async mkdir(path: string): Promise<void> {
    await fileIo.mkdir(path);
  }

  private async tryStat(fullPath: string) {
    try {
      return await fileIo.stat(fullPath);
    } catch (e) {
      this.log.debug(`tryStat: stat ${fullPath} failed: ${e}`);
      throw e as Error;
    }
  }

  async writeFile(fullPath: string, data: string | ArrayBuffer): Promise<string> {
    const path = this.resolve(fullPath);
    const parent = path.split('/').slice(0, -1).join('/');
    if (parent) await this.ensureDir(parent);
    const file = await fileIo.open(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, data)
    } catch (e) {
      this.log.error(`writeFile: write to ${path} failed: ${e.stack}`);
      throw e as Error;
    } finally {
      try { await fileIo.close(file) } catch (_) {}
    }
    return path;
  }

  async readFile(fullPath: string, encoding = 'utf-8'): Promise<string> {
    return fileIo.readText(this.resolve(fullPath), { encoding });
  }

  async readdir(dir: string): Promise<string[]> {
    const path = this.resolve(dir);
    return await fileIo.listFile(path);
  }

  async stat(fullPath: string): Promise<fileIo.Stat> {
    const path = this.resolve(fullPath);
    return await this.tryStat(path);
  }

  async unlink(fullPath: string): Promise<void> {
    const path = this.resolve(fullPath);
    await fileIo.unlink(path);
  }

  async readFileAsBinary(fullPath: string): Promise<ArrayBuffer> {
    const path = this.resolve(fullPath);
    const f = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(f.fd);
      const buf = new ArrayBuffer(stat.size)
      await fileIo.read(f.fd, buf);
      return buf
    } finally {
      await fileIo.close(f);
    }
  }

  parent(filePath: string): string {
    const path = this.resolve(filePath);
    const parts = path.split('/');
    if (parts.length <= 1) return '/';
    return parts.slice(0, -1).join('/');
  }

  basename(filePath: string): string {
    const path = this.resolve(filePath);
    const parts = path.split('/');
    if (parts.length === 0) return '';
    return parts[parts.length - 1];
  }

  async exists(fullPath: string): Promise<boolean> {
    const path = this.resolve(fullPath);
    try {
      await fileIo.stat(path);
      return true;
    } catch (e) {
      return false;
    }
  }
}

let activeFS: FileSystem = new OSFileSystem();
export const getFileSystem = () => activeFS;
export const setFileSystem = (fsImpl: FileSystem) => { activeFS = fsImpl; };

export const fs = getFileSystem()