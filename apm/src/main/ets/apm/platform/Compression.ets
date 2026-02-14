import zlib from '@ohos.zlib';
import { getLogger } from '../utils';

export namespace Compression {
  const TAG: string = 'Compression';
  const log = getLogger(TAG)

  export interface ZipBufferItem {
    buf: Uint8Array;
    filename: string
  }

  export async function packFilesToZip(filePaths: string[], outPath: string,
    compress = false): Promise<string | null> {
    log.debug(`packFilesToZip: zipping ${filePaths.length} files to ${outPath}, compress=${compress}`);
    try {
      await zlib.compressFiles(filePaths, outPath, { level: compress ? 9 : 0 });
      return outPath;
    } catch (e) {
      log.error(`packFilesToZip: error preparing files: ${e}`);
      return null
    }
  }

  // Example function to demonstrate zipping a single file to a zip archive
  export async function packSingleFileToZip(filePath: string, outPath: string,
    compress = false): Promise<string | null> {
    log.debug(`packSingleFileToZip: zipping file ${filePath} to ${outPath}, compress=${compress}`);
    try {
      await zlib.compressFile(filePath, outPath, { level: compress ? 9 : 0 });
      return outPath
    } catch (e) {
      log.error(`packSingleFileToZip: error zipping file: ${e}`);
      return null
    }
  }
}
