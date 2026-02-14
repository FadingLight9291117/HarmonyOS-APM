export class StringUtil {

  static isEmpty(str: string | undefined | null): boolean {
    return str == undefined || str == null || str.length == 0
  }

  static isNotEmpty(str: string | undefined | null) {
    return !StringUtil.isEmpty(str)
  }

}