export { add } from './src/main/ets/utils/Calc';

// 导出崩溃模拟函数
export {
  crashNullPointer,
  crashInvalidMemory,
  crashAbort,
  crashDivideByZero,
  crashBusError,
  crashStackOverflow,
  crashIllegalInstruction,
  crashTrap,
  crashInThread,
  crashHeapOverflow,
  crashDoubleFree,
  crashUseAfterFree
} from 'libnative_error_demo.so';
