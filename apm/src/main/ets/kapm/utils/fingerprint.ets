import { Crypto } from '../platform/Crypto';

export interface BuildJsErrorFingerprintArgs {
  name: string;
  reason: string;
  stack: string;
}

function normalizeStack(stack: string): string {
  if (!stack) return '';
  // 归一化：trim + 去掉空行 + 限制行数，避免超长导致性能问题
  const lines = stack
    .split('\n')
    .map(l => l.trim())
    .filter(l => l.length > 0);
  const top = lines.slice(0, 20);
  return top.join('\n');
}

/**
 * 生成“同类 JS Error 相同”的稳定指纹：
 * - 输入相同 -> 指纹相同
 * - 输入变化（message/stack）-> 指纹变化
 */
export async function buildJsErrorFingerprint(args: BuildJsErrorFingerprintArgs): Promise<string> {
  const payload =
    `type=JsError\n` +
    `name=${args.name || ''}\n` +
    `reason=${args.reason || ''}\n` +
    `stack=${normalizeStack(args.stack || '')}\n`;

  const md5 = await Crypto.md5(payload);
  return md5 || '';
}


