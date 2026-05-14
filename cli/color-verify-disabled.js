// Throwaway test file for Issue #121 verification: CodeRabbit auto_review disabled.
// 意図的なコードスメル 4 件 (vibehawk のレビューを誘発する目的)。

function verifyBundledColorDisabled(input) {
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

module.exports = { verifyBundledColorDisabled };
