
export interface MetaData {
  type: string,        // 事件类型，如'jsError'，'nativeCrash'，'appFreeze'
  userId: string,      // 用户id
  createTime: number,  // 事件发生事件
  business?: string,   // 业务标签，如pdf
  network: string,     // 网络类型，如4g、5g、wifi
  carrier?: string,    // 运营商
}

export interface CacheType<T> {
  metadata: MetaData
  hieventdata: T
}
