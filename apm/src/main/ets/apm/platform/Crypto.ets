import { cryptoFramework } from "@kit.CryptoArchitectureKit";
import { buffer, util } from "@kit.ArkTS";
import { getLogger } from "../utils";
import { getFileSystem } from "./FileSystem";

export namespace Crypto {
  const TAG: string = 'Compression';
  const log = getLogger(TAG);

  export async function encryptAes256CbcToBase64(data: Uint8Array, keyHex: string, iv: string): Promise<string> {
    const _data = await encryptAes256CbcToBuffer(data, keyHex, iv);
    // 转换加密结果为 Base64
    return bytesToHex(_data);
  }

  export async function encryptAes256CbcToBuffer(data: Uint8Array, keyHex: string, iv: string): Promise<Uint8Array> {
    try {
      // 1. 转换 HEX 格式的密钥和 IV 为二进制格式
      let symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
      const keyBlob: cryptoFramework.DataBlob = {
        data: hexToUint8Array(keyHex)
      };
      const symKey = await symKeyGenerator.convertKey(keyBlob)
      const ivParams: cryptoFramework.IvParamsSpec = {
        iv: { data: hexToUint8Array(iv) },
        algName: "IvParamsSpec"
      };

      // 2. 创建 AES-CBC-PKCS5 加密器
      const cipher = cryptoFramework.createCipher('AES256|CBC|PKCS5');
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, ivParams);

      // 3. 执行加密操作
      const inputData: cryptoFramework.DataBlob = { data: data };
      const encryptedData = await cipher.doFinal(inputData);
      return encryptedData.data;
    } catch (error) {
      log.error('AES-256-CBC encryption error:', error);
      throw error as Error;
    }
  }

  export async function md5(input: Uint8Array | string): Promise<string> {
    try {
      // 统一输入格式为 Uint8Array
      let data: Uint8Array;
      if (typeof input === 'string') {
        // 使用 TextEncoder 处理中文字符编码
        const encoder = new util.TextEncoder();
        data = encoder.encodeInto(input);
      } else {
        data = input;
      }

      // 创建 MD5 摘要实例
      const md = cryptoFramework.createMd('MD5');
      await md.update({ data: data });

      // 计算摘要值并转换为 HEX 字符串
      const digest = await md.digest();
      return bytesToHex(digest.data);
    } catch (error) {
      log.error('MD5 computation error:', error);
      return '';
    }
  }

  export async function md5FromFile(_filePath: string): Promise<string> {
    try {
      const fs = getFileSystem();
      const fileContent: ArrayBuffer = await fs.readFileAsBinary(_filePath);
      const data = new Uint8Array(fileContent);
      return await md5(data);
    } catch (error) {
      log.error('MD5 from file computation error:', error);
      return '';
    }
  }

  // 字节数组转 HEX 字符串工具函数
  function bytesToHex(bytes: Uint8Array): string {
    return Array.from(bytes)
      .map(byte => byte.toString(16).padStart(2, '0'))
      .join('');
  }

  // HEX 字符串转 Uint8Array 工具函数
  function hexToUint8Array(hex: string): Uint8Array {
    const buf = buffer.from(hex)
    return new Uint8Array(buf.buffer);
  }

  export function uint8ArrayToString(data: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decode(data);
  }
}
