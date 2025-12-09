
export class ArrayUtil {

  static isEmpty<T = []>(t: T[]) {
    return t == null || t == undefined || t.length == 0
  }

  static isNotEmpty<T = []>(t: T[]) {
    return !ArrayUtil.isEmpty(t)
  }
}