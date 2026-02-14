import { getLogger } from './log/Logger';

const logger = getLogger('safeOperations');

export async function safeFileOperation<T>(operation: () => Promise<T>): Promise<T | null> {
  try {
    return await operation();
  } catch (error) {
    logger.error('File operation failed:', error);
    return null;
  }
}

export function safeJsonParse<T>(str: string): T | null {
  try {
    return JSON.parse(str);
  } catch {
    logger.warn('JSON parse failed (expected invalid content):');
    return null;
  }
}
