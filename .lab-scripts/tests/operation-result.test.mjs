import assert from "node:assert/strict";
import test from "node:test";
import { requireSuccess } from "../templates/05f-code-app/operationResult.ts";

test("returns confirmed data", () => {
  const data = { id: "record" };
  assert.equal(requireSuccess({ success: true, data }), data);
});

test("a resolved SDK failure throws before a success callback", () => {
  assert.throws(() => requireSuccess({
    success: false,
    data: undefined,
    error: new Error("Not enough product in stock"),
  }), /Not enough product in stock/);
});

test("missing server error still produces an explicit failure", () => {
  assert.throws(() => requireSuccess({ success: false, data: undefined }), /Dataverse rejected/);
});

test("successful writes may omit response data", () => {
  assert.equal(requireSuccess({ success: true, data: undefined }), undefined);
});
