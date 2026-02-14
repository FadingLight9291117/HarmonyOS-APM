import fs, { ListFileOptions } from '@ohos.file.fs';
import { getLogger } from '../../utils';

const logger = getLogger('FileUtil');

export class FileUtil {
  private static TAG = "FileUtil"

  /**
   * 获取指定目录下的文件
   *
   * @param dir 文件目录
   * @param suffix 文件类型
   * @returns
   */
  static getListFile(dir: string, suffix: string[] = [".log"]) {
    const paths: string[] = []
    try {
      if (!fs.statSync(dir).isDirectory()) {
        // 不是目录
        return paths
      }
      let listFileOption: ListFileOptions = {
        recursion: false,
        listNum: 0,
        filter: {
          suffix: suffix,
        }
      }

      const files = fs.listFileSync(dir, listFileOption)
      files.forEach((path) => {
        paths.push(`${dir}/${path}`)
      })
    } catch (err) {
      logger.error("accessSync failed with error message: " + err.message + ", error code: " + err.code)
    }
    return paths
  }
}