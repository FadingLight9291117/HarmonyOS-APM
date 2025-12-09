import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { BusInfoDataType, AnalyTypeEnum, CrashBranchEnum } from '../../../main/ets/kapm/types/uploadTypes';
import { buildAnalySemanticName, buildZipFileName } from '../../../main/ets/kapm/utils/uploadHelpers';

export default function uploadHelpersTest() {
  describe('UploadHelpersTest', () => {
    beforeAll(() => {
      // 测试套件初始化
    });

    beforeEach(() => {
      // 每个测试用例前的准备
    });

    afterEach(() => {
      // 每个测试用例后的清理
    });

    afterAll(() => {
      // 测试套件结束后的清理
    });

    describe('buildAnalySemanticName', () => {
      it('should build name for crash with JsError branch', 0, () => {
        const bus: BusInfoDataType = {
          _analy_type: AnalyTypeEnum.Crash,
          _analy_branch: CrashBranchEnum.JsError,
          _ct: Date.now(),
          contents: []
        };
        const result = buildAnalySemanticName(bus);
        expect(result).assertEqual('JsCrash');
      });

      it('should build name for crash with NativeCrash branch', 0, () => {
        const bus: BusInfoDataType = {
          _analy_type: AnalyTypeEnum.Crash,
          _analy_branch: CrashBranchEnum.NativeCrash,
          _ct: Date.now(),
          contents: []
        };
        const result = buildAnalySemanticName(bus);
        expect(result).assertEqual('NativeCrash');
      });

      it('should build name for crash without branch', 0, () => {
        const bus: BusInfoDataType = {
          _analy_type: AnalyTypeEnum.Crash,
          _ct: Date.now(),
          contents: []
        };
        const result = buildAnalySemanticName(bus);
        expect(result).assertContain('Crash');
      });
    });

    describe('buildZipFileName', () => {
      it('should build zip file name with timestamp', 0, () => {
        const bus: BusInfoDataType = {
          _analy_type: AnalyTypeEnum.Crash,
          _analy_branch: CrashBranchEnum.JsError,
          _ct: Date.now(),
          contents: []
        };
        const timestamp = 1234567890;
        const result = buildZipFileName(bus, timestamp);
        expect(result).assertContain('report_');
        expect(result).assertContain('_');
        expect(result).assertContain('.zip');
        expect(result).assertContain('1234567890');
      });

      it('should use current timestamp if not provided', 0, () => {
        const bus: BusInfoDataType = {
          _analy_type: AnalyTypeEnum.Crash,
          _ct: Date.now(),
          contents: []
        };
        const result = buildZipFileName(bus);
        expect(result).assertContain('report_');
        expect(result).assertContain('.zip');
      });
    });
  });
}
