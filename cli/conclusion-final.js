// Throwaway: PR #130 (substantive review refinement) 後の最終動作確認用。
// 4 件のコードスメルで vibehawk CHANGES_REQUESTED → check-run conclusion=failure 期待。

function conclusionFinal(input) {
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

module.exports = { conclusionFinal };
