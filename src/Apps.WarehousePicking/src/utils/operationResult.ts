import type { IOperationResult } from "@microsoft/power-apps/data";

export function requireSuccess<T>(result: IOperationResult<T>): T {
  if (!result.success) {
    throw new Error(result.error?.message || "Dataverse rejected the operation.");
  }
  return result.data;
}

