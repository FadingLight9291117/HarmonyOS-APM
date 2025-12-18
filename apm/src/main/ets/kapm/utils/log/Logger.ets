export interface LogBackend {
  debug(tag: string, ...args: string[]): void;
  info(tag: string, ...args: string[]): void;
  warn(tag: string, ...args: string[]): void;
  error(tag: string, ...args: string[]): void;
}

class ConsoleBackend implements LogBackend {
  debug(tag: string, ...args: string[]) { console.debug(this.format('DEBUG', tag, args)); }
  info(tag: string, ...args: string[]) { console.log(this.format('INFO', tag, args)); }
  warn(tag: string, ...args: string[]) { console.warn(this.format('WARN', tag, args)); }
  error(tag: string, ...args: string[]) { console.error(this.format('ERROR', tag, args)); }

  private format(level: string, tag: string, args: string[]): string {
    const ts = new Date().toISOString();
    const tagPart = tag ? `[${tag}]` : '';
    const levelPart = level.padEnd(5)
    return [`${ts}`, `[${levelPart}]`, tagPart, ...args].join(' ');
  }
}

let backend: LogBackend = new ConsoleBackend();
export const getBackend = () => backend;
export const setBackend = (b: LogBackend) => {
  backend = b;
};

class LoggerImpl {
  private readonly tag: string;

  private constructor(tag: string) {
    this.tag = tag;
  }

  debug(...args: string[]) {
    getBackend().debug(this.tag, ...args);
  }

  info(...args: string[]) {
    getBackend().info(this.tag, ...args);
  }

  warn(...args: string[]) {
    getBackend().warn(this.tag, ...args);
  }

  error(...args: string[]) {
    getBackend().error(this.tag, ...args);
  }

  static getLogger(tag: string = ''): LoggerImpl {
    return new LoggerImpl(tag);
  }
}

export const Logger = LoggerImpl.getLogger();
export const getLogger = (tag?: string) => LoggerImpl.getLogger(tag);


export interface IKLogAdapter {
  d: (tag: string, msg: string) => void
  i: (tag: string, msg: string) => void
  e: (tag: string, msg: string) => void
  w: (tag: string, msg: string) => void
}

export class KLogAdapter<T extends IKLogAdapter> implements LogBackend {
  private kLog: T;

  constructor(kLog: T) {
    this.kLog = kLog;
  }

  debug(tag: string, ...args: string[]): void {
    this.kLog.d(tag, args.join(' '))
  }

  info(tag: string, ...args: string[]): void {
    this.kLog.i(tag, args.join(' '))
  }

  warn(tag: string, ...args: string[]): void {
    this.kLog.w(tag, args.join(' '))
  }

  error(tag: string, ...args: string[]): void {
    this.kLog.e(tag, args.join(' '))
  }
}
