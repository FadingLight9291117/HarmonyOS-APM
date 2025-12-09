import { BusInfoDataType, CRASH_BRANCH_NAME_MAP } from '../types/uploadTypes';
import { CrashBranchEnum, AnalyTypeEnum, getAnalyTypeName } from '../types/uploadTypes';

/** Map analy_type + optional branch to semantic name used in zip file naming. */
export function buildAnalySemanticName(bus: BusInfoDataType): string {
  const base = getAnalyTypeName(bus._analy_type);
  if (bus._analy_type === AnalyTypeEnum.Crash && bus._analy_branch !== undefined) {
    switch (bus._analy_branch) {
      case CrashBranchEnum.JsError: return 'JsCrash';
      case CrashBranchEnum.NativeCrash: return 'NativeCrash';
      default: return 'Crash';
    }
  }
  // PascalCase the base (which is snake or lower) for naming readability
  return base.split(/[_\-]/).map(s => s.charAt(0).toUpperCase() + s.slice(1)).join('');
}

/** Build zip file name: report_<analyName>_<analyType>_<timestamp>.zip */
export function buildZipFileName(bus: BusInfoDataType, ts: number = Date.now()): string {
  const analyName = buildAnalySemanticName(bus);
  return `report_${analyName}_${bus._analy_type}_${ts}.zip`;
}
