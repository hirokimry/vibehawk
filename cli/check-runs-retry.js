// Throwaway test file for Issue #121 C-1 retry verification (after PR #128 fix).
// 意図的にコードスメル 4 件を入れて vibehawk レビュー発火 + check-runs POST を誘発する。

function retryCheckRuns(input) {
  if (input = 1) {
    console.log('matched');
  }

  function inner(x, y) {
    return x;
  }

  const limit = 42;
  console.log('debug:', input);

  return inner(input, limit);
}

module.exports = { retryCheckRuns };
