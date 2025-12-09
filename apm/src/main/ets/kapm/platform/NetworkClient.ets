import { http } from "@kit.NetworkKit";
import { getLogger, safeJsonParse } from "../utils";
import { JSON } from "@kit.ArkTS";

export type QueryParams = Record<string, string | number | undefined>;

export interface SimpleResponse {
  ok: boolean;
  status: number;
  json: <T>() => T | null;
  msg?: string;
}


export interface NetworkClient {
  get(url: string, headers?: Record<string, string>, query?: QueryParams): Promise<SimpleResponse>;

  post(url: string, body: RequestBody, headers?: Record<string, string>, query?: QueryParams): Promise<SimpleResponse>;
}

class DummyResponse<T> implements SimpleResponse {
  private readonly statusCode: number;
  private readonly payload: T;

  constructor(statusCode: number, payload: T) {
    this.statusCode = statusCode;
    this.payload = payload;
  }

  get ok() {
    return this.statusCode >= 200 && this.statusCode < 300;
  }

  get status() {
    return this.statusCode;
  }

  json() {
    return null;
  }
}

interface FakeResponse {
  error: string;
}

class PlaceholderNetworkClient implements NetworkClient {
  async get(_url: string, _headers: Record<string, string> = {},
    _query?: QueryParams): Promise<SimpleResponse> {
    return new DummyResponse<FakeResponse>(501, { error: 'GET not implemented' });
  }

  async post(_url: string, _body: RequestBody, _headers: Record<string, string> = {},
    _query?: QueryParams): Promise<SimpleResponse> {
    return new DummyResponse<FakeResponse>(501, { error: 'POST not implemented' });
  }
}

export type RequestBody = string | Object | ArrayBuffer | undefined;

class DefaultNetworkClient implements NetworkClient {
  private readonly TAG: string = 'NetworkClient';
  private readonly logger = getLogger(this.TAG);

  async get(
    url: string,
    headers: Record<string, string> = {},
    query: QueryParams = {}
  ): Promise<SimpleResponse> {
    return this.request(http.RequestMethod.GET, url, undefined, headers, query);
  }

  async post(
    url: string,
    body: RequestBody,
    headers: Record<string, string> = {},
    query: QueryParams = {}
  ): Promise<SimpleResponse> {
    return this.request(http.RequestMethod.POST, url, body, headers, query);
  }

  private async request(
    method: http.RequestMethod,
    url: string,
    body?: RequestBody,
    headers: Record<string, string> = {},
    query: QueryParams = {}
  ): Promise<SimpleResponse> {
    const request = http.createHttp();
    try {
      const _headers = this.mergeHeaders({ 'Content-Type': 'application/json' }, headers);
      const options: http.HttpRequestOptions = {
        method,
        header: _headers,
        extraData: body,
        readTimeout: 5000,
        connectTimeout: 5000,
      };

      if (Object.keys(query).length > 0) {
        url += this.buildQueryParams(query);
      }

      this.logger.debug(`Making ${http.RequestMethod[method]} request to ${url},` + '\n' + ` with headers: ${JSON.stringify(_headers)}.`);

      const response = await request.request(url, options);
      return this.handleResponse(response);
    } catch (error) {
      return this.handleError(method, url, error.message);
    } finally {
      request.destroy()
    }
  }

  private buildQueryParams(params: QueryParams): string {
    const query = Object.entries(params)
      .filter((kv) => kv[1] !== undefined)
      .map((kv) => `${encodeURIComponent(kv[0])}=${encodeURIComponent(kv[1]!)}`)
      .join('&');
    return query ? `?${query}` : '';
  }

  private handleResponse(response: http.HttpResponse): SimpleResponse {
    return {
      ok: response.responseCode >= 200 && response.responseCode < 300,
      status: response.responseCode,
      json: <T>() => safeJsonParse<T>(response.result.toString()),
    };
  }

  private handleError(method: http.RequestMethod, url: string, error: Error): SimpleResponse {
    this.logger.error(`Error making ${http.RequestMethod[method]} request to ${url}: ${error.message}`);
    return { ok: false, status: -1, json: () => null, msg: error.message };
  }

  private mergeHeaders(mainHeaders: Record<string, string>, customHeaders?: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {};
    Object.keys(mainHeaders).forEach((key) => headers[key] = mainHeaders[key]);
    if (customHeaders) {
      Object.keys(customHeaders).forEach((key) => headers[key] = customHeaders[key]);
    }
    return headers;
  }
}

export function createDefaultNetworkClient(): NetworkClient {
  return new DefaultNetworkClient();
}

export class HttpError extends Error {
  public readonly status: number;

  constructor(name: string, response: SimpleResponse) {
    super(`${name} HTTP status: ${response.status}, reason: ${response.msg || response.json<Record<string, string | number>>()?.['msg'] || ''}`);
    this.status = response.status;
  }
}