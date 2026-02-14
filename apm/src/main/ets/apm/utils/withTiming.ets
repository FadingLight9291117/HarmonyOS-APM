import { humanizeDuration } from './humanize/humanizeDuration';
import { getLogger } from './log/Logger';

export async function withTiming<T>(name: string, fn: () => Promise<T>): Promise<T> {
  const logger = getLogger('withTiming');
  const start = Date.now();
  try {
    const res = await fn();
    const end = Date.now();
    logger.info(`Phase ${name} completed in ${humanizeDuration(end - start)}`);
    return res;
  } catch (error) {
    const end = Date.now();
    logger.error(`Phase ${name} failed after ${humanizeDuration(end - start)}:`, error.message);
    throw error as Error;
  }
}

export function withTimingSync<T>(name: string, fn: () => T): T {
  const logger = getLogger('withTiming');
  const start = Date.now();
  try {
    const res = fn();
    const end = Date.now();
    logger.info(`Phase ${name} completed in ${humanizeDuration(end - start)}`);
    return res;
  } catch (error) {
    const end = Date.now();
    logger.error(`Phase ${name} failed after ${humanizeDuration(end - start)}:`, error.message);
    throw error as Error;
  }
}
