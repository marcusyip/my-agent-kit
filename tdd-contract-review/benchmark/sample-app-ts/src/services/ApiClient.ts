export class ApiClient {
  private baseUrl: string;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl;
  }

  async get<T>(path: string): Promise<T> {
    const url = this.buildUrl(path);
    const res = await fetch(url, { method: "GET" });
    return this.parse<T>(res);
  }

  async post<T>(path: string, body: unknown): Promise<T> {
    const url = this.buildUrl(path);
    const res = await fetch(url, {
      method: "POST",
      body: JSON.stringify(body),
      headers: { "Content-Type": "application/json" },
    });
    return this.parse<T>(res);
  }

  private buildUrl(path: string): string {
    return `${this.baseUrl}${path}`;
  }

  private async parse<T>(res: Response): Promise<T> {
    if (!res.ok) {
      throw new Error(`api error: ${res.status}`);
    }
    return res.json();
  }
}
