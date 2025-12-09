import { DataTypeEntry } from '../config/types';

export interface EventFileInfo {
  path: string;
  dataType: string;
  base: string; // <type>_<timestamp> without extension
  createTime: number; // 0 if not parsed
  priority: number;
  size?: number; // optional stat result
}

export interface EventInfo {
  dataType: string;
  base: string;
  createTime: number; // earliest file timestamp
  priority: number;
  files: EventFileInfo[];
  hasUploaded?: boolean; // marker: directory contains .uploaded file
}

export interface EventScanOptions {
  includeStat?: boolean;          // collect size
  includeUploadedMarker?: boolean; // if true, populate hasUploaded flag (even though uploaded dirs are skipped normally)
}

export interface ScanError {
  path: string;
  code: string;
}

export interface ScanTotals {
  files: number;
  events: number;
  bytes?: number;
}

export interface ScanTimings {
  scanMs: number;
  statMs?: number;
}

export interface EventScanResult {
  events: EventInfo[];
  totals: ScanTotals;
  errors: ScanError[];
  timings: ScanTimings;
}

export type DataTypeConfig = DataTypeEntry;