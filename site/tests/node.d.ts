// The parts of Node's test runner and assert module the tests use, typed
// here so `astro check` can check the tests without @types/node (the site
// keeps to astro and TypeScript).

declare module 'node:test' {
  export function describe(name: string, body: () => void): void;
  export function test(name: string, body: () => void | Promise<void>): void;
}

declare module 'node:assert/strict' {
  interface Assert {
    ok(value: unknown, message?: string): void;
    equal(actual: unknown, expected: unknown, message?: string): void;
    notEqual(actual: unknown, expected: unknown, message?: string): void;
    deepEqual(actual: unknown, expected: unknown, message?: string): void;
    match(value: string, pattern: RegExp, message?: string): void;
    doesNotMatch(value: string, pattern: RegExp, message?: string): void;
    throws(block: () => unknown, error?: RegExp, message?: string): void;
  }
  const assert: Assert;
  export default assert;
}
