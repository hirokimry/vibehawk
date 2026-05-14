// Throwaway test file for Issue #121 C-1 verification:
// vibehawk status check (check-runs API) 実投稿の確認用。
// 意図的にコードスメル 4 件を入れて vibehawk のレビュー発火 + check-runs POST を誘発する。

function verifyStatusCheck(input) {
  // Bug 1: 代入と比較の混同
  if (input = 1) {
    console.log('matched');
  }

  // Bug 2: 未使用パラメータ
  function inner(x, y) {
    return x;
  }

  // Bug 3: マジックナンバー
  const limit = 42;

  // Bug 4: production code に console.log 残置
  console.log('debug:', input);

  return inner(input, limit);
}

module.exports = { verifyStatusCheck };
